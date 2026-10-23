local gitea_api = require("cmp_git.provider.adapters.gitea_api")

local M = {}

---The adapter of a request without tea: curl with `GITEA_TOKEN`, then curl without a token.
M.curl = gitea_api.adapter({
    token_env = "GITEA_TOKEN",
    commands = function()
        return {}
    end,
})

---The adapter of a request with a tea login: `tea api` with the login, then the commands of `M.curl`. Without `-l`,
---tea can use the login of another server.
---@param login string
---@return table adapter
function M.with_login(login)
    return gitea_api.adapter({
        token_env = "GITEA_TOKEN",
        commands = function(_, path)
            -- `tea api` exits with 0 on an HTTP error. Its error body is an object, which is a failure of the request.
            return { { exec = "tea", args = { "api", "-l", login, "/" .. path } } }
        end,
    })
end

---@param bufnr integer
---@return cmp_git.CommandSpec
function M.logins_command(bufnr)
    return { exec = "tea", args = { "login", "list", "-o", "json" }, bufnr = bufnr }
end

---The tea login of a host. A login matches when its URL without the scheme and the trailing `/` is the host. Of more
---than one match, the default login wins, and else the first one.
---@param output string The output of `tea login list -o json`.
---@param host string The host of the remote, with the port and the path prefix if any.
---@return string? name
function M.match_login(output, host)
    local ok, logins = pcall(vim.json.decode, output)
    if not ok or not vim.islist(logins) then
        return nil
    end

    local first = nil
    for _, login in ipairs(logins) do
        if type(login) == "table" and type(login.name) == "string" and type(login.url) == "string" then
            local login_host = string.gsub(string.gsub(login.url, "^%a[%w+.-]*://", ""), "/+$", "")
            if login_host == host then
                -- tea 0.16.0 gives `default` as the string "true" or "false"
                if login.default == true or login.default == "true" then
                    return login.name
                end
                first = first or login.name
            end
        end
    end
    return first
end

return M
