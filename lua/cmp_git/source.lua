local github = require("cmp_git.github")
local gitlab = require("cmp_git.gitlab")
local utils = require("cmp_git.utils")

local Source = {
    cache_issues = {},
    cache_mentions = {},
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

    return self
end

function Source:complete(params, callback)
    local bufnr = vim.api.nvim_get_current_buf()

    if params.completion_context.triggerCharacter == "#" then
        if not self.cache_issues[bufnr] then
            local git_info = utils.get_git_info()

            if
                self.config.github
                and self.config.github.issues
                and git_info.host == "github"
                and git_info.owner ~= nil
                and git_info.repo ~= nil
            then
                github.get_issues(self, callback, bufnr, git_info.owner, git_info.repo)
            elseif
                self.config.gitlab
                and self.config.gitlab.mentions
                and git_info.host == "gitlab"
                and git_info.owner ~= nil
                and git_info.repo ~= nil
            then
                gitlab.get_issues(self, callback, bufnr, git_info.owner, git_info.repo)
            else
                callback({ items = {}, isIncomplete = false })
                self.cache_issues[bufnr] = {}
            end
        else
            callback({ items = self.cache_issues[bufnr], isIncomplete = false })
        end
    elseif params.completion_context.triggerCharacter == "@" then
        if not self.cache_mentions[bufnr] then
            local git_info = utils.get_git_info()

            if
                self.config.github
                and self.config.github.mentions
                and git_info.host == "github"
                and git_info.owner ~= nil
                and git_info.repo ~= nil
            then
                github.get_mentions(self, callback, bufnr, git_info.owner, git_info.repo)
            elseif
                self.config.gitlab
                and self.config.gitlab.mentions
                and git_info.host == "gitlab"
                and git_info.owner ~= nil
                and git_info.repo ~= nil
            then
                gitlab.get_mentions(self, callback, bufnr, git_info.owner, git_info.repo)
            else
                callback({ items = {}, isIncomplete = false })
                self.cache_mentions[bufnr] = {}
            end
        else
            callback({ items = self.cache_mentions[bufnr], isIncomplete = false })
        end
    end
end

function Source:get_trigger_characters()
    return { "#", "@" }
end

function Source:get_debug_name()
    return "cmp_git"
end

function Source:is_available()
    return self.filetypes[vim.bo.filetype] ~= nil
end

return Source
