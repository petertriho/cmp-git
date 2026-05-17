package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

local command = require("cmp_git.command")
local response = require("cmp_git.response")
local log = require("cmp_git.log")
local remote_url = require("cmp_git.repository.remote_url")
local Source = require("cmp_git.source")
local Git = require("cmp_git.sources.git")
local GitHub = require("cmp_git.sources.github")
local GitLab = require("cmp_git.sources.gitlab")
local issue_capability = require("cmp_git.provider.capabilities.issues")
local mention_capability = require("cmp_git.provider.capabilities.mentions")

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
        complete_issues = function()
            table.insert(calls, "gitlab")
            return false
        end,
    }
    source.sources.github = {
        complete_issues_and_change_requests = function()
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
        complete_mentions = function()
            table.insert(calls, "gitlab")
            return false
        end,
    }
    source.sources.github = {
        complete_mentions = function()
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
        complete_issues = function()
            table.insert(calls, "gitlab")
            return true
        end,
    }
    source.sources.github = {
        complete_issues_and_change_requests = function()
            table.insert(calls, "github")
            return true
        end,
    }

    source:_run_trigger_actions("#", function() end, {}, {})

    assert_eq(table.concat(calls, ","), "gitlab", "first handled trigger action wins")
end

local function test_preferred_trigger_action_names()
    local source = Source.new({
        trigger_actions = {
            { trigger_character = "#", actions = { "github_issues" } },
            { trigger_character = "!", actions = { "gitlab_change_requests" } },
        },
    })
    local calls = {}
    source.sources.github = {
        complete_issues = function()
            table.insert(calls, "github_issues")
            return true
        end,
    }
    source.sources.gitlab = {
        complete_change_requests = function()
            table.insert(calls, "gitlab_change_requests")
            return true
        end,
    }

    source:_run_trigger_actions("#", function() end, {}, {})
    source:_run_trigger_actions("!", function() end, {}, {})

    assert_eq(table.concat(calls, ","), "github_issues,gitlab_change_requests", "preferred action names route")
end

local function test_legacy_trigger_action_aliases()
    local source = Source.new({
        trigger_actions = {
            { trigger_character = "#", actions = { "github_issues_and_prs" } },
            { trigger_character = "!", actions = { "gitlab_mrs" } },
        },
    })
    local calls = {}
    source.sources.github = {
        complete_issues_and_change_requests = function()
            table.insert(calls, "github_combined")
            return true
        end,
    }
    source.sources.gitlab = {
        complete_change_requests = function()
            table.insert(calls, "gitlab_cr")
            return true
        end,
    }

    source:_run_trigger_actions("#", function() end, {}, {})
    source:_run_trigger_actions("!", function() end, {}, {})

    assert_eq(table.concat(calls, ","), "github_combined,gitlab_cr", "legacy aliases route")
end

local function test_issue_capability_uses_cache_and_runner()
    local callback_count = 0
    local last_list
    local request_count = 0
    local runner_count = 0
    local cache = {}
    local adapter = {
        issues_request = function()
            request_count = request_count + 1
            return {
                commands = { { exec = "fake", args = { "issues" } } },
                handle_item = function(item)
                    return { label = item.name }
                end,
            }
        end,
    }
    local runner = {
        build_fallback_list = function(commands, callback, handle_item)
            runner_count = runner_count + 1
            assert_eq(commands[1].exec, "fake", "issue capability forwards commands")
            return {
                start = function()
                    callback({ items = { handle_item({ name = "one" }) }, isIncomplete = false })
                end,
            }
        end,
    }
    local args = {
        adapter = adapter,
        cache = cache,
        callback = function(list)
            callback_count = callback_count + 1
            last_list = list
        end,
        config = {},
        git_info = {},
        trigger_char = "#",
        runner = runner,
        bufnr = 42,
    }

    issue_capability.complete(args)
    issue_capability.complete(args)

    assert_eq(request_count, 1, "issue capability requests once")
    assert_eq(runner_count, 1, "issue capability runs once")
    assert_eq(callback_count, 2, "issue capability callbacks on miss and hit")
    assert_eq(last_list.items[1].label, "one", "issue capability caches mapped items")
end

local function test_mention_capability_preflight_and_pagination()
    local callbacks = {}
    local request_pages = {}
    local runner = {
        build_fallback = function(commands, callback)
            assert_eq(commands[1].exec, "preflight", "mention preflight command forwarded")
            return {
                start = function()
                    callback('{"status":"404"}', true)
                end,
            }
        end,
        build_fallback_list = function(commands, callback, handle_item)
            local page = commands[1].page
            table.insert(request_pages, page)
            return {
                start = function()
                    local raw_items = page == 1 and { { name = "one" } } or {}
                    local items = {}
                    for _, item in ipairs(raw_items) do
                        table.insert(items, handle_item(item))
                    end
                    callback({ items = items, isIncomplete = false })
                end,
            }
        end,
    }
    local adapter = {
        mentions_preflight_request = function()
            return {
                commands = { { exec = "preflight", args = {} } },
                handle_result = function(result)
                    local parsed = vim.json.decode(result)
                    return { member_type = parsed.status == "404" and "collaborators" or "contributors" }
                end,
            }
        end,
        mentions_request = function(_git_info, _trigger_char, _config, opts)
            assert_eq(opts.context.member_type, "collaborators", "mention context comes from preflight")
            return {
                commands = { { exec = "mentions", args = {}, page = opts.page } },
                handle_item = function(item)
                    return { label = item.name }
                end,
            }
        end,
    }

    mention_capability.complete({
        adapter = adapter,
        cache = {},
        callback = function(list)
            table.insert(callbacks, list)
        end,
        config = { limit = 2 },
        git_info = {},
        trigger_char = "@",
        runner = runner,
        bufnr = 43,
    })

    assert_eq(table.concat(request_pages, ","), "1,2", "mention capability paginates")
    assert_eq(#callbacks, 2, "mention capability returns partial and final callbacks")
    assert_eq(callbacks[1].isIncomplete, true, "first mention callback is incomplete")
    assert_eq(callbacks[2].isIncomplete, false, "final mention callback is complete")
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
test_preferred_trigger_action_names()
test_legacy_trigger_action_aliases()
test_legacy_trigger_action_arguments()
test_issue_capability_uses_cache_and_runner()
test_mention_capability_preflight_and_pagination()
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
