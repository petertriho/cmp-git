local gitea_api = require("cmp_git.provider.adapters.gitea_api")

---The adapter of a request: curl with `FORGEJO_TOKEN`, then curl without a token.
return gitea_api.adapter({
    token_env = "FORGEJO_TOKEN",
    commands = function()
        return {}
    end,
})
