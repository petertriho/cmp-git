local log = require("cmp_git.log")
local Job = require("plenary.job")

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

function M.is_git_repo()
    local function is_inside_git_repo()
        local cmd = "git rev-parse --is-inside-work-tree --is-inside-git-dir"
        return string.find(vim.fn.system(cmd), "true") ~= nil
    end

    -- buffer cwd
    local is_git_repo = M.run_in_cwd(M.get_cwd(), is_inside_git_repo)

    if not is_git_repo then
        -- fallback to cwd
        is_git_repo = is_inside_git_repo()
    end

    return is_git_repo
end

---@class cmp_git.GitInfo
---@field host string?
---@field owner string?
---@field repo string?

---@param remotes string|string[]
---@param opts {enableRemoteUrlRewrites: boolean, ssh_aliases: {[string]: string}}
---@return cmp_git.GitInfo
function M.get_git_info(remotes, opts)
    opts = opts or {}

    ---@return cmp_git.GitInfo
    local function get_git_info()
        if type(remotes) == "string" then
            remotes = { remotes }
        end

        local host, owner, repo = nil, nil, nil

        if vim.bo.filetype == "octo" then
            host = require("octo.config").values.github_hostname or ""
            if host == "" then
                host = "github.com"
            end
            local filename = vim.fn.expand("%:p:h")
            owner, repo = string.match(filename, "^octo://([^/]+)/([^/]+)")
        else
            for _, remote in ipairs(remotes) do
                local cmd
                if opts.enableRemoteUrlRewrites then
                    cmd = "git remote get-url " .. remote
                else
                    cmd = "git config --get remote." .. remote .. ".url"
                end
                local remote_origin_url = vim.fn.system(cmd)

                if remote_origin_url ~= "" then
                    local clean_remote_origin_url = remote_origin_url:gsub("%.git", ""):gsub("%s", "")

                    host, owner, repo = string.match(clean_remote_origin_url, "^git.*@(.+):(.+)/(.+)$")

                    if host == nil then
                        host, owner, repo = string.match(clean_remote_origin_url, "^https?://(.+)/(.+)/(.+)$")
                    end

                    if host == nil then
                        host, owner, repo = string.match(clean_remote_origin_url, "^ssh://git@([^:]+):*.*/(.+)/(.+)$")
                    end

                    if host == nil then
                        host, owner, repo = string.match(clean_remote_origin_url, "^([^:]+):(.+)/(.+)$")
                    end

                    if host ~= nil and owner ~= nil and repo ~= nil then
                        break
                    end
                end
            end
        end

        if host ~= nil then
            for alias, rhost in pairs(opts.ssh_aliases) do
                host = host:gsub("^" .. alias:gsub("%-", "%%-"):gsub("%.", "%%.") .. "$", rhost, 1)
            end
        end

        return { host = host, owner = owner, repo = repo }
    end

    -- buffer cwd
    local git_info = M.run_in_cwd(M.get_cwd(), get_git_info)

    if git_info.host == nil then
        -- fallback to cwd
        git_info = get_git_info()
    end

    return git_info
end

---@generic TResult
---@param cwd string
---@param callback fun(...): TResult
---@return TResult
function M.run_in_cwd(cwd, callback, ...)
    local args = ...
    local old_cwd = vim.fn.getcwd()

    local ok, result = pcall(function()
        vim.cmd(([[lcd %s]]):format(cwd))
        return callback(args)
    end)
    vim.cmd(([[lcd %s]]):format(old_cwd))
    if not ok then
        error(result)
    end
    return result
end

function M.get_cwd()
    if vim.fn.getreg("%") ~= "" and vim.bo.filetype ~= "octo" then
        return vim.fn.expand("%:p:h")
    end
    return vim.fn.getcwd()
end

---@generic TItem
---@param callback fun(list: cmp_git.CompletionList)
---@param handle_item fun(item: TItem): cmp_git.CompletionItem
---@param handle_parsed? fun(parsed: any): TItem[]
---@return Job?
function M.build_job(exec, args, env, callback, handle_item, handle_parsed)
    -- TODO: Find a nicer way, that we can keep chaining jobs at call side
    if vim.fn.executable(exec) ~= 1 or not args then
        log.fmt_debug("Can't work with %s for this call", exec)
        return nil
    end

    local job_env = nil
    if env ~= nil then
        -- NOTE: setting env causes it to not inherit it from the parent environment
        vim.tbl_extend("force", env, {
            path = vim.fn.getenv("PATH"),
        })
    end

    ---@diagnostic disable-next-line: missing-fields
    return Job:new({
        command = exec,
        args = args,
        env = job_env,
        cwd = M.get_cwd(),
        on_exit = vim.schedule_wrap(function(job, code)
            if code ~= 0 then
                log.fmt_debug("%s returned with exit code %d", exec, code)
            else
                log.fmt_debug("%s returned with a result", exec)
                local result = table.concat(job:result(), "")

                local items = M.handle_response(result, handle_item, handle_parsed)

                callback({ items = items, isIncomplete = false })
            end
        end),
    })
end

---Start the second job if the first on fails, handle cases if the first or second job is nil.
---The last job debug prints on failure
---@param first Job?
---@param second Job?
---@return Job?
function M.chain_fallback(first, second)
    if first and second then
        first:and_then_on_failure(second)
        second:after_failure(function(_, code, _)
            log.fmt_debug("%s failed with exit code %d, couldn't retrieve any completion info", second.command, code)
        end)

        return first
    elseif first then
        first:after_failure(function(_, code, _)
            log.fmt_debug("%s failed with exit code %d, couldn't retrieve any completion info", first.command, code)
        end)
        return first
    elseif second then
        second:after_failure(function(_, code, _)
            log.fmt_debug("%s failed with exit code %d, couldn't retrieve any completion info", second.command, code)
        end)
        return second
    else
        log.debug("Neither %s or %s could be found", first.command, second.command)
        return nil
    end
end

---@generic TItem
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

    if vim.json and vim.json.decode then
        local ok, parsed = pcall(vim.json.decode, response)
        process_data(ok, parsed)
    else
        vim.schedule(function()
            local ok, parsed = pcall(vim.fn.json_decode, response)
            process_data(ok, parsed)
        end)
    end

    return items
end

return M
