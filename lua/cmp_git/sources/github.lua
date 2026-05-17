local adapter = require("cmp_git.provider.adapters.github")
local issues = require("cmp_git.provider.capabilities.issues")
local mentions = require("cmp_git.provider.capabilities.mentions")
local change_requests = require("cmp_git.provider.capabilities.change_requests")
local log = require("cmp_git.log")

---@class cmp_git.AsyncItemList
---@field in_progress boolean
---@field items cmp_git.CompletionItem[]

---@class cmp_git.Source.GitHub
local GitHub = {}

---@param overrides cmp_git.Config.GitHub
function GitHub.new(overrides)
    local self = setmetatable({}, {
        __index = GitHub,
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
        pull_requests = change_requests_cache,
    }

    self.config = vim.tbl_deep_extend("force", require("cmp_git.config").github, overrides or {})

    if overrides.filter_fn then
        self.config.format.filterText = overrides.filter_fn
    end

    if not vim.tbl_contains(self.config.hosts, "github.com") then
        table.insert(self.config.hosts, "github.com")
    end

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
    return true
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
    return true
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
function GitHub:complete_issues_and_change_requests(callback, git_info, trigger_char)
    if not self:is_valid_host(git_info) then
        return false
    end

    git_info = self:_normalize_git_info(git_info)

    local bufnr = vim.api.nvim_get_current_buf()
    if self.cache.issues[bufnr] and self.cache.change_requests[bufnr] then
        local items = {}
        items = vim.list_extend(items, self.cache.issues[bufnr])
        items = vim.list_extend(items, self.cache.change_requests[bufnr])
        log.fmt_debug("Got %d issues and prs from cache", #items)
        callback({ items = self.cache.issues[bufnr], isIncomplete = false })
        return true
    end

    local items = {}
    local issues_job = self:_issues_job(function(args)
        items = args.items
        self.cache.issues[bufnr] = args.items
    end, git_info, trigger_char)

    local change_requests_job = self:_change_requests_job(function(args)
        local prs = args.items
        self.cache.change_requests[bufnr] = args.items
        items = vim.list_extend(items, prs)

        log.fmt_debug("Got %d issues and prs from GitHub", #items)
        callback({ items = items, isIncomplete = false })
    end, git_info, trigger_char)

    if issues_job then
        issues_job:start(function()
            if change_requests_job then
                change_requests_job:start()
            end
        end)
    elseif change_requests_job then
        change_requests_job:start()
    end

    return true
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
function GitHub:complete_mentions(callback, git_info, trigger_char)
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
