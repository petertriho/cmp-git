local log = require("cmp_git.log")
local repository = require("cmp_git.repository")
local response = require("cmp_git.response")

local M = {}

---@class cmp_git.SystemJob
---@field command string
---@field start fun(self: cmp_git.SystemJob, on_complete?: fun(success: boolean): nil, suppress_failure_callback?: boolean): nil
---@field cancel? fun(self: cmp_git.SystemJob): nil

---@class cmp_git.CommandSpec
---@field exec string
---@field args string[]
---@field env? table<string, string | integer>

---@param spec cmp_git.CommandSpec
---@return table<string, string>? env
local function command_env(spec)
    if spec.env == nil then
        return nil
    end

    -- NOTE: setting env causes it to not inherit it from the parent environment
    local env = vim.tbl_extend("force", spec.env, {
        PATH = vim.fn.getenv("PATH"),
    })
    for key, value in pairs(env) do
        env[key] = tostring(value)
    end
    return env
end

---@param spec cmp_git.CommandSpec
---@param callback fun(result: string, success: boolean): nil
---@return cmp_git.SystemJob?
function M.build(spec, callback)
    if vim.fn.executable(spec.exec) ~= 1 or not spec.args then
        log.fmt_debug("Can't work with %s for this call", spec.exec)
        return nil
    end

    local job_env = command_env(spec)

    return {
        command = spec.exec,
        handle = nil,
        cancelled = false,
        start = function(_, on_complete, suppress_failure_callback)
            local job = _
            job.handle = vim.system(vim.list_extend({ spec.exec }, spec.args), {
                text = true,
                env = job_env,
                cwd = repository.get_cwd(),
            }, function(result)
                vim.schedule(function()
                    if job.cancelled then
                        if on_complete then
                            on_complete(false)
                        end
                        return
                    end

                    local success = result.code == 0
                    if not success then
                        log.fmt_debug("%s returned with exit code %d", spec.exec, result.code)
                        if result.stderr and result.stderr ~= "" then
                            log.fmt_debug("%s stderr: %s", spec.exec, result.stderr)
                        end
                    else
                        log.fmt_debug("%s returned with a result", spec.exec)
                    end
                    if success or not suppress_failure_callback then
                        callback(result.stdout or "", success)
                    end
                    if on_complete then
                        on_complete(success)
                    end
                end)
            end)
        end,
        cancel = function(_)
            _.cancelled = true
            if _.handle and _.handle.kill then
                _.handle:kill(15)
            end
        end,
    }
end

---@generic TItem
---@param spec cmp_git.CommandSpec
---@param callback fun(list: cmp_git.CompletionList)
---@param handle_item fun(item: TItem): cmp_git.CompletionItem
---@param handle_parsed? fun(parsed: any): TItem[]
---@return cmp_git.SystemJob?
function M.build_list(spec, callback, handle_item, handle_parsed)
    return M.build(spec, function(result, success)
        if not success then
            return
        end

        callback(response.completion_list(result, handle_item, handle_parsed))
    end)
end

---Start the second job if the first one fails, handle cases if the first or second job is nil.
---@param first cmp_git.SystemJob?
---@param second cmp_git.SystemJob?
---@return cmp_git.SystemJob?
function M.fallback(first, second)
    if not first and not second then
        log.debug("No executable could be found for completion source")
        return nil
    end

    return {
        command = first and first.command or second.command,
        active = nil,
        cancelled = false,
        start = function(_, on_complete)
            local job = _
            local function done(success)
                if on_complete then
                    on_complete(success)
                end
            end

            if not first then
                if job.cancelled then
                    done(false)
                    return
                end
                job.active = second
                second:start(done)
                return
            end

            job.active = first
            first:start(function(success)
                if job.cancelled then
                    done(false)
                    return
                end

                if success then
                    done(true)
                    return
                end

                if second then
                    job.active = second
                    second:start(done)
                else
                    done(false)
                end
            end, true)
        end,
        cancel = function(_)
            _.cancelled = true
            if _.active and _.active.cancel then
                _.active:cancel()
            end
        end,
    }
end

---@param specs cmp_git.CommandSpec[]
---@param callback fun(result: string, success: boolean): nil
---@return cmp_git.SystemJob?
function M.build_fallback(specs, callback)
    local job
    for i = #specs, 1, -1 do
        job = M.fallback(M.build(specs[i], callback), job)
    end
    return job
end

---@generic TItem
---@param specs cmp_git.CommandSpec[]
---@param callback fun(list: cmp_git.CompletionList)
---@param handle_item fun(item: TItem): cmp_git.CompletionItem
---@param handle_parsed? fun(parsed: any): TItem[]
---@return cmp_git.SystemJob?
function M.build_fallback_list(specs, callback, handle_item, handle_parsed)
    local job
    for i = #specs, 1, -1 do
        job = M.fallback(M.build_list(specs[i], callback, handle_item, handle_parsed), job)
    end
    return job
end

return M
