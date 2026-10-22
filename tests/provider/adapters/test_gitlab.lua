local helpers = require("tests.helpers")
local adapter = require("cmp_git.provider.adapters.gitlab")
local config = require("cmp_git.config")

local eq = helpers.eq

local T = helpers.new_set()

local gitlab = { host = "gitlab.com", owner = "group/subgroup", repo = "project" }
local self_hosted = { host = "gitlab.example.com", owner = "group", repo = "project" }

---@param overrides? table
local function gitlab_config(overrides)
    return config.normalize({ gitlab = overrides }).gitlab
end

T["issues_request"] = function()
    local request = adapter.issues_request(gitlab, "#", gitlab_config().issues)
    local glab, curl = request.commands[1], request.commands[2]

    eq(#request.commands, 2, "glab first, then the curl fallback")
    eq(glab.exec, "glab", "glab command")
    eq(glab.args, { "api", "/projects/group%2Fsubgroup%2Fproject/issues?per_page=100&state=opened" }, "glab arguments")
    eq(glab.env.NO_COLOR, 1, "glab output has no colors")
    eq(curl.exec, "curl", "curl command")
    eq(curl.args, {
        "-s",
        "https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/issues?per_page=100&state=opened",
    }, "curl arguments")
end

T["change_requests_request"] = function()
    local request = adapter.change_requests_request(
        self_hosted,
        "!",
        gitlab_config({
            merge_requests = { state = "merged", limit = 3 },
        }).merge_requests
    )

    eq(request.commands[1].args, { "api", "/projects/group%2Fproject/merge_requests?per_page=3&state=merged" }, "glab")
    eq(request.commands[1].env.NO_COLOR, 1, "glab output has no colors")
    eq(request.commands[2].args, {
        "-s",
        "https://gitlab.example.com/api/v4/projects/group%2Fproject/merge_requests?per_page=3&state=merged",
    }, "curl arguments for a self-hosted host")
end

T["mentions_request"] = function()
    local request = adapter.mentions_request(gitlab, "@", gitlab_config({ mentions = { limit = 20 } }).mentions)

    eq(request.commands[1].args, { "api", "/projects/group%2Fsubgroup%2Fproject/users?per_page=20" }, "glab")
    eq(request.commands[1].env.NO_COLOR, 1, "glab output has no colors")
    eq(request.commands[2].args, {
        "-s",
        "https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/users?per_page=20",
    }, "curl arguments")
    eq(adapter.mentions_has_more(), false, "one page of mentions")
    eq(request.handle_item({ username = "ada", name = "Ada" }).label, "@ada", "mention item")
end

T["issue_state_and_limit"] = function()
    local request =
        adapter.issues_request(gitlab, "#", gitlab_config({ issues = { state = "closed", limit = 5 } }).issues)

    eq(request.commands[1].args[2], "/projects/group%2Fsubgroup%2Fproject/issues?per_page=5&state=closed", "glab")
    eq(
        request.commands[2].args[2],
        "https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/issues?per_page=5&state=closed",
        "curl"
    )
end

T["token_header"] = function()
    vim.env.GITLAB_TOKEN = "secret"
    local request = adapter.issues_request(gitlab, "#", gitlab_config().issues)

    eq(request.commands[1].env.GITLAB_TOKEN, "secret", "glab gets the token")
    eq(request.commands[2].args[3], "-H", "curl header flag")
    eq(request.commands[2].args[4], "Authorization: Bearer secret", "curl sends the token")
end

T["handle_item_fills_null_description"] = function()
    local request = adapter.issues_request(gitlab, "#", gitlab_config().issues)
    local item = request.handle_item({
        iid = 3,
        title = "t",
        description = vim.NIL,
        updated_at = "2024-01-01T00:00:00.000Z",
    })

    eq(item.label, "#3: t", "item label")
    eq(item.data.description, "", "a null description is empty")
end

return T
