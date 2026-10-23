-- The real glab against a fake GitLab API on 127.0.0.1. `glab api` prints the body of the API.
local helpers = require("tests.helpers")
local integration = require("tests.integration.helpers")
local config = require("cmp_git.config")
local GitLab = require("cmp_git.sources.gitlab")

local eq = helpers.eq

local T = helpers.new_set()

---A fake GitLab API for glab, a GitLab source for its host, and the remote of a project on it.
---@return tests.integration.HttpServer server
---@return cmp_git.Source.Gitlab source
---@return cmp_git.GitInfo git_info
local function gitlab_server()
    integration.require_binaries({ "glab" })
    local server = integration.http_server()
    helpers.defer(function()
        server:close()
    end)
    local host = integration.use_glab(server)
    integration.offline_curl()
    integration.edit_outside_repository()
    local source = GitLab.new(config.normalize({ gitlab = { hosts = { host } } }).gitlab)
    return server, source, { host = host, owner = "group/sub", repo = "project" }
end

---@param source cmp_git.Source.Gitlab
---@param method string
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@return string[] labels
local function complete(source, method, git_info, trigger_char)
    local callback, lists = helpers.recorder()
    eq(source[method](source, callback, git_info, trigger_char), true, method .. " handles the host")
    helpers.wait_for(function()
        return #lists > 0
    end, method .. " answers")
    return vim.tbl_map(function(item)
        return item.label
    end, lists[1].items)
end

local PROJECT = "/api/v4/projects/group%2Fsub%2Fproject"

T["issues_come_from_glab_api"] = function()
    local server, source, git_info = gitlab_server()
    server.routes["GET " .. PROJECT .. "/issues"] = {
        body = {
            { id = 101, iid = 1, title = "Slow pipeline", description = vim.NIL, updated_at = "2026-01-02T00:00:00Z" },
        },
    }

    eq(complete(source, "complete_issues", git_info, "#"), { "#1: Slow pipeline" }, "the issues")
    eq(server:request_lines(), { "GET " .. PROJECT .. "/issues?per_page=100&state=opened" }, "one request")
    eq(server.requests[1].headers["private-token"], "glab-token", "glab sends its token")
end

T["merge_requests_come_from_glab_api"] = function()
    local server, source, git_info = gitlab_server()
    server.routes["GET " .. PROJECT .. "/merge_requests"] = {
        body = { { id = 102, iid = 2, title = "Speed up", description = "", updated_at = "2026-01-03T00:00:00Z" } },
    }

    eq(complete(source, "complete_change_requests", git_info, "!"), { "!2: Speed up" }, "the merge requests")
    eq(server:request_lines(), { "GET " .. PROJECT .. "/merge_requests?per_page=100&state=opened" }, "one request")
end

T["mentions_come_from_the_users_of_the_project"] = function()
    local server, source, git_info = gitlab_server()
    server.routes["GET " .. PROJECT .. "/users"] = {
        body = { { id = 1, username = "ada", name = "Ada Lovelace" }, { id = 2, username = "grace", name = vim.NIL } },
    }

    eq(complete(source, "complete_mentions", git_info, "@"), { "@ada", "@grace" }, "the users")
    eq(server:request_lines(), { "GET " .. PROJECT .. "/users?per_page=100" }, "one request")
end

T["an_http_error_gives_no_items"] = function()
    local server, source, git_info = gitlab_server()

    eq(complete(source, "complete_issues", git_info, "#"), {}, "no issues")
    eq(#server.requests, 1, "glab asks once, and the curl fallback does not reach the network")
    eq(source:_entry("issues", git_info):get(), nil, "the failure is not cached")
end

return T
