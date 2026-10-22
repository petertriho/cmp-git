local helpers = require("tests.helpers")
local Blink = require("cmp_git.blink")

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
    eq(cancelled, true, "blink cancellation delegates to core job")
end

T["blink_adapter_suppresses_stale_callbacks_after_cancel"] = function()
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

    eq(called, false, "blink suppresses stale callback after cancellation")
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

return T
