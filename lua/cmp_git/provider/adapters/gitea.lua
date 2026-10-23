local gitea_api = require("cmp_git.provider.adapters.gitea_api")

local M = {}

---The adapter of a request without tea: curl with `GITEA_TOKEN`, then curl without a token.
M.curl = gitea_api.adapter({
    token_env = "GITEA_TOKEN",
    commands = function()
        return {}
    end,
})

return M
