local M = {}

---@class cmp_git.RepositoryMetadata
---@field host string?
---@field owner string?
---@field repo string?

---@param authority string `[user[:password]@]host[:port]`
---@return string? host
---@return string? port Empty when the authority has no port.
local function split_authority(authority)
    -- Credentials are not part of the host
    authority = authority:gsub("^.*@", "")

    local host, port = authority:match("^(%[.*%]):?(%d*)$")
    if host == nil then
        host, port = authority:match("^([^:]*):?(%d*)$")
    end
    return host, port
end

---@param remote_url string?
---@return cmp_git.RepositoryMetadata
function M.parse(remote_url)
    if remote_url == nil then
        return {}
    end

    local url = vim.trim(remote_url)
    local host, port, path ---@type string?, string?, string?
    local scheme, rest = url:match("^(%a[%w+.-]*)://(.*)$")
    if scheme ~= nil then
        scheme = scheme:lower()
        if scheme == "file" then
            return {}
        end

        local authority
        authority, path = rest:match("^([^/]*)(.*)$")
        host, port = split_authority(authority)
        -- The API of an http(s) remote is on the same origin. Other ports, such as the one of an `ssh://` remote,
        -- are not the port of the API.
        if host ~= nil and port ~= "" and (scheme == "http" or scheme == "https") then
            host = host .. ":" .. port
        end
    else
        -- Git reads `[user@]host:path` as an scp-like ssh URL when no slash comes before the first colon. Anything
        -- else is a local path.
        local authority
        authority, path = url:match("^([^/:]+):(.*)$")
        if authority == nil then
            return {}
        end
        host = authority:gsub("^.*@", "")
    end

    if host == nil or host == "" or path == nil then
        return {}
    end

    path = path:gsub("/+$", ""):gsub("%.git$", ""):gsub("^/+", ""):gsub("//+", "/")
    -- The owner is all segments before the last one, for example a GitLab group and its subgroups
    local owner, repo = path:match("^(.+)/([^/]+)$")
    if owner == nil then
        return {}
    end

    return { host = host, owner = owner, repo = repo }
end

return M
