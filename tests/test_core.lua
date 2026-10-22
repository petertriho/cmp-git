local helpers = require("tests.helpers")
local Core = require("cmp_git.core")
local Source = require("cmp_git.source")
local repository = require("cmp_git.repository")

local eq = helpers.eq
local ok = helpers.ok

-- The cases replace the provider sources with partial fakes
---@diagnostic disable: missing-fields

local T = helpers.new_set()

T["git_commit_edit_range_is_preserved"] = function()
    local items = Core.apply_text_edits(
        { { insertText = "abcdef1" } },
        { cursor = { row = 3, character = 5 }, line = ":abcd", trigger_character = ":" }
    )

    eq(items[1].textEdit.range.start.line, 2, "commit edit range start line")
    eq(items[1].textEdit.range.start.character, 0, "commit edit range start character")
    eq(items[1].textEdit.range["end"].line, 2, "commit edit range end line")
    eq(items[1].textEdit.range["end"].character, 5, "commit edit range end character")
    eq(items[1].textEdit.newText, "abcdef1", "commit edit range new text")
end

T["core_text_edit_ranges_for_all_triggers"] = function()
    local cases = {
        { trigger = ":", line = "refs :abc", cursor = 9, insert = "abcdef1" },
        { trigger = "#", line = "fix #12", cursor = 7, insert = "#123" },
        { trigger = "@", line = "cc @ad", cursor = 6, insert = "@ada" },
        { trigger = "!", line = "see !4", cursor = 6, insert = "!42" },
    }

    for _, case in ipairs(cases) do
        local items = Core.apply_text_edits({ { insertText = case.insert } }, {
            cursor = { row = 1, character = case.cursor },
            line = case.line,
            trigger_character = case.trigger,
        })

        local expected_start = string.find(case.line, case.trigger, 1, true) - 1
        eq(items[1].textEdit.range.start.character, expected_start, case.trigger .. " range starts at trigger")
        eq(items[1].textEdit.range["end"].character, case.cursor, case.trigger .. " range ends at cursor")
        eq(items[1].textEdit.newText, case.insert, case.trigger .. " range inserts text")
    end
end

