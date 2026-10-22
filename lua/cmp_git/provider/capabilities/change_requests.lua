local issues = require("cmp_git.provider.capabilities.issues")

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

return M
