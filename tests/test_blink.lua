local helpers = require("tests.helpers")
local Blink = require("cmp_git.blink")
local repository = require("cmp_git.repository")

local eq = helpers.eq

local T = helpers.new_set()

T["blink_adapter_api_and_cancellation"] = function()
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
            eq(context.trigger_character, "#", "blink forwards trigger character")
            eq(context.cursor.row, 1, "blink forwards cursor row")
            eq(context.cursor.character, 5, "blink forwards cursor character")
            callback({ items = { { label = "#1", insertText = "#1" } }, isIncomplete = true })
            return {
                cancel = function()
                    cancelled = true
                end,
            }
        end,
    }

    eq(blink:enabled(), true, "blink enabled delegates to core")
    eq(blink:get_trigger_characters()[1], "#", "blink trigger characters delegate to core")

    local cancel = blink:get_completions({
        trigger = { character = "#" },
        cursor = { line = 0, character = 5 },
        line = "fix #",
        bufnr = 1,
    }, function(result)
        callback_result = result
    end)

    eq(callback_result.items[1].label, "#1", "blink maps completion items")
    eq(callback_result.is_incomplete_backward, false, "blink disables backward incomplete requests")
    eq(callback_result.is_incomplete_forward, true, "blink forwards incomplete state")

    cancel()
    eq(cancelled, false, "a request that answered continues to fill the cache")
end

T["blink_adapter_suppresses_stale_callbacks_after_cancel"] = function()
    local blink = Blink.new({})
    local pending_callback
    local called = false
    local cancelled = false
    blink.core = {
        is_available = function()
            return true
        end,
        get_trigger_characters = function()
            return { "#" }
        end,
        complete = function(_, _context, callback)
            pending_callback = callback
            return {
                cancel = function()
                    cancelled = true
                end,
            }
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

    eq(cancelled, true, "blink cancellation delegates to core job")
    eq(called, false, "blink suppresses stale callback after cancellation")
end

T["blink_adapter_forwards_the_first_response_only"] = function()
    local blink = Blink.new({})
    blink.core = {
        get_trigger_characters = function()
            return { "@" }
        end,
        -- Like the mentions capability: a first page, then the cached list with the next page
        complete = function(_, _context, callback)
            local first = { label = "@ada" }
            callback({ items = { first }, isIncomplete = true })
            callback({ items = { first, { label = "@grace" } }, isIncomplete = false })
            return { cancel = function() end }
        end,
    }
    local responses = {}

    blink:get_completions({ trigger = { character = "@" }, cursor = { 1, 4 }, line = "cc @" }, function(response)
        table.insert(responses, response)
    end)

    eq(#responses, 1, "blink gets one response for each request")
    eq(#responses[1].items, 1, "the response has the first page")
    eq(responses[1].is_incomplete_forward, true, "blink asks again on the next keystroke")
end

T["blink_adapter_special_trigger_characters"] = function()
    local blink = Blink.new({})
    local received
    blink.core = {
        get_trigger_characters = function()
            return { "%", "]", "-" }
        end,
        complete = function(_, context, _callback)
            received = context
            return { cancel = function() end }
        end,
    }

    blink:get_completions({ cursor = { 1, 7 }, line = "see %ab", bufnr = 1 }, function() end)

    eq(received.trigger_character, "%", "blink detects a special trigger character")
end

T["blink_adapter_matches_text_before_cursor"] = function()
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

    eq(received.line, "fix #", "blink passes the text before the cursor")
    eq(received.trigger_character, "#", "blink detects the trigger before the cursor")
    eq(received.cursor.row, 3, "blink converts the cursor row")
    eq(received.cursor.character, 5, "blink converts the cursor column")
end

---A prefix word item, as the autosquash capability gives it and blink.cmp keeps it.
local PREFIX_ITEM = {
    label = "fixup!",
    insertText = "fixup! ",
    data = { word = "fixup", index = 1, reopen = true },
    source_id = "cmp_git",
}
---A commit item of the autosquash commit list.
local COMMIT_ITEM = {
    label = "feat: add parser",
    insertText = "feat: add parser",
    data = { sha = "abcdef1" },
    source_id = "cmp_git",
}

---Replace the `blink.cmp` module with a stub that records the `show` calls in `events`.
---@param events table[]
local function stub_blink(events)
    helpers.stub(package.loaded, "blink.cmp", {
        show = function(opts)
            table.insert(events, { "show", opts })
        end,
    })
end

T["blink_execute_reopens_the_menu_after_a_prefix_item"] = function()
    local blink = Blink.new({})
    local events = {}
    stub_blink(events)
    local function callback()
        table.insert(events, { "callback" })
    end
    local function default_implementation()
        table.insert(events, { "default_implementation" })
    end

    blink:execute({}, PREFIX_ITEM, callback, default_implementation)
    eq(events, { { "default_implementation" }, { "callback" } }, "the insert and the callback run at once")
    helpers.flush()
    eq(
        events,
        { { "default_implementation" }, { "callback" }, { "show", { providers = { "cmp_git" } } } },
        "one show for the provider of the item, after the callback"
    )

    events = {}
    stub_blink(events)
    blink:execute({}, COMMIT_ITEM, callback, default_implementation)
    helpers.flush()
    eq(events, { { "default_implementation" }, { "callback" } }, "a commit item does not reopen the menu")
end

T["blink_execute_without_blink"] = function()
    local blink = Blink.new({})
    helpers.stub(package.loaded, "blink.cmp", nil)
    helpers.stub(package.preload, "blink.cmp", function()
        error("module 'blink.cmp' not found")
    end)
    -- A scheduled error would only print a message, so the reopen runs at once
    helpers.stub(vim, "schedule", function(fn)
        fn()
    end)
    local calls = {}

    blink:execute({}, PREFIX_ITEM, function()
        table.insert(calls, "callback")
    end, function()
        table.insert(calls, "default_implementation")
    end)

    eq(calls, { "default_implementation", "callback" }, "the insert and the callback run, and execute raises no error")
end

T["blink_reopen_request_gives_the_commit_items"] = function()
    helpers.stub(repository, "is_git_repo", function(on_result)
        on_result(true)
    end)
    local blink = Blink.new({})
    local bufnr = helpers.buffer({ "fixup! " })
    blink.core.sources.git.cache_commits[bufnr] = {
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
    local result

    blink:get_completions({ cursor = { 1, 7 }, line = "fixup! ", bufnr = bufnr }, function(response)
        result = response
    end)

    local item = helpers.not_nil(result, "the request answers").items[1]
    eq(item.label, "feat: add parser", "the commit items")
    eq(item.textEdit.range.start.character, 7, "the edit starts after the prefix and its space")
    eq(item.textEdit.newText, "feat: add parser", "the insert is the title")
end

return T
