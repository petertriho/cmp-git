local adapter = require("cmp_git.provider.adapters.github")
local command = require("cmp_git.command")
local issues = require("cmp_git.provider.capabilities.issues")
local mentions = require("cmp_git.provider.capabilities.mentions")
local change_requests = require("cmp_git.provider.capabilities.change_requests")
local log = require("cmp_git.log")

---@class cmp_git.Source.GitHub.Cache
---@field issues table<integer, cmp_git.CompletionItem[]>
---@field mentions table<integer, cmp_git.AsyncItemList>
---@field change_requests table<integer, cmp_git.CompletionItem[]>
---@field pull_requests table<integer, cmp_git.CompletionItem[]> The `change_requests` table.

---The result of `gh repo set-default --view` for a repository. Until it is `done`, the requests wait in `waiters`.
---@class cmp_git.Source.GitHub.DefaultRepo
---@field done boolean
---@field owner? string
---@field repo? string
---@field waiters fun()[]

---@class cmp_git.Source.GitHub
---@field config cmp_git.Config.GitHub
---@field cache cmp_git.Source.GitHub.Cache
---@field default_repos table<string, cmp_git.Source.GitHub.DefaultRepo> By `host/owner/repo` of the remote.
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
    self.default_repos = {}

    self.config = overrides or {}

    return self
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

---Call `on_resolved` with the repository that `gh repo set-default` chose, or with `git_info` when none is set or gh
---is not installed. gh runs at most once for each repository, and without blocking: it takes about 60 ms.
---@param git_info cmp_git.GitInfo
---@param bufnr integer The buffer of the request. gh reads the default repository of its working directory.
---@param on_resolved fun(git_info: cmp_git.GitInfo)
function GitHub:_resolve_default_repo(git_info, bufnr, on_resolved)
    local key = string.format("%s/%s/%s", git_info.host, git_info.owner, git_info.repo)
    local lookup = self.default_repos[key]

    local function resolve()
        ---@cast lookup -nil
        if lookup.owner and lookup.repo then
            on_resolved(vim.tbl_extend("force", git_info, { owner = lookup.owner, repo = lookup.repo }))
        else
            on_resolved(git_info)
        end
    end

    if lookup and lookup.done then
        resolve()
        return
    end
    if lookup then
        table.insert(lookup.waiters, resolve)
        return
    end

    local spec = { exec = "gh", args = { "repo", "set-default", "--view" }, bufnr = bufnr }
    local job = command.build(spec, function(result, success)
        ---@cast lookup -nil
        -- Without a default repository, gh prints nothing. Outside a repository, it fails.
        if success then
            lookup.owner, lookup.repo = string.match(vim.trim(result), "^([^/%s]+)/([^/%s]+)$")
        end
        lookup.done = true
        local waiters = lookup.waiters
        lookup.waiters = {}
        for _, waiter in ipairs(waiters) do
            waiter()
        end
    end)
    if not job then
        -- gh is optional
        on_resolved(git_info)
        return
    end

    lookup = { done = false, waiters = { resolve } }
    self.default_repos[key] = lookup
    job:start()
end

