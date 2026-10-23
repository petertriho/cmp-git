local helpers = require("tests.helpers")
local config = require("cmp_git.config")
local gitea_api = require("cmp_git.provider.adapters.gitea_api")

local eq = helpers.eq

local T = helpers.new_set()

local remote = { host = "gitea.com", owner = "owner", repo = "repo" }
local defaults = config.normalize({}).gitea

---An adapter whose provider gives one command before curl, and records the paths that it gets.
---@return table adapter
---@return string[] paths
local function adapter()
    local paths = {}
    return gitea_api.adapter({
        token_env = "GITEA_TOKEN",
        commands = function(_, path)
            table.insert(paths, path)
            return { { exec = "tea", args = { "api", "/" .. path } } }
        end,
    }),
        paths
end

---@param spec cmp_git.CommandSpec
---@return string url The last argument.
local function url(spec)
    return spec.args[#spec.args]
end

T["api_url"] = function()
    local cases = {
        { remote, "https://gitea.com/api/v1/x", "an SSH remote uses HTTPS" },
        { vim.tbl_extend("force", remote, { scheme = "https" }), "https://gitea.com/api/v1/x", "an https remote" },
        { { host = "127.0.0.1:3000", scheme = "http" }, "http://127.0.0.1:3000/api/v1/x", "an http remote" },
        { { host = "example.com/gitea", scheme = "https" }, "https://example.com/gitea/api/v1/x", "a path prefix" },
        { { host = "example.com:8443/gitea" }, "https://example.com:8443/gitea/api/v1/x", "a port and a prefix" },
    }

    for _, case in ipairs(cases) do
        eq(gitea_api.api_url(case[1], "x"), case[2], case[3])
    end
end

T["issues_request"] = function()
    local gitea, paths = adapter()
    local request = gitea.issues_request(remote, "#", defaults.issues)

    local path = "repos/owner/repo/issues?state=open&type=issues&limit=50&page=1"
    eq(paths, { path }, "the provider gets the API path")
    eq(#request.commands, 2, "the provider command, then curl without a token")
    eq(request.commands[1].args, { "api", "/" .. path }, "the provider command comes first")
    eq(request.commands[2], {
        exec = "curl",
        args = { "-s", "-S", "--fail", "-L", "https://gitea.com/api/v1/" .. path },
    }, "curl without a token has no header and no stdin")
end

T["change_requests_request"] = function()
    local gitea = adapter()
    local request = gitea.change_requests_request(
        { host = "127.0.0.1:3000", owner = "owner", repo = "repo", scheme = "http" },
        "!",
        config.normalize({ gitea = { pull_requests = { state = "all", limit = 7 } } }).gitea.pull_requests
    )

    eq(
        url(request.commands[2]),
        "http://127.0.0.1:3000/api/v1/repos/owner/repo/issues?state=all&type=pulls&limit=7&page=1",
        "the pull requests of the issues API, with the state and the limit of the config"
    )
end

T["the_token_variable_adds_curl_with_the_token"] = function()
    vim.env.GITEA_TOKEN = "secret"
    local gitea = adapter()
    local requests = {
        issues = gitea.issues_request(remote, "#", defaults.issues),
        pull_requests = gitea.change_requests_request(remote, "#", defaults.pull_requests),
        mentions = gitea.mentions_request(remote, "@", defaults.mentions),
    }

    for name, request in pairs(requests) do
        local curl = request.commands[2]
        eq(curl.stdin, "Authorization: token secret\n", name .. ": curl reads the token header from stdin")
        eq(vim.list_slice(curl.args, 1, 6), { "-s", "-S", "--fail", "-L", "-H", "@-" }, name .. ": headers from stdin")
        for _, arg in ipairs(curl.args) do
            eq(arg:find("secret", 1, true), nil, name .. ": the token is not an argument")
        end
    end
    eq(#requests.issues.commands, 3, "issues: then curl without a token")
    eq(requests.issues.commands[3].stdin, nil, "the last command has no token")
    eq(#requests.mentions.commands, 2, "mentions: no curl without a token")
end

T["an_empty_token_variable_is_not_a_token"] = function()
    vim.env.GITEA_TOKEN = ""
    local request = adapter().issues_request(remote, "#", defaults.issues)

    eq(#request.commands, 2, "the provider command and curl without a token")
    eq(request.commands[2].stdin, nil, "no empty token header")
end

T["mentions_request"] = function()
    local gitea = adapter()
    local request = gitea.mentions_request(remote, "@", defaults.mentions, { page = 1, page_size = 100 })

    eq(request.commands[1].args, { "api", "/repos/owner/repo/assignees" }, "the assignees of the repository")
    eq(#request.commands, 1, "the assignees API needs a token, so there is no curl without one")
    eq(gitea.mentions_has_more(), false, "one page of mentions")
    eq(
        request.handle_item({ login = "ada", full_name = vim.NIL }).documentation.value,
        "# ada\n\n",
        "a null full name is empty"
    )
end

T["the_owner_and_the_repository_are_url_encoded"] = function()
    local gitea, paths = adapter()
    gitea.issues_request({ host = "gitea.com", owner = "a/b", repo = "r#1" }, "#", defaults.issues)

    eq(paths[1]:match("^repos/[^?]+"), "repos/a%2Fb/r%231/issues", "the owner and the repository")
end

T["handle_item_fills_null_text_and_removes_carriage_returns"] = function()
    local request = adapter().issues_request(remote, "#", defaults.issues)

    local item = request.handle_item({ number = 1, title = vim.NIL, body = vim.NIL, updated_at = vim.NIL })
    for _, text in ipairs({ item.label, item.filterText, item.insertText, item.documentation.value }) do
        eq(text:find("vim.NIL", 1, true), nil, "no vim.NIL text in " .. vim.inspect(text))
    end
    eq(item.label, "#1: ", "a null title is empty")

    local crlf = request.handle_item({ number = 2, title = "t", body = "line 1\r\nline 2", updated_at = "" })
    eq(crlf.data.body, "line 1\nline 2", "the body has no carriage returns")
end

return T
