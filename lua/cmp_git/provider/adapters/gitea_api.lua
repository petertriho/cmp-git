-- The API of Gitea and Forgejo, which Forgejo kept after its fork. The `gitea` and `forgejo` adapters add their own
-- commands before the curl commands of this module.
local format = require("cmp_git.format")
local utils = require("cmp_git.utils")

local M = {}

---An issue or a pull request from the issues API.
---@class cmp_git.Gitea.Issue
---@field number integer
---@field title string
---@field body string
---@field state string
---@field updated_at string
---@field user { login: string }
---@field pull_request? table Set for a pull request.

---A user from the assignees API.
---@class cmp_git.Gitea.Mention
---@field login string
---@field full_name string

---The adapter of a provider. It gives the commands of the provider for an API path.
---@class cmp_git.Gitea.Provider
---@field token_env string The variable with the token for curl, such as `GITEA_TOKEN`.
---@field commands fun(git_info: cmp_git.GitInfo, path: string): cmp_git.CommandSpec[] The commands before curl.

---The URL of an API path. An `http://` remote gives a plain HTTP URL, and all other remotes give HTTPS. The host can
---have a port and a path prefix.
---@param git_info cmp_git.GitInfo
---@param path string The path after `/api/v1/`.
---@return string
function M.api_url(git_info, path)
    local scheme = git_info.scheme == "http" and "http" or "https"
    return string.format("%s://%s/api/v1/%s", scheme, git_info.host, path)
end

---@param git_info cmp_git.GitInfo
---@param endpoint string The path after the repository, with the query.
---@return string path The API path of the endpoint of the repository.
function M.repo_path(git_info, endpoint)
    local owner = utils.url_encode(git_info.owner)
    local repo = utils.url_encode(git_info.repo)
    return string.format("repos/%s/%s/%s", owner, repo, endpoint)
end

---@param url string
---@param token? string
---@return cmp_git.CommandSpec
function M.curl_command(url, token)
    -- Without --fail, curl exits with 0 on an HTTP error, and the next command does not run
    local args = { "-s", "-S", "--fail", "-L" }
    local stdin = nil

    -- A request without a header, because an empty or invalid token fails also on a public repository
    if token then
        -- `-H @-` reads the header from stdin, so that the token is not in the process list
        vim.list_extend(args, { "-H", "@-" })
        stdin = string.format("Authorization: token %s\n", token)
    end

    table.insert(args, url)
    return { exec = "curl", args = args, stdin = stdin }
end

---@param item cmp_git.Gitea.Issue
---@return cmp_git.Gitea.Issue
local function normalize_issue(item)
    utils.empty_nulls(item, { "title", "body" })
    -- The web editor saves the body with CRLF line endings
    item.body = string.gsub(item.body, "\r", "")
    return item
end

---The adapter of a provider. The commands of a request are the commands of the provider, then curl with the token of
---`token_env` if it is set, then curl without a token. One variable can give the token of another host, which fails
---also on a public repository, so the last command still gets the public items.
---@param provider cmp_git.Gitea.Provider
function M.adapter(provider)
    ---@param git_info cmp_git.GitInfo
    ---@param path string
    ---@param anonymous boolean Add curl without a token.
    ---@return cmp_git.CommandSpec[]
    local function commands(git_info, path, anonymous)
        local list = provider.commands(git_info, path)
        local url = M.api_url(git_info, path)
        local token = vim.env[provider.token_env]
        if token and token ~= "" then
            table.insert(list, M.curl_command(url, token))
        end
        if anonymous then
            table.insert(list, M.curl_command(url))
        end
        return list
    end

    ---The issues API gives the pull requests too, in the same shape, with `type=pulls`
    ---@param git_info cmp_git.GitInfo
    ---@param trigger_char string
    ---@param config cmp_git.Config.Gitea.List
    ---@param type "issues" | "pulls"
    ---@return cmp_git.Provider.ListRequest
    local function list_request(git_info, trigger_char, config, type)
        local endpoint =
            string.format("issues?state=%s&type=%s&limit=%d&page=1", utils.url_encode(config.state), type, config.limit)
        return {
            commands = commands(git_info, M.repo_path(git_info, endpoint), true),
            handle_item = function(issue)
                return format.item(config, trigger_char, normalize_issue(issue))
            end,
        }
    end

    local adapter = {}

    function adapter.issues_request(git_info, trigger_char, config)
        return list_request(git_info, trigger_char, config, "issues")
    end

    function adapter.change_requests_request(git_info, trigger_char, config)
        return list_request(git_info, trigger_char, config, "pulls")
    end

    function adapter.mentions_request(git_info, trigger_char, config)
        return {
            -- The assignees API needs a token, so a request without one would always fail
            commands = commands(git_info, M.repo_path(git_info, "assignees"), false),
            handle_item = function(mention)
                return format.item(config, trigger_char, utils.empty_nulls(mention, { "full_name" }))
            end,
        }
    end

    ---The assignees API gives all users on one page
    function adapter.mentions_has_more()
        return false
    end

    return adapter
end

return M
