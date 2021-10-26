local Job = require("plenary.job")
local utils = require("cmp_git.utils")

local M = {}

M.get_issues = function(source, callback, bufnr, owner, repo)
    local command = nil

    if vim.fn.executable("glab") == 1 then
        command = {
            "glab",
            "api",
            string.format(
                "/projects/:id/issues?per_page=%d&state=%s",
                source.config.gitlab.issues.limit,
                source.config.gitlab.issues.state
            ),
        }
    elseif vim.fn.executable("curl") == 1 then
        local url = string.format(
            "https://gitlab.com/api/v4/projects/%s/issues?per_page=%d&state=%s",
            utils.url_encode(string.format("%s/%s", owner, repo)),
            source.config.gitlab.issues.limit,
            source.config.gitlab.issues.state
        )

        command = {
            "curl",
            "-s",
            url,
        }

        if vim.fn.exists("$GITLAB_TOKEN") == 1 then
            local token = vim.fn.getenv("GITLAB_TOKEN")
            local authorization_header = string.format("Authorization: Bearer %s", token)
            table.insert(command, "-H")
            table.insert(command, authorization_header)
        end
    else
        vim.notify("glab and curl executables not found!")
        return
    end

    local process_data = function(ok, parsed)
        if not ok then
            vim.notify("Failed to parse gitlab api result")
            return
        end

        local items = {}

        for _, issue in ipairs(parsed) do
            if issue.description == vim.NIL then
                issue.description = ""
            end

            table.insert(items, {
                label = string.format("#%s", issue.iid),
                documentation = {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", issue.title, issue.description),
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

    if vim.fn.executable("glab") == 1 then
        command = {
            "glab",
            "api",
            string.format("/projects/:id/users?per_page=%d", source.config.gitlab.mentions.limit),
        }
    elseif vim.fn.executable("curl") == 1 then
        local url = string.format(
            "https://gitlab.com/api/v4/projects/%s/users?per_page=%d",
            utils.url_encode(string.format("%s/%s", owner, repo)),
            source.config.gitlab.mentions.limit
        )

        command = {
            "curl",
            "-s",
            url,
        }

        if vim.fn.exists("$GITLAB_TOKEN") == 1 then
            local token = vim.fn.getenv("GITLAB_TOKEN")
            local authorization_header = string.format("Authorization: Bearer %s", token)
            table.insert(command, "-H")
            table.insert(command, authorization_header)
        end
    else
        vim.notify("glab executables not found!")
        return
    end

    local process_data = function(ok, parsed)
        if not ok then
            vim.notify("Failed to parse gitlab api result")
            return
        end

        local items = {}

        for _, mention in ipairs(parsed) do
            table.insert(items, {
                label = string.format("@%s", mention.username),
                documentation = {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", mention.username, mention.name),
                },
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
