local log = require("cmp_git.log")
local M = {}

---@param c integer|string
local function char_to_hex(c)
    return string.format("%%%02X", string.byte(c))
end

---@param cmd string
---@param opts { on_complete: fun(success: boolean, output: string[]): nil; cwd?: string }
---@return nil
local function run_cmd_async(cmd, opts)
    vim.system({ "sh", "-c", cmd }, {
        text = true,
        cwd = opts.cwd,
    }, function(result)
        vim.schedule(function()
            local output = vim.split(result.stdout or "", "\n", { trimempty = true })
            opts.on_complete(result.code == 0, output)
        end)
    end)
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
                cwd = M.get_cwd(),
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
