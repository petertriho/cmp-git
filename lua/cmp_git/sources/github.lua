local adapter = require("cmp_git.provider.adapters.github")
local cache = require("cmp_git.cache")
local command = require("cmp_git.command")
local issues = require("cmp_git.provider.capabilities.issues")
local mentions = require("cmp_git.provider.capabilities.mentions")
local change_requests = require("cmp_git.provider.capabilities.change_requests")

---The result of `gh repo set-default --view` for a repository. Until it is `done`, the requests wait in `waiters`.
---@class cmp_git.Source.GitHub.DefaultRepo
---@field done boolean
---@field owner? string
---@field repo? string
---@field waiters fun()[]

---@class cmp_git.Source.GitHub
---@field config cmp_git.Config.GitHub
---@field cache_config cmp_git.Config.Cache
---@field default_repos table<string, cmp_git.Source.GitHub.DefaultRepo> By `host/owner/repo` of the remote.
local GitHub = {}

---@param overrides cmp_git.Config.GitHub
---@param cache_config? cmp_git.Config.Cache
function GitHub.new(overrides, cache_config)
    local self = setmetatable({}, {
        __index = GitHub,
    })

    self.default_repos = {}

    self.config = overrides or {}
    self.cache_config = cache_config or require("cmp_git.config").cache

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

---The cache entry of a list of the remote. The key is the remote that discovery found and not the default repository,
---so that a hit needs no gh. A refresh asks gh again, so the entry follows a change of the default repository.
---@param kind "issues" | "pull_requests" | "mentions"
---@param git_info cmp_git.GitInfo
---@return cmp_git.CacheEntry
function GitHub:_entry(kind, git_info)
    return cache.entry(git_info, "github-" .. kind, self.config[kind])
end

---Refresh the entry in the background when its items are stale.
---@param entry cmp_git.CacheEntry
---@param capability cmp_git.Provider.Capability
---@param kind "issues" | "pull_requests" | "mentions"
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@param bufnr integer
function GitHub:_refresh(entry, capability, kind, git_info, trigger_char, bufnr)
    entry:refresh(self.cache_config.ttl, function(done)
        self:_with_repo(git_info, bufnr, false, function(repo_info)
            capability.refresh({
                adapter = adapter,
                config = self.config[kind],
                git_info = repo_info,
                trigger_char = trigger_char,
            }, done)
        end)
    end)
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@param entry cmp_git.CacheEntry
function GitHub:_issues_job(callback, git_info, trigger_char, entry)
    return issues.job({
        adapter = adapter,
        cache = entry,
        callback = callback,
        config = self.config.issues,
        git_info = git_info,
        trigger_char = trigger_char,
    })
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@param entry cmp_git.CacheEntry
function GitHub:_change_requests_job(callback, git_info, trigger_char, entry)
    return change_requests.job({
        adapter = adapter,
        cache = entry,
        callback = callback,
        config = self.config.pull_requests,
        git_info = git_info,
        trigger_char = trigger_char,
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
    local entry = self:_entry("issues", git_info)
    local job = self:_with_repo(git_info, bufnr, entry:get() ~= nil, function(repo_info)
        local request = self:_issues_job(callback, repo_info, trigger_char, entry)
        if request then
            request:start()
        end
        return request
    end)
    self:_refresh(entry, issues, "issues", git_info, trigger_char, bufnr)
    return true, job
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
    local entry = self:_entry("pull_requests", git_info)
    local job = self:_with_repo(git_info, bufnr, entry:get() ~= nil, function(repo_info)
        local request = self:_change_requests_job(callback, repo_info, trigger_char, entry)
        if request then
            request:start()
        end
        return request
    end)
    self:_refresh(entry, change_requests, "pull_requests", git_info, trigger_char, bufnr)
    return true, job
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@param issues_entry cmp_git.CacheEntry
---@param change_requests_entry cmp_git.CacheEntry
function GitHub:_issues_and_change_requests(callback, git_info, trigger_char, issues_entry, change_requests_entry)
    return change_requests.with_issues(callback, function(on_list)
        return self:_issues_job(on_list, git_info, trigger_char, issues_entry)
    end, function(on_list)
        return self:_change_requests_job(on_list, git_info, trigger_char, change_requests_entry)
    end)
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
    local issues_entry = self:_entry("issues", git_info)
    local change_requests_entry = self:_entry("pull_requests", git_info)
    local cached = issues_entry:get() ~= nil and change_requests_entry:get() ~= nil
    local job = self:_with_repo(git_info, bufnr, cached, function(repo_info)
        return self:_issues_and_change_requests(callback, repo_info, trigger_char, issues_entry, change_requests_entry)
    end)
    self:_refresh(issues_entry, issues, "issues", git_info, trigger_char, bufnr)
    self:_refresh(change_requests_entry, change_requests, "pull_requests", git_info, trigger_char, bufnr)
    return true, job
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@param bufnr? integer The buffer of the request, by default the current one.
function GitHub:complete_mentions(callback, git_info, trigger_char, bufnr)
    if not self:is_valid_host(git_info) then
        return false
    end

    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local entry = self:_entry("mentions", git_info)
    -- A request during a fetch joins it, so it needs no repository either
    local job = self:_with_repo(git_info, bufnr, entry:get() ~= nil or entry.fetch ~= nil, function(repo_info)
        return mentions.complete({
            adapter = adapter,
            cache = entry,
            callback = callback,
            config = self.config.mentions,
            git_info = repo_info,
            trigger_char = trigger_char,
        })
    end)
    self:_refresh(entry, mentions, "mentions", git_info, trigger_char, bufnr)
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
