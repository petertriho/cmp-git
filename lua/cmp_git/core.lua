local github = require("cmp_git.sources.github")
local gitlab = require("cmp_git.sources.gitlab")
local git = require("cmp_git.sources.git")
local config = require("cmp_git.config")
local repository = require("cmp_git.repository")

local ROUTE_HANDLED = "handled"
local ROUTE_UNSUPPORTED_HOST = "unsupported_host"
local ROUTE_UNAVAILABLE = "unavailable"

local function route_status(handled, job)
    if handled then
        return ROUTE_HANDLED, job
    end

    return ROUTE_UNSUPPORTED_HOST, job
end

local builtin_trigger_actions = {
    git_commits = function(core, callback, context, _git_info, trigger_char)
        return route_status(core.sources.git:get_commits(callback, context, trigger_char))
    end,
    github_issues = function(core, callback, _context, git_info, trigger_char)
        return route_status(core.sources.github:complete_issues(callback, git_info, trigger_char))
    end,
    github_mentions = function(core, callback, _context, git_info, trigger_char)
        return route_status(core.sources.github:complete_mentions(callback, git_info, trigger_char))
    end,
    github_change_requests = function(core, callback, _context, git_info, trigger_char)
        return route_status(core.sources.github:complete_change_requests(callback, git_info, trigger_char))
    end,
    github_issues_and_change_requests = function(core, callback, _context, git_info, trigger_char)
        return route_status(core.sources.github:complete_issues_and_change_requests(callback, git_info, trigger_char))
    end,
    gitlab_issues = function(core, callback, _context, git_info, trigger_char)
        return route_status(core.sources.gitlab:complete_issues(callback, git_info, trigger_char))
    end,
    gitlab_mentions = function(core, callback, _context, git_info, trigger_char)
        return route_status(core.sources.gitlab:complete_mentions(callback, git_info, trigger_char))
    end,
    gitlab_change_requests = function(core, callback, _context, git_info, trigger_char)
        return route_status(core.sources.gitlab:complete_change_requests(callback, git_info, trigger_char))
    end,
    gitlab_mrs = function(core, callback, _context, git_info, trigger_char)
        return route_status(core.sources.gitlab:complete_change_requests(callback, git_info, trigger_char))
    end,
    github_issues_and_prs = function(core, callback, _context, git_info, trigger_char)
        return route_status(core.sources.github:complete_issues_and_change_requests(callback, git_info, trigger_char))
    end,
}

local function normalize_trigger_action(configured_action)
    if configured_action.action then
        return {
            debug_name = configured_action.debug_name,
            trigger_character = configured_action.trigger_character,
            action = function(core, _callback, context, git_info, trigger_char)
                return route_status(
                    configured_action.action(
                        core.sources,
                        trigger_char,
                        context.original_callback,
                        context.params,
                        git_info
                    )
                )
            end,
        }
    end

    local normalized = {}
    for _, action_name in ipairs(configured_action.actions or {}) do
        local action = builtin_trigger_actions[action_name]
        table.insert(normalized, {
            debug_name = action_name,
            trigger_character = configured_action.trigger_character,
            action = function(core, callback, context, git_info, trigger_char)
                if not action then
                    return ROUTE_UNAVAILABLE
                end

                return action(core, callback, context, git_info, trigger_char)
            end,
        })
    end

    return normalized
end

local Core = {}

function Core.new(overrides)
    local self = setmetatable({}, {
        __index = Core,
    })

    self.config = config.normalize(overrides)
    self.filetypes = {}
    self.sources = {}
    self.trigger_actions = {}
    self.trigger_characters = {}

    for _, item in ipairs(self.config.filetypes) do
        self.filetypes[item] = true
    end

    self.sources.git = git.new(self.config.git)
    self.sources.gitlab = gitlab.new(self.config.gitlab)
    self.sources.github = github.new(self.config.github)

    for _, configured_action in ipairs(self.config.trigger_actions) do
        local normalized = normalize_trigger_action(configured_action)
        if normalized.action then
            normalized = { normalized }
        end

        for _, trigger_action in ipairs(normalized) do
            table.insert(self.trigger_actions, trigger_action)
            if not vim.tbl_contains(self.trigger_characters, trigger_action.trigger_character) then
                table.insert(self.trigger_characters, trigger_action.trigger_character)
            end
        end
    end

    self.trigger_characters_str = table.concat(self.trigger_characters, "")
    self.keyword_pattern = string.format("[%s]\\S*", self.trigger_characters_str)

    return self
end

local function find_trigger_start(line, trigger_character, cursor_character)
    if not line or not trigger_character then
        return cursor_character
    end

    local before_cursor = string.sub(line, 1, cursor_character)
    local trigger_start = nil
    local search_start = 1
    while true do
        local found = string.find(before_cursor, trigger_character, search_start, true)
        if not found then
            break
        end
        trigger_start = found - 1
        search_start = found + 1
    end

    return trigger_start or cursor_character
end

function Core.apply_text_edits(items, context)
    if not context or not context.cursor then
        return
    end

    local row = context.cursor.row or context.cursor.line or 1
    local character = context.cursor.character or context.cursor.col or 0
    local start_character = find_trigger_start(context.line, context.trigger_character, character)

    for _, item in ipairs(items or {}) do
        local new_text = item.insertText or item.label
        item.textEdit = {
            range = {
                start = {
                    line = row - 1,
                    character = start_character,
                },
                ["end"] = {
                    line = row - 1,
                    character = character,
                },
            },
            newText = new_text,
        }
    end
end

function Core:_wrap_callback(context, callback)
    return function(list)
        Core.apply_text_edits(list.items, context)
        callback(list)
    end
end

function Core:_run_trigger_actions(trigger_character, callback, context, git_info)
    context = context or {}
    context.trigger_character = trigger_character
    context.original_callback = callback
    local wrapped_callback = self:_wrap_callback(context, callback)

    for _, trigger in ipairs(self.trigger_actions) do
        if trigger.trigger_character == trigger_character then
            local result, job = trigger.action(self, wrapped_callback, context, git_info, trigger_character)
            if result == ROUTE_HANDLED then
                return job
            end
        end
    end
end

function Core:_complete(context, callback)
    local state = { cancelled = false, active = nil }
    local controller = {
        command = "cmp_git_complete",
        cancel = function()
            state.cancelled = true
            if state.active and state.active.cancel then
                state.active:cancel()
            end
        end,
    }

    repository.discover(self.config.remotes, {
        enableRemoteUrlRewrites = self.config.enableRemoteUrlRewrites,
        ssh_aliases = self.config.ssh_aliases,
        on_complete = function(git_info)
            if state.cancelled then
                return
            end
            state.active = self:_run_trigger_actions(context.trigger_character, callback, context, git_info)
        end,
    })

    return controller
end

function Core:complete(context, callback)
    local state = { cancelled = false, active = nil }
    local controller = {
        command = "cmp_git_complete",
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
        state.active = self:_complete(context, callback)
    end)

    return controller
end

function Core:get_keyword_pattern()
    return self.keyword_pattern
end

function Core:get_trigger_characters()
    return self.trigger_characters
end

function Core:get_debug_name()
    return "git"
end

function Core:is_available()
    if self.filetypes["*"] ~= nil or self.filetypes[vim.bo.filetype] ~= nil then
        return true
    end

    for ft in string.gmatch(vim.bo.filetype, "[^%.]*") do
        if self.filetypes[ft] ~= nil then
            return true
        end
    end

    return false
end

return Core
