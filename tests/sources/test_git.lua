local helpers = require("tests.helpers")
local config = require("cmp_git.config")
local Git = require("cmp_git.sources.git")

local eq = helpers.eq
local ok = helpers.ok

local T = helpers.new_set()

T["git_instance_state_isolation"] = function()
    local first = Git.new(config.normalize({}).git)
    local second = Git.new(config.normalize({}).git)

    first.cache_commits[1] = { { label = "first" } }

    eq(second.cache_commits[1], nil, "Git commit cache is instance-local")
    ok(first.cache_commits ~= second.cache_commits, "Git commit cache table is instance-local")
    ok(first.cache_trailer_keys ~= second.cache_trailer_keys, "Git trailer key cache is instance-local")
    ok(
        first.cache_trailer_identities ~= second.cache_trailer_identities,
        "Git trailer identities cache is instance-local"
    )
    ok(first.cache_trailer_values ~= second.cache_trailer_values, "Git trailer values cache is instance-local")
end

---Starts the requests that a commit message buffer can make, and records the lists that each one gives.
---@param git cmp_git.Source.Git
---@return table<string, cmp_git.CompletionList[]> lists
local function request_all(git)
    local bufnr = helpers.buffer({ "feat: subject", "", "" })
    local lists = { commits = {}, keys = {}, identities = {}, values = {} }
    local function context(line)
        return { bufnr = bufnr, cursor = { row = 3, character = #line }, line = line }
    end
    local function record(name)
        return function(list)
            table.insert(lists[name], list)
        end
    end

    ok(git:get_commits(record("commits"), context("See :"), ":"), "commits are handled")
    ok(git:get_trailer_keys(record("keys"), context("Si")), "trailer keys are handled")
    ok(git:get_trailer_identities(record("identities"), context("Co-authored-by: Te")), "identities are handled")
    ok(git:get_trailer_values(record("values"), context("Assisted-by: C")), "trailer values are handled")
    return lists
end

---@param list cmp_git.CompletionList
---@return string[]
local function labels(list)
    local result = {}
    for _, item in ipairs(list.items) do
        table.insert(result, item.label)
    end
    return result
end

T["git_requests_answer_in_a_repository_without_commits"] = function()
    if vim.fn.executable("git") ~= 1 then
        helpers.skip("git is not installed")
    end

    local repo = helpers.git_repo()
    vim.env.GIT_AUTHOR_NAME = "Test Self"
    vim.env.GIT_AUTHOR_EMAIL = "self@example.com"
    vim.fn.chdir(repo.dir)

    local git_config = config.normalize({}).git
    local git = Git.new(git_config)
    local lists = request_all(git)
    helpers.wait_for(function()
        return #lists.commits > 0 and #lists.keys > 0 and #lists.identities > 0 and #lists.values > 0
    end, "each request calls back")
    helpers.flush()

    eq(lists.commits, { { items = {}, isIncomplete = false } }, "commits give one final empty list")
    eq(#lists.keys, 1, "trailer keys call back once")
    eq(#lists.keys[1].items, #git_config.trailers.keys.builtin, "trailer keys give the built-in keys")
    eq(#lists.identities, 1, "identities call back once")
    eq(labels(lists.identities[1]), { "Test Self <self@example.com>" }, "identities give your identity")
    eq(lists.values, { { items = {}, isIncomplete = false } }, "trailer values give one final empty list")

    eq(next(git.cache_commits), nil, "commits are not cached")
    eq(next(git.cache_trailer_keys), nil, "trailer keys are not cached")
    eq(next(git.cache_trailer_identities), nil, "identities are not cached")
    eq(next(git.cache_trailer_values), nil, "trailer values are not cached")
end

T["git_requests_answer_without_git"] = function()
    -- `command.build` gives no job when git is not installed
    helpers.stub(vim.fn, "executable", function()
        return 0
    end)

    local git_config = config.normalize({}).git
    local lists = request_all(Git.new(git_config))

    eq(lists.commits, { { items = {}, isIncomplete = false } }, "commits give one final empty list")
    eq(#lists.keys, 1, "trailer keys call back once")
    eq(#lists.keys[1].items, #git_config.trailers.keys.builtin, "trailer keys give the built-in keys")
    eq(lists.identities, { { items = {}, isIncomplete = false } }, "identities give one final empty list")
    eq(lists.values, { { items = {}, isIncomplete = false } }, "trailer values give one final empty list")
end

return T
