package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

local command = require("cmp_git.command")
local config = require("cmp_git.config")
local response = require("cmp_git.response")
local log = require("cmp_git.log")
local remote_url = require("cmp_git.repository.remote_url")
local Core = require("cmp_git.core")
local Blink = require("cmp_git.blink")
local Source = require("cmp_git.source")
local Git = require("cmp_git.sources.git")
local GitHub = require("cmp_git.sources.github")
local GitLab = require("cmp_git.sources.gitlab")
local issue_capability = require("cmp_git.provider.capabilities.issues")
local mention_capability = require("cmp_git.provider.capabilities.mentions")
local commit_capability = require("cmp_git.provider.capabilities.commits")
local change_request_capability = require("cmp_git.provider.capabilities.change_requests")
local trailer_capability = require("cmp_git.provider.capabilities.trailers")
local repository = require("cmp_git.repository")

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

local function test_command_fallback_cancels_active_job()
    local first_cancelled = false
    local second_started = false
    local first = {
        command = "first",
        start = function() end,
        cancel = function()
            first_cancelled = true
        end,
    }
    local second = {
        command = "second",
        start = function()
            second_started = true
        end,
    }

    local job = command.fallback(first, second)
    job:start()
    job:cancel()

    assert_true(first_cancelled, "fallback cancellation cancels active job")
    assert_true(not second_started, "fallback cancellation does not start later job")
end

local function test_command_build_cancel_suppresses_callback()
    local called = false
    local job = command.build({ exec = "sh", args = { "-c", "sleep 0.2; printf done" } }, function()
        called = true
    end)

    assert_true(job ~= nil, "cancellable command job is created")
    job:start()
    job:cancel()
    vim.wait(350)

    assert_true(not called, "cancelled command suppresses callback")
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

    local job = issue_capability.complete(args)
    local cached_job = issue_capability.complete(args)

    assert_eq(request_count, 1, "issue capability requests once")
    assert_eq(runner_count, 1, "issue capability runs once")
    assert_eq(callback_count, 2, "issue capability callbacks on miss and hit")
    assert_eq(last_list.items[1].label, "one", "issue capability caches mapped items")
    assert_true(job ~= nil, "issue capability returns started job")
    assert_eq(cached_job, nil, "issue capability cache hit returns no job")
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

local function test_change_request_capability_returns_job()
    local runner = {
        build_fallback_list = function(_commands, callback, handle_item)
            return {
                start = function()
                    callback({ items = { handle_item({ name = "pr" }) }, isIncomplete = false })
                end,
            }
        end,
    }
    local adapter = {
        change_requests_request = function()
            return {
                commands = { { exec = "fake", args = {} } },
                handle_item = function(item)
                    return { label = item.name }
                end,
            }
        end,
    }

    local job = change_request_capability.complete({
        adapter = adapter,
        cache = {},
        callback = function() end,
        config = {},
        git_info = {},
        trigger_char = "#",
        runner = runner,
        bufnr = 45,
    })

    assert_true(job ~= nil, "change request capability returns started job")
end

local function commit_test_config()
    return {
        limit = 100,
        sha_length = 7,
        sort_by = function(commit)
            return commit.sha
        end,
        format = {
            label = function(trigger_char, commit)
                return string.format("%s%s: %s", trigger_char, commit.sha, commit.title)
            end,
            filterText = function(trigger_char, commit)
                return string.format("%s %s %s", trigger_char, commit.sha, commit.title)
            end,
            insertText = function(_, commit)
                return commit.sha
            end,
            documentation = function(_, commit)
                return { kind = "markdown", value = commit.description }
            end,
        },
    }
end

local function commit_record(sha, title, description, author_name, author_mail, timestamp)
    return table.concat({ sha, title, description, author_name, author_mail, tostring(timestamp) }, "\0") .. "\0"
end

