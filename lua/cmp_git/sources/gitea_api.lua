-- The source of Gitea and Forgejo. `cmp_git.sources.gitea` and `cmp_git.sources.forgejo` give it their adapter.
local cache = require("cmp_git.cache")
local change_requests = require("cmp_git.provider.capabilities.change_requests")
local issues = require("cmp_git.provider.capabilities.issues")
local mentions = require("cmp_git.provider.capabilities.mentions")

---What the source needs from a provider.
---@class cmp_git.Source.GiteaApi.Provider
---@field name "gitea" | "forgejo" The prefix of the cache files.
---@field adapter table The adapter of a request without a lookup. A cache hit makes no request with it.
---@field with_adapter? fun(git_info: cmp_git.GitInfo, bufnr: integer, on_adapter: fun(adapter: table)) Looks up the
---adapter of a request, and calls `on_adapter` once with it. Without it, the requests use `adapter`.

---The capability of the issues or the pull requests.
---@class cmp_git.Source.GiteaApi.ListCapability: cmp_git.Provider.Capability
---@field job fun(args: cmp_git.Provider.CapabilityArgs): cmp_git.SystemJob?

---@class cmp_git.Source.GiteaApi
---@field provider cmp_git.Source.GiteaApi.Provider
---@field config cmp_git.Config.Gitea
---@field cache_config cmp_git.Config.Cache
local GiteaApi = {}

---@param provider cmp_git.Source.GiteaApi.Provider
---@param overrides cmp_git.Config.Gitea
---@param cache_config? cmp_git.Config.Cache
---@return cmp_git.Source.GiteaApi
function GiteaApi.new(provider, overrides, cache_config)
    local self = setmetatable({}, {
        __index = GiteaApi,
    })

    self.provider = provider
    self.config = overrides or {}
    self.cache_config = cache_config or require("cmp_git.config").cache

    return self
end

---@param git_info cmp_git.GitInfo
function GiteaApi:is_valid_host(git_info)
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

---@param kind "issues" | "pull_requests" | "mentions"
---@param git_info cmp_git.GitInfo
---@return cmp_git.CacheEntry
function GiteaApi:_entry(kind, git_info)
    return cache.entry(git_info, self.provider.name .. "-" .. kind, self.config[kind])
end

---Run `start` with the adapter of the request. A cache hit makes no request, so it starts no lookup.
---@param git_info cmp_git.GitInfo
---@param bufnr integer The buffer of the request. The lookup runs in its repository.
---@param cached boolean
---@param start fun(adapter: table): table? Starts the request and gives its job, if any.
---@return table? job nil or a table with an optional `cancel` method.
function GiteaApi:_with_adapter(git_info, bufnr, cached, start)
    local provider = self.provider
    if cached or provider.with_adapter == nil then
        return start(provider.adapter)
    end

    local state = { cancelled = false, active = nil }
    provider.with_adapter(git_info, bufnr, function(adapter)
        if state.cancelled then
            return
        end
        state.active = start(adapter)
    end)

    return {
        command = provider.name,
        cancel = function()
            state.cancelled = true
            if state.active and state.active.cancel then
                state.active:cancel()
            end
        end,
    }
end

---Refresh the entry in the background when its items are stale.
---@param entry cmp_git.CacheEntry
---@param capability cmp_git.Provider.Capability
---@param kind "issues" | "pull_requests" | "mentions"
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@param bufnr integer
function GiteaApi:_refresh(entry, capability, kind, git_info, trigger_char, bufnr)
    entry:refresh(self.cache_config.ttl, function(done)
        self:_with_adapter(git_info, bufnr, false, function(adapter)
            capability.refresh({
                adapter = adapter,
                config = self.config[kind],
                git_info = git_info,
                trigger_char = trigger_char,
            }, done)
        end)
    end)
end

---@param capability cmp_git.Source.GiteaApi.ListCapability
---@param kind "issues" | "pull_requests"
---@param adapter table
---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@param entry cmp_git.CacheEntry
---@return cmp_git.SystemJob?
function GiteaApi:_list_job(capability, kind, adapter, callback, git_info, trigger_char, entry)
    return capability.job({
        adapter = adapter,
        cache = entry,
        callback = callback,
        config = self.config[kind],
        git_info = git_info,
        trigger_char = trigger_char,
    })
end

---@param capability cmp_git.Source.GiteaApi.ListCapability
---@param kind "issues" | "pull_requests"
---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@param bufnr? integer
function GiteaApi:_complete_list(capability, kind, callback, git_info, trigger_char, bufnr)
    if not self:is_valid_host(git_info) then
        return false
    end

    -- The buffer of the request, also when the lookup ends in another buffer
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local entry = self:_entry(kind, git_info)
    local job = self:_with_adapter(git_info, bufnr, entry:get() ~= nil, function(adapter)
        local request = self:_list_job(capability, kind, adapter, callback, git_info, trigger_char, entry)
        if request then
            request:start()
        end
        return request
    end)
    self:_refresh(entry, capability, kind, git_info, trigger_char, bufnr)
    return true, job
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@param bufnr? integer The buffer of the request, by default the current one.
function GiteaApi:complete_issues(callback, git_info, trigger_char, bufnr)
    return self:_complete_list(issues, "issues", callback, git_info, trigger_char, bufnr)
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@param bufnr? integer The buffer of the request, by default the current one.
function GiteaApi:complete_change_requests(callback, git_info, trigger_char, bufnr)
    return self:_complete_list(change_requests, "pull_requests", callback, git_info, trigger_char, bufnr)
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@param bufnr? integer The buffer of the request, by default the current one.
function GiteaApi:complete_issues_and_change_requests(callback, git_info, trigger_char, bufnr)
    if not self:is_valid_host(git_info) then
        return false
    end

    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local issues_entry = self:_entry("issues", git_info)
    local change_requests_entry = self:_entry("pull_requests", git_info)
    local cached = issues_entry:get() ~= nil and change_requests_entry:get() ~= nil
    local job = self:_with_adapter(git_info, bufnr, cached, function(adapter)
        return change_requests.with_issues(callback, function(on_list)
            return self:_list_job(issues, "issues", adapter, on_list, git_info, trigger_char, issues_entry)
        end, function(on_list)
            return self:_list_job(
                change_requests,
                "pull_requests",
                adapter,
                on_list,
                git_info,
                trigger_char,
                change_requests_entry
            )
        end)
    end)
    self:_refresh(issues_entry, issues, "issues", git_info, trigger_char, bufnr)
    self:_refresh(change_requests_entry, change_requests, "pull_requests", git_info, trigger_char, bufnr)
    return true, job
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@param bufnr? integer The buffer of the request, by default the current one.
function GiteaApi:complete_mentions(callback, git_info, trigger_char, bufnr)
    if not self:is_valid_host(git_info) then
        return false
    end

    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local entry = self:_entry("mentions", git_info)
    -- A request during a fetch joins it, so it needs no adapter either
    local job = self:_with_adapter(git_info, bufnr, entry:get() ~= nil or entry.fetch ~= nil, function(adapter)
        return mentions.complete({
            adapter = adapter,
            cache = entry,
            callback = callback,
            config = self.config.mentions,
            git_info = git_info,
            trigger_char = trigger_char,
        })
    end)
    self:_refresh(entry, mentions, "mentions", git_info, trigger_char, bufnr)
    return true, job
end

return GiteaApi
