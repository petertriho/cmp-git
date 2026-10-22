local log = require("cmp_git.log")
local repository = require("cmp_git.repository")
local response = require("cmp_git.response")

local M = {}

---@class cmp_git.SystemJob
---@field command string
---@field start fun(self: cmp_git.SystemJob, on_complete?: fun(success: boolean), suppress_failure_callback?: boolean)
---@field cancel? fun(self: cmp_git.SystemJob): nil

---@class cmp_git.CommandSpec
---@field exec string
---@field args string[]
---@field env? table<string, string | integer> Added to the environment of Neovim.
---@field stdin? string Written to the standard input. Secrets go here, because other users can read the arguments.

---@param spec cmp_git.CommandSpec
---@param callback fun(result: string, success: boolean): nil
---@return cmp_git.SystemJob?
function M.build(spec, callback)
    if vim.fn.executable(spec.exec) ~= 1 or not spec.args then
        log.fmt_debug("Can't work with %s for this call", spec.exec)
        return nil
    end

    return {
        command = spec.exec,
        handle = nil,
        cancelled = false,
        start = function(_, on_complete, suppress_failure_callback)
            local job = _

            ---@param result vim.SystemCompleted
            local function complete(result)
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
            end

            local ok, handle = pcall(vim.system, vim.list_extend({ spec.exec }, spec.args), {
                text = true,
                env = spec.env,
                stdin = spec.stdin,
                cwd = repository.get_cwd(),
            }, function(result)
                vim.schedule(function()
                    complete(result)
                end)
            end)
            if not ok then
                -- For example, a cwd that does not exist. The caller gets a failed command, not an error.
                vim.schedule(function()
                    complete({ code = -1, signal = 0, stdout = "", stderr = tostring(handle) })
                end)
                return
            end
            job.handle = handle
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
---@param callback fun(list: cmp_git.CompletionList, success: boolean) The list is empty when the command fails.
---@param handle_item fun(item: TItem): cmp_git.CompletionItem
---@param handle_parsed? fun(parsed: any): TItem[]? A result that is not a list is a failure.
---@return cmp_git.SystemJob?
function M.build_list(spec, callback, handle_item, handle_parsed)
    return M.build(spec, function(result, success)
        if not success then
            callback({ items = {}, isIncomplete = false }, false)
            return
        end

        -- An output that is not a list, for example an error object, is a failure
        local list, ok = response.completion_list(result, handle_item, handle_parsed)
        callback(list, ok)
    end)
end

---Start the second job if the first one fails, handle cases if the first or second job is nil. Only the last job that
---runs reports a failure to its callback.
---@param first cmp_git.SystemJob?
---@param second cmp_git.SystemJob?
---@return cmp_git.SystemJob?
function M.fallback(first, second)
    if not first and not second then
        log.debug("No executable could be found for completion source")
        return nil
    end

    return {
        -- The check above leaves at least one job
        command = first and first.command or (second --[[@as cmp_git.SystemJob]]).command,
        active = nil,
        cancelled = false,
        start = function(_, on_complete, suppress_failure_callback)
            local job = _
            local function done(success)
                if on_complete then
                    on_complete(success)
                end
            end

            if not first then
                ---@cast second -nil
                if job.cancelled then
                    done(false)
                    return
                end
                job.active = second
                second:start(done, suppress_failure_callback)
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
                    second:start(done, suppress_failure_callback)
                else
                    done(false)
                end
            end, second ~= nil or suppress_failure_callback)
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
---@param callback fun(list: cmp_git.CompletionList, success: boolean) The list is empty when all commands fail.
---@param handle_item fun(item: TItem): cmp_git.CompletionItem
---@param handle_parsed? fun(parsed: any): TItem[]? A result that is not a list is a failure.
---@return cmp_git.SystemJob? job nil when no command is executable.
function M.build_fallback_list(specs, callback, handle_item, handle_parsed)
    local job
    for i = #specs, 1, -1 do
        job = M.fallback(M.build_list(specs[i], callback, handle_item, handle_parsed), job)
    end
    return job
end

return M
