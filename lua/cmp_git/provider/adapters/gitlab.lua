local format = require("cmp_git.format")
local utils = require("cmp_git.utils")

local M = {}

---An issue from the issues API.
---@class cmp_git.GitLab.Issue
---@field iid integer
---@field title string
---@field description string
---@field updated_at string

---A merge request from the merge requests API.
---@class cmp_git.GitLab.MergeRequest: cmp_git.GitLab.Issue

---A user from the project users API.
---@class cmp_git.GitLab.Mention
---@field username string
---@field name string

local function project_id(git_info)
    return utils.url_encode(string.format("%s/%s", git_info.owner, git_info.repo))
end

local function env()
    return {
        -- `vim.env` is nil for an unset variable. `vim.fn.getenv` gives `vim.NIL`, which the command passes as the
        -- string "vim.NIL".
        GITLAB_TOKEN = vim.env.GITLAB_TOKEN,
        NO_COLOR = 1,
    }
end

---Replace the missing and null text fields that the formats read. JSON null is `vim.NIL`, which a format would show as
---the text "vim.NIL".
---@generic T: table
---@param item T
---@param fields string[]
---@return T item
local function empty_nulls(item, fields)
    for _, field in ipairs(fields) do
        if item[field] == nil or item[field] == vim.NIL then
            item[field] = ""
        end
    end
    return item
end

---@param curl_url string
---@return cmp_git.CommandSpec
local function curl_command(curl_url)
    -- Without --fail, curl exits with 0 on an HTTP error, and the error object looks like an empty list
    local args = { "-s", "-S", "--fail" }
    local stdin = nil

    local token = vim.env.GITLAB_TOKEN
    if token and token ~= "" then
        -- `-H @-` reads the header from stdin, so that the token is not in the process list
        vim.list_extend(args, { "-H", "@-" })
        stdin = string.format("Authorization: Bearer %s\n", token)
    end

    table.insert(args, curl_url)
    return { exec = "curl", args = args, stdin = stdin }
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
            curl_command(
                string.format(
                    "https://%s/api/v4/projects/%s/issues?per_page=%d&state=%s",
                    git_info.host,
                    id,
                    config.limit,
                    config.state
                )
            ),
        },
        handle_item = function(issue)
            return format.item(config, trigger_char, empty_nulls(issue, { "title", "description" }))
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
            curl_command(
                string.format(
                    "https://%s/api/v4/projects/%s/merge_requests?per_page=%d&state=%s",
                    git_info.host,
                    id,
                    config.limit,
                    config.state
                )
            ),
        },
        handle_item = function(mr)
            return format.item(config, trigger_char, empty_nulls(mr, { "title", "description" }))
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
            curl_command(
                string.format("https://%s/api/v4/projects/%s/users?per_page=%d", git_info.host, id, config.limit)
            ),
        },
        handle_item = function(mention)
            return format.item(config, trigger_char, empty_nulls(mention, { "name" }))
        end,
    }
end

function M.mentions_has_more()
    return false
end

return M
