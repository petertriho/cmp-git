local Job = require("plenary.job")

local M = {}

M.get_issues = function(source, callback, bufnr, owner, repo)
    local command = nil

    if vim.fn.executable("gh") == 1 then
        command = {
            "gh",
            "issue",
            "list",
            "--limit",
            source.config.github.issues.limit,
            "--state",
            source.config.github.issues.state,
            "--json",
            "title,number,body",
        }
    elseif vim.fn.executable("curl") == 1 then
        local url = string.format(
            "https://api.github.com/repos/%s/%s/issues?state=%s&per_page=%d&page=%d",
            owner,
            repo,
            source.config.github.filter,
            source.config.github.issues.limit,
            source.config.github.issues.state,
            1
        )

        command = {
            "curl",
            "-s",
            "-H",
            "'Accept: application/vnd.github.v3+json'",
            url,
        }

        if vim.fn.exists("$GITHUB_API_TOKEN") == 1 then
            local token = vim.fn.getenv("GITHUB_API_TOKEN")
            local authorization_header = string.format("Authorization: token %s", token)
            table.insert(command, "-H")
            table.insert(command, authorization_header)
        end
    else
        vim.notify("gh and curl executables not found!")
        return
    end

    local process_data = function(ok, parsed)
        if not ok then
            vim.notify("Failed to parse github api result")
            return
        end

        local items = {}

        for _, issue in ipairs(parsed) do
            if issue.body ~= vim.NIL then
                issue.body = string.gsub(issue.body or "", "\r", "")
            else
                issue.body = ""
            end

            table.insert(items, {
                label = string.format("#%s", issue.number),
                documentation = {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", issue.title, issue.body),
                },
            })
        end

        callback({ items = items, isIncomplete = false })

        source.cache_issues[bufnr] = items
    end

    command.on_exit = function(job)
        local result = table.concat(job:result(), "")

        if vim.fn.has("nvim-0.5.1") then
            vim.schedule(function()
                local ok, parsed = pcall(vim.fn.json_decode, result)
                process_data(ok, parsed)
            end)
        else
            local ok, parsed = pcall(vim.json_decode, result)
            process_data(ok, parsed)
        end
    end

    Job:new(command):start()
end

M.get_mentions = function(source, callback, bufnr, owner, repo)
    local command = nil

    if vim.fn.executable("curl") == 1 then
        local url = string.format(
            "https://api.github.com/repos/%s/%s/contributors?per_page=%d&page=%d",
            owner,
            repo,
            source.config.github.mentions.limit,
            1
        )

        command = {
            "curl",
            "-s",
            url,
        }

        if vim.fn.exists("$GITHUB_API_TOKEN") == 1 then
            local token = vim.fn.getenv("GITHUB_API_TOKEN")
            local authorization_header = string.format("Authorization: token %s", token)
            table.insert(command, "-H")
            table.insert(command, authorization_header)
        end
    else
        vim.notify("curl executable not found!")
        return
    end

    local process_data = function(ok, parsed)
        if not ok then
            vim.notify("Failed to parse github api result")
            return
        end

        local items = {}

        for _, mention in ipairs(parsed) do
            table.insert(items, {
                label = string.format("@%s", mention.login),
            })
        end

        callback({ items = items, isIncomplete = false })

        source.cache_mentions[bufnr] = items
    end

    command.on_exit = function(job)
        local result = table.concat(job:result(), "")

        if vim.fn.has("nvim-0.5.1") then
            vim.schedule(function()
                local ok, parsed = pcall(vim.fn.json_decode, result)
                process_data(ok, parsed)
            end)
        else
            local ok, parsed = pcall(vim.json_decode, result)
            process_data(ok, parsed)
        end
    end

    Job:new(command):start()
end

return M
