local helpers = require("tests.helpers")
local Core = require("cmp_git.core")
local Source = require("cmp_git.source")
local repository = require("cmp_git.repository")

local eq = helpers.eq

-- The cases replace the provider sources with partial fakes
---@diagnostic disable: missing-fields

local T = helpers.new_set()

T["git_commit_edit_range_is_preserved"] = function()
    local items = { { insertText = "abcdef1" } }

    Core.apply_text_edits(items, { cursor = { row = 3, character = 5 }, line = ":abcd", trigger_character = ":" })

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
        local items = { { insertText = case.insert } }
        Core.apply_text_edits(items, {
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

T["custom_trigger_actions_remove_trailers"] = function()
    local core = Core.new({
        trigger_actions = {
            { trigger_character = ":", actions = { "git_commits" } },
        },
    })

    eq(#core.trigger_actions, 1, "custom trigger actions replace the trailer entries")
    eq(core.keyword_pattern, "[:]\\S*", "keyword pattern without pattern entries is unchanged")
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

return T
