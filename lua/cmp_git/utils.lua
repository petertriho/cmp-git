local log = require("cmp_git.log")
local Job = require("plenary.job")

local M = {}

---@param c integer|string
local function char_to_hex(c)
    return string.format("%%%02X", string.byte(c))
end

---@param cmd string
---@param opts { on_complete: fun(success: boolean, output: string[]): nil; cwd?: string }
---@return nil
local function run_cmd_async(cmd, opts)
    ---@type string[]
    local output = {}
    vim.fn.jobstart(cmd, {
        on_stdout = function(_, data)
            if not data then
                return
            end
            vim.list_extend(output, data)
        end,
        on_stderr = function(_, data)
            if not data then
                return
            end
            vim.list_extend(output, data)
        end,
        on_exit = function(_, exit_code)
            opts.on_complete(exit_code == 0, output)
        end,
        cwd = opts.cwd,
    })
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

---@param on_result fun(is_git_repo: boolean): nil
---@return nil
function M.is_git_repo(on_result)
    local cwd = M.get_cwd() ---@type string?
    local function check_in_git_repo()
        local cmd = "git rev-parse --is-inside-work-tree --is-inside-git-dir"
        run_cmd_async(cmd, {
            on_complete = function(success, output)
                local is_git_repo = success and #output > 0 and output[1]:find("true") ~= nil
                if not is_git_repo and cwd ~= nil then
                    cwd = nil
                    check_in_git_repo()
                    return
                end
                on_result(is_git_repo)
            end,
        })
    end
    check_in_git_repo()
end

---@class cmp_git.GitInfo
---@field host string?
---@field owner string?
---@field repo string?

---@param remotes string|string[]
---@param opts {enableRemoteUrlRewrites: boolean, ssh_aliases: {[string]: string}, on_complete: fun(git_info: cmp_git.GitInfo): nil}
---@return nil
function M.get_git_info(remotes, opts)
    opts = opts or {}
    local cwd = M.get_cwd() ---@type string?

    local get_git_info ---@type fun(): nil

    ---@param git_info cmp_git.GitInfo
    local function handle_git_info(git_info)
        if git_info.host == nil and cwd ~= nil then
            cwd = nil
            get_git_info()
            return
        end
        if git_info.host ~= nil then
            for alias, rhost in pairs(opts.ssh_aliases) do
                git_info.host = git_info.host:gsub("^" .. alias:gsub("%-", "%%-"):gsub("%.", "%%.") .. "$", rhost, 1)
            end
        end

        opts.on_complete(git_info)
    end

    get_git_info = function()
        if type(remotes) == "string" then
            remotes = { remotes }
        end

        ---@type string?, string?, string?
        local host, owner, repo = nil, nil, nil

        if vim.bo.filetype == "octo" then
            host = require("octo.config").values.github_hostname or ""
            if host == "" then
                host = "github.com"
            end
            local filename = vim.fn.expand("%:p:h")
            owner, repo = string.match(filename, "^octo://([^/]+)/([^/]+)")
            handle_git_info({ host = host, owner = owner, repo = repo })
            return
        end
        local remote_index = 1
        local function check_remote()
            if remote_index > #remotes then
                handle_git_info({ host = host, owner = owner, repo = repo })
                return
            end
            local remote = remotes[remote_index]
            local cmd ---@type string
            if opts.enableRemoteUrlRewrites then
                cmd = "git remote get-url " .. remote
            else
                cmd = "git config --get remote." .. remote .. ".url"
            end
            run_cmd_async(cmd, {
                on_complete = function(success, output)
                    remote_index = remote_index + 1
                    if not success then
                        check_remote()
                        return
                    end
                    local remote_origin_url = output[1]
                    if remote_origin_url ~= "" then
                        local clean_remote_origin_url = remote_origin_url:gsub("%.git", ""):gsub("%s", "")

                        host, owner, repo = string.match(clean_remote_origin_url, "^git.*@(.+):(.+)/(.+)$")

                        if host == nil then
                            host, owner, repo = string.match(clean_remote_origin_url, "^https?://(.+)/(.+)/(.+)$")
                        end

                        if host == nil then
                            host, owner, repo =
                                string.match(clean_remote_origin_url, "^ssh://git@([^:]+):*.*/(.+)/(.+)$")
                        end

                        if host == nil then
                            host, owner, repo = string.match(clean_remote_origin_url, "^([^:]+):(.+)/(.+)$")
                        end

                        if host ~= nil and owner ~= nil and repo ~= nil then
                            handle_git_info({ host = host, owner = owner, repo = repo })
                            return
                        end
                    end
                end,
                cwd = cwd,
            })
        end
        check_remote()

        return { host = host, owner = owner, repo = repo }
    end
    get_git_info()
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
