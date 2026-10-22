local adapter = require("cmp_git.provider.adapters.gitlab")
local cache = require("cmp_git.cache")
local issues = require("cmp_git.provider.capabilities.issues")
local mentions = require("cmp_git.provider.capabilities.mentions")
local change_requests = require("cmp_git.provider.capabilities.change_requests")

---@class cmp_git.Source.Gitlab
---@field config cmp_git.Config.Gitlab
---@field cache_config cmp_git.Config.Cache
local GitLab = {}

---@param overrides cmp_git.Config.Gitlab
---@param cache_config? cmp_git.Config.Cache
function GitLab.new(overrides, cache_config)
    local self = setmetatable({}, {
        __index = GitLab,
    })

    self.config = overrides or {}
    self.cache_config = cache_config or require("cmp_git.config").cache

    return self
end

---@param git_info cmp_git.GitInfo
function GitLab:is_valid_host(git_info)
    if
        git_info.host == nil
        or git_info.owner == nil
        or git_info.repo == nil
        or not vim.tbl_contains(self.config.hosts, git_info.host)
    then
        return false
    end
    return true
end

---@param kind "issues" | "merge_requests" | "mentions"
---@param git_info cmp_git.GitInfo
---@return cmp_git.CacheEntry
function GitLab:_entry(kind, git_info)
    return cache.entry(git_info, "gitlab-" .. kind, self.config[kind])
end

---Start the request of a capability, then refresh its entry in the background when the items are stale.
---@param capability cmp_git.Provider.Capability
---@param kind "issues" | "merge_requests" | "mentions"
---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@return table? job
function GitLab:_complete(capability, kind, callback, git_info, trigger_char)
    local entry = self:_entry(kind, git_info)
    local job = capability.complete({
        adapter = adapter,
        cache = entry,
        callback = callback,
        config = self.config[kind],
        git_info = git_info,
        trigger_char = trigger_char,
    })

    entry:refresh(self.cache_config.ttl, function(done)
        capability.refresh({
            adapter = adapter,
            config = self.config[kind],
            git_info = git_info,
            trigger_char = trigger_char,
        }, done)
    end)

    return job
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
function GitLab:complete_issues(callback, git_info, trigger_char)
    if not self:is_valid_host(git_info) then
        return false
    end

    return true, self:_complete(issues, "issues", callback, git_info, trigger_char)
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
function GitLab:complete_mentions(callback, git_info, trigger_char)
    if not self:is_valid_host(git_info) then
        return false
    end

    return true, self:_complete(mentions, "mentions", callback, git_info, trigger_char)
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
function GitLab:complete_change_requests(callback, git_info, trigger_char)
    if not self:is_valid_host(git_info) then
        return false
    end

    return true, self:_complete(change_requests, "merge_requests", callback, git_info, trigger_char)
end

function GitLab:get_issues(callback, git_info, trigger_char)
    return self:complete_issues(callback, git_info, trigger_char)
end

function GitLab:get_mentions(callback, git_info, trigger_char)
    return self:complete_mentions(callback, git_info, trigger_char)
end

function GitLab:get_merge_requests(callback, git_info, trigger_char)
    return self:complete_change_requests(callback, git_info, trigger_char)
end

return GitLab
