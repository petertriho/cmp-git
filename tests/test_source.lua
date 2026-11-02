local helpers = require("tests.helpers")
local Source = require("cmp_git.source")
local repository = require("cmp_git.repository")

local eq = helpers.eq
local ok = helpers.ok

-- The cases replace the provider sources with partial fakes
---@diagnostic disable: missing-fields

local T = helpers.new_set()

-- Core runs the action of a provider only for the hosts of that provider. A host of both providers lets a case run
-- the GitLab and the GitHub actions of a trigger.
local function shared_hosts()
    return { hosts = { "git.example.com" } }
end

---@return cmp_git.GitInfo
local function shared_remote()
    return { host = "git.example.com", owner = "owner", repo = "repo" }
end

T["trigger_action_fallback_for_hash"] = function()
    local source = Source.new({
        github = shared_hosts(),
        gitlab = shared_hosts(),
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

    source:_run_trigger_actions("#", function() end, {}, shared_remote())

    eq(table.concat(calls, ","), "gitlab,github", "hash trigger falls back in configured order")
end

T["trigger_action_ordering_for_at"] = function()
    local source = Source.new({
        github = shared_hosts(),
        gitlab = shared_hosts(),
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

    source:_run_trigger_actions("@", function() end, {}, shared_remote())

    eq(table.concat(calls, ","), "gitlab,github", "at trigger falls back in configured order")
end

T["trigger_action_first_handled_wins"] = function()
    local source = Source.new({
        github = shared_hosts(),
        gitlab = shared_hosts(),
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

    source:_run_trigger_actions("#", function() end, {}, shared_remote())

    eq(table.concat(calls, ","), "gitlab", "first handled trigger action wins")
end

T["preferred_trigger_action_names"] = function()
    local source = Source.new({
        github = shared_hosts(),
        gitlab = shared_hosts(),
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

    source:_run_trigger_actions("#", function() end, {}, shared_remote())
    source:_run_trigger_actions("!", function() end, {}, shared_remote())

    eq(table.concat(calls, ","), "github_issues,gitlab_change_requests", "preferred action names route")
end

T["legacy_trigger_action_aliases"] = function()
    local source = Source.new({
        github = shared_hosts(),
        gitlab = shared_hosts(),
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

    source:_run_trigger_actions("#", function() end, {}, shared_remote())
    source:_run_trigger_actions("!", function() end, {}, shared_remote())

    eq(table.concat(calls, ","), "github_combined,gitlab_cr", "legacy aliases route")
end

T["legacy_trigger_action_arguments"] = function()
    ---@type { sources: cmp_git.Sources, trigger_char: string, callback: function, params: table, git_info: cmp_git.GitInfo }?
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

    local actual = helpers.not_nil(received, "legacy trigger action runs")
    ok(actual.sources == source.sources, "legacy trigger action receives sources")
    eq(actual.trigger_char, "#", "legacy trigger action receives trigger character")
    ok(actual.callback == callback, "legacy trigger action receives callback")
    ok(actual.params == params, "legacy trigger action receives params")
    ok(actual.git_info == git_info, "legacy trigger action receives git info")
end

---A source whose GitHub actions answer from a fake cache, in a repository with a GitHub remote.
---@return table source
---@return string[] calls
local function github_source()
    helpers.stub(repository, "is_git_repo", function(on_result)
        on_result(true)
    end)
    helpers.stub(repository, "discover", function(_, opts)
        opts.on_complete({ host = "github.com", owner = "owner", repo = "repo" })
    end)

    local source = Source.new({})
    local calls = {}
    local function answer(name, insert)
        return function(_, callback)
            table.insert(calls, name)
            callback({ items = { { label = insert, insertText = insert } }, isIncomplete = false })
            return true
        end
    end
    source.sources.gitlab = {
        complete_issues = function()
            return false
        end,
        complete_mentions = function()
            return false
        end,
    }
    source.sources.github = {
        complete_issues_and_change_requests = answer("issues", "#123"),
        complete_mentions = answer("mentions", "@login"),
    }
    return source, calls
end

---The nvim-cmp parameters of a request at the end of `line`.
---@param line string
---@param trigger_kind integer
---@return cmp_git.CmpCompletionParams
local function cmp_params(line, trigger_kind)
    return {
        context = {
            cursor_before_line = line,
            cursor = { row = 1, col = #line + 1, character = vim.str_utfindex(line, "utf-16") },
        },
        completion_context = { triggerKind = trigger_kind },
    }
end

T["nvim_cmp_text_edits_use_bytes"] = function()
    local source = github_source()
    eq(source:get_position_encoding_kind(), "utf-8", "the source reports byte positions")

    for _, line in ipairs({ "für #12", "héllo @ab" }) do
        local callback, lists = helpers.recorder()
        source:complete(cmp_params(line, 1), callback)

        local range = lists[1].items[1].textEdit.range
        eq(range.start.character, #line:match("^.* "), "edit starts at the trigger byte of " .. vim.inspect(line))
        eq(range["end"].character, #line, "edit ends at the cursor byte of " .. vim.inspect(line))
    end
end

T["nvim_cmp_incomplete_list_requests_find_the_trigger"] = function()
    local source, calls = github_source()

    -- TriggerForIncompleteCompletions, after the user typed `ad` behind an incomplete list of mentions
    local callback, lists = helpers.recorder()
    source:complete(cmp_params("cc @ad", 3), callback)

    eq(calls, { "mentions" }, "the request completes mentions")
    eq(lists[1].items[1].label, "@login", "the request gets the mentions")
end

T["nvim_cmp_special_trigger_characters"] = function()
    local source = Source.new({
        github = shared_hosts(),
        gitlab = shared_hosts(),
        trigger_actions = {
            { trigger_character = "%", actions = { "github_issues" } },
            { trigger_character = "]", actions = { "github_issues" } },
        },
    })
    local triggers = {}
    source.sources.github = {
        complete_issues = function(_, _, _, trigger_char)
            table.insert(triggers, trigger_char)
            return true
        end,
    }

    for _, line in ipairs({ "see %ab", "see ]ab" }) do
        local context = source:_context_from_params(cmp_params(line, 1))
        source:_run_trigger_actions(context.trigger_character, function() end, cmp_params(line, 1), shared_remote())
    end

    eq(triggers, { "%", "]" }, "special trigger characters route")
end

---A prefix word item, as the autosquash capability gives it.
local PREFIX_ITEM = { label = "fixup!", insertText = "fixup! ", data = { word = "fixup", index = 1, reopen = true } }
---A commit item of the autosquash commit list.
local COMMIT_ITEM = { label = "feat: add parser", insertText = "feat: add parser", data = { sha = "abcdef1" } }

---Replace the `cmp` module with a stub that records the `complete` calls in `events`.
---@param events table[]
local function stub_cmp(events)
    helpers.stub(package.loaded, "cmp", {
        complete = function(option)
            table.insert(events, { "complete", option })
        end,
    })
end

T["nvim_cmp_execute_reopens_the_menu_after_a_prefix_item"] = function()
    local source = Source.new({})
    local events = {}
    stub_cmp(events)
    local function callback()
        table.insert(events, { "callback" })
    end

    source:execute(PREFIX_ITEM, callback)
    eq(events, { { "callback" } }, "the callback runs at once, and the reopen waits for nvim-cmp to finish the confirm")
    helpers.flush()
    eq(
        events,
        { { "callback" }, { "complete", { config = { sources = { { name = "git" } } } } } },
        "one request with only the git source, after the callback"
    )

    events = {}
    stub_cmp(events)
    source:execute(COMMIT_ITEM, callback)
    helpers.flush()
    eq(events, { { "callback" } }, "a commit item runs the callback and does not reopen the menu")
end

T["nvim_cmp_execute_without_nvim_cmp"] = function()
    local source = Source.new({})
    helpers.stub(package.loaded, "cmp", nil)
    helpers.stub(package.preload, "cmp", function()
        error("module 'cmp' not found")
    end)
    -- A scheduled error would only print a message, so the reopen runs at once
    helpers.stub(vim, "schedule", function(fn)
        fn()
    end)
    local called = false

    source:execute(PREFIX_ITEM, function()
        called = true
    end)

    ok(called, "the callback runs, and execute raises no error")
end

T["nvim_cmp_reopen_request_gives_the_commit_items"] = function()
    helpers.stub(repository, "is_git_repo", function(on_result)
        on_result(true)
    end)
    local source = Source.new({})
    local bufnr = helpers.buffer({ "fixup! " })
    vim.api.nvim_set_current_buf(bufnr)
    source.sources.git.cache_commits[bufnr] = {
        {
            sha = "abcdef1",
            title = "feat: add parser",
            description = "",
            author_name = "Ada Lovelace",
            author_mail = "ada@example.com",
            commit_timestamp = 1700000000,
            diff = 1,
        },
    }
    local callback, lists = helpers.recorder()

    -- `cmp.complete` asks with the Invoked trigger kind
    source:complete(cmp_params("fixup! ", 1), callback)

    eq(#lists, 1, "the request answers")
    local item = lists[1].items[1]
    eq(item.label, "feat: add parser", "the commit items")
    eq(item.textEdit.range.start.character, 7, "the edit starts after the prefix and its space")
    eq(item.textEdit.newText, "feat: add parser", "the insert is the title")
end

T["source_new_uses_normalized_config"] = function()
    local source = Source.new({
        github = {
            issues = {
                limit = 5,
            },
        },
    })

    eq(source.config.github.issues.limit, 5, "source config keeps normalized override")
    eq(source.sources.github.config.issues.limit, 5, "github source receives normalized override")
    eq(
        type(source.sources.github.config.pull_requests.format.label),
        "function",
        "github source receives normalized defaults"
    )
    ok(
        source.sources.github:is_valid_host({ host = "github.com", owner = "owner", repo = "repo" }),
        "github source receives normalized default host"
    )
end

return T
