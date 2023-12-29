local log = require("cmp_git.log")
local Job = require("plenary.job")

local M = {}

local char_to_hex = function(c)
    return string.format("%%%02X", string.byte(c))
end

M.url_encode = function(value)
    return string.gsub(value, "([^%w _%%%-%.~])", char_to_hex)
end

M.parse_gitlab_date = function(d)
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

M.parse_github_date = function(d)
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

M.is_git_repo = function()
    local is_inside_git_repo = function()
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

M.get_git_info = function(remotes, opts)
    opts = opts or {}

    local get_git_info = function()
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
            owner, repo = string.match(filename, "^octo://(.+)/(.+)/.+$")
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

                    host, owner, repo = string.match(clean_remote_origin_url, "^git@(.+):(.+)/(.+)$")

                    if host == nil then
                        host, owner, repo = string.match(clean_remote_origin_url, "^https?://(.+)/(.+)/(.+)$")
                    end

                    if host == nil then
                        host, owner, repo = string.match(clean_remote_origin_url, "^ssh://git@([^:]+):*.*/(.+)/(.+)$")
                    end

                    if host ~= nil and owner ~= nil and repo ~= nil then
                        break
                    end
                end
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

M.run_in_cwd = function(cwd, callback, ...)
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

M.get_cwd = function()
    if vim.fn.getreg("%") ~= "" and vim.bo.filetype ~= "octo" then
        return vim.fn.expand("%:p:h")
    end
    return vim.fn.getcwd()
end

M.build_job = function(exec, callback, args, handle_item, handle_parsed)
    -- TODO: Find a nicer way, that we can keep chaining jobs at call side
    if vim.fn.executable(exec) ~= 1 or not args then
        log.fmt_debug("Can't work with %s for this call", exec)
        return nil
    end

    return Job:new({
        command = exec,
        args = args,
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

--- Start the second job if the first on fails, handle cases if the first or second job is nil.
--- The last job debug prints on failure
M.chain_fallback = function(first, second)
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

M.handle_response = function(response, handle_item, handle_parsed)
    local items = {}

    local process_data = function(ok, parsed)
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
