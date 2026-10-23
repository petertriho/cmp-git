-- The code of the user commands that `plugin/cmp_git.lua` defines
local M = {}

---@param message string
local function notify(message)
    vim.notify(message, vim.log.levels.INFO, { title = "cmp-git" })
end

---Drop the cached commits and trailers of the buffer, or of all buffers. A source module that is not loaded has no
---caches.
---@param bufnr? integer
local function clear_git_caches(bufnr)
    local Git = package.loaded["cmp_git.sources.git"]
    if Git then
        Git.clear_caches(bufnr)
    end
end

---Drop the tea logins of the Gitea source, so that a login added during the session applies.
local function clear_tea_logins()
    local Gitea = package.loaded["cmp_git.sources.gitea"]
    if Gitea then
        Gitea.clear_logins()
    end
end

---The remotes of the buffer, without repeats. Discovery runs with the config of each core, because the configs can
---give other hosts for one remote URL, for example with `ssh_aliases`. Without a core, it uses the default config.
---@param bufnr integer
---@param on_complete fun(remotes: cmp_git.GitInfo[])
local function discover_remotes(bufnr, on_complete)
    local Core = require("cmp_git.core")
    local cores = Core.instances()
    if #cores == 0 then
        cores = { Core.new({}) }
    end

    local remotes = {}
    local found = {}
    local pending = #cores
    for _, core in ipairs(cores) do
        core:discover_remote(bufnr, function(git_info)
            if git_info.host ~= nil and git_info.owner ~= nil and git_info.repo ~= nil then
                local name = string.format("%s/%s/%s", git_info.host, git_info.owner, git_info.repo)
                if not found[name] then
                    found[name] = true
                    table.insert(remotes, git_info)
                end
            end

            pending = pending - 1
            if pending == 0 then
                on_complete(remotes)
            end
        end)
    end
end

---Clear the cache of the remote of the buffer, or of all remotes. Both forms also drop the cached commits and
---trailers, of the buffer or of all buffers, and the tea logins.
---@param all boolean
---@param bufnr? integer The buffer, by default the current one.
function M.clear_cache(all, bufnr)
    local cache = require("cmp_git.cache")
    clear_tea_logins()
    if all then
        cache.clear_all()
        clear_git_caches(nil)
        notify("Cleared the cache of all remotes.")
        return
    end

    bufnr = bufnr or vim.api.nvim_get_current_buf()
    clear_git_caches(bufnr)
    discover_remotes(bufnr, function(remotes)
        if #remotes == 0 then
            notify("Cleared the commits and trailers of the buffer. The buffer has no remote.")
            return
        end

        local names = {}
        for _, git_info in ipairs(remotes) do
            cache.clear_remote(git_info)
            table.insert(names, string.format("%s/%s/%s", git_info.host, git_info.owner, git_info.repo))
        end
        table.sort(names)
        notify(string.format("Cleared the cache of %s.", table.concat(names, ", ")))
    end)
end

return M
