-- Fake curl and tea commands for the Gitea and Forgejo source cases
local helpers = require("tests.helpers")

local M = {}

local ISSUES =
    '[{"number":1,"title":"An issue","body":"","updated_at":"2024-01-01T00:00:00+02:00","pull_request":null}]'
local PULLS =
    '[{"number":2,"title":"A pull request","body":null,"updated_at":"2024-01-02T00:00:00Z","pull_request":{}}]'
local USERS = '[{"login":"ada","full_name":"Ada Lovelace"}]'

---The answer to the API path in `$url`.
---@param fail string The script for a failed request.
---@return string script
local function answers(fail)
    return table.concat({
        'case "$url" in',
        string.format("*type=issues*) printf '%%s' '%s' ;;", ISSUES),
        string.format("*type=pulls*) printf '%%s' '%s' ;;", PULLS),
        string.format("*/assignees) printf '%%s' '%s' ;;", USERS),
        "*) " .. fail .. " ;;",
        "esac",
    }, "\n")
end

---@class tests.FakeGiteaApi.Options
---@field fail? boolean Fail each API request of curl and tea.
---@field logins? table[] The logins of `tea login list -o json`. Without them, PATH has no tea.
---@field tea_logins_fail? boolean `tea login list` fails.
---@field tea_api_fails? boolean `tea api` gives an error object.

---Make PATH a directory with only a fake curl, and a fake tea with `logins`, until the end of the case. They answer
---the issue `#1`, the pull request `#2`, and the assignee `ada`. A token `bad` fails, as a 401 fails with `--fail`. As
---the real tea, the fake `tea api` exits with 0 and prints an error object on an HTTP error.
---@param opts? tests.FakeGiteaApi.Options
---@return fun(): string[] log A line for each run so far: `<url> <header>` for curl, `tea <arguments>` for tea.
function M.commands(opts)
    opts = opts or {}
    local log = helpers.tempdir() .. "/commands.log"
    local append = string.format(">> '%s'", log)
    local scripts = {
        curl = table.concat({
            'for arg in "$@"; do url=$arg; done',
            "header=",
            -- The header with the token comes on stdin
            'case " $* " in *" @- "*) IFS= read -r header ;; esac',
            'printf \'%s %s\\n\' "$url" "$header" ' .. append,
            'case "$header" in *" bad") exit 22 ;; esac',
            opts.fail and "exit 22" or answers("exit 22"),
        }, "\n"),
    }

    if opts.logins then
        local not_found = [[printf '%s' '{"message":"not found"}']]
        scripts.tea = table.concat({
            "printf 'tea %s\\n' \"$*\" " .. append,
            'if [ "$1 $2 $3 $4" = "login list -o json" ]; then',
            opts.tea_logins_fail and "exit 1" or string.format("printf '%%s' '%s'", vim.json.encode(opts.logins)),
            "exit 0",
            "fi",
            'if [ "$1 $2" != "api -l" ]; then exit 1; fi',
            "url=$4",
            (opts.fail or opts.tea_api_fails) and not_found or answers(not_found),
        }, "\n")
    end

    helpers.fake_commands(scripts)
    return function()
        if vim.fn.filereadable(log) == 0 then
            return {}
        end
        return vim.fn.readfile(log)
    end
end

---A login as `tea login list -o json` gives it.
---@param name string
---@param url string
---@param default? boolean
---@return table
function M.login(name, url, default)
    local host = string.match(url, "^%a+://([^/]+)")
    return { name = name, url = url, ssh_host = host, user = "ada", default = default and "true" or "false" }
end

return M
