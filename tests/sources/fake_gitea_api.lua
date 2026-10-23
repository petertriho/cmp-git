-- A fake curl for the Gitea and Forgejo source cases
local helpers = require("tests.helpers")

local M = {}

local ISSUES =
    '[{"number":1,"title":"An issue","body":"","updated_at":"2024-01-01T00:00:00+02:00","pull_request":null}]'
local PULLS =
    '[{"number":2,"title":"A pull request","body":null,"updated_at":"2024-01-02T00:00:00Z","pull_request":{}}]'
local USERS = '[{"login":"ada","full_name":"Ada Lovelace"}]'

---Make PATH a directory with only a fake curl, until the end of the case. It answers the issue `#1`, the pull request
---`#2`, and the assignee `ada`. A token `bad` fails, as a 401 fails with `--fail`.
---@param opts? { fail?: boolean } Fail each request.
---@return fun(): string[] log A line `<url> <header>` for each run so far.
function M.curl(opts)
    local log = helpers.tempdir() .. "/curl.log"
    local answers = opts and opts.fail and "exit 22"
        or table.concat({
            'case "$url" in',
            string.format("*type=issues*) printf '%%s' '%s' ;;", ISSUES),
            string.format("*type=pulls*) printf '%%s' '%s' ;;", PULLS),
            string.format("*/assignees) printf '%%s' '%s' ;;", USERS),
            "*) exit 22 ;;",
            "esac",
        }, "\n")
    helpers.fake_commands({
        curl = table.concat({
            'for arg in "$@"; do url=$arg; done',
            "header=",
            -- The header with the token comes on stdin
            'case " $* " in *" @- "*) IFS= read -r header ;; esac',
            string.format("printf '%%s %%s\\n' \"$url\" \"$header\" >> '%s'", log),
            'case "$header" in *" bad") exit 22 ;; esac',
            answers,
        }, "\n"),
    })

    return function()
        if vim.fn.filereadable(log) == 0 then
            return {}
        end
        return vim.fn.readfile(log)
    end
end

return M
