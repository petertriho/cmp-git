local commits = require("cmp_git.provider.capabilities.commits")

---@class cmp_git.Source.Git
local Git = {}

---@param overrides cmp_git.Config.Git
function Git.new(overrides)
    local self = setmetatable({}, {
        __index = Git,
    })

    ---@type table<integer, cmp_git.Commit[]>
    self.cache_commits = {}

    self.config = overrides or {}

    return self
end

---@param callback fun(commits: cmp_git.CompletionList)
---@param trigger_char string
function Git:get_commits(callback, context, trigger_char)
    local config = self.config.commits
    local bufnr = context.bufnr or vim.api.nvim_get_current_buf()

    return true,
        commits.complete({
            cache = self.cache_commits,
            callback = callback,
            config = config,
            trigger_char = trigger_char,
            bufnr = bufnr,
        })
end

return Git
