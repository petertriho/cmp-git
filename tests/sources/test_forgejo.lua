local helpers = require("tests.helpers")
local fake_gitea_api = require("tests.sources.fake_gitea_api")
local config = require("cmp_git.config")
local Forgejo = require("cmp_git.sources.forgejo")

local eq = helpers.eq
local ok = helpers.ok

local T = helpers.new_set()

local REMOTE = { host = "codeberg.org", owner = "owner", repo = "repo" }
local API = "https://codeberg.org/api/v1/repos/owner/repo/"
local ISSUES_URL = API .. "issues?state=open&type=issues&limit=50&page=1"
local PULLS_URL = API .. "issues?state=open&type=pulls&limit=50&page=1"

---@param overrides? table
---@return cmp_git.Source.GiteaApi
local function source(overrides)
    return Forgejo.new(config.normalize({ forgejo = overrides }).forgejo)
end

---Run a request of the source and return the labels of its final list.
---@param forgejo cmp_git.Source.GiteaApi
---@param method string
---@param trigger_char string
---@return string[]
local function complete(forgejo, method, trigger_char)
    local callback, lists = helpers.recorder()
    eq(forgejo[method](forgejo, callback, REMOTE, trigger_char), true, method .. " handles the host")
    helpers.wait_for(function()
        return #lists > 0
    end, method .. " answers")
    return vim.tbl_map(function(item)
        return item.label
    end, lists[1].items)
end

T["forgejo_hosts"] = function()
    local forgejo = source({ hosts = { "forgejo.example.com:3000" } })

    ok(forgejo:is_valid_host(REMOTE), "codeberg.org by default")
    ok(forgejo:is_valid_host({ host = "forgejo.example.com:3000", owner = "o", repo = "r" }), "a host with a port")
    ok(not forgejo:is_valid_host({ host = "gitea.com", owner = "o", repo = "r" }), "a Gitea host")
end

T["the_forgejo_token_variable_gives_the_items"] = function()
    vim.env.FORGEJO_TOKEN = "secret"
    vim.env.GITEA_TOKEN = "gitea"
    local log = fake_gitea_api.curl()
    local forgejo = source()

    eq(complete(forgejo, "complete_issues_and_change_requests", "#"), { "#1: An issue", "#2: A pull request" }, "#")
    eq(complete(forgejo, "complete_mentions", "@"), { "@ada" }, "the assignees")

    local runs = log()
    table.sort(runs)
    eq(runs, {
        API .. "assignees Authorization: token secret",
        ISSUES_URL .. " Authorization: token secret",
        PULLS_URL .. " Authorization: token secret",
    }, "curl sends FORGEJO_TOKEN, not GITEA_TOKEN")
    ok(forgejo:_entry("issues", REMOTE).path:find("/forgejo%-issues%-") ~= nil, "the items are in the forgejo files")
end

T["without_a_token_the_public_items_come_from_curl"] = function()
    local log = fake_gitea_api.curl()
    local forgejo = source()

    eq(complete(forgejo, "complete_change_requests", "!"), { "!2: A pull request" }, "the pull requests")
    eq(complete(forgejo, "complete_mentions", "@"), {}, "no mentions without a token")
    eq(log(), { PULLS_URL .. " " }, "one request without a token, and none for the mentions")
end

return T
