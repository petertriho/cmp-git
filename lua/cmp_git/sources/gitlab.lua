local adapter = require("cmp_git.provider.adapters.gitlab")
local issues = require("cmp_git.provider.capabilities.issues")
local mentions = require("cmp_git.provider.capabilities.mentions")
local change_requests = require("cmp_git.provider.capabilities.change_requests")

---@class cmp_git.Source.Gitlab
local GitLab = {}

---@param overrides cmp_git.Config.Gitlab
function GitLab.new(overrides)
    local self = setmetatable({}, {
        __index = GitLab,
    })

    local change_requests_cache = {}
    self.cache = {
        ---@type table<integer, cmp_git.CompletionItem[]>
        issues = {},
        ---@type table<integer, cmp_git.AsyncItemList>
        mentions = {},
        ---@type table<integer, cmp_git.CompletionItem[]>
        change_requests = change_requests_cache,
        ---@type table<integer, cmp_git.CompletionItem[]>
        merge_requests = change_requests_cache,
    }

    self.config = overrides or {}

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

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
function GitLab:complete_issues(callback, git_info, trigger_char)
    if not self:is_valid_host(git_info) then
        return false
    end

    issues.complete({
        adapter = adapter,
        cache = self.cache.issues,
        callback = callback,
        config = self.config.issues,
        git_info = git_info,
        trigger_char = trigger_char,
    })

    return true
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
function GitLab:complete_mentions(callback, git_info, trigger_char)
    if not self:is_valid_host(git_info) then
        return false
    end

    mentions.complete({
        adapter = adapter,
        cache = self.cache.mentions,
        callback = callback,
        config = self.config.mentions,
        git_info = git_info,
        trigger_char = trigger_char,
    })

    return true
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
function GitLab:complete_change_requests(callback, git_info, trigger_char)
    if not self:is_valid_host(git_info) then
        return false
    end

    change_requests.complete({
        adapter = adapter,
        cache = self.cache.change_requests,
        callback = callback,
        config = self.config.merge_requests,
        git_info = git_info,
        trigger_char = trigger_char,
    })

    return true
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
