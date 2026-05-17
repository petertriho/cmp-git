local M = {}

---@class cmp_git.RepositoryMetadata
---@field host string?
---@field owner string?
---@field repo string?

---@param remote_url string?
---@return cmp_git.RepositoryMetadata
function M.parse(remote_url)
    if remote_url == nil or remote_url == "" then
        return {}
    end

    local clean_remote_url = remote_url:gsub("%.git", ""):gsub("%s", "")
    local host, owner, repo = string.match(clean_remote_url, "^git.*@(.+):(.+)/(.+)$")

    if host == nil then
        host, owner, repo = string.match(clean_remote_url, "^https?://(.+)/(.+)/(.+)$")
    end

    if host == nil then
        host, owner, repo = string.match(clean_remote_url, "^ssh://git@([^:]+):*.*/(.+)/(.+)$")
    end

    if host == nil then
        host, owner, repo = string.match(clean_remote_url, "^([^:]+):(.+)/(.+)$")
    end

    return { host = host, owner = owner, repo = repo }
end

return M