---Run `start` with the repository to complete from. On a cache miss, that is the repository that `gh repo set-default`
---chose, so that issues, pull requests, and mentions come from the same repository. An octo buffer names its
---repository, and a cache hit needs no repository.
---@param git_info cmp_git.GitInfo
---@param bufnr integer
---@param cached boolean
---@param start fun(git_info: cmp_git.GitInfo): table? Starts the request and gives its job, if any.
---@return table? job nil or a table with an optional `cancel` method.
function GitHub:_with_repo(git_info, bufnr, cached, start)
    if cached or vim.bo[bufnr].filetype == "octo" then
        return start(git_info)
    end

    local state = { cancelled = false, active = nil }
    self:_resolve_default_repo(git_info, bufnr, function(resolved)
        if state.cancelled then
            return
        end
        state.active = start(resolved)
    end)

    return {
        command = "github",
        cancel = function()
            state.cancelled = true
            if state.active and state.active.cancel then
                state.active:cancel()
            end
        end,
    }
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@param bufnr integer
function GitHub:_issues_job(callback, git_info, trigger_char, bufnr)
    return issues.job({
        adapter = adapter,
        cache = self.cache.issues,
        callback = callback,
        config = self.config.issues,
        git_info = git_info,
        trigger_char = trigger_char,
        bufnr = bufnr,
    })
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@param bufnr integer
function GitHub:_change_requests_job(callback, git_info, trigger_char, bufnr)
    return change_requests.job({
        adapter = adapter,
        cache = self.cache.change_requests,
        callback = callback,
        config = self.config.pull_requests,
        git_info = git_info,
        trigger_char = trigger_char,
        bufnr = bufnr,
    })
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@param bufnr? integer The buffer of the request, by default the current one.
function GitHub:complete_issues(callback, git_info, trigger_char, bufnr)
    if not self:is_valid_host(git_info) then
        return false
    end

    -- The buffer of the request, also when the lookup of the default repository ends in another buffer
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    return true,
        self:_with_repo(git_info, bufnr, self.cache.issues[bufnr] ~= nil, function(repo_info)
            local job = self:_issues_job(callback, repo_info, trigger_char, bufnr)
            if job then
                job:start()
            end
            return job
        end)
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@param bufnr? integer The buffer of the request, by default the current one.
function GitHub:complete_change_requests(callback, git_info, trigger_char, bufnr)
    if not self:is_valid_host(git_info) then
        return false
    end

    bufnr = bufnr or vim.api.nvim_get_current_buf()
    return true,
        self:_with_repo(git_info, bufnr, self.cache.change_requests[bufnr] ~= nil, function(repo_info)
            local job = self:_change_requests_job(callback, repo_info, trigger_char, bufnr)
            if job then
                job:start()
            end
            return job
        end)
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@param bufnr integer
function GitHub:_issues_and_change_requests(callback, git_info, trigger_char, bufnr)
    local results = {}
    local pending = 2
    local cancelled = false

    -- Each capability calls back once: at once on a cache hit, and with an empty list on a failure. So a failure of
    -- one request still gives the items of the other.
    ---@param kind "issues" | "change_requests"
    local function collect(kind)
        return function(list)
            if cancelled then
                return
            end
            results[kind] = list.items
            pending = pending - 1
            if pending > 0 then
                return
            end

            -- A new list, so that the issue cache does not get the pull requests
            local items = vim.list_extend(vim.list_extend({}, results.issues), results.change_requests)
            log.fmt_debug("Got %d issues and prs", #items)
            callback({ items = items, isIncomplete = false })
        end
    end

    local issues_job = self:_issues_job(collect("issues"), git_info, trigger_char, bufnr)
    local change_requests_job = self:_change_requests_job(collect("change_requests"), git_info, trigger_char, bufnr)
    -- Both commands run at once, so that a cold request waits for the slower one, not for both in turn
    if issues_job then
        issues_job:start()
    end
    if change_requests_job then
        change_requests_job:start()
    end

    return {
        command = "github_issues_and_change_requests",
        cancel = function()
            cancelled = true
            for _, job in ipairs({ issues_job or false, change_requests_job or false }) do
                if job and job.cancel then
                    job:cancel()
                end
            end
        end,
    }
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@param bufnr? integer The buffer of the request, by default the current one.
function GitHub:complete_issues_and_change_requests(callback, git_info, trigger_char, bufnr)
    if not self:is_valid_host(git_info) then
        return false
    end

    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local cached = self.cache.issues[bufnr] ~= nil and self.cache.change_requests[bufnr] ~= nil
    return true,
        self:_with_repo(git_info, bufnr, cached, function(repo_info)
            return self:_issues_and_change_requests(callback, repo_info, trigger_char, bufnr)
        end)
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@param bufnr? integer The buffer of the request, by default the current one.
function GitHub:complete_mentions(callback, git_info, trigger_char, bufnr)
    if not self:is_valid_host(git_info) then
        return false
    end

    -- A request during a fetch joins it, so it needs no repository either
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    return true,
        self:_with_repo(git_info, bufnr, self.cache.mentions[bufnr] ~= nil, function(repo_info)
            return mentions.complete({
                adapter = adapter,
                cache = self.cache.mentions,
                callback = callback,
                config = self.config.mentions,
                git_info = repo_info,
                trigger_char = trigger_char,
                bufnr = bufnr,
            })
        end)
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
