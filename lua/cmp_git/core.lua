local github = require("cmp_git.sources.github")
local gitlab = require("cmp_git.sources.gitlab")
local git = require("cmp_git.sources.git")
local config = require("cmp_git.config")
local log = require("cmp_git.log")
local repository = require("cmp_git.repository")
local trailers = require("cmp_git.provider.capabilities.trailers")

local ROUTE_HANDLED = "handled"
local ROUTE_UNSUPPORTED_HOST = "unsupported_host"
local ROUTE_UNAVAILABLE = "unavailable"

---A final list without items. The completion engines wait for a final list: blink.cmp holds back the items of all
---sources until its timeout, and nvim-cmp waits when cmp-git is its first source.
---@return cmp_git.CompletionList
local function empty_list()
    return { items = {}, isIncomplete = false }
end

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
    git_trailer_keys = function(core, callback, context, _git_info, trigger_char)
        return route_status(core.sources.git:get_trailer_keys(callback, context, trigger_char))
    end,
    git_trailer_identities = function(core, callback, context, _git_info, trigger_char)
        return route_status(core.sources.git:get_trailer_identities(callback, context, trigger_char))
    end,
    git_trailer_values = function(core, callback, context, _git_info, trigger_char)
        return route_status(core.sources.git:get_trailer_values(callback, context, trigger_char))
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

-- Synchronous checks that run before repository discovery, so that a declined request starts no git process.
local builtin_trigger_availability = {
    git_trailer_keys = function(core, context)
        return trailers.available(core.config.git.trailers, context, "keys")
    end,
    git_trailer_identities = function(core, context)
        return trailers.available(core.config.git.trailers, context, "identities")
    end,
    git_trailer_values = function(core, context)
        return trailers.available(core.config.git.trailers, context, "values")
            and core.sources.git:may_have_trailer_values(context)
    end,
}

---@param pattern string
---@param field "pattern" | "keyword_pattern" The config field, for the warning.
---@return any? regex
local function compile_pattern(pattern, field)
    local ok, regex = pcall(vim.regex, [[\%(]] .. pattern .. [[\)$]])
    if not ok then
        log.warn(string.format("Invalid trigger action %s %s: %s", field, vim.inspect(pattern), regex))
        return nil
    end
    return regex
end

---@class cmp_git.TriggerAction
---@field debug_name string
---@field trigger_character? string
---@field regex? any The compiled `pattern`. Entries with the same pattern share it.
---@field keyword_pattern? string
---@field available? fun(core: table, context: table): boolean
---@field action fun(core: table, callback: fun(list: cmp_git.CompletionList), context: table, git_info: cmp_git.GitInfo, trigger_char: string?): string, table?

