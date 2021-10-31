local github = require("cmp_git.github")
local gitlab = require("cmp_git.gitlab")
local git = require("cmp_git.git")
local utils = require("cmp_git.utils")

local Source = {
    cache_issues = {},
    cache_mentions = {},
    cache_merge_requests = {},
    cache_commits = {},
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

    self.trigger_characters = { "#", "@", "!", ":" }
    self.trigger_characters_str = table.concat(self.trigger_characters, "")
    self.keyword_pattern = string.format("[%s]\\S*", self.trigger_characters_str)

    return self
end

function Source:complete(params, callback)
    local bufnr = vim.api.nvim_get_current_buf()

    local trigger_character = nil

    if params.completion_context.triggerKind == 1 then
        trigger_character = string.match(
            params.context.cursor_before_line,
            "%s*([" .. self.trigger_characters_str .. "])%S*$"
        )
    elseif params.completion_context.triggerKind == 2 then
        trigger_character = params.completion_context.triggerCharacter
    end

    local git_info = utils.get_git_info(self.config.remote)

    if trigger_character == ":" then
        if not self.cache_commits[bufnr] then
            if self.config.git and self.config.git.commits then
                git.get_git_commits(self, callback, bufnr, params.context.cursor, params.offset)
            else
                callback({ items = {}, isIncomplete = false })
                self.cache_commits[bufnr] = {}
            end
        else
            git.update_edit_range(self.cache_commits[bufnr], params.context.cursor, params.offset)
            callback({ items = self.cache_commits[bufnr], isIncomplete = false })
        end
    elseif trigger_character == "#" then
        if not self.cache_issues[bufnr] then
            if
                self.config.github
                and self.config.github.issues
                and git_info.host == "github.com"
                and git_info.owner ~= nil
                and git_info.repo ~= nil
            then
                github.get_issues(self, callback, bufnr, git_info)
            elseif
                self.config.gitlab
                and self.config.gitlab.issues
                and git_info.host ~= nil
                and git_info.owner ~= nil
                and git_info.repo ~= nil
            then
                gitlab.get_issues(self, callback, bufnr, git_info)
            else
                callback({ items = {}, isIncomplete = false })
                self.cache_issues[bufnr] = {}
            end
        else
            callback({ items = self.cache_issues[bufnr], isIncomplete = false })
        end
    elseif trigger_character == "@" then
        if not self.cache_mentions[bufnr] then
            if
                self.config.github
                and self.config.github.mentions
                and git_info.host == "github.com"
                and git_info.owner ~= nil
                and git_info.repo ~= nil
            then
                github.get_mentions(self, callback, bufnr, git_info)
            elseif
                self.config.gitlab
                and self.config.gitlab.mentions
                and git_info.host ~= nil
                and git_info.owner ~= nil
                and git_info.repo ~= nil
            then
                gitlab.get_mentions(self, callback, bufnr, git_info)
            else
                callback({ items = {}, isIncomplete = false })
                self.cache_mentions[bufnr] = {}
            end
        else
            callback({ items = self.cache_mentions[bufnr], isIncomplete = false })
        end
    elseif trigger_character == "!" then
        if not self.cache_merge_requests[bufnr] then
            if
                self.config.gitlab
                and self.config.gitlab.mentions
                and git_info.host ~= "github.com"
                and git_info.owner ~= nil
                and git_info.repo ~= nil
            then
                gitlab.get_merge_requests(self, callback, bufnr, git_info)
            end
        else
            callback({ items = self.cache_merge_requests[bufnr], isIncomplete = false })
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
    return "cmp_git"
end

function Source:is_available()
    return self.filetypes["*"] ~= nil or self.filetypes[vim.bo.filetype] ~= nil
end

return Source