local function test_commit_capability_parse_nul_records()
    local commits = commit_capability.parse(
        commit_record(
            "abcdef1234567890",
            " subject with spaces ",
            "body line one\nbody line two",
            "Ada Lovelace",
            "ada@example.com",
            1234567890
        ),
        commit_test_config()
    )

    assert_eq(#commits, 1, "commit parser item count")
    assert_eq(commits[1].sha, "abcdef1", "commit parser truncates sha")
    assert_eq(commits[1].title, "subject with spaces", "commit parser trims title")
    assert_eq(commits[1].description, "body line one\nbody line two", "commit parser keeps multiline body")
    assert_eq(commits[1].author_name, "Ada Lovelace", "commit parser author name")
    assert_eq(commits[1].author_mail, "ada@example.com", "commit parser author mail")
    assert_eq(commits[1].commit_timestamp, 1234567890, "commit parser numeric timestamp")
    assert_eq(type(commits[1].diff), "number", "commit parser diff shape")
end

local function test_commit_capability_parse_marker_collision_and_malformed_records()
    local raw = commit_record(
        "1111111222222222",
        "subject with ###CMP_GIT### marker",
        "body with ###CMP_GIT_END### marker",
        "Grace Hopper",
        "grace@example.com",
        1234567890
    ) .. "dangling\0record\0without\0all\0fields\0"

    local commits = commit_capability.parse(raw, commit_test_config())

    assert_eq(#commits, 1, "commit parser skips malformed trailing record")
    assert_eq(commits[1].title, "subject with ###CMP_GIT### marker", "commit parser allows old part marker text")
    assert_eq(
        commits[1].description,
        "body with ###CMP_GIT_END### marker",
        "commit parser allows old entry marker text"
    )
end

local function test_commit_capability_maps_items_without_cmp_params()
    local items = commit_capability.items({
        {
            sha = "abcdef1",
            title = "mapped commit",
            description = "mapped docs",
            author_name = "Linus",
            author_mail = "linus@example.com",
            commit_timestamp = 1234567890,
            diff = 1,
        },
    }, commit_test_config(), ":")

    assert_eq(#items, 1, "commit mapper item count")
    assert_eq(items[1].label, ":abcdef1: mapped commit", "commit mapper label")
    assert_eq(items[1].filterText, ": abcdef1 mapped commit", "commit mapper filter text")
    assert_eq(items[1].insertText, "abcdef1", "commit mapper insert text")
    assert_eq(items[1].documentation.value, "mapped docs", "commit mapper documentation")
end

local function test_commit_capability_uses_parsed_cache_and_runner()
    local callback_count = 0
    local runner_count = 0
    local last_list
    local cache = {}
    local raw = commit_record("abcdef1234567890", "cache me", "body", "Author", "author@example.com", 1234567890)
    local runner = {
        build = function(spec, callback)
            runner_count = runner_count + 1
            assert_eq(spec.exec, "git", "commit capability command exec")
            assert_eq(spec.args[1], "log", "commit capability command action")
            assert_eq(spec.args[3], "100", "commit capability command limit")
            assert_eq(
                spec.args[5],
                "--pretty=format:%H%x00%s%x00%b%x00%cn%x00%ce%x00%cd%x00",
                "commit capability command format"
            )
            return {
                start = function()
                    callback(raw, true)
                end,
            }
        end,
    }
    local args = {
        cache = cache,
        callback = function(list)
            callback_count = callback_count + 1
            last_list = list
        end,
        config = commit_test_config(),
        trigger_char = ":",
        runner = runner,
        bufnr = 44,
    }

    commit_capability.complete(args)
    commit_capability.complete(args)

    assert_eq(runner_count, 1, "commit capability runs once")
    assert_eq(callback_count, 2, "commit capability callbacks on miss and hit")
    assert_eq(cache[44][1].sha, "abcdef1", "commit capability caches parsed commits")
    assert_eq(cache[44][1].label, nil, "commit capability does not cache completion items")
    assert_eq(last_list.items[1].label, ":abcdef1: cache me", "commit capability maps cached commits")
end

local function test_git_commit_edit_range_is_preserved()
    local items = { { insertText = "abcdef1" } }

    Core.apply_text_edits(items, { cursor = { row = 3, character = 5 }, line = ":abcd", trigger_character = ":" })

    assert_eq(items[1].textEdit.range.start.line, 2, "commit edit range start line")
    assert_eq(items[1].textEdit.range.start.character, 0, "commit edit range start character")
    assert_eq(items[1].textEdit.range["end"].line, 2, "commit edit range end line")
    assert_eq(items[1].textEdit.range["end"].character, 5, "commit edit range end character")
    assert_eq(items[1].textEdit.newText, "abcdef1", "commit edit range new text")
end

local function test_core_text_edit_ranges_for_all_triggers()
    local cases = {
        { trigger = ":", line = "refs :abc", cursor = 9, insert = "abcdef1" },
        { trigger = "#", line = "fix #12", cursor = 7, insert = "#123" },
        { trigger = "@", line = "cc @ad", cursor = 6, insert = "@ada" },
        { trigger = "!", line = "see !4", cursor = 6, insert = "!42" },
    }

    for _, case in ipairs(cases) do
        local items = { { insertText = case.insert } }
        Core.apply_text_edits(items, {
            cursor = { row = 1, character = case.cursor },
            line = case.line,
            trigger_character = case.trigger,
        })

        local expected_start = string.find(case.line, case.trigger, 1, true) - 1
        assert_eq(items[1].textEdit.range.start.character, expected_start, case.trigger .. " range starts at trigger")
        assert_eq(items[1].textEdit.range["end"].character, case.cursor, case.trigger .. " range ends at cursor")
        assert_eq(items[1].textEdit.newText, case.insert, case.trigger .. " range inserts text")
    end
end

local function test_blink_adapter_api_and_cancellation()
    local blink = Blink.new({})
    local cancelled = false
    local callback_result
    blink.core = {
        is_available = function()
            return true
        end,
        get_trigger_characters = function()
            return { "#" }
        end,
        complete = function(_, context, callback)
            assert_eq(context.trigger_character, "#", "blink forwards trigger character")
            assert_eq(context.cursor.row, 1, "blink forwards cursor row")
            assert_eq(context.cursor.character, 5, "blink forwards cursor character")
            callback({ items = { { label = "#1", insertText = "#1" } }, isIncomplete = true })
            return {
                cancel = function()
                    cancelled = true
                end,
            }
        end,
    }

    assert_true(blink:enabled(), "blink enabled delegates to core")
    assert_eq(blink:get_trigger_characters()[1], "#", "blink trigger characters delegate to core")

    local cancel = blink:get_completions({
        trigger = { character = "#" },
        cursor = { line = 0, character = 5 },
        line = "fix #",
        bufnr = 1,
    }, function(result)
        callback_result = result
    end)

    assert_eq(callback_result.items[1].label, "#1", "blink maps completion items")
    assert_eq(callback_result.is_incomplete_backward, false, "blink disables backward incomplete requests")
    assert_eq(callback_result.is_incomplete_forward, true, "blink forwards incomplete state")

    cancel()
    assert_true(cancelled, "blink cancellation delegates to core job")
end

local function test_blink_adapter_suppresses_stale_callbacks_after_cancel()
    local blink = Blink.new({})
    local pending_callback
    local called = false
    blink.core = {
        is_available = function()
            return true
        end,
        get_trigger_characters = function()
            return { "#" }
        end,
        complete = function(_, _context, callback)
            pending_callback = callback
            return { cancel = function() end }
        end,
    }

    local cancel = blink:get_completions(
        { trigger = { character = "#" }, cursor = { line = 0, character = 1 }, line = "#" },
        function()
            called = true
        end
    )
    cancel()
    pending_callback({ items = { { label = "stale" } }, isIncomplete = false })

    assert_true(not called, "blink suppresses stale callback after cancellation")
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

local function test_config_normalize_fills_defaults_and_hosts()
    local normalized = config.normalize({
        github = {
            issues = {
                limit = 7,
            },
        },
    })

    assert_eq(normalized.github.issues.limit, 7, "normalized config keeps nested override")
    assert_eq(normalized.github.issues.state, "open", "normalized config fills issue defaults")
    assert_eq(type(normalized.github.issues.format.label), "function", "normalized config fills format defaults")
    assert_eq(
        type(normalized.github.pull_requests.format.label),
        "function",
        "normalized config fills sibling defaults"
    )
    assert_true(vim.tbl_contains(normalized.github.hosts, "github.com"), "normalized config adds github host")
    assert_true(vim.tbl_contains(normalized.gitlab.hosts, "gitlab.com"), "normalized config adds gitlab host")
end

local function test_config_normalize_nested_filter_and_sort_overrides()
    local issue_filter = function()
        return "issue-filter"
    end
    local sort_by = function(issue)
        return issue.title
    end

    local normalized = config.normalize({
        github = {
            issues = {
                sort_by = sort_by,
                format = {
                    filterText = issue_filter,
                },
            },
        },
    })

    assert_eq(normalized.github.issues.format.filterText, issue_filter, "nested issue filter is preserved")
    assert_true(
        normalized.github.mentions.format.filterText ~= issue_filter,
        "nested issue filter does not affect mentions"
    )
    assert_eq(normalized.github.issues.sort_by, sort_by, "custom sort is preserved")
end

local function test_config_normalize_provider_filter_alias()
    local git_filter = function()
        return "git"
    end
    local github_filter = function()
        return "github"
    end
    local gitlab_filter = function()
        return "gitlab"
    end

    local normalized = config.normalize({
        git = {
            filter_fn = git_filter,
        },
        github = {
            filter_fn = github_filter,
        },
        gitlab = {
            filter_fn = gitlab_filter,
        },
    })

    assert_eq(normalized.git.commits.format.filterText, git_filter, "git filter alias applies to commits")
    assert_eq(normalized.github.issues.format.filterText, github_filter, "github filter alias applies to issues")
    assert_eq(normalized.github.mentions.format.filterText, github_filter, "github filter alias applies to mentions")
    assert_eq(
        normalized.github.pull_requests.format.filterText,
        github_filter,
        "github filter alias applies to pull requests"
    )
    assert_eq(normalized.gitlab.issues.format.filterText, gitlab_filter, "gitlab filter alias applies to issues")
    assert_eq(normalized.gitlab.mentions.format.filterText, gitlab_filter, "gitlab filter alias applies to mentions")
    assert_eq(
        normalized.gitlab.merge_requests.format.filterText,
        gitlab_filter,
        "gitlab filter alias applies to merge requests"
    )
end

local function test_config_normalize_provider_filter_alias_overrides_nested_filter()
    local nested_filter = function()
        return "nested"
    end
    local provider_filter = function()
        return "provider"
    end

    local normalized = config.normalize({
        github = {
            filter_fn = provider_filter,
            issues = {
                format = {
                    filterText = nested_filter,
                },
            },
        },
    })

    assert_eq(
        normalized.github.issues.format.filterText,
        provider_filter,
        "provider filter alias overrides nested filter"
    )
end

local function test_config_normalize_does_not_leak_hosts_between_instances()
    local first = config.normalize({
        github = {
            hosts = { "github.example.com" },
        },
    })
    local second = config.normalize({
        github = {
            hosts = { "github.other.com" },
        },
    })

    assert_true(vim.tbl_contains(first.github.hosts, "github.example.com"), "first normalized config keeps own host")
    assert_true(
        not vim.tbl_contains(first.github.hosts, "github.other.com"),
        "first normalized config rejects second host"
    )
    assert_true(vim.tbl_contains(second.github.hosts, "github.other.com"), "second normalized config keeps own host")
    assert_true(vim.tbl_contains(second.github.hosts, "github.com"), "second normalized config keeps default host")
end

local function test_source_new_uses_normalized_config()
    local source = Source.new({
        github = {
            issues = {
                limit = 5,
            },
        },
    })

    assert_eq(source.config.github.issues.limit, 5, "source config keeps normalized override")
    assert_eq(source.sources.github.config.issues.limit, 5, "github source receives normalized override")
    assert_eq(
        type(source.sources.github.config.pull_requests.format.label),
        "function",
        "github source receives normalized defaults"
    )
    assert_true(
        source.sources.github:is_valid_host({ host = "github.com", owner = "owner", repo = "repo" }),
        "github source receives normalized default host"
    )
end

local function test_github_instance_state_isolation()
    local first = GitHub.new(config.normalize({ github = { hosts = { "github.example.com" } } }).github)
    local second = GitHub.new(config.normalize({ github = { hosts = { "github.other.com" } } }).github)

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
    local first = GitLab.new(config.normalize({ gitlab = { hosts = { "gitlab.example.com" } } }).gitlab)
    local second = GitLab.new(config.normalize({ gitlab = { hosts = { "gitlab.other.com" } } }).gitlab)

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
    local first = Git.new(config.normalize({}).git)
    local second = Git.new(config.normalize({}).git)

    first.cache_commits[1] = { { label = "first" } }

    assert_eq(second.cache_commits[1], nil, "Git commit cache is instance-local")
    assert_true(first.cache_commits ~= second.cache_commits, "Git commit cache table is instance-local")
    assert_true(first.cache_trailer_keys ~= second.cache_trailer_keys, "Git trailer key cache is instance-local")
    assert_true(
        first.cache_trailer_identities ~= second.cache_trailer_identities,
        "Git trailer identities cache is instance-local"
    )
    assert_true(first.cache_trailer_values ~= second.cache_trailer_values, "Git trailer values cache is instance-local")
end

local function trailer_buffer(lines, filetype)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].filetype = filetype or "gitcommit"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    return bufnr
end

local function test_config_trailer_defaults()
    local normalized = config.normalize({})

    assert_eq(normalized.trigger_actions[1].actions[1], "git_trailer_keys", "trailer keys action is first")
    assert_eq(normalized.trigger_actions[2].actions[1], "git_trailer_identities", "trailer identities action is second")
    assert_eq(
        normalized.trigger_actions[2].actions[2],
        "git_trailer_values",
        "trailer values action follows identities"
    )
    assert_eq(normalized.git.trailers.values.limit, 1000, "trailer values scan limit")
    assert_eq(normalized.trigger_actions[3].trigger_character, ":", "commit trigger follows trailer actions")
    assert_eq(normalized.git.trailers.keys.limit, 100, "trailer keys scan limit")
    assert_eq(normalized.git.trailers.identities.limit, 1000, "trailer identities scan limit")
    assert_eq(normalized.git.trailers.keys.builtin[1], "Co-authored-by", "built-in keys start with Co-authored-by")
    assert_true(vim.tbl_contains(normalized.git.trailers.keys.builtin, "Fixes"), "built-in keys contain Fixes")
    assert_true(
        vim.tbl_contains(normalized.git.trailers.identities.keys, "Signed-off-by"),
        "identity keys contain Signed-off-by"
    )
    assert_true(
        not vim.tbl_contains(normalized.git.trailers.identities.keys, "Fixes"),
        "identity keys do not contain Fixes"
    )
    assert_true(vim.tbl_contains(normalized.git.trailers.filetypes, "gitcommit"), "trailers in gitcommit")
    assert_true(not vim.tbl_contains(normalized.git.trailers.filetypes, "octo"), "no trailers in octo")
end

local function test_custom_trigger_actions_remove_trailers()
    local core = Core.new({
        trigger_actions = {
            { trigger_character = ":", actions = { "git_commits" } },
        },
    })

    assert_eq(#core.trigger_actions, 1, "custom trigger actions replace the trailer entries")
    assert_eq(core.keyword_pattern, "[:]\\S*", "keyword pattern without pattern entries is unchanged")
end

local function test_invalid_trigger_action_pattern_is_skipped()
    local core = Core.new({
        trigger_actions = {
            { pattern = [[\%(]], actions = { "git_trailer_keys" } },
            { trigger_character = ":", actions = { "git_commits" } },
        },
    })

    assert_eq(#core.trigger_actions, 1, "invalid pattern entry is skipped")
    assert_eq(core.trigger_actions[1].debug_name, "git_commits", "valid entry is kept")
end

local function test_config_git_filter_alias_skips_trailers()
    local git_filter = function()
        return "git"
    end
    local normalized = config.normalize({ git = { filter_fn = git_filter } })

    assert_eq(normalized.git.commits.format.filterText, git_filter, "git filter alias applies to commits")
    assert_true(
        normalized.git.trailers.keys.format.filterText ~= git_filter,
        "git filter alias does not apply to trailer keys"
    )
    assert_true(
        normalized.git.trailers.identities.format.filterText ~= git_filter,
        "git filter alias does not apply to trailer identities"
    )
    assert_true(
        normalized.git.trailers.values.format.filterText ~= git_filter,
        "git filter alias does not apply to trailer values"
    )
end

local function test_core_keyword_pattern_offsets()
    local core = Core.new({})
    local regex = vim.regex([[\%(]] .. core.keyword_pattern .. [[\)\m$]])
    local cases = {
        { "Co-auth", 0 },
        { "Co-authored-by:", 14 },
        { "Co-authored-by: Ada Lo", 16 },
        { "Co-authored-by: Ada <ada@ex", 16 },
        { "Note: see #12", 10 },
        { "Note: thanks @ada", 13 },
        { "Note: see :abc", 10 },
        { "refs :abc", 5 },
        { "fix #12", 4 },
        { "cc @ad", 3 },
        { "see !4", 4 },
        { "body text he", nil },
    }

    for _, case in ipairs(cases) do
        assert_eq(regex:match_str(case[1]), case[2], "keyword offset for " .. vim.inspect(case[1]))
    end
end

local function test_trailer_routing()
    local core = Core.new({})
    local calls = {}
    local function record(name, handled)
        return function()
            table.insert(calls, name)
            return handled
        end
    end
    core.sources.git = {
        get_commits = record("commits", true),
        get_trailer_keys = record("keys", true),
        get_trailer_identities = record("identities", true),
        get_trailer_values = record("values", true),
        may_have_trailer_values = function()
            return true
        end,
    }
    core.sources.gitlab = {
        complete_issues = record("gitlab_issues", false),
        complete_mentions = record("gitlab_mentions", false),
        complete_change_requests = record("gitlab_change_requests", false),
    }
    core.sources.github = {
        complete_issues_and_change_requests = record("github_issues", true),
        complete_mentions = record("github_mentions", true),
    }

    local cases = {
        { line = "Co-auth", expected = "keys" },
        { line = "Co-authored-by:", trigger = ":", expected = "identities" },
        { line = "Co-authored-by: Ada", expected = "identities" },
        { line = "Co-authored-by: Ada <ada@", trigger = "@", expected = "identities" },
        { line = "Fixes:", trigger = ":", expected = "commits" },
        { line = "Fixes: #12", trigger = "#", expected = "gitlab_issues,github_issues" },
        { line = "Fixes: 29", expected = "values" },
        { line = "Assisted-by:Co", trigger = ":", expected = "values" },
        { line = "Note: plain text", expected = "values" },
    }

    for _, case in ipairs(cases) do
        calls = {}
        local bufnr = trailer_buffer({ "feat: subject", "", case.line })
        core:_run_trigger_actions(case.trigger, function() end, {
            cursor = { row = 3, character = #case.line },
            line = case.line,
            bufnr = bufnr,
        }, {})
        vim.api.nvim_buf_delete(bufnr, { force = true })

        assert_eq(table.concat(calls, ","), case.expected, "route for " .. vim.inspect(case.line))
    end
end

local function test_trailer_gating()
    local trailers_config = config.normalize({}).git.trailers
    local function available(lines, row, line, kind, filetype)
        local bufnr = trailer_buffer(lines, filetype)
        local result = trailer_capability.available(trailers_config, {
            bufnr = bufnr,
            cursor = { row = row },
            line = line,
        }, kind)
        vim.api.nvim_buf_delete(bufnr, { force = true })
        return result
    end

    assert_true(available({ "subject", "", "Co" }, 3, "Co", "keys"), "keys after the blank line")
    assert_true(
        available({ "subject", "", "Signed-off-by: Ada <ada@example.com>", "Co" }, 4, "Co", "keys"),
        "keys after another trailer"
    )
    assert_true(
        available({ "subject", "", "Co" }, 3, "Co", "keys", "NeogitCommitMessage"),
        "keys in Neogit commit messages"
    )
    assert_true(available({ "subject", "", "Co" }, 3, "Co", "keys", "gitcommit.markdown"), "keys in compound filetype")
    assert_true(not available({ "Co" }, 1, "Co", "keys"), "no keys on the subject line")
    assert_true(not available({ "subject", "Co" }, 2, "Co", "keys"), "no keys on row 2")
    assert_true(not available({ "subject", "", "body text", "Co" }, 4, "Co", "keys"), "no keys inside a paragraph")
    assert_true(not available({ "subject", "", "Co" }, 3, "Co", "keys", "octo"), "no keys in octo")
    assert_true(
        available({ "subject", "", "" }, 3, "Co-authored-by: Ad", "identities"),
        "identities for an identity key"
    )
    assert_true(
        available({ "subject", "", "" }, 3, "co-AUTHORED-by: Ad", "identities"),
        "identity keys match case-insensitively"
    )
    assert_true(not available({ "subject", "", "" }, 3, "Fixes: Ad", "identities"), "no identities for other keys")
    assert_true(not available({ "subject", "Ad" }, 2, "Co-authored-by: Ad", "identities"), "no identities on row 2")
    assert_true(available({ "subject", "", "" }, 3, "Assisted-by: Co", "values"), "values for any key")
    assert_true(available({ "subject", "", "" }, 3, "Fixes: ", "values"), "values for an empty value after a space")
    assert_true(not available({ "subject", "", "" }, 3, "Fixes:", "values"), "no values right after the colon")
    assert_true(not available({ "subject", "", "body", "" }, 4, "Fixes: 2", "values"), "no values inside a paragraph")
end

local function test_core_pre_route_skips_repository()
    local original_is_git_repo = repository.is_git_repo
    local checks = 0
    repository.is_git_repo = function()
        checks = checks + 1
    end

    local core = Core.new({})
    local bufnr = trailer_buffer({ "fe" })
    local lists = {}
    core:complete({ cursor = { row = 1, character = 2 }, line = "fe", bufnr = bufnr }, function(list)
        table.insert(lists, list)
    end)

    assert_eq(checks, 0, "declined request does not check the repository")
    assert_eq(#lists, 1, "declined request calls the callback once")
    assert_eq(#lists[1].items, 0, "declined request has no items")
    assert_eq(lists[1].isIncomplete, false, "declined request is complete")

    local source = Source.new({})
    source:complete({
        context = { cursor_before_line = "fe", cursor = { row = 1, col = 3, character = 2 } },
        completion_context = { triggerKind = 1 },
    }, function() end)
    assert_eq(checks, 0, "declined nvim-cmp request does not check the repository")

    core:complete(
        { trigger_character = ":", cursor = { row = 1, character = 3 }, line = "fe:", bufnr = bufnr },
        function() end
    )
    assert_eq(checks, 1, "matched request checks the repository")

    repository.is_git_repo = original_is_git_repo
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

local function test_trailer_text_edits()
    local core = Core.new({})
    local bufnr = trailer_buffer({ "subject", "", "" })
    core.sources.git.cache_trailer_keys[bufnr] = { { key = "Co-authored-by", count = 1, builtin_index = 1 } }
    core.sources.git.cache_trailer_identities[bufnr] = {
        { name = "Ada Lovelace", email = "ada@example.com", diff = 0, source = "author", is_self = false },
    }
    core.sources.git.cache_trailer_values[bufnr] = {
        ["assisted-by"] = { { key = "Assisted-by", value = "Codex", count = 1, diff = 0 } },
    }

    local function run(line, trigger)
        local result
        core:_run_trigger_actions(trigger, function(list)
            result = list
        end, { cursor = { row = 3, character = #line }, line = line, bufnr = bufnr }, {})
        return result.items[1]
    end

    local key = run("Co-au")
    assert_eq(key.textEdit.range.start.character, 0, "trailer key edit starts at the line start")
    assert_eq(key.textEdit.range["end"].character, 5, "trailer key edit ends at the cursor")
    assert_eq(key.textEdit.newText, "Co-authored-by: ", "trailer key inserts the key and a space")

    local identity = run("Co-authored-by: Ad")
    assert_eq(identity.textEdit.range.start.character, 16, "trailer identity edit starts at the value")
    assert_eq(identity.textEdit.range["end"].character, 18, "trailer identity edit ends at the cursor")
    assert_eq(identity.textEdit.newText, "Ada Lovelace <ada@example.com>", "trailer identity inserts the identity")
    assert_eq(identity.filterText, "Ada Lovelace <ada@example.com>", "trailer identity filters on the identity")

    local attached = run("Co-authored-by:", ":")
    assert_eq(attached.textEdit.range.start.character, 15, "attached trailer identity edit starts after the colon")
    assert_eq(attached.textEdit.newText, " Ada Lovelace <ada@example.com>", "attached trailer identity adds a space")
    assert_eq(attached.filterText, ": Ada Lovelace <ada@example.com>", "attached trailer identity filters on the colon")

    local email = run("Co-authored-by: Ada <ada@", "@")
    assert_eq(email.textEdit.range.start.character, 16, "trailer identity edit ignores the @ trigger in the email")
    assert_eq(email.textEdit.newText, "Ada Lovelace <ada@example.com>", "trailer identity ignores the @ trigger")

    local value = run("Assisted-by: Co")
    assert_eq(value.textEdit.range.start.character, 13, "trailer value edit starts at the value")
    assert_eq(value.textEdit.newText, "Codex", "trailer value inserts the earlier value")
    assert_eq(value.filterText, "Codex", "trailer value filters on the value")

    local attached_value = run("Assisted-by:Co", ":")
    assert_eq(attached_value.textEdit.range.start.character, 12, "attached trailer value edit starts after the colon")
    assert_eq(attached_value.textEdit.newText, " Codex", "attached trailer value adds a space")
    assert_eq(attached_value.filterText, ": Codex", "attached trailer value filters on the colon")

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

local function test_trailer_keys_parse_and_sort()
    local result = table.concat({
        "Signed-off-by\031co-authored-by\0",
        "\nChange-Id\0",
        "\nsigned-off-by\0",
        "\n%(trailers:keyonly,separator=%x1f)\0",
        "\n\0",
    })
    local keys = trailer_capability.keys.parse(result, { builtin = { "Co-authored-by", "Signed-off-by", "Fixes" } })
    local by_key = {}
    for _, trailer in ipairs(keys) do
        by_key[trailer.key] = trailer
    end

    assert_eq(#keys, 4, "trailer key count")
    assert_eq(by_key["Signed-off-by"].count, 2, "trailer keys count case-insensitively")
    assert_eq(by_key["Co-authored-by"].count, 1, "built-in trailer key casing wins")
    assert_eq(by_key["Change-Id"].count, 1, "mined trailer key count")
    assert_eq(by_key["Change-Id"].builtin_index, nil, "mined trailer key has no built-in index")
    assert_eq(by_key["Fixes"].count, 0, "unused built-in trailer key is kept")

    local items = trailer_capability.keys.items(keys, config.normalize({}).git.trailers.keys, nil)
    table.sort(items, function(a, b)
        return a.sortText < b.sortText
    end)
    local labels = {}
    for _, item in ipairs(items) do
        table.insert(labels, item.label)
    end
    assert_eq(table.concat(labels, ","), "Signed-off-by,Co-authored-by,Change-Id,Fixes", "trailer key sort order")
    assert_eq(items[1].insertText, "Signed-off-by: ", "trailer key insert text")
end

local function test_trailer_identities_request()
    local spec = trailer_capability.identities.request({
        keys = { "Co-authored-by", "bad key", "Signed-off-by" },
        limit = 5,
    })

    assert_eq(spec.exec, "git", "trailer identities command exec")
    assert_eq(spec.args[3], "5", "trailer identities command limit")
    assert_eq(
        spec.args[4],
        "--format=%at%x1f%aN%x1f%aE%x1f%(trailers:key=Co-authored-by,key=Signed-off-by,unfold,separator=%x1f)%x00",
        "trailer identities command format"
    )
end

local function test_trailer_identities_parse()
    local now = os.time()
    local log_result = table.concat({
        tostring(now - 10)
            .. "\031Ada Lovelace\031ada@example.com"
            .. "\031Co-authored-by: Grace Hopper <grace@example.com>"
            .. "\031Signed-off-by: Ada Lovelace <ADA@example.com>\0",
        "\n" .. tostring(now - 20) .. "\031Ada L\031ada@example.com\031Co-authored-by: no email here\0",
        "\n" .. tostring(now - 30) .. "\031Me\031me@example.com\031\0",
        "\n",
    })
    local identities = trailer_capability.identities.parse(log_result, "Me Myself <ME@example.com> 1792648118 +1100\n")

    assert_eq(#identities, 3, "trailer identities dedupe by email")
    assert_eq(identities[1].name, "Ada Lovelace", "trailer identities keep the most recent name")
    assert_eq(identities[1].source, "author", "trailer identities record the author source")
    assert_eq(identities[2].email, "grace@example.com", "trailer identities include trailer values")
    assert_eq(identities[2].source, "Co-authored-by", "trailer identities record the trailer key")
    assert_true(identities[2].diff >= 10, "trailer identities use the commit time")
    assert_eq(identities[3].name, "Me", "your identity in history keeps the history record")
    assert_eq(identities[3].is_self, true, "your identity in history is marked")

    local only_self = trailer_capability.identities.parse("", "Solo <solo@example.com> 1 +0000")
    assert_eq(#only_self, 1, "your identity without history is added")
    assert_eq(only_self[1].is_self, true, "your identity without history is marked")
    assert_eq(only_self[1].diff, 0, "your identity without history sorts first")
    assert_eq(only_self[1].source, "self", "your identity without history has the self source")
end

local function test_trailer_capabilities_use_cache_and_runner()
    local builds = {}
    local runner = {
        build = function(spec, callback)
            table.insert(builds, spec.args[1])
            return {
                command = "git",
                start = function()
                    if spec.args[1] == "var" then
                        callback("Me <me@example.com> 1 +0000", true)
                    else
                        callback("fatal: no commits", false)
                    end
                end,
            }
        end,
    }
    local trailers_config = config.normalize({}).git.trailers

    local key_lists = {}
    local key_args = {
        cache = {},
        callback = function(list)
            table.insert(key_lists, list)
        end,
        config = trailers_config.keys,
        runner = runner,
        bufnr = 50,
    }
    trailer_capability.keys.complete(key_args)
    trailer_capability.keys.complete(key_args)

    assert_eq(table.concat(builds, ","), "log", "trailer keys run once")
    assert_eq(#key_lists, 2, "trailer keys callback on miss and hit")
    assert_eq(#key_lists[1].items, #trailers_config.keys.builtin, "failed log still gives the built-in keys")

    builds = {}
    local identities_lists = {}
    local identities_args = {
        cache = {},
        callback = function(list)
            table.insert(identities_lists, list)
        end,
        config = trailers_config.identities,
        runner = runner,
        bufnr = 51,
    }
    trailer_capability.identities.complete(identities_args)
    trailer_capability.identities.complete(identities_args)

    assert_eq(table.concat(builds, ","), "log,var", "trailer identities run log and var once")
    assert_eq(#identities_lists, 2, "trailer identities callback on miss and hit")
    assert_eq(identities_lists[1].items[1].label, "Me <me@example.com>", "failed log still gives your identity")
end

local function test_trailer_identities_job_cancel()
    local pending
    local builds = 0
    local runner = {
        build = function(_spec, callback)
            builds = builds + 1
            return {
                command = "git",
                start = function()
                    pending = callback
                end,
            }
        end,
    }
    local called = false
    local job = trailer_capability.identities.complete({
        cache = {},
        callback = function()
            called = true
        end,
        config = config.normalize({}).git.trailers.identities,
        runner = runner,
        bufnr = 52,
    })

    job:cancel()
    pending("", true)

    assert_eq(builds, 1, "cancelled trailer identities job does not start git var")
    assert_true(not called, "cancelled trailer identities job does not call back")
end

local function test_blink_adapter_matches_text_before_cursor()
    local blink = Blink.new({})
    local received
    blink.core = {
        get_trigger_characters = function()
            return { "#" }
        end,
        complete = function(_, context, _callback)
            received = context
            return { cancel = function() end }
        end,
    }

    blink:get_completions({ cursor = { 3, 5 }, line = "fix #12 later", bufnr = 1 }, function() end)

    assert_eq(received.line, "fix #", "blink passes the text before the cursor")
    assert_eq(received.trigger_character, "#", "blink detects the trigger before the cursor")
    assert_eq(received.cursor.row, 3, "blink converts the cursor row")
    assert_eq(received.cursor.character, 5, "blink converts the cursor column")
end

local function test_trailer_capabilities_with_git()
    if vim.fn.executable("git") ~= 1 then
        return
    end

    local env_names = { "GIT_CONFIG_GLOBAL", "GIT_CONFIG_NOSYSTEM", "GIT_AUTHOR_NAME", "GIT_AUTHOR_EMAIL" }
    local saved_env = {}
    for _, name in ipairs(env_names) do
        saved_env[name] = vim.env[name]
    end
    vim.env.GIT_CONFIG_GLOBAL = "/dev/null"
    vim.env.GIT_CONFIG_NOSYSTEM = "1"

    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local function git(args)
        local base = { "git", "-C", dir, "-c", "user.name=Ada Lovelace", "-c", "user.email=ada@example.com" }
        local result = vim.system(vim.list_extend(base, args), { text = true }):wait()
        assert_eq(result.code, 0, "test git command " .. table.concat(args, " ") .. ": " .. (result.stderr or ""))
    end
    git({ "init", "-q" })
    git({
        "commit",
        "-q",
        "--allow-empty",
        "--no-verify",
        "-m",
        "feat: first\n\nCo-authored-by: Grace Hopper <grace@example.com>\nChange-Id: I1234\nAssisted-by: Codex",
    })

    vim.env.GIT_AUTHOR_NAME = "Test Self"
    vim.env.GIT_AUTHOR_EMAIL = "self@example.com"
    local cwd = vim.fn.getcwd()
    vim.cmd.cd(dir)

    local trailers_config = config.normalize({}).git.trailers
    local key_list, identities_list, values_list
    trailer_capability.keys.complete({
        cache = {},
        callback = function(list)
            key_list = list
        end,
        config = trailers_config.keys,
        bufnr = 60,
    })
    trailer_capability.identities.complete({
        cache = {},
        callback = function(list)
            identities_list = list
        end,
        config = trailers_config.identities,
        bufnr = 61,
    })
    trailer_capability.values.complete({
        cache = {},
        callback = function(list)
            values_list = list
        end,
        config = trailers_config.values,
        key = "assisted-by",
        bufnr = 62,
    })
    wait_for(function()
        return key_list ~= nil and identities_list ~= nil and values_list ~= nil
    end, "trailer capabilities complete with git")

    vim.cmd.cd(cwd)
    -- A nil value unsets the variable again
    for _, name in ipairs(env_names) do
        vim.env[name] = saved_env[name]
    end
    vim.fn.delete(dir, "rf")

    local keys = {}
    for _, item in ipairs(key_list and key_list.items or {}) do
        keys[item.label] = item.data.count
    end
    assert_eq(keys["Change-Id"], 1, "git trailer keys include mined keys")
    assert_eq(keys["Co-authored-by"], 1, "git trailer keys count built-in keys")

    local identities = {}
    for _, item in ipairs(identities_list and identities_list.items or {}) do
        identities[item.label] = item.data
    end
    assert_true(identities["Ada Lovelace <ada@example.com>"] ~= nil, "git trailer identities include authors")
    assert_eq(
        identities["Grace Hopper <grace@example.com>"] and identities["Grace Hopper <grace@example.com>"].source,
        "Co-authored-by",
        "git trailer identities include trailer values"
    )
    assert_eq(
        identities["Test Self <self@example.com>"] and identities["Test Self <self@example.com>"].is_self,
        true,
        "git trailer identities include your identity"
    )
    assert_eq(values_list and values_list.items[1] and values_list.items[1].label, "Codex", "git trailer values")
end

local function test_trailer_values_request_and_parse()
    local spec = trailer_capability.values.request({ limit = 7 })
    assert_eq(spec.args[3], "7", "trailer values command limit")
    assert_eq(
        spec.args[4],
        "--format=%at%x1f%(trailers:only,unfold,separator=%x1f)%x00",
        "trailer values command format"
    )

    local now = os.time()
    local result = table.concat({
        tostring(now - 10)
            .. '\031Assisted-by: Codex\031Fixes: 29c8d7267dd7 ("fix: snippet edit range")'
            .. "\031Co-authored-by: Grace Hopper <grace@example.com>\0",
        "\n" .. tostring(now - 20) .. "\031assisted-by: Codex\031Assisted-by: claude-code Opus 5\031Ref:\0",
        "\n",
    })
    local by_key = trailer_capability.values.parse(result)

    assert_eq(#by_key["assisted-by"], 2, "trailer values dedupe by value")
    assert_eq(by_key["assisted-by"][1].key, "Assisted-by", "trailer values keep the first key casing")
    assert_eq(by_key["assisted-by"][1].count, 2, "trailer values count across key casing")
    assert_eq(by_key["fixes"][1].value, '29c8d7267dd7 ("fix: snippet edit range")', "trailer values keep colons")
    assert_eq(by_key["co-authored-by"][1].value, "Grace Hopper <grace@example.com>", "trailer values keep identities")
    assert_eq(by_key["ref"], nil, "trailer values skip empty values")

    local items = trailer_capability.values.items(by_key, "Assisted-By", config.normalize({}).git.trailers.values, nil)
    table.sort(items, function(a, b)
        return a.sortText < b.sortText
    end)
    assert_eq(items[1].label, "Codex", "trailer values sort by use count")
    assert_eq(items[2].label, "claude-code Opus 5", "trailer values for the key only")
    assert_eq(#items, 2, "trailer values filter by key")
end

local function test_trailer_values_cache_and_fall_through()
    local builds = 0
    local runner = {
        build = function(_spec, callback)
            builds = builds + 1
            return {
                command = "git",
                start = function()
                    callback("fatal: no commits", false)
                end,
            }
        end,
    }
    local lists = {}
    local args = {
        cache = {},
        callback = function(list)
            table.insert(lists, list)
        end,
        config = config.normalize({}).git.trailers.values,
        key = "Assisted-by",
        runner = runner,
        bufnr = 53,
    }

    assert_true(
        trailer_capability.values.may_have(args.cache, { bufnr = 53, line = "Assisted-by: C" }),
        "unknown cache"
    )
    trailer_capability.values.complete(args)
    trailer_capability.values.complete(args)

    assert_eq(builds, 1, "trailer values run once")
    assert_eq(#lists, 2, "trailer values callback on miss and hit")
    assert_eq(#lists[1].items, 0, "failed log gives no trailer values")
    assert_true(
        not trailer_capability.values.may_have(args.cache, { bufnr = 53, line = "Assisted-by: C" }),
        "cached history without values for the key"
    )

    local core = Core.new({})
    local bufnr = trailer_buffer({ "feat: subject", "", "Note: plain text" })
    local context = { cursor = { row = 3, character = 16 }, line = "Note: plain text", bufnr = bufnr }
    assert_eq(#core:_route(context), 1, "body line with a key routes to values before the first fetch")
    core.sources.git.cache_trailer_values[bufnr] = {}
    assert_eq(#core:_route(context), 0, "body line without history values falls through")
    vim.api.nvim_buf_delete(bufnr, { force = true })
end

test_handle_response()
test_parse_remote_url()
test_missing_executable()
test_fallback()
test_command_fallback_cancels_active_job()
test_command_build_cancel_suppresses_callback()
test_build_job()
test_logger()
test_trigger_action_fallback_for_hash()
test_trigger_action_ordering_for_at()
test_trigger_action_first_handled_wins()
test_preferred_trigger_action_names()
test_legacy_trigger_action_aliases()
test_legacy_trigger_action_arguments()
test_config_normalize_fills_defaults_and_hosts()
test_config_normalize_nested_filter_and_sort_overrides()
test_config_normalize_provider_filter_alias()
test_config_normalize_provider_filter_alias_overrides_nested_filter()
test_config_normalize_does_not_leak_hosts_between_instances()
test_source_new_uses_normalized_config()
test_issue_capability_uses_cache_and_runner()
test_mention_capability_preflight_and_pagination()
test_change_request_capability_returns_job()
test_commit_capability_parse_nul_records()
test_commit_capability_parse_marker_collision_and_malformed_records()
test_commit_capability_maps_items_without_cmp_params()
test_commit_capability_uses_parsed_cache_and_runner()
test_git_commit_edit_range_is_preserved()
test_core_text_edit_ranges_for_all_triggers()
test_blink_adapter_api_and_cancellation()
test_blink_adapter_suppresses_stale_callbacks_after_cancel()
test_github_instance_state_isolation()
test_gitlab_instance_state_isolation()
test_git_instance_state_isolation()
test_config_trailer_defaults()
test_custom_trigger_actions_remove_trailers()
test_invalid_trigger_action_pattern_is_skipped()
test_config_git_filter_alias_skips_trailers()
test_core_keyword_pattern_offsets()
test_trailer_routing()
test_trailer_gating()
test_core_pre_route_skips_repository()
test_trailer_text_edits()
test_trailer_keys_parse_and_sort()
test_trailer_identities_request()
test_trailer_identities_parse()
test_trailer_capabilities_use_cache_and_runner()
test_trailer_identities_job_cancel()
test_blink_adapter_matches_text_before_cursor()
test_trailer_capabilities_with_git()
test_trailer_values_request_and_parse()
test_trailer_values_cache_and_fall_through()

if #failures > 0 then
    for _, failure in ipairs(failures) do
        vim.api.nvim_err_writeln(failure)
    end
    os.exit(1)
end

print("cmp-git tests passed")