---@param configured_action table
---@param regexes table<string, any> The compiled patterns, by pattern.
---@return cmp_git.TriggerAction[]
local function normalize_trigger_action(configured_action, regexes)
    if configured_action.action then
        if configured_action.pattern then
            log.warn("Trigger action patterns need named `actions`. The pattern of a legacy `action` is ignored.")
        end

        return {
            {
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
            },
        }
    end

    local regex = nil
    local keyword_pattern = nil
    local trigger_character = configured_action.trigger_character
    if configured_action.pattern then
        regex = regexes[configured_action.pattern] or compile_pattern(configured_action.pattern, "pattern")
        if not regex then
            return {}
        end
        regexes[configured_action.pattern] = regex
        trigger_character = nil

        keyword_pattern = configured_action.pattern
        -- An invalid keyword pattern would make nvim-cmp fail on each keystroke
        if
            configured_action.keyword_pattern
            and compile_pattern(configured_action.keyword_pattern, "keyword_pattern")
        then
            keyword_pattern = configured_action.keyword_pattern
        end
    end

    local normalized = {}
    for _, action_name in ipairs(configured_action.actions or {}) do
        local action = builtin_trigger_actions[action_name]
        table.insert(normalized, {
            debug_name = action_name,
            trigger_character = trigger_character,
            keyword_pattern = keyword_pattern,
            regex = regex,
            available = builtin_trigger_availability[action_name],
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

---@class cmp_git.Sources
---@field git cmp_git.Source.Git
---@field github cmp_git.Source.GitHub
---@field gitlab cmp_git.Source.Gitlab

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

    local patterns = {}
    local regexes = {}
    for _, configured_action in ipairs(self.config.trigger_actions) do
        for _, trigger_action in ipairs(normalize_trigger_action(configured_action, regexes)) do
            table.insert(self.trigger_actions, trigger_action)
            if trigger_action.regex then
                if not vim.tbl_contains(patterns, trigger_action.keyword_pattern) then
                    table.insert(patterns, trigger_action.keyword_pattern)
                end
            elseif
                trigger_action.trigger_character
                and not vim.tbl_contains(self.trigger_characters, trigger_action.trigger_character)
            then
                table.insert(self.trigger_characters, trigger_action.trigger_character)
            end
        end
    end

    self.trigger_characters_str = table.concat(self.trigger_characters, "")
    self.keyword_pattern = string.format("[%s]\\S*", self.trigger_characters_str)
    if #patterns > 0 then
        if #self.trigger_characters > 0 then
            table.insert(patterns, self.keyword_pattern)
        end
        self.keyword_pattern = [[\%(]] .. table.concat(patterns, [[\|]]) .. [[\)]]
    end

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
    local start_character = context.edit_start or find_trigger_start(context.line, context.trigger_character, character)

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

---@class cmp_git.Route
---@field trigger_action cmp_git.TriggerAction
---@field edit_start? integer The match start of a pattern entry.

---Find the trigger actions that apply to the context, in config order. This must stay synchronous and start no
---process, because it runs for every completion request.
---@return cmp_git.Route[]
function Core:_route(context)
    local routes = {}
    -- The match start of each regex, or false. The actions of one entry share its regex.
    local matches = nil

    for _, trigger_action in ipairs(self.trigger_actions) do
        local regex = trigger_action.regex
        local candidate = regex ~= nil
            or (
                trigger_action.trigger_character ~= nil
                and trigger_action.trigger_character == context.trigger_character
            )

        -- `available` runs before the regex, because it is cheap, and a regex can take long on a long line
        if candidate and (not trigger_action.available or trigger_action.available(self, context)) then
            local edit_start = nil
            if regex then
                matches = matches or {}
                if matches[regex] == nil then
                    matches[regex] = context.line and regex:match_str(context.line) or false
                end
                edit_start = matches[regex] or nil
            end

            if not regex or edit_start then
                table.insert(routes, { trigger_action = trigger_action, edit_start = edit_start })
            end
        end
    end

    return routes
end

---@param routes? cmp_git.Route[] The routes of the context, when the caller has them.
function Core:_run_trigger_actions(trigger_character, callback, context, git_info, routes)
    context = context or {}
    context.trigger_character = trigger_character
    context.original_callback = callback
    local wrapped_callback = self:_wrap_callback(context, callback)

    for _, route in ipairs(routes or self:_route(context)) do
        -- Set before the action runs, because a cache hit calls the callback synchronously
        context.edit_start = route.edit_start
        local result, job = route.trigger_action.action(self, wrapped_callback, context, git_info, trigger_character)
        if result == ROUTE_HANDLED then
            return job
        end
    end

    -- No action handled the request, for example `#` with a remote on another host
    callback(empty_list())
end

---@param routes? cmp_git.Route[] The routes of the context, when the caller has them.
function Core:_complete(context, callback, routes)
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
            state.active = self:_run_trigger_actions(context.trigger_character, callback, context, git_info, routes)
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

    -- Routing once for each request matches each regex once
    local routes = self:_route(context)
    if #routes == 0 then
        callback(empty_list())
        return controller
    end

    repository.is_git_repo(function(is_git_repo)
        if state.cancelled then
            return
        end
        if not is_git_repo then
            callback(empty_list())
            return
        end
        state.active = self:_complete(context, callback, routes)
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
