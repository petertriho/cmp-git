local Job = require("plenary.job")
local utils = require("cmp_git.utils")

local M = {}

M.get_issues = function(source, callback, bufnr, git_info)
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
            git_info.owner,
            git_info.repo,
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

    command.on_exit = function(job)
        local result = table.concat(job:result(), "")

        local items = utils.handle_response(result, function(issue)
            if issue.body ~= vim.NIL then
                issue.body = string.gsub(issue.body or "", "\r", "")
            else
                issue.body = ""
            end
            return {
                label = string.format("#%s", issue.number),
                documentation = {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", issue.title, issue.body),
                },
            }
        end)

        callback({ items = items, isIncomplete = false })

        source.cache_issues[bufnr] = items
    end

    Job:new(command):start()
end

M.get_mentions = function(source, callback, bufnr, git_info)
    local command = nil

    if vim.fn.executable("curl") == 1 then
        local url = string.format(
            "https://api.github.com/repos/%s/%s/contributors?per_page=%d&page=%d",
            git_info.owner,
            git_info.repo,
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

    command.on_exit = function(job)
        local result = table.concat(job:result(), "")

        local items = utils.handle_response(result, function(mention)
            return {
                label = string.format("@%s", mention.login),
            }
        end)

        callback({ items = items, isIncomplete = false })

        source.cache_mentions[bufnr] = items
    end

    Job:new(command):start()
end

return M
