local issues = require("cmp_git.provider.capabilities.issues")
local log = require("cmp_git.log")

local M = {}

---@param args cmp_git.Provider.CapabilityArgs
---@return cmp_git.SystemJob?
function M.job(args)
    if issues.from_cache(args) then
        return nil
    end

    return issues.list_job(args, args.adapter.change_requests_request(args.git_info, args.trigger_char, args.config))
end

---@param args cmp_git.Provider.CapabilityArgs
function M.complete(args)
    local job = M.job(args)
    if job then
        job:start()
    end
    return job
end

---@param args cmp_git.Provider.RefreshArgs
---@param done fun(items: table[]?)
function M.refresh(args, done)
    issues.fetch(args.runner, args.adapter.change_requests_request(args.git_info, args.trigger_char, args.config), done)
end

---Give one list with the issues, then the change requests. Each job calls back once: at once on a cache hit, and with
---an empty list on a failure. So a failure of one request still gives the items of the other.
---@param callback fun(list: cmp_git.CompletionList)
---@param issues_job fun(callback: fun(list: cmp_git.CompletionList)): cmp_git.SystemJob? Makes the job of the issues.
---@param change_requests_job fun(callback: fun(list: cmp_git.CompletionList)): cmp_git.SystemJob?
---@return { command: string, cancel: fun() } controller
function M.with_issues(callback, issues_job, change_requests_job)
    local results = {}
    local pending = 2
    local cancelled = false

    ---@param kind "issues" | "change_requests"
    local function collect(kind)
        return function(list)
            if cancelled then
                return
            end
            results[kind] = list.items
            pending = pending - 1
            if pending > 0 then
                return
            end

            -- Each request gets new lists, because the cache keeps the raw items
            local items = vim.list_extend(results.issues, results.change_requests)
            log.fmt_debug("Got %d issues and change requests", #items)
            callback({ items = items, isIncomplete = false })
        end
    end

    local jobs = { issues_job(collect("issues")) or false, change_requests_job(collect("change_requests")) or false }
    -- Both commands run at once, so that a cold request waits for the slower one, not for both in turn
    for _, job in ipairs(jobs) do
        if job then
            job:start()
        end
    end

    return {
        command = "issues_and_change_requests",
        cancel = function()
            cancelled = true
            for _, job in ipairs(jobs) do
                if job and job.cancel then
                    job:cancel()
                end
            end
        end,
    }
end

return M
