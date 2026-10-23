local helpers = require("tests.helpers")
local config = require("cmp_git.config")
local forgejo = require("cmp_git.provider.adapters.forgejo")

local eq = helpers.eq

local T = helpers.new_set()

local remote = { host = "codeberg.org", owner = "owner", repo = "repo" }
local defaults = config.normalize({}).forgejo

---Write the key file of fj to the default Linux path.
---@param content string
local function write_keys(content)
    vim.env.XDG_DATA_HOME = helpers.tempdir()
    vim.fn.mkdir(vim.env.XDG_DATA_HOME .. "/forgejo-cli", "p")
    vim.fn.writefile(vim.split(content, "\n"), vim.env.XDG_DATA_HOME .. "/forgejo-cli/keys.json")
end

---@param hosts table<string, table>
local function write_hosts(hosts)
    write_keys(vim.json.encode({ hosts = hosts, aliases = vim.empty_dict(), default_ssh = {} }))
end

---@param sysname string
local function on(sysname)
    helpers.stub(vim.uv, "os_uname", function()
        return { sysname = sysname, release = "", version = "", machine = "x86_64" }
    end)
end

T["keys_path_on_linux"] = function()
    on("Linux")
    local home = vim.uv.os_homedir()

    eq(forgejo.keys_path(), home .. "/.local/share/forgejo-cli/keys.json", "without XDG_DATA_HOME")
    vim.env.XDG_DATA_HOME = "/data"
    eq(forgejo.keys_path(), "/data/forgejo-cli/keys.json", "an absolute XDG_DATA_HOME")
    vim.env.XDG_DATA_HOME = "data"
    eq(forgejo.keys_path(), home .. "/.local/share/forgejo-cli/keys.json", "a relative XDG_DATA_HOME is not valid")
end

T["keys_path_on_macos_and_windows"] = function()
    vim.env.XDG_DATA_HOME = "/data"

    on("Darwin")
    eq(
        forgejo.keys_path(),
        vim.uv.os_homedir() .. "/Library/Application Support/forgejo-cli.forgejo-cli/keys.json",
        "macOS ignores XDG_DATA_HOME"
    )

    on("Windows_NT")
    vim.env.APPDATA = "C:\\Users\\ada\\AppData\\Roaming"
    eq(
        forgejo.keys_path(),
        "C:\\Users\\ada\\AppData\\Roaming/forgejo-cli/forgejo-cli/data/keys.json",
        "Windows uses APPDATA"
    )
    vim.env.APPDATA = nil
    eq(forgejo.keys_path(), nil, "Windows without APPDATA")
end

T["a_missing_or_invalid_key_file_gives_no_token"] = function()
    eq(forgejo.fj_token("codeberg.org"), nil, "no file")

    local files = {
        "{",
        "null",
        "[]",
        '{"hosts":[]}',
        '{"hosts":{"codeberg.org":"secret"}}',
        '{"hosts":{"codeberg.org":null}}',
        '{"hosts":{"codeberg.org":{"type":"Application"}}}',
        '{"hosts":{"codeberg.org":{"type":"Application","token":5}}}',
        '{"hosts":{"codeberg.org":{"type":"Application","token":""}}}',
        '{"hosts":{"gitea.com":{"type":"Application","token":"secret"}}}',
    }
    for _, content in ipairs(files) do
        write_keys(content)
        eq(forgejo.fj_token("codeberg.org"), nil, content)
    end
end

T["application_and_oauth_entries_give_their_tokens"] = function()
    write_hosts({
        ["codeberg.org"] = { type = "Application", token = "app" },
        ["forgejo.example.com"] = {
            type = "OAuth",
            token = "oauth",
            refresh_token = "refresh",
            expires_at = "2020-01-01T00:00:00Z",
        },
    })

    eq(forgejo.fj_token("codeberg.org"), "app", "an Application entry")
    eq(forgejo.fj_token("forgejo.example.com"), "oauth", "an OAuth entry, also when it expired")
end

T["the_host_key_has_the_port_and_the_path_prefix"] = function()
    write_hosts({
        ["127.0.0.1:3000"] = { type = "Application", token = "port" },
        ["example.com:8443/forgejo"] = { type = "Application", token = "prefix" },
    })

    eq(forgejo.fj_token("127.0.0.1:3000"), "port", "a host with a port")
    eq(forgejo.fj_token("example.com:8443/forgejo"), "prefix", "a host with a port and a path prefix")
    eq(forgejo.fj_token("127.0.0.1"), nil, "the host without the port")
    eq(forgejo.fj_token("example.com:8443"), nil, "the host without the path prefix")
end

T["the_fj_token_comes_before_the_token_variable"] = function()
    write_hosts({ ["codeberg.org"] = { type = "Application", token = "fj" } })
    vim.env.FORGEJO_TOKEN = "secret"

    local issues = forgejo.issues_request(remote, "#", defaults.issues)
    eq(
        vim.tbl_map(function(spec)
            return spec.stdin or ""
        end, issues.commands),
        {
            "Authorization: token fj\n",
            "Authorization: token secret\n",
            "",
        },
        "the fj token, FORGEJO_TOKEN, then no token"
    )
    eq(
        issues.commands[1].args[#issues.commands[1].args],
        "https://codeberg.org/api/v1/repos/owner/repo/issues?state=open&type=issues&limit=50&page=1",
        "curl with the fj token asks the API of the host"
    )

    local mentions = forgejo.mentions_request(remote, "@", defaults.mentions)
    eq(#mentions.commands, 2, "the mentions: the fj token and FORGEJO_TOKEN")
end

T["the_key_file_is_read_for_each_request"] = function()
    eq(#forgejo.mentions_request(remote, "@", defaults.mentions).commands, 0, "no token, no command")

    write_hosts({ ["codeberg.org"] = { type = "Application", token = "fj" } })
    local mentions = forgejo.mentions_request(remote, "@", defaults.mentions)
    eq(mentions.commands[1].stdin, "Authorization: token fj\n", "a new login applies to the next request")
end

return T
