local Core = require("cmp_git.core")

local Blink = {}

function Blink.new(opts)
    local self = setmetatable({}, {
        __index = Blink,
    })

    self.core = Core.new(opts)

    return self
end

function Blink:enabled()
    return self.core:is_available()
end

function Blink:get_trigger_characters()
    return self.core:get_trigger_characters()
end

local function trigger_character_from_context(ctx, trigger_characters)
    if ctx.trigger and ctx.trigger.character then
        return ctx.trigger.character
    end

    if ctx.trigger_character then
        return ctx.trigger_character
    end

    local line = ctx.line or ctx.cursor_before_line or vim.api.nvim_get_current_line()
    local escaped = table.concat(trigger_characters, "")
    return string.match(line, "%s*([" .. escaped .. "])%S*$")
end

local function cursor_from_context(ctx)
    if ctx.cursor and ctx.cursor.row and ctx.cursor.character then
        return ctx.cursor
    end

    if ctx.cursor and ctx.cursor.line and ctx.cursor.character then
        return { row = ctx.cursor.line + 1, character = ctx.cursor.character }
    end

    local position = vim.api.nvim_win_get_cursor(0)
    return { row = position[1], character = position[2] }
end

function Blink:get_completions(ctx, callback)
    local cancelled = false
    local cursor = cursor_from_context(ctx)
    local line = ctx.line or ctx.cursor_before_line or string.sub(vim.api.nvim_get_current_line(), 1, cursor.character)
    local controller = self.core:complete({
        trigger_character = trigger_character_from_context(ctx, self.core:get_trigger_characters()),
        cursor = cursor,
        line = line,
        bufnr = ctx.bufnr or vim.api.nvim_get_current_buf(),
    }, function(list)
        if cancelled then
            return
        end

        callback({
            items = list.items,
            is_incomplete_backward = false,
            is_incomplete_forward = list.isIncomplete or false,
        })
    end)

    return function()
        cancelled = true
        if controller and controller.cancel then
            controller:cancel()
        end
    end
end

return Blink
