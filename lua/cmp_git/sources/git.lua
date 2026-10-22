local commits = require("cmp_git.provider.capabilities.commits")
local trailers = require("cmp_git.provider.capabilities.trailers")

---@class cmp_git.Source.Git
---@field config cmp_git.Config.Git
---@field cache_commits table<integer, cmp_git.Commit[]>
---@field cache_trailer_keys table<integer, cmp_git.TrailerKey[]>
---@field cache_trailer_identities table<integer, cmp_git.TrailerIdentity[]>
---@field cache_trailer_values table<integer, table<string, cmp_git.TrailerValue[]>>
local Git = {}

-- The fields of the caches, which are keyed by buffer number
local CACHE_FIELDS = { "cache_commits", "cache_trailer_keys", "cache_trailer_identities", "cache_trailer_values" }

---The sources that are alive. `:CmpGitClearCache` drops their caches.
local instances = setmetatable({}, { __mode = "k" })

---@param overrides cmp_git.Config.Git
function Git.new(overrides)
    local self = setmetatable({}, {
        __index = Git,
    })
    instances[self] = true

    self.cache_commits = {}
    self.cache_trailer_keys = {}
    self.cache_trailer_identities = {}
    self.cache_trailer_values = {}

    self.config = overrides or {}

    return self
end

---Drop the cached commits and trailers of the buffer in all sources, or of all buffers.
---@param bufnr? integer
function Git.clear_caches(bufnr)
    for source in pairs(instances) do
        for _, field in ipairs(CACHE_FIELDS) do
            if bufnr then
                source[field][bufnr] = nil
            else
                -- A new table, so that a git command that ends after the clear fills the old one
                source[field] = {}
            end
        end
    end
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
            -- The values route only matches lines with a key
            key = trailers.line_key(context.line) --[[@as string]],
            trigger_char = trailers.attached_trigger(context.line),
            bufnr = bufnr,
        })
end

---False when the cached history has no values for the key, so the request falls through without starting git.
function Git:may_have_trailer_values(context)
    return trailers.values.may_have(self.cache_trailer_values, context)
end

return Git
