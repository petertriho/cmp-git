local adapter = require("cmp_git.provider.adapters.gitea")
local GiteaApi = require("cmp_git.sources.gitea_api")

local M = {}

---@param overrides cmp_git.Config.Gitea
---@param cache_config? cmp_git.Config.Cache
---@return cmp_git.Source.GiteaApi
function M.new(overrides, cache_config)
    return GiteaApi.new({ name = "gitea", adapter = adapter.curl }, overrides, cache_config)
end

return M
