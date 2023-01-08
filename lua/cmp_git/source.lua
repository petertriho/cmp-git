local github = require("cmp_git.sources.github")
local gitlab = require("cmp_git.sources.gitlab")
local git = require("cmp_git.sources.git")
local utils = require("cmp_git.utils")

local Source = {
    config = {},
    filetypes = {},
}

Source.new = function(overrides)
    local self = setmetatable({}, {
        __index = Source,
    })

    self.config = vim.tbl_extend("force", require("cmp_git.config"), overrides or {})
    for _, item in ipairs(self.config.filetypes) do
        self.filetypes[item] = true
    end

    self.sources = {}
    self.sources.git = git.new(self.config.git)
    self.sources.gitlab = gitlab.new(self.config.gitlab)
    self.sources.github = github.new(self.config.github)

    self.trigger_characters = {}
    for _, v in pairs(self.config.trigger_actions) do
        if not vim.tbl_contains(self.trigger_characters, v.trigger_character) then
            table.insert(self.trigger_characters, v.trigger_character)
        end
    end

    self.trigger_characters_str = table.concat(self.trigger_characters, "")
    self.keyword_pattern = string.format("[%s]\\S*", self.trigger_characters_str)

    self.trigger_actions = self.config.trigger_actions

    return self
end

function Source:complete(params, callback)
    if not utils.is_git_repo() then
        return
    end

    local trigger_character = nil

    if params.completion_context.triggerKind == 1 then
        trigger_character =
            string.match(params.context.cursor_before_line, "%s*([" .. self.trigger_characters_str .. "])%S*$")
    elseif params.completion_context.triggerKind == 2 then
        trigger_character = params.completion_context.triggerCharacter
    end

    for _, trigger in pairs(self.trigger_actions) do
        if trigger.trigger_character == trigger_character then
            local git_info = utils.get_git_info(
                self.config.remotes,
                { enableRemoteUrlRewrites = self.config.enableRemoteUrlRewrites }
            )

            if trigger.action(self.sources, trigger_character, callback, params, git_info) then
                break
            end
        end
    end
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
