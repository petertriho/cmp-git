local helpers = require("tests.helpers")
local fake_gitea_api = require("tests.sources.fake_gitea_api")
local config = require("cmp_git.config")
local Gitea = require("cmp_git.sources.gitea")

local eq = helpers.eq
local ok = helpers.ok

local T = helpers.new_set()

local EMPTY = { items = {}, isIncomplete = false }

local REMOTE = { host = "gitea.com", owner = "owner", repo = "repo" }
local API = "https://gitea.com/api/v1/repos/owner/repo/"
local ISSUES_URL = API .. "issues?state=open&type=issues&limit=50&page=1"
local PULLS_URL = API .. "issues?state=open&type=pulls&limit=50&page=1"

---@param overrides? table
---@return cmp_git.Source.GiteaApi
local function source(overrides)
    return Gitea.new(config.normalize({ gitea = overrides }).gitea)
end

---Run a request of the source and return its final list.
---@param gitea cmp_git.Source.GiteaApi
---@param method string
---@param trigger_char string
---@param git_info? cmp_git.GitInfo
---@return cmp_git.CompletionList
local function complete(gitea, method, trigger_char, git_info)
    local callback, lists = helpers.recorder()
    eq(gitea[method](gitea, callback, git_info or REMOTE, trigger_char), true, method .. " handles the host")
    helpers.wait_for(function()
        return #lists > 0
    end, method .. " answers")
    helpers.flush()
    eq(#lists, 1, method .. " gives one list")
    return lists[1]
end

---@param list cmp_git.CompletionList
---@return string[]
local function labels(list)
    return vim.tbl_map(function(item)
        return item.label
    end, list.items)
end

T["gitea_hosts"] = function()
    local gitea = source({ hosts = { "example.com/gitea" } })

    ok(gitea:is_valid_host(REMOTE), "gitea.com by default")
    ok(gitea:is_valid_host({ host = "example.com/gitea", owner = "o", repo = "r" }), "a host with a path prefix")
    ok(not gitea:is_valid_host({ host = "codeberg.org", owner = "o", repo = "r" }), "a Forgejo host")
    ok(not gitea:is_valid_host({ host = "gitea.com" }), "a remote without a repository")
end

T["issues_and_pull_requests_come_from_curl"] = function()
    local log = fake_gitea_api.curl()
    local gitea = source()

    local list = complete(gitea, "complete_issues_and_change_requests", "#")

    eq(labels(list), { "#1: An issue", "#2: A pull request" }, "the issues, then the pull requests")
    eq(list.items[2].data.body, "", "a null body is empty")
    local runs = log()
    table.sort(runs)
    eq(runs, { ISSUES_URL .. " ", PULLS_URL .. " " }, "one request for each list, without a token")
    eq(#gitea:_entry("issues", REMOTE):get(), 1, "the issues are cached")
    ok(gitea:_entry("pull_requests", REMOTE).path:find("/gitea%-pull_requests%-") ~= nil, "in the gitea files")

    eq(labels(complete(gitea, "complete_issues_and_change_requests", "#")), labels(list), "a cache hit")
    eq(#log(), 2, "a cache hit runs no command")
end

T["pull_requests_under_the_bang"] = function()
    fake_gitea_api.curl()

    eq(labels(complete(source(), "complete_change_requests", "!")), { "!2: A pull request" }, "the pull requests")
    eq(labels(complete(source(), "complete_issues", "#")), { "#1: An issue" }, "the issues alone")
end

T["failed_commands_give_an_empty_list_that_is_not_cached"] = function()
    vim.env.GITEA_TOKEN = "secret"
    local log = fake_gitea_api.curl({ fail = true })
    local gitea = source()

    for _, method in ipairs({ "complete_issues", "complete_change_requests", "complete_issues_and_change_requests" }) do
        eq(complete(gitea, method, "#"), EMPTY, method)
    end
    eq(complete(gitea, "complete_mentions", "@"), EMPTY, "mentions")
    for _, kind in ipairs({ "issues", "pull_requests", "mentions" }) do
        eq(gitea:_entry(kind, REMOTE):get(), nil, kind .. " are not cached")
    end
    eq(#log(), 9, "curl with the token, then without, for each list, and with the token for the mentions")
end

T["missing_commands_give_an_empty_list"] = function()
    helpers.fake_commands({})
    local gitea = source()

    eq(complete(gitea, "complete_issues_and_change_requests", "#"), EMPTY, "issues and pull requests")
    eq(complete(gitea, "complete_change_requests", "!"), EMPTY, "pull requests")
end

T["mentions_need_a_token"] = function()
    local log = fake_gitea_api.curl()
    local gitea = source()

    eq(complete(gitea, "complete_mentions", "@"), EMPTY, "no mentions without a token")
    eq(log(), {}, "and no process")

    vim.env.GITEA_TOKEN = "secret"
    local list = complete(gitea, "complete_mentions", "@")

    eq(labels(list), { "@ada" }, "the assignees")
    eq(list.items[1].documentation.value, "# ada\n\nAda Lovelace", "with the full name")
    eq(log(), { API .. "assignees Authorization: token secret" }, "curl sends the token")
    eq(#gitea:_entry("mentions", REMOTE):get(), 1, "the mentions are cached")
end

T["an_invalid_token_falls_back_to_curl_without_a_token"] = function()
    vim.env.GITEA_TOKEN = "bad"
    local log = fake_gitea_api.curl()

    eq(labels(complete(source(), "complete_issues", "#")), { "#1: An issue" }, "the public issues")
    eq(log(), { ISSUES_URL .. " Authorization: token bad", ISSUES_URL .. " " }, "with the token, then without")
end

T["an_http_remote_uses_plain_http"] = function()
    local log = fake_gitea_api.curl()
    local remote = { host = "127.0.0.1:3000", owner = "owner", repo = "repo", scheme = "http" }

    complete(source({ hosts = { "127.0.0.1:3000" } }), "complete_issues", "#", remote)

    eq(
        log(),
        { "http://127.0.0.1:3000/api/v1/repos/owner/repo/issues?state=open&type=issues&limit=50&page=1 " },
        "the API URL of an http remote"
    )
end

T["stale_items_refresh_in_the_background"] = function()
    local log = fake_gitea_api.curl()
    local gitea = Gitea.new(config.normalize({}).gitea, { ttl = 60 })
    local entry = gitea:_entry("issues", REMOTE)
    entry:set({ { number = 9, title = "An old issue", body = "", updated_at = "2024-01-01T00:00:00Z" } })
    entry.fetched_at = os.time() - 60

    eq(labels(complete(gitea, "complete_issues", "#")), { "#9: An old issue" }, "the stale items at once")
    helpers.wait_for(function()
        return not entry.refreshing
    end, "the refresh ends")

    eq(log(), { ISSUES_URL .. " " }, "the refresh runs curl")
    eq(labels(complete(gitea, "complete_issues", "#")), { "#1: An issue" }, "the next request gets the new items")
end

return T
