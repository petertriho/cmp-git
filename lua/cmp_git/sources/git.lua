local commits = require("cmp_git.provider.capabilities.commits")
local trailers = require("cmp_git.provider.capabilities.trailers")

---@class cmp_git.Source.Git
local Git = {}

---@param overrides cmp_git.Config.Git
function Git.new(overrides)
    local self = setmetatable({}, {
        __index = Git,
    })

    ---@type table<integer, cmp_git.Commit[]>
    self.cache_commits = {}
    ---@type table<integer, cmp_git.TrailerKey[]>
    self.cache_trailer_keys = {}
    ---@type table<integer, cmp_git.TrailerIdentity[]>
    self.cache_trailer_identities = {}
    ---@type table<integer, table<string, cmp_git.TrailerValue[]>>
    self.cache_trailer_values = {}

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

---@param callback fun(list: cmp_git.CompletionList)
---@param trigger_char string?
function Git:get_trailer_keys(callback, context, trigger_char)
    local bufnr = context.bufnr or vim.api.nvim_get_current_buf()

    return true,
        trailers.keys.complete({
            cache = self.cache_trailer_keys,
            callback = callback,
            config = self.config.trailers.keys,
            trigger_char = trigger_char,
            bufnr = bufnr,
        })
end

---@param callback fun(list: cmp_git.CompletionList)
function Git:get_trailer_identities(callback, context)
    local bufnr = context.bufnr or vim.api.nvim_get_current_buf()

    return true,
        trailers.identities.complete({
            cache = self.cache_trailer_identities,
            callback = callback,
            config = self.config.trailers.identities,
            -- The detected trigger character can be an `@` inside the email, so derive it from the line
            trigger_char = trailers.attached_trigger(context.line),
            bufnr = bufnr,
        })
end

---@param callback fun(list: cmp_git.CompletionList)
function Git:get_trailer_values(callback, context)
    local bufnr = context.bufnr or vim.api.nvim_get_current_buf()

    return true,
        trailers.values.complete({
            cache = self.cache_trailer_values,
            callback = callback,
            config = self.config.trailers.values,
            key = trailers.line_key(context.line),
            trigger_char = trailers.attached_trigger(context.line),
            bufnr = bufnr,
        })
end

---False when the cached history has no values for the key, so the request falls through without starting git.
function Git:may_have_trailer_values(context)
    return trailers.values.may_have(self.cache_trailer_values, context)
end

return Git
