local M = {}

local char_to_hex = function(c)
    return string.format("%%%02X", string.byte(c))
end

M.url_encode = function(value)
    return string.gsub(value, "([^%w _%%%-%.~])", char_to_hex)
end

M.get_git_info = function()
    local remote_origin_url = vim.fn.system("git config --get remote.origin.url")
    local clean_remote_origin_url = remote_origin_url:gsub("%.git", ""):gsub("%s", "")

    local host, owner, repo = string.match(clean_remote_origin_url, "^git@(.+):(.+)/(.+)$")

    if host == nil then
        host, owner, repo = string.match(clean_remote_origin_url, "^https?://(.+)/(.+)/(.+)$")
    end

    return { host = host, owner = owner, repo = repo }
end

return M
