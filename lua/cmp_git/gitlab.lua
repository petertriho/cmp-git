local Job = require("plenary.job")
local utils = require("cmp_git.utils")

local M = {}

local get_project_id = function(git_info)
    return utils.url_encode(string.format("%s/%s", git_info.owner, git_info.repo))
end

local get_items = function(callback, glab_command, curl_url, handle_item)
    local command = nil

    if vim.fn.executable("glab") == 1 and glab_command then
        command = glab_command
    elseif vim.fn.executable("curl") == 1 and curl_url then
        command = {
            "curl",
            "-s",
            curl_url,
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

    command.cwd = utils.get_cwd()
    command.on_exit = function(job)
        local result = table.concat(job:result(), "")

        local items = utils.handle_response(result, handle_item)

        callback({ items = items, isIncomplete = false })
    end

    Job:new(command):start()
end

M.get_issues = function(source, callback, bufnr, git_info)
    local id = get_project_id(git_info)

    get_items(
        function(args)
            callback(args)
            source.cache_issues[bufnr] = args.items
        end,
        {
            "glab",
            "api",
            string.format(
                "/projects/%s/issues?per_page=%d&state=%s",
                id,
                source.config.gitlab.issues.limit,
                source.config.gitlab.issues.state
            ),
        },
        string.format(
            "https://%s/api/v4/projects/%s/issues?per_page=%d&state=%s",
            git_info.host,
            id,
            source.config.gitlab.issues.limit,
            source.config.gitlab.issues.state
        ),
        function(issue)
            if issue.description == vim.NIL then
                issue.description = ""
            end

            return {
                label = string.format("#%s: %s", issue.iid, issue.title),
                insertText = string.format("#%s", issue.iid),
                documentation = {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", issue.title, issue.description),
                },
            }
        end
    )
end

M.get_mentions = function(source, callback, bufnr, git_info)
    local id = get_project_id(git_info)

    get_items(
        function(args)
            callback(args)
            source.cache_mentions[bufnr] = args.items
        end,
        {
            "glab",
            "api",
            string.format("/projects/%s/users?per_page=%d", id, source.config.gitlab.mentions.limit),
        },
        string.format(
            "https://%s/api/v4/projects/%s/users?per_page=%d",
            git_info.host,
            id,
            source.config.gitlab.mentions.limit
        ),
        function(mention)
            return {
                label = string.format("@%s", mention.username),
                documentation = {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", mention.username, mention.name),
                },
            }
        end
    )
end

M.get_merge_requests = function(source, callback, bufnr, git_info)
    local id = get_project_id(git_info)

    get_items(
        function(args)
            callback(args)
            source.cache_merge_requests[bufnr] = args.items
        end,
        {
            "glab",
            "api",
            string.format(
                "/projects/%s/merge_requests?per_page=%d&state=%s",
                id,
                source.config.gitlab.merge_requests.limit,
                source.config.gitlab.merge_requests.state
            ),
        },
        string.format(
            "https://%s/api/v4/projects/%s/merge_requests?per_page=%d&state=%s",
            git_info.host,
            id,
            source.config.gitlab.merge_requests.limit,
            source.config.gitlab.merge_requests.state
        ),

        function(mr)
            return {
                label = string.format("!%s: %s", mr.iid, mr.title),
                insertText = string.format("!%s", mr.iid),
                documentation = {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", mr.title, mr.description),
                },
            }
        end
    )
end

return M
