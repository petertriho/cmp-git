local Core = require("cmp_git.core")
local repository = require("cmp_git.repository")

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

---@param params cmp.SourceCompletionApiParams
---@param callback fun(args: cmp_git.CompletionList)
local function trigger_character_from_params(params, trigger_characters_str)
    if params.completion_context.triggerKind == 1 then
        return string.match(params.context.cursor_before_line, "%s*([" .. trigger_characters_str .. "])%S*$")
    elseif params.completion_context.triggerKind == 2 then
        return params.completion_context.triggerCharacter
    end

    return nil
end

function Source:_context_from_params(params)
    local trigger_character = trigger_character_from_params(params, self.trigger_characters_str)

    return {
        trigger_character = trigger_character,
        cursor = params.context.cursor,
        line = params.context.cursor_before_line,
        params = params,
        bufnr = vim.api.nvim_get_current_buf(),
    }
end

---@param params cmp.SourceCompletionApiParams
---@param callback fun(args: cmp_git.CompletionList)
function Source:_complete(params, callback)
    return self.core:_complete(self:_context_from_params(params), callback)
end

---@param trigger_character string?
---@param callback fun(args: cmp_git.CompletionList)
---@param params cmp.SourceCompletionApiParams
---@param git_info cmp_git.GitInfo
function Source:_run_trigger_actions(trigger_character, callback, params, git_info)
    return self.core:_run_trigger_actions(trigger_character, callback, {
        trigger_character = trigger_character,
        cursor = params and params.context and params.context.cursor,
        line = params and params.context and params.context.cursor_before_line,
        params = params,
        bufnr = vim.api.nvim_get_current_buf(),
    }, git_info)
end

---@module 'cmp'
---@param params cmp.SourceCompletionApiParams
---@param callback fun(args: cmp_git.CompletionList)
function Source:complete(params, callback)
    local state = { cancelled = false, active = nil }
    local controller = {
        command = "cmp_git_source_complete",
        cancel = function()
            state.cancelled = true
            if state.active and state.active.cancel then
                state.active:cancel()
            end
        end,
    }

    repository.is_git_repo(function(is_git_repo)
        if state.cancelled then
            return
        end
        if not is_git_repo then
            return
        end
        state.active = self:_complete(params, callback)
    end)

    return controller
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