T["requests_get_new_item_tables"] = function()
    local data = { number = 12 }
    local cached = { { label = "#12: Fix", insertText = "#12", data = data } }
    local core = Core.new({})
    core.sources.gitlab = {
        complete_issues = function()
            return false
        end,
    }
    core.sources.github = {
        -- Like a cache hit of the issues capability
        complete_issues_and_change_requests = function(_, callback)
            callback({ items = cached, isIncomplete = false })
            return true
        end,
    }
    local callback, lists = helpers.recorder()
    local function request(line)
        core:_run_trigger_actions("#", callback, { cursor = { row = 1, character = #line }, line = line }, {})
        return lists[#lists].items[1]
    end

    local first = request("see #1")
    -- blink.cmp writes these into the items that it gets
    first.pos = { 0, 6 }
    first.score_offset = 3
    local second = request("x #")

    ok(first ~= cached[1] and second ~= first, "each request gets new item tables")
    eq(cached[1].textEdit, nil, "the cached item has no text edit")
    eq(first.textEdit.range["end"].character, 6, "a later request does not change the first text edit")
    eq(second.textEdit.range.start.character, 2, "the second text edit starts at its trigger")
    eq(second.textEdit.range["end"].character, 3, "the second text edit ends at its cursor")
    eq(second.pos, nil, "the second item has no position of the first request")
    eq(second.score_offset, nil, "the score offset does not grow")
    eq(second.label, "#12: Fix", "the copy keeps the label")
    ok(second.data == data, "the copy keeps the data")
    eq(lists[2].isIncomplete, false, "the list keeps isIncomplete")
end

T["custom_trigger_actions_remove_trailers"] = function()
    local core = Core.new({
        trigger_actions = {
            { trigger_character = ":", actions = { "git_commits" } },
        },
    })

    eq(#core.trigger_actions, 1, "custom trigger actions replace the trailer entries")
    eq(core.keyword_pattern, "[:]\\S*", "keyword pattern without pattern entries is unchanged")
end

-- Characters that are special in a Vim collection or a Lua pattern set. `^` comes first, where it would negate the
-- set, and `-` between `#` and `@` would make a range that contains `+`.
local SPECIAL_TRIGGER_CHARACTERS = { "^", "#", "-", "@", "%", "]", "\\", "[" }

---@param characters string[]
---@return table core
local function core_with_triggers(characters)
    local trigger_actions = {}
    for _, character in ipairs(characters) do
        table.insert(trigger_actions, { trigger_character = character, actions = { "git_commits" } })
    end
    return Core.new({ trigger_actions = trigger_actions })
end

T["trigger_characters_are_escaped"] = function()
    local core = core_with_triggers(SPECIAL_TRIGGER_CHARACTERS)
    local regex = vim.regex([[\%(]] .. core.keyword_pattern .. [[\)\m$]])

    for _, character in ipairs(SPECIAL_TRIGGER_CHARACTERS) do
        local line = "see " .. character .. "ab"
        eq(regex:match_str(line), 4, "keyword offset of " .. vim.inspect(line))
        eq(
            Core.find_trigger_character(line, core:get_trigger_characters()),
            character,
            "trigger character of " .. vim.inspect(line)
        )
    end
    for _, line in ipairs({ "see ab", "see +ab" }) do
        eq(regex:match_str(line), nil, "no keyword offset for " .. vim.inspect(line))
    end
    eq(Core.find_trigger_character("see +ab", core:get_trigger_characters()), nil, "no trigger in a range")

    local brackets = core_with_triggers({ "[", "]" })
    eq(vim.regex(brackets.keyword_pattern):match_str("see \\ab"), nil, "brackets do not add a backslash")

    local without_triggers = Core.new({ trigger_actions = {} })
    eq(without_triggers:get_keyword_pattern(), nil, "no keyword pattern without trigger characters")
    eq(Core.find_trigger_character("see #ab", {}), nil, "no trigger character without trigger characters")
end

T["invalid_trigger_action_pattern_is_skipped"] = function()
    local core = Core.new({
        trigger_actions = {
            { pattern = [[\%(]], actions = { "git_trailer_keys" } },
            { trigger_character = ":", actions = { "git_commits" } },
        },
    })

    eq(#core.trigger_actions, 1, "invalid pattern entry is skipped")
    eq(core.trigger_actions[1].debug_name, "git_commits", "valid entry is kept")
    helpers.flush()
    eq(
        helpers.notifications[1].message:match("^Invalid trigger action pattern"),
        "Invalid trigger action pattern",
        "invalid pattern logs a warning"
    )
end

T["trigger_action_keyword_pattern"] = function()
    local core = Core.new({
        trigger_actions = {
            { pattern = [[^Refs:\s*\zs\S*]], keyword_pattern = [[^Refs:\zs\S*]], actions = { "git_trailer_values" } },
            { pattern = [[^Key\S*]], keyword_pattern = [[\%(]], actions = { "git_trailer_keys" } },
        },
    })

    eq(core.keyword_pattern, [[\%(^Refs:\zs\S*\|^Key\S*\)]], "keyword patterns replace the patterns")
    eq(core.trigger_actions[1].regex:match_str("Refs: 12"), 6, "routing uses the pattern")
    helpers.flush()
    eq(
        helpers.notifications[1].message:match("^Invalid trigger action keyword_pattern"),
        "Invalid trigger action keyword_pattern",
        "invalid keyword pattern logs a warning"
    )
end

T["core_keyword_pattern_offsets"] = function()
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
        eq(regex:match_str(case[1]), case[2], "keyword offset for " .. vim.inspect(case[1]))
    end
end

-- The trailer value pattern of earlier versions. Its lookbehind is slow, so the default changed to a `\zs` form that
-- must give the same results.
local LOOKBEHIND_VALUE_PATTERN = [[\%(^[[:alnum:]-]\+:\s*\)\@<=\%([^[:space:]<>:#@!][^<>:#@!]*\%(<[^>]*\)\?\)\?]]

---Deterministic lines over the characters that the trailer patterns treat differently.
---@param count integer
---@return string[]
local function random_lines(count)
    local chars = { "a", "B", "-", ":", " ", "#", "@", "!", "<", ">", "\t", "é" }
    local seed = 1
    local function next_int(n)
        seed = (seed * 1103515245 + 12345) % 2147483648
        return seed % n + 1
    end

    local lines = {}
    for _ = 1, count do
        local chunks = {}
        for _ = 1, next_int(16) - 1 do
            table.insert(chunks, chars[next_int(#chars)])
        end
        table.insert(lines, table.concat(chunks))
    end
    return lines
end

---@param core table
---@param debug_name string
---@return any regex
local function action_regex(core, debug_name)
    for _, trigger_action in ipairs(core.trigger_actions) do
        if trigger_action.debug_name == debug_name then
            return trigger_action.regex
        end
    end
    error("no trigger action " .. debug_name)
end

T["trailer_value_pattern_matches_the_lookbehind_pattern"] = function()
    local core = Core.new({})
    -- nvim-cmp wraps the keyword pattern like this
    local keyword = vim.regex([[\%(]] .. core.keyword_pattern .. [[\)\m$]])
    local lookbehind_keyword =
        vim.regex([[\%(\%(^[[:alnum:]-]\+\|]] .. LOOKBEHIND_VALUE_PATTERN .. [[\|[:#@!]\S*\)\)\m$]])
    local value = action_regex(core, "git_trailer_values")
    local lookbehind_value = vim.regex([[\%(]] .. LOOKBEHIND_VALUE_PATTERN .. [[\)$]])

    local lines = {
        "",
        "Co-auth",
        "Co-authored-by:",
        "Co-authored-by: ",
        "Co-authored-by:Ad",
        "Co-authored-by: Ada Lo",
        "Co-authored-by: Ada <ada@ex",
        "Co-authored-by: Ada <ada@example.com> x",
        "Co-authored-by: Ada <a:b#c> @x",
        "Fixes:",
        "Fixes:abc",
        "Fixes: #12",
        "Fixes: 12 #",
        "Fixes:\tvalue",
        "Note: see #12",
        "Note: thanks @ada",
        "Note: see :abc",
        "Key : value",
        " Key: value",
        "-: value",
        "é-key: value",
        "refs :abc",
        "body text he",
    }
    vim.list_extend(lines, random_lines(3000))

    for _, line in ipairs(lines) do
        eq(keyword:match_str(line), lookbehind_keyword:match_str(line), "keyword offset for " .. vim.inspect(line))
        eq(value:match_str(line), lookbehind_value:match_str(line), "value edit start for " .. vim.inspect(line))
    end
end

T["trailer_patterns_are_fast_on_long_lines"] = function()
    local core = Core.new({})
    local regexes = { vim.regex([[\%(]] .. core.keyword_pattern .. [[\)\m$]]) }
    for _, trigger_action in ipairs(core.trigger_actions) do
        table.insert(regexes, trigger_action.regex)
    end
    local line = string.rep("parser cache ", 400)

    local start = vim.uv.hrtime()
    for _ = 1, 3 do
        for _, regex in ipairs(regexes) do
            regex:match_str(line)
        end
    end
    local elapsed_ms = (vim.uv.hrtime() - start) / 1e6

    -- The lookbehind took about 2 s here, and the `\zs` form takes about 1 ms
    ok(elapsed_ms < 200, string.format("patterns take %.1f ms on a %d character line", elapsed_ms, #line))
end

T["trailer_routing"] = function()
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
        local bufnr = helpers.buffer({ "feat: subject", "", case.line })
        core:_run_trigger_actions(case.trigger, function() end, {
            cursor = { row = 3, character = #case.line },
            line = case.line,
            bufnr = bufnr,
        }, {})

        eq(table.concat(calls, ","), case.expected, "route for " .. vim.inspect(case.line))
    end
end

---Replace the regexes of the trigger actions with wrappers that count the matches.
---@param core table
---@return table<string, integer> counts By the name of the first action of each regex.
local function count_regex_matches(core)
    local counts = {}
    local wrappers = {}
    for _, trigger_action in ipairs(core.trigger_actions) do
        local regex = trigger_action.regex
        if regex then
            if not wrappers[regex] then
                local name = trigger_action.debug_name
                counts[name] = 0
                wrappers[regex] = {
                    match_str = function(_, line)
                        counts[name] = counts[name] + 1
                        return regex:match_str(line)
                    end,
                }
            end
            trigger_action.regex = wrappers[regex]
        end
    end
    return counts
end

T["routing_checks_availability_first_and_matches_each_regex_once"] = function()
    local core = Core.new({})
    local counts = count_regex_matches(core)
    local line = "Co-authored-by: Ad"

    local octo = helpers.buffer({ "title", "", line }, "octo")
    eq(#core:_route({ cursor = { row = 3, character = #line }, line = line, bufnr = octo }), 0, "no trailers in octo")
    eq(counts, { git_trailer_keys = 0, git_trailer_identities = 0 }, "unavailable actions match no regex")

    local bufnr = helpers.buffer({ "feat: subject", "", line })
    local context = { cursor = { row = 3, character = #line }, line = line, bufnr = bufnr }
    local routes = core:_route(context)
    eq(#routes, 2, "identities and values routes")
    eq(routes[1].edit_start, 16, "identities edit start")
    eq(routes[2].edit_start, 16, "values edit start")
    eq(counts, { git_trailer_keys = 1, git_trailer_identities = 1 }, "the value actions share one match")

    helpers.stub(repository, "is_git_repo", function(on_result)
        on_result(true)
    end)
    helpers.stub(repository, "discover", function(_, opts)
        opts.on_complete({})
    end)
    core.sources.git = {
        get_trailer_identities = function()
            return true
        end,
        may_have_trailer_values = function()
            return true
        end,
    }
    counts.git_trailer_keys, counts.git_trailer_identities = 0, 0
    core:complete(context, function() end)
    eq(counts, { git_trailer_keys = 1, git_trailer_identities = 1 }, "a request matches each regex once")
end

T["core_pre_route_skips_repository"] = function()
    local checks = 0
    helpers.stub(repository, "is_git_repo", function()
        checks = checks + 1
    end)

    local core = Core.new({})
    local bufnr = helpers.buffer({ "fe" })
    local callback, lists = helpers.recorder()
    core:complete({ cursor = { row = 1, character = 2 }, line = "fe", bufnr = bufnr }, callback)

    eq(checks, 0, "declined request does not check the repository")
    eq(#lists, 1, "declined request calls the callback once")
    eq(#lists[1].items, 0, "declined request has no items")
    eq(lists[1].isIncomplete, false, "declined request is complete")

    local source = Source.new({})
    source:complete({
        context = { cursor_before_line = "fe", cursor = { row = 1, col = 3, character = 2 } },
        completion_context = { triggerKind = 1 },
    }, function() end)
    eq(checks, 0, "declined nvim-cmp request does not check the repository")

    core:complete(
        { trigger_character = ":", cursor = { row = 1, character = 3 }, line = "fe:", bufnr = bufnr },
        function() end
    )
    eq(checks, 1, "matched request checks the repository")
end

---A request for a trigger character on line 1 of a scratch buffer.
---@param trigger string
---@return table context
local function trigger_context(trigger)
    local line = "see " .. trigger
    return {
        trigger_character = trigger,
        cursor = { row = 1, character = #line },
        line = line,
        bufnr = helpers.buffer({ line }),
    }
end

---@param git_info cmp_git.GitInfo
local function stub_repository(git_info)
    helpers.stub(repository, "is_git_repo", function(on_result)
        on_result(true)
    end)
    helpers.stub(repository, "discover", function(_, opts)
        opts.on_complete(git_info)
    end)
end

---@param lists cmp_git.CompletionList[]
---@param reason string
local function expect_one_empty_list(lists, reason)
    eq(#lists, 1, reason .. ": one callback")
    eq(#lists[1].items, 0, reason .. ": no items")
    eq(lists[1].isIncomplete, false, reason .. ": final list")
end

T["complete_answers_when_no_action_handles_the_request"] = function()
    helpers.stub(repository, "is_git_repo", function(on_result)
        on_result(false)
    end)
    local core = Core.new({})
    local callback, lists = helpers.recorder()
    core:complete(trigger_context("#"), callback)
    expect_one_empty_list(lists, "outside a git repository")

    -- Neither GitHub nor GitLab handles these hosts, so the sources decline without a process
    for _, git_info in ipairs({ { host = "gitea.com", owner = "owner", repo = "repo" }, {} }) do
        stub_repository(git_info)
        for _, trigger in ipairs({ "#", "@", "!" }) do
            callback, lists = helpers.recorder()
            core:complete(trigger_context(trigger), callback)
            expect_one_empty_list(lists, string.format("%s with host %s", trigger, git_info.host))
        end
    end

    local unknown = Core.new({ trigger_actions = { { trigger_character = "#", actions = { "no_such_action" } } } })
    callback, lists = helpers.recorder()
    unknown:complete(trigger_context("#"), callback)
    expect_one_empty_list(lists, "unknown action")
end

T["complete_does_not_answer_after_cancel"] = function()
    local pending
    helpers.stub(repository, "is_git_repo", function(on_result)
        pending = on_result
    end)
    local core = Core.new({})
    local callback, lists = helpers.recorder()

    local controller = core:complete(trigger_context("#"), callback)
    controller:cancel()
    pending(false)

    eq(#lists, 0, "cancelled request does not call back")
end

---Stub the repository checks and the sources, and record the calls.
---@param core table
---@param is_git_repo boolean
---@return string[] calls
local function record_calls(core, is_git_repo)
    local calls = {}
    helpers.stub(repository, "is_git_repo", function(on_result)
        table.insert(calls, "is_git_repo")
        on_result(is_git_repo)
    end)
    helpers.stub(repository, "discover", function(_, opts)
        table.insert(calls, "discover")
        opts.on_complete({ host = "github.com", owner = "owner", repo = "repo" })
    end)

    local function record(name, handled)
        return function()
            table.insert(calls, name)
            return handled
        end
    end
    core.sources.git = {
        get_commits = record("commits", true),
        get_trailer_identities = record("identities", true),
        may_have_trailer_values = function()
            return true
        end,
    }
    core.sources.gitlab = {
        complete_issues = record("gitlab_issues", false),
        complete_mentions = record("gitlab_mentions", false),
    }
    core.sources.github = {
        complete_issues = record("github_issues", true),
        complete_issues_and_change_requests = record("github_issues", true),
        complete_mentions = record("github_mentions", true),
    }
    return calls
end

T["complete_discovers_the_remote_only_for_actions_that_need_it"] = function()
    local core = Core.new({})
    local calls = record_calls(core, true)
    local function run(context)
        for key in pairs(calls) do
            calls[key] = nil
        end
        core:complete(context, function() end)
        return table.concat(calls, ",")
    end

    eq(run(trigger_context(":")), "is_git_repo,commits", "commits need no remote")
    eq(run(trigger_context("#")), "is_git_repo,discover,gitlab_issues,github_issues", "issues need the remote")

    -- The identities action handles the request, so the mention actions after it never run
    local line = "Co-authored-by: Ada <ada@"
    local bufnr = helpers.buffer({ "feat: subject", "", line })
    eq(
        run({ trigger_character = "@", cursor = { row = 3, character = #line }, line = line, bufnr = bufnr }),
        "is_git_repo,identities",
        "identities need no remote"
    )

    core = Core.new({
        trigger_actions = {
            {
                trigger_character = "#",
                action = function()
                    table.insert(calls, "legacy")
                    return true
                end,
            },
            { trigger_character = "!", actions = { "no_such_action", "github_issues" } },
        },
    })
    calls = record_calls(core, true)
    eq(run(trigger_context("#")), "is_git_repo,discover,legacy", "legacy actions get the remote")
    eq(run(trigger_context("!")), "is_git_repo,discover,github_issues", "unknown actions do not stop discovery")
end

T["complete_in_octo_buffers_outside_a_git_repository"] = function()
    local core = Core.new({})
    local calls = record_calls(core, false)
    local function run(trigger)
        for key in pairs(calls) do
            calls[key] = nil
        end
        local context = trigger_context(trigger)
        vim.bo[context.bufnr].filetype = "octo"
        local callback, lists = helpers.recorder()
        core:complete(context, callback)
        return table.concat(calls, ","), lists
    end

    eq(run("#"), "discover,gitlab_issues,github_issues", "octo issues skip the repository check")
    eq(run("@"), "discover,gitlab_mentions,github_mentions", "octo mentions skip the repository check")

    local commits, lists = run(":")
    eq(commits, "is_git_repo", "octo commits need a local repository")
    eq(#lists, 1, "octo commits outside a repository answer")
end

T["trailer_text_edits"] = function()
    local core = Core.new({})
    local bufnr = helpers.buffer({ "subject", "", "" })
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
    eq(key.textEdit.range.start.character, 0, "trailer key edit starts at the line start")
    eq(key.textEdit.range["end"].character, 5, "trailer key edit ends at the cursor")
    eq(key.textEdit.newText, "Co-authored-by: ", "trailer key inserts the key and a space")

    local identity = run("Co-authored-by: Ad")
    eq(identity.textEdit.range.start.character, 16, "trailer identity edit starts at the value")
    eq(identity.textEdit.range["end"].character, 18, "trailer identity edit ends at the cursor")
    eq(identity.textEdit.newText, "Ada Lovelace <ada@example.com>", "trailer identity inserts the identity")
    eq(identity.filterText, "Ada Lovelace <ada@example.com>", "trailer identity filters on the identity")

    local attached = run("Co-authored-by:", ":")
    eq(attached.textEdit.range.start.character, 15, "attached trailer identity edit starts after the colon")
    eq(attached.textEdit.newText, " Ada Lovelace <ada@example.com>", "attached trailer identity adds a space")
    eq(attached.filterText, ": Ada Lovelace <ada@example.com>", "attached trailer identity filters on the colon")

    local email = run("Co-authored-by: Ada <ada@", "@")
    eq(email.textEdit.range.start.character, 16, "trailer identity edit ignores the @ trigger in the email")
    eq(email.textEdit.newText, "Ada Lovelace <ada@example.com>", "trailer identity ignores the @ trigger")

    local value = run("Assisted-by: Co")
    eq(value.textEdit.range.start.character, 13, "trailer value edit starts at the value")
    eq(value.textEdit.newText, "Codex", "trailer value inserts the earlier value")
    eq(value.filterText, "Codex", "trailer value filters on the value")

    local attached_value = run("Assisted-by:Co", ":")
    eq(attached_value.textEdit.range.start.character, 12, "attached trailer value edit starts after the colon")
    eq(attached_value.textEdit.newText, " Codex", "attached trailer value adds a space")
    eq(attached_value.filterText, ": Codex", "attached trailer value filters on the colon")
end

T["complete_discovers_the_repository_of_the_request_buffer"] = function()
    local core = Core.new({})
    local request_bufnr = helpers.buffer({ "See #" })
    vim.api.nvim_set_current_buf(helpers.buffer({ "Another buffer" }))

    local seen = {}
    helpers.stub(repository, "is_git_repo", function(on_result, bufnr)
        seen.is_git_repo = bufnr
        on_result(true)
    end)
    helpers.stub(repository, "discover", function(_, opts)
        seen.discover = opts.bufnr
        opts.on_complete({})
    end)

    local callback, lists = helpers.recorder()
    core:complete({
        trigger_character = "#",
        cursor = { row = 1, character = 5 },
        line = "See #",
        bufnr = request_bufnr,
    }, callback)

    eq(seen, { is_git_repo = request_bufnr, discover = request_bufnr }, "discovery reads the request buffer")
    eq(#lists, 1, "the request answers")
end

return T
