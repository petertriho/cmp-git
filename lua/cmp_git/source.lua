local Core = require("cmp_git.core")

---The fields of nvim-cmp's `cmp.SourceCompletionApiParams` that cmp-git reads.
---@class cmp_git.CmpCompletionParams
---@field context { cursor_before_line: string, cursor: { row: integer, col: integer, character: integer } } `col` is a 1-based byte column, and `character` counts UTF-16 code units.
---@field completion_context { triggerKind: integer, triggerCharacter?: string }

local Source = {}

function Source.new(overrides)
    local core = Core.new(overrides)
    local self = setmetatable({ core = core }, {
        __index = function(_, key)
            return Source[key] or core[key]
        end,
    })

    self.config = core.config
    self.filetypes = core.filetypes
    self.sources = core.sources
    self.trigger_actions = core.trigger_actions
    self.trigger_characters = core.trigger_characters
    self.trigger_characters_str = core.trigger_characters_str
    self.keyword_pattern = core.keyword_pattern

    return self
end

---@param params cmp_git.CmpCompletionParams
---@param trigger_characters_str string
---@return string?
local function trigger_character_from_params(params, trigger_characters_str)
    local trigger_kind = params.completion_context.triggerKind
    -- nvim-cmp asks again with TriggerForIncompleteCompletions (3) when the user types after an incomplete list, such
    -- as the first page of mentions. Like Invoked (1), it has no trigger character.
    if trigger_kind == 1 or trigger_kind == 3 then
        return string.match(params.context.cursor_before_line, "%s*([" .. trigger_characters_str .. "])%S*$")
    elseif trigger_kind == 2 then
        return params.completion_context.triggerCharacter
    end

    return nil
end

---@param cursor? { row: integer, col: integer }
---@return { row: integer, character: integer }?
local function byte_cursor(cursor)
    return cursor and { row = cursor.row, character = cursor.col - 1 }
end

---@param params cmp_git.CmpCompletionParams
---@return cmp_git.CompletionContext
function Source:_context_from_params(params)
    local trigger_character = trigger_character_from_params(params, self.trigger_characters_str)

    return {
        trigger_character = trigger_character,
        cursor = byte_cursor(params.context.cursor),
        line = params.context.cursor_before_line,
        params = params,
        bufnr = vim.api.nvim_get_current_buf(),
    }
end

---@param params cmp_git.CmpCompletionParams
---@param callback fun(args: cmp_git.CompletionList)
function Source:_complete(params, callback)
    return self.core:_complete(self:_context_from_params(params), callback)
end

---@param trigger_character string?
---@param callback fun(args: cmp_git.CompletionList)
---@param params cmp_git.CmpCompletionParams
---@param git_info cmp_git.GitInfo
function Source:_run_trigger_actions(trigger_character, callback, params, git_info)
    return self.core:_run_trigger_actions(trigger_character, callback, {
        trigger_character = trigger_character,
        cursor = params and params.context and byte_cursor(params.context.cursor),
        line = params and params.context and params.context.cursor_before_line,
        params = params,
        bufnr = vim.api.nvim_get_current_buf(),
    }, git_info)
end

---@param params cmp_git.CmpCompletionParams
---@param callback fun(args: cmp_git.CompletionList)
function Source:complete(params, callback)
    return self.core:complete(self:_context_from_params(params), callback)
end

---nvim-cmp reads the text edit ranges as UTF-16 unless the source names another encoding. cmp-git finds the edit
---start in bytes.
---@return string
function Source:get_position_encoding_kind()
    return "utf-8"
end

function Source:get_keyword_pattern()
    return self.core:get_keyword_pattern()
end

function Source:get_trigger_characters()
    return self.core:get_trigger_characters()
end

function Source:get_debug_name()
    return self.core:get_debug_name()
end

function Source:is_available()
    return self.core:is_available()
end

return Source
