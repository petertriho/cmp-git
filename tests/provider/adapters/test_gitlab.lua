local helpers = require("tests.helpers")
local adapter = require("cmp_git.provider.adapters.gitlab")
local command = require("cmp_git.command")
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
        "-S",
        "--fail",
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
        "-S",
        "--fail",
        "https://gitlab.example.com/api/v4/projects/group%2Fproject/merge_requests?per_page=3&state=merged",
    }, "curl arguments for a self-hosted host")
end

T["mentions_request"] = function()
    local request = adapter.mentions_request(gitlab, "@", gitlab_config({ mentions = { limit = 20 } }).mentions)

    eq(request.commands[1].args, { "api", "/projects/group%2Fsubgroup%2Fproject/users?per_page=20" }, "glab")
    eq(request.commands[1].env.NO_COLOR, 1, "glab output has no colors")
    eq(request.commands[2].args, {
        "-s",
        "-S",
        "--fail",
        "https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/users?per_page=20",
    }, "curl arguments")
    eq(adapter.mentions_has_more(), false, "one page of mentions")
    eq(request.handle_item({ username = "ada", name = "Ada" }).label, "@ada", "mention item")
end

T["issue_state_and_limit"] = function()
    local request =
        adapter.issues_request(gitlab, "#", gitlab_config({ issues = { state = "closed", limit = 5 } }).issues)

    eq(request.commands[1].args[2], "/projects/group%2Fsubgroup%2Fproject/issues?per_page=5&state=closed", "glab")
    local curl_args = request.commands[2].args
    eq(
        curl_args[#curl_args],
        "https://gitlab.com/api/v4/projects/group%2Fsubgroup%2Fproject/issues?per_page=5&state=closed",
        "curl"
    )
end

T["token_header"] = function()
    local request = adapter.issues_request(gitlab, "#", gitlab_config().issues)
    eq(request.commands[1].env.GITLAB_TOKEN, nil, "no token for glab")
    eq(vim.tbl_contains(request.commands[2].args, "-H"), false, "no token, no curl header")
    eq(request.commands[2].stdin, nil, "no token, no stdin")

    vim.env.GITLAB_TOKEN = "secret"
    local requests = {
        issues = adapter.issues_request(gitlab, "#", gitlab_config().issues),
        merge_requests = adapter.change_requests_request(gitlab, "!", gitlab_config().merge_requests),
        mentions = adapter.mentions_request(gitlab, "@", gitlab_config().mentions),
    }
    for name, token_request in pairs(requests) do
        local curl = token_request.commands[2]
        eq(token_request.commands[1].env.GITLAB_TOKEN, "secret", name .. ": glab gets the token")
        eq(curl.stdin, "Authorization: Bearer secret\n", name .. ": curl reads the token header from stdin")
        eq(vim.tbl_contains(curl.args, "@-"), true, name .. ": curl reads headers from stdin")
        for _, arg in ipairs(curl.args) do
            eq(arg:find("secret", 1, true), nil, name .. ": the token is not an argument")
        end
    end
end

T["unset_token_does_not_reach_glab"] = function()
    local glab = adapter.issues_request(gitlab, "#", gitlab_config().issues).commands[1]
    local seen
    local job = helpers.not_nil(
        command.build(
            { exec = "sh", args = { "-c", 'printf "%s" "${GITLAB_TOKEN-unset}"' }, env = glab.env },
            function(stdout)
                seen = stdout
            end
        )
    )
    job:start()
    helpers.wait_for(function()
        return seen ~= nil
    end, "the command completes")

    -- glab prefers GITLAB_TOKEN over the credentials from `glab auth login`
    eq(seen, "unset", "the glab environment has no GITLAB_TOKEN")
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

T["handle_item_fills_null_text"] = function()
    local cases = {
        issue = adapter.issues_request(gitlab, "#", gitlab_config().issues).handle_item({
            iid = 3,
            title = vim.NIL,
            description = vim.NIL,
            updated_at = "2024-01-01T00:00:00.000Z",
        }),
        merge_request = adapter.change_requests_request(gitlab, "!", gitlab_config().merge_requests).handle_item({
            iid = 4,
            title = vim.NIL,
            description = vim.NIL,
            updated_at = "2024-01-01T00:00:00.000Z",
        }),
        mention = adapter.mentions_request(gitlab, "@", gitlab_config().mentions).handle_item({
            username = "ada",
            name = vim.NIL,
        }),
    }

    for name, item in pairs(cases) do
        for _, text in ipairs({ item.label, item.filterText, item.insertText, item.documentation.value }) do
            eq(text:find("vim.NIL", 1, true), nil, name .. ": no vim.NIL text in " .. vim.inspect(text))
        end
    end
    eq(cases.merge_request.documentation.value, "# \n\n", "a merge request with a null title and description")
end

return T
