local helpers = require("tests.helpers")
local adapter = require("cmp_git.provider.adapters.github")
local command = require("cmp_git.command")
local config = require("cmp_git.config")

local eq = helpers.eq

local T = helpers.new_set()

local github = { host = "github.com", owner = "owner", repo = "repo" }
local enterprise = { host = "github.example.com", owner = "owner", repo = "repo" }

---@param overrides? table
local function github_config(overrides)
    return config.normalize({ github = overrides }).github
end

---@param spec cmp_git.CommandSpec
---@return string?
local function curl_url(spec)
    for _, arg in ipairs(spec.args) do
        if arg:match("^https://") then
            return arg
        end
    end
end

---@param spec cmp_git.CommandSpec
---@param name string
---@return string?
local function curl_header(spec, name)
    for i = 2, #spec.args do
        if spec.args[i - 1] == "-H" then
            local header, value = spec.args[i]:match("^([^:]+): (.*)$")
            if header == name then
                return value
            end
        end
    end
end

T["issues_request"] = function()
    local request = adapter.issues_request(github, "#", github_config().issues)
    local gh, curl = request.commands[1], request.commands[2]

    eq(#request.commands, 2, "gh first, then the curl fallback")
    eq(gh.exec, "gh", "gh command")
    eq(gh.args, {
        "issue",
        "list",
        "--repo",
        "github.com/owner/repo",
        "--limit",
        100,
        "--state",
        "open",
        "--json",
        "title,number,body,updatedAt,state",
    }, "gh issue arguments")
    eq(gh.env.CLICOLOR, 0, "gh output has no colors")
    eq(curl.exec, "curl", "curl command")
    eq(curl.args[1], "-s", "curl is silent")
    eq(curl_header(curl, "Accept"), "application/vnd.github.v3+json", "curl asks for the v3 API")
    eq(
        curl_url(curl),
        "https://api.github.com/repos/owner/repo/issues?state=open&per_page=100&page=1",
        "curl issue URL"
    )
end

T["change_requests_request"] = function()
    local request = adapter.change_requests_request(
        github,
        "#",
        github_config({
            pull_requests = { state = "merged", limit = 3 },
        }).pull_requests
    )

    eq(request.commands[1].args, {
        "pr",
        "list",
        "--repo",
        "github.com/owner/repo",
        "--limit",
        3,
        "--state",
        "merged",
        "--json",
        "title,number,body,updatedAt,state",
    }, "gh pull request arguments")
    eq(request.commands[1].env.CLICOLOR, 0, "gh output has no colors")
    eq(
        curl_url(request.commands[2]),
        "https://api.github.com/repos/owner/repo/pulls?state=merged&per_page=3&page=1",
        "curl pull request URL"
    )
end

T["enterprise_host"] = function()
    local issues = adapter.issues_request(enterprise, "#", github_config().issues)
    local pulls = adapter.change_requests_request(enterprise, "#", github_config().pull_requests)

    eq(issues.commands[1].args[4], "github.example.com/owner/repo", "gh repository includes the host")
    eq(
        curl_url(issues.commands[2]),
        "https://github.example.com/api/v3/repos/owner/repo/issues?state=open&per_page=100&page=1",
        "curl issue URL for an enterprise host"
    )
    eq(
        curl_url(pulls.commands[2]),
        "https://github.example.com/api/v3/repos/owner/repo/pulls?state=open&per_page=100&page=1",
        "curl pull request URL for an enterprise host"
    )
end

---The requests that run curl, so that a case can check each of them.
---@return table<string, table>
local function all_requests()
    return {
        issues = adapter.issues_request(github, "#", github_config().issues),
        change_requests = adapter.change_requests_request(github, "#", github_config().pull_requests),
        preflight = adapter.mentions_preflight_request(github),
        mentions = adapter.mentions_request(github, "@", github_config().mentions, { page = 1, page_size = 100 }),
    }
end

T["token_header"] = function()
    local request = adapter.issues_request(github, "#", github_config().issues)
    eq(curl_header(request.commands[2], "Authorization"), nil, "no token, no header")
    eq(request.commands[2].stdin, nil, "no token, no stdin")
    eq(request.commands[1].env.GITHUB_API_TOKEN, nil, "no token for gh")

    vim.env.GITHUB_API_TOKEN = "secret"
    for name, token_request in pairs(all_requests()) do
        local curl = token_request.commands[2]
        eq(curl.stdin, "Authorization: token secret\n", name .. ": curl reads the token header from stdin")
        eq(curl_header(curl, "Authorization"), nil, name .. ": the token is not an argument")
        eq(vim.tbl_contains(curl.args, "@-"), true, name .. ": curl reads headers from stdin")
        eq(token_request.commands[1].env.GITHUB_API_TOKEN, "secret", name .. ": gh gets the token")
    end
end

T["curl_fails_on_http_errors"] = function()
    for name, request in pairs(all_requests()) do
        -- The preflight reads the status of the error body
        eq(vim.tbl_contains(request.commands[2].args, "--fail"), name ~= "preflight", name .. ": --fail")
    end
end

T["error_and_null_responses_are_not_lists"] = function()
    local requests = all_requests()

    eq(requests.mentions.handle_parsed(vim.NIL), vim.NIL, "a null mention response stays null")
    eq(requests.preflight.handle_result("null"), { member_type = "contributors" }, "a null preflight falls back")
    eq(requests.preflight.handle_result("[]"), { member_type = "collaborators" }, "a list is not an error")
end

T["token_reaches_curl_on_stdin"] = function()
    local bin = helpers.tempdir()
    local file = assert(io.open(bin .. "/curl", "w"))
    -- Prints the arguments on the first line, then stdin
    file:write('#!/bin/sh\nprintf "%s\\n" "$*"\ncat\n')
    file:close()
    vim.uv.fs_chmod(bin .. "/curl", tonumber("755", 8))
    helpers.stub(vim.env, "PATH", bin .. ":" .. vim.env.PATH)
    vim.env.GITHUB_API_TOKEN = "secret"

    local output
    local curl = adapter.issues_request(github, "#", github_config().issues).commands[2]
    local job = helpers.not_nil(command.build(curl, function(stdout)
        output = stdout
    end))
    job:start()
    helpers.wait_for(function()
        return output ~= nil
    end, "the command completes")

    local lines = vim.split(output, "\n", { trimempty = true })
    eq(lines[1]:find("secret", 1, true), nil, "the arguments have no token")
    eq(lines[2], "Authorization: token secret", "stdin has the token header")
end

T["unset_token_does_not_reach_gh"] = function()
    local gh = adapter.issues_request(github, "#", github_config().issues).commands[1]
    local seen
    local job = helpers.not_nil(
        command.build(
            { exec = "sh", args = { "-c", 'printf "%s" "${GITHUB_API_TOKEN-unset}"' }, env = gh.env },
            function(stdout)
                seen = stdout
            end
        )
    )
    job:start()
    helpers.wait_for(function()
        return seen ~= nil
    end, "the command completes")

    eq(seen, "unset", "the gh environment has no GITHUB_API_TOKEN")
end

T["issue_state_limit_and_filter"] = function()
    local cases = {
        { filter = "all", gh = {}, query = "" },
        { filter = "mentioned", gh = { "--mention", "@me" }, query = "&mentioned=@me" },
        { filter = "assigned", gh = { "--assignee", "@me" }, query = "&assignee=@me" },
        { filter = "created", gh = { "--author", "@me" }, query = "&creator=@me" },
    }

    for _, case in ipairs(cases) do
        local issues_config = github_config({ issues = { filter = case.filter, state = "closed", limit = 7 } }).issues
        local request = adapter.issues_request(github, "#", issues_config)

        eq(
            request.commands[1].args,
            vim.list_extend({
                "issue",
                "list",
                "--repo",
                "github.com/owner/repo",
                "--limit",
                7,
                "--state",
                "closed",
                "--json",
                "title,number,body,updatedAt,state",
            }, case.gh),
            case.filter .. " gh arguments"
        )
        eq(
            curl_url(request.commands[2]),
            "https://api.github.com/repos/owner/repo/issues?state=closed&per_page=7&page=1" .. case.query,
            case.filter .. " curl URL"
        )
    end
end

T["mentions_preflight_request"] = function()
    local preflight = adapter.mentions_preflight_request(enterprise)

    eq(preflight.commands[1].args, {
        "api",
        "repos/owner/repo/collaborators/testing/permission",
        "--hostname",
        "github.example.com",
    }, "gh preflight arguments")
    eq(preflight.commands[1].env.CLICOLOR, 0, "gh output has no colors")
    eq(
        curl_url(preflight.commands[2]),
        "https://github.example.com/api/v3/repos/owner/repo/collaborators/testing/permission",
        "curl preflight URL"
    )
    eq(preflight.handle_result('{"status":"404"}'), { member_type = "collaborators" }, "a collaborator can list")
    eq(preflight.handle_result('{"status":"403"}'), { member_type = "contributors" }, "403 falls back")
    eq(preflight.handle_result('{"status":"401"}'), { member_type = "contributors" }, "401 falls back")
    eq(preflight.handle_result("not json"), { member_type = "contributors" }, "invalid JSON falls back")
end

T["mentions_request"] = function()
    local request = adapter.mentions_request(github, "@", github_config().mentions, {
        context = { member_type = "collaborators" },
        page = 2,
        page_size = 50,
    })

    eq(request.commands[1].args, {
        "api",
        "repos/owner/repo/collaborators?per_page=50&page=2",
        "--hostname",
        "github.com",
    }, "gh mention arguments")
    eq(request.commands[1].env.CLICOLOR, 0, "gh output has no colors")
    eq(
        curl_url(request.commands[2]),
        "https://api.github.com/repos/owner/repo/collaborators?per_page=50&page=2",
        "curl mention URL"
    )
    eq(
        curl_url(
            adapter.mentions_request(enterprise, "@", github_config().mentions, { page = 1, page_size = 100 }).commands[2]
        ),
        "https://github.example.com/api/v3/repos/owner/repo/contributors?per_page=100&page=1",
        "curl mention URL for an enterprise host"
    )

    local without_context = adapter.mentions_request(github, "@", github_config().mentions, {
        page = 1,
        page_size = 100,
    })
    eq(
        without_context.commands[1].args[2],
        "repos/owner/repo/contributors?per_page=100&page=1",
        "contributors without a preflight context"
    )

    eq(request.handle_parsed({ mentionableUsers = { "graphql" } }), { "graphql" }, "GraphQL mention shape")
    eq(request.handle_parsed({ "rest" }), { "rest" }, "REST mention shape")
    eq(request.handle_item({ login = "octocat" }).label, "@octocat", "mention item")
end

T["issues_request_drops_pull_requests"] = function()
    local request = adapter.issues_request(github, "#", github_config().issues)

    eq(
        request.handle_parsed({ { number = 1 }, { number = 2, pull_request = { url = "u" } }, { number = 3 } }),
        { { number = 1 }, { number = 3 } },
        "the REST issues endpoint also returns pull requests"
    )
    eq(request.handle_parsed({ message = "Not Found" }), nil, "an error response is not a list")
    eq(request.handle_parsed(vim.NIL), nil, "a null response is not a list")
end

T["handle_item_normalizes_body"] = function()
    local request = adapter.issues_request(github, "#", github_config().issues)

    local item = request.handle_item({ number = 1, title = "t", body = "a\r\nb", updated_at = "2024-01-01T00:00:00Z" })
    eq(item.label, "#1: t", "item label")
    eq(item.data.body, "a\nb", "body without carriage returns")
    eq(item.data.updatedAt, "2024-01-01T00:00:00Z", "curl updated_at fills updatedAt")

    local null_body =
        request.handle_item({ number = 2, title = "t", body = vim.NIL, updatedAt = "2024-01-01T00:00:00Z" })
    eq(null_body.data.body, "", "a null body is empty")
end

T["handle_item_fills_null_text"] = function()
    local requests = all_requests()
    for _, name in ipairs({ "issues", "change_requests" }) do
        local item = requests[name].handle_item({
            number = 3,
            title = vim.NIL,
            body = vim.NIL,
            updated_at = "2024-01-01T00:00:00Z",
        })
        eq(item.label, "#3: ", name .. ": a null title is empty")
        eq(item.documentation.value, "# \n\n", name .. ": the documentation has no vim.NIL text")
    end
end

return T
