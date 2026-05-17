package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

local command = require("cmp_git.command")
local response = require("cmp_git.response")
local log = require("cmp_git.log")
local remote_url = require("cmp_git.repository.remote_url")
local Source = require("cmp_git.source")
local Git = require("cmp_git.sources.git")
local GitHub = require("cmp_git.sources.github")
local GitLab = require("cmp_git.sources.gitlab")

local failures = {}

local function assert_eq(actual, expected, message)
    if actual ~= expected then
        table.insert(
            failures,
            string.format("%s: expected %s, got %s", message, vim.inspect(expected), vim.inspect(actual))
        )
    end
end

local function assert_true(value, message)
    if not value then
        table.insert(failures, message)
    end
end

local function wait_for(predicate, message)
    local ok = vim.wait(2000, predicate, 10)
    assert_true(ok, message)
end

local function test_handle_response()
    local items = response.handle_response('[{"name":"one"}]', function(item)
        return { label = item.name }
    end)
    assert_eq(#items, 1, "valid JSON item count")
    assert_eq(items[1].label, "one", "valid JSON item mapping")

    local mapped = response.handle_response('{"items":[{"name":"two"}]}', function(item)
        return { label = item.name }
    end, function(parsed)
        return parsed.items
    end)
    assert_eq(#mapped, 1, "mapped JSON item count")
    assert_eq(mapped[1].label, "two", "mapped JSON item mapping")

    local empty = response.handle_response("[]", function(item)
        return item
    end)
    assert_eq(#empty, 0, "empty JSON item count")

    local invalid = response.handle_response("not json", function(item)
        return item
    end)
    assert_eq(#invalid, 0, "invalid JSON item count")
end

local function test_parse_remote_url()
    local ssh = remote_url.parse("git@github.com:owner/repo.git")
    assert_eq(ssh.host, "github.com", "ssh remote host")
    assert_eq(ssh.owner, "owner", "ssh remote owner")
    assert_eq(ssh.repo, "repo", "ssh remote repo")

    local https = remote_url.parse("https://gitlab.com/group/project.git")
    assert_eq(https.host, "gitlab.com", "https remote host")
    assert_eq(https.owner, "group", "https remote owner")
    assert_eq(https.repo, "project", "https remote repo")

    local ssh_url = remote_url.parse("ssh://git@example.com/owner/repo.git")
    assert_eq(ssh_url.host, "example.com", "ssh url remote host")
    assert_eq(ssh_url.owner, "owner", "ssh url remote owner")
    assert_eq(ssh_url.repo, "repo", "ssh url remote repo")

    local alias = remote_url.parse("github-work:owner/repo.git")
    assert_eq(alias.host, "github-work", "alias remote host")
    assert_eq(alias.owner, "owner", "alias remote owner")
    assert_eq(alias.repo, "repo", "alias remote repo")
end

local function test_missing_executable()
    local job = command.build({ exec = "cmp-git-missing-executable", args = {} }, function() end)
    assert_eq(job, nil, "missing executable returns nil")
end

local function test_fallback()
    local result
    local first = command.build({ exec = "sh", args = { "-c", "exit 7" } }, function()
        result = "first-callback"
    end)
    local second = command.build({ exec = "sh", args = { "-c", "printf fallback" } }, function(stdout, success)
        result = { stdout = stdout, success = success }
    end)

    local job = command.fallback(first, second)
    assert_true(job ~= nil, "fallback job is created")
    job:start()

    wait_for(function()
        return type(result) == "table"
    end, "fallback job completes")

    assert_eq(result.stdout, "fallback", "fallback stdout")
    assert_eq(result.success, true, "fallback success")
end

local function test_build_job()
    local list
    local job = command.build_list({ exec = "sh", args = { "-c", 'printf \'[{"name":"item"}]\'' } }, function(result)
        list = result
    end, function(item)
        return { label = item.name }
    end)

    assert_true(job ~= nil, "json job is created")
    job:start()

    wait_for(function()
        return list ~= nil
    end, "json job completes")

    assert_eq(#list.items, 1, "json job item count")
    assert_eq(list.items[1].label, "item", "json job item label")
    assert_eq(list.isIncomplete, false, "json job completion flag")
end

local function test_logger()
    log.debug("debug message")
    log.fmt_debug("debug %s", "message")
    log.warn("warn message")
    vim.wait(20)
    assert_true(true, "logger calls do not throw")
end

local function test_trigger_action_fallback_for_hash()
    local source = Source.new({
        trigger_actions = {
            { trigger_character = "#", actions = { "gitlab_issues", "github_issues_and_prs" } },
        },
    })
    local calls = {}
    source.sources.gitlab = {
        get_issues = function()
            table.insert(calls, "gitlab")
            return false
        end,
    }
    source.sources.github = {
        get_issues_and_prs = function()
            table.insert(calls, "github")
            return true
        end,
    }

    source:_run_trigger_actions("#", function() end, {}, {})

    assert_eq(table.concat(calls, ","), "gitlab,github", "hash trigger falls back in configured order")
end

local function test_trigger_action_ordering_for_at()
    local source = Source.new({
        trigger_actions = {
            { trigger_character = "@", actions = { "gitlab_mentions", "github_mentions" } },
        },
    })
    local calls = {}
    source.sources.gitlab = {
        get_mentions = function()
            table.insert(calls, "gitlab")
            return false
        end,
    }
    source.sources.github = {
        get_mentions = function()
            table.insert(calls, "github")
            return true
        end,
    }

    source:_run_trigger_actions("@", function() end, {}, {})

    assert_eq(table.concat(calls, ","), "gitlab,github", "at trigger falls back in configured order")
end

local function test_trigger_action_first_handled_wins()
    local source = Source.new({
        trigger_actions = {
            { trigger_character = "#", actions = { "gitlab_issues", "github_issues_and_prs" } },
        },
    })
    local calls = {}
    source.sources.gitlab = {
        get_issues = function()
            table.insert(calls, "gitlab")
            return true
        end,
    }
    source.sources.github = {
        get_issues_and_prs = function()
            table.insert(calls, "github")
            return true
        end,
    }

    source:_run_trigger_actions("#", function() end, {}, {})

    assert_eq(table.concat(calls, ","), "gitlab", "first handled trigger action wins")
end

local function test_legacy_trigger_action_arguments()
    local received = nil
    local callback = function() end
    local params = { context = {} }
    local git_info = { host = "github.com" }
    local source = Source.new({
        trigger_actions = {
            {
                debug_name = "legacy",
                trigger_character = "#",
                action = function(sources, trigger_char, actual_callback, actual_params, actual_git_info)
                    received = {
                        sources = sources,
                        trigger_char = trigger_char,
                        callback = actual_callback,
                        params = actual_params,
                        git_info = actual_git_info,
                    }
                    return true
                end,
            },
        },
    })

    source:_run_trigger_actions("#", callback, params, git_info)

    assert_true(received ~= nil, "legacy trigger action runs")
    assert_eq(received.sources, source.sources, "legacy trigger action receives sources")
    assert_eq(received.trigger_char, "#", "legacy trigger action receives trigger character")
    assert_eq(received.callback, callback, "legacy trigger action receives callback")
    assert_eq(received.params, params, "legacy trigger action receives params")
    assert_eq(received.git_info, git_info, "legacy trigger action receives git info")
end

local function test_github_instance_state_isolation()
    local first = GitHub.new({ hosts = { "github.example.com" } })
    local second = GitHub.new({ hosts = { "github.other.com" } })

    assert_true(
        first:is_valid_host({ host = "github.example.com", owner = "owner", repo = "repo" }),
        "first GitHub instance validates own host"
    )
    assert_true(
        not first:is_valid_host({ host = "github.other.com", owner = "owner", repo = "repo" }),
        "first GitHub instance rejects second host"
    )
    assert_true(
        second:is_valid_host({ host = "github.other.com", owner = "owner", repo = "repo" }),
        "second GitHub instance validates own host"
    )
    assert_true(
        second:is_valid_host({ host = "github.com", owner = "owner", repo = "repo" }),
        "GitHub instance validates default host"
    )

    first.cache.issues[1] = { { label = "first" } }
    assert_eq(second.cache.issues[1], nil, "GitHub issue cache is instance-local")
    assert_true(first.cache.mentions ~= second.cache.mentions, "GitHub mention cache table is instance-local")
    assert_true(first.cache.pull_requests ~= second.cache.pull_requests, "GitHub PR cache table is instance-local")
end

local function test_gitlab_instance_state_isolation()
    local first = GitLab.new({ hosts = { "gitlab.example.com" } })
    local second = GitLab.new({ hosts = { "gitlab.other.com" } })

    assert_true(
        first:is_valid_host({ host = "gitlab.example.com", owner = "owner", repo = "repo" }),
        "first GitLab instance validates own host"
    )
    assert_true(
        not first:is_valid_host({ host = "gitlab.other.com", owner = "owner", repo = "repo" }),
        "first GitLab instance rejects second host"
    )
    assert_true(
        second:is_valid_host({ host = "gitlab.other.com", owner = "owner", repo = "repo" }),
        "second GitLab instance validates own host"
    )
    assert_true(
        second:is_valid_host({ host = "gitlab.com", owner = "owner", repo = "repo" }),
        "GitLab instance validates default host"
    )

    first.cache.issues[1] = { { label = "first" } }
    assert_eq(second.cache.issues[1], nil, "GitLab issue cache is instance-local")
    assert_true(first.cache.mentions ~= second.cache.mentions, "GitLab mention cache table is instance-local")
    assert_true(first.cache.merge_requests ~= second.cache.merge_requests, "GitLab MR cache table is instance-local")
end

local function test_git_instance_state_isolation()
    local first = Git.new({})
    local second = Git.new({})

    first.cache_commits[1] = { { label = "first" } }

    assert_eq(second.cache_commits[1], nil, "Git commit cache is instance-local")
    assert_true(first.cache_commits ~= second.cache_commits, "Git commit cache table is instance-local")
end

test_handle_response()
test_parse_remote_url()
test_missing_executable()
test_fallback()
test_build_job()
test_logger()
test_trigger_action_fallback_for_hash()
test_trigger_action_ordering_for_at()
test_trigger_action_first_handled_wins()
test_legacy_trigger_action_arguments()
test_github_instance_state_isolation()
test_gitlab_instance_state_isolation()
test_git_instance_state_isolation()

if #failures > 0 then
    for _, failure in ipairs(failures) do
        vim.api.nvim_err_writeln(failure)
    end
    os.exit(1)
end

print("cmp-git tests passed")
