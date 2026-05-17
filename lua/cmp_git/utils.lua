local log = require("cmp_git.log")
local repository = require("cmp_git.repository")
local M = {}

---@param c integer|string
local function char_to_hex(c)
    return string.format("%%%02X", string.byte(c))
end

---@param value string
function M.url_encode(value)
    return string.gsub(value, "([^%w _%%%-%.~])", char_to_hex)
end

---@param d string
function M.parse_gitlab_date(d)
    local year, month, day, hours, mins, secs, _, offsethours, offsetmins =
        d:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)%.(%d+)[+-](%d+):(%d+)")

    if hours == nil then
        year, month, day, hours, mins, secs = d:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)%.(%d+)Z")
        offsethours = 0
        offsetmins = 0
    end

    return os.time({
        year = year,
        month = month,
        day = day,
        hour = hours + offsethours,
        min = mins + offsetmins,
        sec = secs,
    })
end

---@param d string
function M.parse_github_date(d)
    local year, month, day, hours, mins, secs = d:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)Z")

    return os.time({
        year = year,
        month = month,
        day = day,
        hour = hours,
        min = mins,
        sec = secs,
    })
end

---@class cmp_git.SystemJob
---@field command string
---@field start fun(self: cmp_git.SystemJob, on_complete?: fun(success: boolean): nil, suppress_failure_callback?: boolean): nil

---@param exec string
---@param args string[]
---@param env table<string, string | integer>?
---@param callback fun(result: string, success: boolean): nil
---@return cmp_git.SystemJob?
function M.build_simple_job(exec, args, env, callback)
    if vim.fn.executable(exec) ~= 1 or not args then
        log.fmt_debug("Can't work with %s for this call", exec)
        return nil
    end

    local job_env = nil
    if env ~= nil then
        -- NOTE: setting env causes it to not inherit it from the parent environment
        job_env = vim.tbl_extend("force", env, {
            PATH = vim.fn.getenv("PATH"),
        })
        for key, value in pairs(job_env) do
            job_env[key] = tostring(value)
        end
    end

    return {
        command = exec,
        start = function(_, on_complete, suppress_failure_callback)
            vim.system(vim.list_extend({ exec }, args), {
                text = true,
                env = job_env,
                cwd = repository.get_cwd(),
            }, function(result)
                vim.schedule(function()
                    local success = result.code == 0
                    if not success then
                        log.fmt_debug("%s returned with exit code %d", exec, result.code)
                        if result.stderr and result.stderr ~= "" then
                            log.fmt_debug("%s stderr: %s", exec, result.stderr)
                        end
                    else
                        log.fmt_debug("%s returned with a result", exec)
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
    }
end

---@generic TItem
---@param exec string
---@param args string[]
---@param env table<string, string | integer>?
---@param callback fun(list: cmp_git.CompletionList)
---@param handle_item fun(item: TItem): cmp_git.CompletionItem
---@param handle_parsed? fun(parsed: any): TItem[]
---@return cmp_git.SystemJob?
function M.build_job(exec, args, env, callback, handle_item, handle_parsed)
    return M.build_simple_job(exec, args, env, function(result, success)
        if not success then
            return
        end
        local items = M.handle_response(result, handle_item, handle_parsed)

        callback({ items = items, isIncomplete = false })
    end)
end

---Start the second job if the first one fails, handle cases if the first or second job is nil.
---@param first cmp_git.SystemJob?
---@param second cmp_git.SystemJob?
---@return cmp_git.SystemJob?
function M.chain_fallback(first, second)
    if not first and not second then
        log.debug("No executable could be found for completion source")
        return nil
    end

    return {
        command = first and first.command or second.command,
        start = function(_, on_complete)
            local function done(success)
                if on_complete then
                    on_complete(success)
                end
            end

            if not first then
                second:start(done)
                return
            end

            first:start(function(success)
                if success then
                    done(true)
                    return
                end

                if second then
                    second:start(done)
                else
                    done(false)
                end
            end, true)
        end,
    }
end

---@generic TItem
---@param response string
---@param handle_item fun(item: TItem): cmp_git.CompletionItem
---@param handle_parsed fun(parsed: any): TItem[]
---@return cmp_git.CompletionItem[]
function M.handle_response(response, handle_item, handle_parsed)
    local items = {}

    local function process_data(ok, parsed)
        if not ok then
            log.warn("Failed to parse api result")
            return
        end

        if handle_parsed then
            parsed = handle_parsed(parsed)
        end

        for _, item in ipairs(parsed) do
            table.insert(items, handle_item(item))
        end
    end

    local ok, parsed = pcall(vim.json.decode, response)
    process_data(ok, parsed)

    return items
end

return M
