local github = require("cmp_git.sources.github")
local gitlab = require("cmp_git.sources.gitlab")
local git = require("cmp_git.sources.git")
local repository = require("cmp_git.repository")

local ROUTE_HANDLED = "handled"
local ROUTE_UNSUPPORTED_HOST = "unsupported_host"
local ROUTE_UNAVAILABLE = "unavailable"

local function route_status(handled)
    if handled then
        return ROUTE_HANDLED
    end

    return ROUTE_UNSUPPORTED_HOST
end

local builtin_trigger_actions = {
    git_commits = function(source, callback, params, _git_info, trigger_char)
        return route_status(source.sources.git:get_commits(callback, params, trigger_char))
    end,
    github_issues = function(source, callback, _params, git_info, trigger_char)
        return route_status(source.sources.github:complete_issues(callback, git_info, trigger_char))
    end,
    github_mentions = function(source, callback, _params, git_info, trigger_char)
        return route_status(source.sources.github:complete_mentions(callback, git_info, trigger_char))
    end,
    github_change_requests = function(source, callback, _params, git_info, trigger_char)
        return route_status(source.sources.github:complete_change_requests(callback, git_info, trigger_char))
    end,
    github_issues_and_change_requests = function(source, callback, _params, git_info, trigger_char)
        return route_status(source.sources.github:complete_issues_and_change_requests(callback, git_info, trigger_char))
    end,
    gitlab_issues = function(source, callback, _params, git_info, trigger_char)
        return route_status(source.sources.gitlab:complete_issues(callback, git_info, trigger_char))
    end,
    gitlab_mentions = function(source, callback, _params, git_info, trigger_char)
        return route_status(source.sources.gitlab:complete_mentions(callback, git_info, trigger_char))
    end,
    gitlab_change_requests = function(source, callback, _params, git_info, trigger_char)
        return route_status(source.sources.gitlab:complete_change_requests(callback, git_info, trigger_char))
    end,
    gitlab_mrs = function(source, callback, _params, git_info, trigger_char)
        return route_status(source.sources.gitlab:complete_change_requests(callback, git_info, trigger_char))
    end,
    github_issues_and_prs = function(source, callback, _params, git_info, trigger_char)
        return route_status(source.sources.github:complete_issues_and_change_requests(callback, git_info, trigger_char))
    end,
}

local function normalize_trigger_action(configured_action)
    if configured_action.action then
        return {
            debug_name = configured_action.debug_name,
            trigger_character = configured_action.trigger_character,
            action = function(source, callback, params, git_info, trigger_char)
                return route_status(configured_action.action(source.sources, trigger_char, callback, params, git_info))
            end,
        }
    end

    local normalized = {}
    for _, action_name in ipairs(configured_action.actions or {}) do
        local action = builtin_trigger_actions[action_name]
        table.insert(normalized, {
            debug_name = action_name,
            trigger_character = configured_action.trigger_character,
            action = function(source, callback, params, git_info, trigger_char)
                if not action then
                    return ROUTE_UNAVAILABLE
                end

                return action(source, callback, params, git_info, trigger_char)
            end,
        })
    end

    return normalized
end

local Source = {
    ---@type cmp_git.Config
    ---@diagnostic disable-next-line: missing-fields
    config = {},
    ---@type table<string, true>
    filetypes = {},
    ---@type cmp_git.Sources
    ---@diagnostic disable-next-line: missing-fields
    sources = {},
    ---@type cmp_git.Config.TriggerAction[]
    trigger_actions = {},
    ---@type string[]
    trigger_characters = {},
}

---@class cmp_git.Sources
---@field git cmp_git.Source.Git
---@field gitlab cmp_git.Source.Gitlab
---@field github cmp_git.Source.GitHub

function Source.new(overrides)
    local self = setmetatable({}, {
        __index = Source,
    })

    self.config = vim.tbl_extend("force", require("cmp_git.config"), overrides or {})
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

---@class cmp_git.CompletionList : lsp.CompletionList
---@field items cmp_git.CompletionItem[]

---@param params cmp.SourceCompletionApiParams
---@param callback fun(args: cmp_git.CompletionList)
function Source:_complete(params, callback)
    ---@type string?
    local trigger_character = nil

    if params.completion_context.triggerKind == 1 then
        trigger_character =
            string.match(params.context.cursor_before_line, "%s*([" .. self.trigger_characters_str .. "])%S*$")
    elseif params.completion_context.triggerKind == 2 then
        trigger_character = params.completion_context.triggerCharacter
    end

    repository.discover(self.config.remotes, {
        enableRemoteUrlRewrites = self.config.enableRemoteUrlRewrites,
        ssh_aliases = self.config.ssh_aliases,
        on_complete = function(git_info)
            self:_run_trigger_actions(trigger_character, callback, params, git_info)
        end,
    })
end

---@param trigger_character string?
---@param callback fun(args: cmp_git.CompletionList)
---@param params cmp.SourceCompletionApiParams
---@param git_info cmp_git.GitInfo
function Source:_run_trigger_actions(trigger_character, callback, params, git_info)
    for _, trigger in ipairs(self.trigger_actions) do
        if trigger.trigger_character == trigger_character then
            local result = trigger.action(self, callback, params, git_info, trigger_character)
            if result == ROUTE_HANDLED then
                break
            end
        end
    end
end

---@module 'cmp'
---@param params cmp.SourceCompletionApiParams
---@param callback fun(args: cmp_git.CompletionList)
function Source:complete(params, callback)
    repository.is_git_repo(function(is_git_repo)
        if not is_git_repo then
            return
        end
        self:_complete(params, callback)
    end)
end

function Source:get_keyword_pattern()
    return self.keyword_pattern
end

function Source:get_trigger_characters()
    return self.trigger_characters
end

function Source:get_debug_name()
    return "git"
end

function Source:is_available()
    if self.filetypes["*"] ~= nil or self.filetypes[vim.bo.filetype] ~= nil then
        return true
    end

    -- split filetype on period to support multi-filetype buffers (see `:h 'filetype'`)
    --
    -- the pattern captures all non-period characters
    for ft in string.gmatch(vim.bo.filetype, "[^%.]*") do
        if self.filetypes[ft] ~= nil then
            return true
        end
    end

    return false
end

return Source
