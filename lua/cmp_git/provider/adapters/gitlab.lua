local format = require("cmp_git.format")
local utils = require("cmp_git.utils")

local M = {}

local function project_id(git_info)
    return utils.url_encode(string.format("%s/%s", git_info.owner, git_info.repo))
end

local function env()
    return {
        GITLAB_TOKEN = vim.fn.getenv("GITLAB_TOKEN"),
        NO_COLOR = 1,
    }
end

local function curl_args(curl_url)
    local args = {
        "-s",
        curl_url,
    }

    if vim.fn.exists("$GITLAB_TOKEN") == 1 then
        local token = vim.fn.getenv("GITLAB_TOKEN")
        table.insert(args, "-H")
        table.insert(args, string.format("Authorization: Bearer %s", token))
    end

    return args
end

function M.issues_request(git_info, trigger_char, config)
    local id = project_id(git_info)
    return {
        commands = {
            {
                exec = "glab",
                args = {
                    "api",
                    string.format("/projects/%s/issues?per_page=%d&state=%s", id, config.limit, config.state),
                },
                env = env(),
            },
            {
                exec = "curl",
                args = curl_args(
                    string.format(
                        "https://%s/api/v4/projects/%s/issues?per_page=%d&state=%s",
                        git_info.host,
                        id,
                        config.limit,
                        config.state
                    )
                ),
            },
        },
        handle_item = function(issue)
            if issue.description == vim.NIL then
                issue.description = ""
            end
            return format.item(config, trigger_char, issue)
        end,
    }
end

function M.change_requests_request(git_info, trigger_char, config)
    local id = project_id(git_info)
    return {
        commands = {
            {
                exec = "glab",
                args = {
                    "api",
                    string.format("/projects/%s/merge_requests?per_page=%d&state=%s", id, config.limit, config.state),
                },
                env = env(),
            },
            {
                exec = "curl",
                args = curl_args(
                    string.format(
                        "https://%s/api/v4/projects/%s/merge_requests?per_page=%d&state=%s",
                        git_info.host,
                        id,
                        config.limit,
                        config.state
                    )
                ),
            },
        },
        handle_item = function(mr)
            return format.item(config, trigger_char, mr)
        end,
    }
end

function M.mentions_request(git_info, trigger_char, config)
    local id = project_id(git_info)
    return {
        commands = {
            {
                exec = "glab",
                args = {
                    "api",
                    string.format("/projects/%s/users?per_page=%d", id, config.limit),
                },
                env = env(),
            },
            {
                exec = "curl",
                args = curl_args(
                    string.format("https://%s/api/v4/projects/%s/users?per_page=%d", git_info.host, id, config.limit)
                ),
            },
        },
        handle_item = function(mention)
            return format.item(config, trigger_char, mention)
        end,
    }
end

function M.mentions_has_more()
    return false
end

return M
