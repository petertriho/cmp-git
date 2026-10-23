local gitea_api = require("cmp_git.provider.adapters.gitea_api")
local log = require("cmp_git.log")

local M = {}

---The key file of fj: `keys.json` in `data_dir()` of `ProjectDirs::from("", "forgejo-cli", "forgejo-cli")` of the
---`directories` crate.
---@return string? path nil when the OS gives no directory.
function M.keys_path()
    local sysname = vim.uv.os_uname().sysname
    local home = vim.uv.os_homedir()
    if sysname == "Darwin" then
        return home and home .. "/Library/Application Support/forgejo-cli.forgejo-cli/keys.json"
    end
    if sysname == "Windows_NT" then
        local appdata = vim.env.APPDATA
        return appdata and appdata .. "/forgejo-cli/forgejo-cli/data/keys.json"
    end

    -- As in the XDG spec, a relative path is not valid
    local data = vim.env.XDG_DATA_HOME ---@type string?
    if not data or data:sub(1, 1) ~= "/" then
        data = home and home .. "/.local/share"
    end
    return data and data .. "/forgejo-cli/keys.json"
end

---The token that fj keeps for a host, from an `Application` or an `OAuth` entry. fj refreshes an OAuth token only when
---fj runs, so the token can be expired. Then the request fails, and the next command runs.
---@param host string The host with the port and the path prefix, as in the keys of fj.
---@return string? token nil when the file is missing or has no token for the host.
function M.fj_token(host)
    local path = M.keys_path()
    local file = path and io.open(path, "rb")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()

    local ok, keys = pcall(vim.json.decode, content or "")
    local entry = ok and type(keys) == "table" and type(keys.hosts) == "table" and keys.hosts[host]
    local token = type(entry) == "table" and entry.token
    if type(token) ~= "string" or token == "" then
        log.fmt_debug("No fj token for %s in %s", host, path)
        return nil
    end
    return token
end

---The adapter of a request: curl with the fj token of the host, then curl with `FORGEJO_TOKEN`, then curl without a
---token. The key file is read for each request, so a new `fj auth` login applies to the next request.
return vim.tbl_extend(
    "error",
    M,
    gitea_api.adapter({
        token_env = "FORGEJO_TOKEN",
        commands = function(git_info, path)
            local token = M.fj_token(git_info.host)
            if not token then
                return {}
            end
            return { gitea_api.curl_command(gitea_api.api_url(git_info, path), token) }
        end,
    })
)
