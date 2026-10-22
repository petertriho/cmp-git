local adapter = require("cmp_git.provider.adapters.github")
local issues = require("cmp_git.provider.capabilities.issues")
local mentions = require("cmp_git.provider.capabilities.mentions")
local change_requests = require("cmp_git.provider.capabilities.change_requests")
local log = require("cmp_git.log")

---@class cmp_git.Source.GitHub.Cache
---@field issues table<integer, cmp_git.CompletionItem[]>
---@field mentions table<integer, cmp_git.AsyncItemList>
---@field change_requests table<integer, cmp_git.CompletionItem[]>
---@field pull_requests table<integer, cmp_git.CompletionItem[]> The `change_requests` table.

---@class cmp_git.Source.GitHub
---@field config cmp_git.Config.GitHub
---@field cache cmp_git.Source.GitHub.Cache
local GitHub = {}

---@param overrides cmp_git.Config.GitHub
function GitHub.new(overrides)
    local self = setmetatable({}, {
        __index = GitHub,
    })

    local change_requests_cache = {}
    self.cache = {
        issues = {},
        mentions = {},
        change_requests = change_requests_cache,
        pull_requests = change_requests_cache,
    }

    self.config = overrides or {}

    return self
end

---@param git_info cmp_git.GitInfo
local function use_gh_default_repo_if_set(git_info)
    local gh_default_repo = vim.fn.system({ "gh", "repo", "set-default", "--view" })
    if vim.v.shell_error ~= 0 then
        return git_info
    end
    local owner, repo = string.match(vim.fn.trim(gh_default_repo), "^(.+)/(.+)$")
    if owner ~= nil and repo ~= nil then
        git_info.owner = owner
        git_info.repo = repo
    end
    return git_info
end

---@param git_info cmp_git.GitInfo
function GitHub:is_valid_host(git_info)
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

---@param git_info cmp_git.GitInfo
function GitHub:_normalize_git_info(git_info)
    return use_gh_default_repo_if_set(git_info)
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
function GitHub:_issues_job(callback, git_info, trigger_char)
    return issues.job({
        adapter = adapter,
        cache = self.cache.issues,
        callback = callback,
        config = self.config.issues,
        git_info = git_info,
        trigger_char = trigger_char,
    })
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
function GitHub:_change_requests_job(callback, git_info, trigger_char)
    return change_requests.job({
        adapter = adapter,
        cache = self.cache.change_requests,
        callback = callback,
        config = self.config.pull_requests,
        git_info = git_info,
        trigger_char = trigger_char,
    })
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
function GitHub:complete_issues(callback, git_info, trigger_char)
    if not self:is_valid_host(git_info) then
        return false
    end

    git_info = self:_normalize_git_info(git_info)
    local job = self:_issues_job(callback, git_info, trigger_char)
    if job then
        job:start()
    end
    return true, job
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
function GitHub:complete_change_requests(callback, git_info, trigger_char)
    if not self:is_valid_host(git_info) then
        return false
    end

    git_info = self:_normalize_git_info(git_info)
    local job = self:_change_requests_job(callback, git_info, trigger_char)
    if job then
        job:start()
    end
    return true, job
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
function GitHub:complete_issues_and_change_requests(callback, git_info, trigger_char)
    if not self:is_valid_host(git_info) then
        return false
    end

    git_info = self:_normalize_git_info(git_info)

    local issue_items = {}
    local state = { cancelled = false, active = nil }
    local controller = {
        command = "github_issues_and_change_requests",
        cancel = function()
            state.cancelled = true
            if state.active and state.active.cancel then
                state.active:cancel()
            end
        end,
    }

    -- The capability jobs fill the caches. On a cache hit, a capability calls the callback at once and gives no job,
    -- so the pull requests are requested only after the issues are known.
    local function complete_change_requests()
        if state.cancelled then
            return
        end

        local change_requests_job = self:_change_requests_job(function(args)
            if state.cancelled then
                return
            end
            -- A new list, so that the issue cache does not get the pull requests
            local items = vim.list_extend(vim.list_extend({}, issue_items), args.items)
            log.fmt_debug("Got %d issues and prs", #items)
            callback({ items = items, isIncomplete = false })
        end, git_info, trigger_char)

        if change_requests_job then
            state.active = change_requests_job
            change_requests_job:start()
        end
    end

    local issues_job = self:_issues_job(function(args)
        if state.cancelled then
            return
        end
        issue_items = args.items
    end, git_info, trigger_char)

    if issues_job then
        state.active = issues_job
        issues_job:start(complete_change_requests)
    else
        complete_change_requests()
    end

    return true, controller
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
function GitHub:complete_mentions(callback, git_info, trigger_char)
    if not self:is_valid_host(git_info) then
        return false
    end

    local job = mentions.complete({
        adapter = adapter,
        cache = self.cache.mentions,
        callback = callback,
        config = self.config.mentions,
        git_info = git_info,
        trigger_char = trigger_char,
    })

    return true, job
end

function GitHub:get_issues(callback, git_info, trigger_char)
    return self:complete_issues(callback, git_info, trigger_char)
end

function GitHub:get_pull_requests(callback, git_info, trigger_char)
    return self:complete_change_requests(callback, git_info, trigger_char)
end

function GitHub:get_issues_and_prs(callback, git_info, trigger_char)
    return self:complete_issues_and_change_requests(callback, git_info, trigger_char)
end

function GitHub:get_mentions(callback, git_info, trigger_char)
    return self:complete_mentions(callback, git_info, trigger_char)
end

return GitHub
