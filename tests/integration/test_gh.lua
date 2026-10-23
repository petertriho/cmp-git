-- The real gh against a fake server on a Unix socket. gh 2.102.0 sends `gh issue list --json` as the GraphQL query
-- `IssueList` and `gh pr list --json` as `PullRequestList`, and reads `data.repository.issues` and
-- `data.repository.pullRequests`. A gh update that changes these needs new canned answers.
local helpers = require("tests.helpers")
local integration = require("tests.integration.helpers")
local config = require("cmp_git.config")
local GitHub = require("cmp_git.sources.github")

local eq = helpers.eq

local T = helpers.new_set()

local ISSUES = {
    { title = "Crash on start", number = 12, body = "Steps", updatedAt = "2026-01-02T00:00:00Z", state = "OPEN" },
}
local PULL_REQUESTS = {
    { title = "Fix the crash", number = 34, body = "Fixes #12", updatedAt = "2026-01-03T00:00:00Z", state = "OPEN" },
}

---@param nodes table[]
local function connection(nodes)
    return { totalCount = #nodes, nodes = nodes, pageInfo = { hasNextPage = false, endCursor = "" } }
end

---The GraphQL route. It answers the issue and pull request lists of gh, and records their variables.
---@param variables table[] Gets the variables of each query.
---@return tests.integration.Route
local function graphql(variables)
    return function(request)
        local payload = vim.json.decode(request.body)
        table.insert(variables, payload.variables)
        if string.find(payload.query, "query IssueList", 1, true) then
            return { body = { data = { repository = { hasIssuesEnabled = true, issues = connection(ISSUES) } } } }
        end
        if string.find(payload.query, "query PullRequestList", 1, true) then
            return { body = { data = { repository = { pullRequests = connection(PULL_REQUESTS) } } } }
        end
        return { status = 400, body = { message = "Unknown query" } }
    end
end

---A fake GitHub API for gh, and a buffer outside a repository.
---@return tests.integration.HttpServer server
---@return integer bufnr
local function github_server()
    integration.require_binaries({ "gh" })
    local server = integration.http_server({ socket = helpers.tempdir() .. "/gh.sock" })
    helpers.defer(function()
        server:close()
    end)
    integration.use_gh(server)
    integration.offline_curl()
    return server, integration.edit_outside_repository()
end

---Run a request of the source and wait for its final list.
---@param source cmp_git.Source.GitHub
---@param method string
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@param bufnr integer
---@return cmp_git.CompletionList
local function complete(source, method, git_info, trigger_char, bufnr)
    local callback, lists = helpers.recorder()
    eq(source[method](source, callback, git_info, trigger_char, bufnr), true, method .. " handles the host")
    helpers.wait_for(function()
        return #lists > 0 and not lists[#lists].isIncomplete
    end, method .. " answers")
    return lists[#lists]
end

---@param list cmp_git.CompletionList
---@return string[]
local function labels(list)
    return vim.tbl_map(function(item)
        return item.label
    end, list.items)
end

local REMOTE = { host = "github.com", owner = "owner", repo = "repo" }

T["issues_and_pull_requests_come_from_the_graphql_api"] = function()
    local server, bufnr = github_server()
    local variables = {}
    server.routes["POST /graphql"] = graphql(variables)
    local source = GitHub.new(config.normalize({}).github)

    local list = complete(source, "complete_issues_and_change_requests", REMOTE, "#", bufnr)

    eq(labels(list), { "#12: Crash on start", "#34: Fix the crash" }, "the issues, then the pull requests")
    eq(list.items[2].documentation.value, "# Fix the crash\n\nFixes #12", "the body of the pull request")
    eq(server:request_lines(), { "POST /graphql", "POST /graphql" }, "one query for each list")
    table.sort(variables, function(a, b)
        return a.states ~= nil and b.states == nil
    end)
    eq(variables, {
        { limit = 100, owner = "owner", repo = "repo", states = { "OPEN" } },
        { limit = 100, owner = "owner", repo = "repo", state = { "OPEN" } },
    }, "the repository, the limit, and the state of each list")
    eq(server.requests[1].headers.authorization, "token gh-token", "gh sends its token")
end

T["the_state_and_the_limit_reach_gh"] = function()
    local server, bufnr = github_server()
    local variables = {}
    server.routes["POST /graphql"] = graphql(variables)
    local source = GitHub.new(config.normalize({
        github = { issues = { state = "closed", limit = 5 }, pull_requests = { state = "merged", limit = 7 } },
    }).github)

    eq(labels(complete(source, "complete_issues", REMOTE, "#", bufnr)), { "#12: Crash on start" }, "the issues")
    eq(labels(complete(source, "complete_change_requests", REMOTE, "#", bufnr)), { "#34: Fix the crash" }, "the PRs")

    eq(variables, {
        { limit = 5, owner = "owner", repo = "repo", states = { "CLOSED" } },
        { limit = 7, owner = "owner", repo = "repo", state = { "MERGED" } },
    }, "gh sends the state and the limit of the config")
end

---@param count integer
---@param first integer The number in the first login.
---@return table[]
local function users(count, first)
    local result = {}
    for i = 1, count do
        table.insert(result, { login = string.format("user%03d", first + i - 1) })
    end
    return result
end

T["mentions_come_from_the_collaborators_in_pages"] = function()
    local server, bufnr = github_server()
    server.routes["GET /repos/owner/repo/collaborators/testing/permission"] = { body = { permission = "admin" } }
    server.routes["GET /repos/owner/repo/collaborators"] = function(request)
        return { body = request.query.page == "1" and users(100, 1) or users(1, 101) }
    end
    local source = GitHub.new(config.normalize({ github = { mentions = { limit = math.huge } } }).github)

    local list = complete(source, "complete_mentions", REMOTE, "@", bufnr)

    eq(#list.items, 101, "the users of both pages")
    eq({ list.items[1].label, list.items[101].label }, { "@user001", "@user101" }, "in the order of the pages")
    eq(server:request_lines(), {
        "GET /repos/owner/repo/collaborators/testing/permission",
        "GET /repos/owner/repo/collaborators?per_page=100&page=1",
        "GET /repos/owner/repo/collaborators?per_page=100&page=2",
    }, "the preflight, then a request for each page")
end

T["mentions_come_from_the_contributors_when_the_preflight_fails"] = function()
    local server, bufnr = github_server()
    server.routes["GET /repos/owner/repo/collaborators/testing/permission"] = {
        status = 403,
        body = { message = "Must have push access to view collaborator permission.", status = "403" },
    }
    server.routes["GET /repos/owner/repo/contributors"] = { body = users(2, 1) }
    local source = GitHub.new(config.normalize({}).github)

    local list = complete(source, "complete_mentions", REMOTE, "@", bufnr)

    eq(labels(list), { "@user001", "@user002" }, "the contributors")
    eq(server:request_lines(), {
        "GET /repos/owner/repo/collaborators/testing/permission",
        "GET /repos/owner/repo/contributors?per_page=100&page=1",
    }, "the preflight, then the contributors")
end

T["the_default_repository_of_gh_needs_no_server"] = function()
    local server = github_server()
    local variables = {}
    server.routes["POST /graphql"] = graphql(variables)
    local repo = helpers.git_repo({
        remotes = {
            { "origin", "https://github.com/owner/repo.git" },
            { "upstream", "https://github.com/upstream/project.git" },
        },
    })
    -- What `gh repo set-default upstream/project` writes
    repo.git("config", "remote.upstream.gh-resolved", "base")
    vim.cmd.edit(vim.fn.fnameescape(repo.dir .. "/COMMIT_EDITMSG"))
    local source = GitHub.new(config.normalize({}).github)

    local list = complete(source, "complete_issues", REMOTE, "#", vim.api.nvim_get_current_buf())

    eq(labels(list), { "#12: Crash on start" }, "the issues")
    eq(server:request_lines(), { "POST /graphql" }, "gh reads the default repository without a request")
    eq({ variables[1].owner, variables[1].repo }, { "upstream", "project" }, "from the default repository")
end

return T
