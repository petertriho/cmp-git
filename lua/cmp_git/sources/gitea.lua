local adapter = require("cmp_git.provider.adapters.gitea")
local command = require("cmp_git.command")
local GiteaApi = require("cmp_git.sources.gitea_api")

local M = {}

---The output of `tea login list -o json`. Until it is `done`, the requests wait in `waiters`.
---@class cmp_git.Source.Gitea.Logins
---@field done boolean
---@field output? string nil when tea failed.
---@field waiters fun(output: string?)[]

---The logins of tea are the same for all repositories, so one lookup serves the session. `M.clear_logins` drops it.
---@type cmp_git.Source.Gitea.Logins?
local logins = nil

---Call `on_done` with the output of `tea login list -o json`, or with nil when tea fails or is not installed. tea runs
---at most once until `M.clear_logins`, and without blocking.
---@param bufnr integer
---@param on_done fun(output: string?)
local function with_logins(bufnr, on_done)
    local lookup = logins
    if lookup and lookup.done then
        on_done(lookup.output)
        return
    end
    if lookup then
        table.insert(lookup.waiters, on_done)
        return
    end

    local job = command.build(adapter.logins_command(bufnr), function(result, success)
        ---@cast lookup -nil
        lookup.output = success and result or nil
        lookup.done = true
        local waiters = lookup.waiters
        lookup.waiters = {}
        for _, waiter in ipairs(waiters) do
            waiter(lookup.output)
        end
    end)
    if not job then
        -- tea is optional
        on_done(nil)
        return
    end

    lookup = { done = false, waiters = { on_done } }
    logins = lookup
    job:start()
end

---Give the adapter of the tea login of the host, or the curl adapter when no login matches.
---@param git_info cmp_git.GitInfo
---@param bufnr integer
---@param on_adapter fun(adapter: table)
local function with_adapter(git_info, bufnr, on_adapter)
    with_logins(bufnr, function(output)
        local login = output and adapter.match_login(output, git_info.host)
        on_adapter(login and adapter.with_login(login) or adapter.curl)
    end)
end

---@param overrides cmp_git.Config.Gitea
---@param cache_config? cmp_git.Config.Cache
---@return cmp_git.Source.GiteaApi
function M.new(overrides, cache_config)
    return GiteaApi.new(
        { name = "gitea", adapter = adapter.curl, with_adapter = with_adapter },
        overrides,
        cache_config
    )
end

---Drop the tea logins, so that the next request that is not a cache hit reads them again. A lookup that runs still
---answers the requests that wait for it.
function M.clear_logins()
    logins = nil
end

return M
