local helpers = require("tests.helpers")
local command = require("cmp_git.command")
local config = require("cmp_git.config")
local GitHub = require("cmp_git.sources.github")

local eq = helpers.eq
local ok = helpers.ok

local T = helpers.new_set()

T["github_instance_state_isolation"] = function()
    local first = GitHub.new(config.normalize({ github = { hosts = { "github.example.com" } } }).github)
    local second = GitHub.new(config.normalize({ github = { hosts = { "github.other.com" } } }).github)

    ok(
        first:is_valid_host({ host = "github.example.com", owner = "owner", repo = "repo" }),
        "first GitHub instance validates own host"
    )
    ok(
        not first:is_valid_host({ host = "github.other.com", owner = "owner", repo = "repo" }),
        "first GitHub instance rejects second host"
    )
    ok(
        second:is_valid_host({ host = "github.other.com", owner = "owner", repo = "repo" }),
        "second GitHub instance validates own host"
    )
    ok(
        second:is_valid_host({ host = "github.com", owner = "owner", repo = "repo" }),
        "GitHub instance validates default host"
    )

    first.cache.issues[1] = {}
    eq(second.cache.issues[1], nil, "GitHub issue cache is instance-local")
    ok(first.cache.mentions ~= second.cache.mentions, "GitHub mention cache table is instance-local")
    ok(first.cache.pull_requests ~= second.cache.pull_requests, "GitHub PR cache table is instance-local")
end

local git_info = { host = "github.com", owner = "owner", repo = "repo" }

---A GitHub source whose `gh` commands give one issue and one pull request. `requests` counts the commands that ran.
---@return cmp_git.Source.GitHub source
---@return { issue: integer, pr: integer } requests
local function fake_github()
    local source = GitHub.new(config.normalize({}).github)
    local requests = { issue = 0, pr = 0 }
    local records = {
        issue = { number = 1, title = "an issue", body = "", updatedAt = "2024-01-01T00:00:00Z" },
        pr = { number = 2, title = "a pull request", body = "", updatedAt = "2024-01-01T00:00:00Z" },
    }

    -- Do not run `gh repo set-default`
    helpers.stub(source, "_normalize_git_info", function(_, info)
        return info
    end)
    helpers.stub(command, "build_fallback_list", function(commands, callback, handle_item)
        local kind = commands[1].args[1]
        return {
            command = "fake",
            start = function(_, on_complete)
                requests[kind] = requests[kind] + 1
                callback({ items = { handle_item(vim.deepcopy(records[kind])) }, isIncomplete = false })
                if on_complete then
                    on_complete(true)
                end
            end,
        }
    end)

    return source, requests
end

---@param items cmp_git.CompletionItem[]
---@return string[]
local function labels(items)
    return vim.tbl_map(function(item)
        return item.label
    end, items)
end

T["issues_and_change_requests_keep_the_caches_separate"] = function()
    local source, requests = fake_github()
    local callback, lists = helpers.recorder()
    local bufnr = vim.api.nvim_get_current_buf()

    source:complete_issues_and_change_requests(callback, git_info, "#")
    eq(labels(lists[1].items), { "#1: an issue", "#2: a pull request" }, "issues, then pull requests")
    eq(labels(source.cache.issues[bufnr]), { "#1: an issue" }, "the issue cache has no pull requests")

    source:complete_issues_and_change_requests(callback, git_info, "#")
    eq(
        labels(lists[2].items),
        { "#1: an issue", "#2: a pull request" },
        "a cache hit gives the issues and pull requests"
    )

    source:complete_issues(callback, git_info, "#")
    eq(labels(lists[3].items), { "#1: an issue" }, "the issues action gives only issues")
    eq(requests, { issue = 1, pr = 1 }, "each command runs once")
end

T["issues_and_change_requests_after_a_cached_change_request"] = function()
    local source, requests = fake_github()
    local callback, lists = helpers.recorder()

    source:complete_change_requests(callback, git_info, "#")
    source:complete_issues_and_change_requests(callback, git_info, "#")

    eq(#lists, 2, "one list for each request")
    eq(
        labels(lists[2].items),
        { "#1: an issue", "#2: a pull request" },
        "the cached pull requests come after the issues"
    )
    eq(requests, { issue = 1, pr = 1 }, "each command runs once")
end

return T
