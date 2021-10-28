local Job = require("plenary.job")
local utils = require("cmp_git.utils")

local M = {}

local get_items = function(callback, gh_command, curl_url, handle_item)
    local command = nil

    if vim.fn.executable("gh") == 1 and gh_command then
        command = gh_command
    elseif vim.fn.executable("curl") == 1 and curl_url then
        command = {
            "curl",
            "-s",
            "-H",
            "'Accept: application/vnd.github.v3+json'",
            curl_url,
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

        local items = utils.handle_response(result, handle_item)

        callback({ items = items, isIncomplete = false })
    end

    Job:new(command):start()
end

M.get_issues = function(source, callback, bufnr, git_info)
    get_items(
        function(args)
            callback(args)
            source.cache_issues[bufnr] = args.items
        end,
        {
            "gh",
            "issue",
            "list",
            "--limit",
            source.config.github.issues.limit,
            "--state",
            source.config.github.issues.state,
            "--json",
            "title,number,body",
        },
        string.format(
            "https://api.github.com/repos/%s/%s/issues?filter=%s&state=%s&per_page=%d&page=%d",
            git_info.owner,
            git_info.repo,
            source.config.github.issues.filter,
            source.config.github.issues.state,
            source.config.github.issues.limit,
            1
        ),
        function(issue)
            if issue.body ~= vim.NIL then
                issue.body = string.gsub(issue.body or "", "\r", "")
            else
                issue.body = ""
            end

            return {
                label = string.format("#%s: %s", issue.number, issue.title),
                insertText = string.format("#%s", issue.number),
                documentation = {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", issue.title, issue.body),
                },
            }
        end
    )
end

M.get_mentions = function(source, callback, bufnr, git_info)
    get_items(
        function(args)
            callback(args)
            source.cache_mentions[bufnr] = args.items
        end,
        nil,
        string.format(
            "https://api.github.com/repos/%s/%s/contributors?per_page=%d&page=%d",
            git_info.owner,
            git_info.repo,
            source.config.github.mentions.limit,
            1
        ),
        function(mention)
            return {
                label = string.format("@%s", mention.login),
            }
        end
    )
end

return M
