local helpers = require("tests.helpers")
local config = require("cmp_git.config")
local GitHub = require("cmp_git.sources.github")

local eq = helpers.eq
local ok = helpers.ok

local T = helpers.new_set()

T["github_instance_state_isolation"] = function()
    local first = GitHub.new(config.normalize({ github = { hosts = { "github.example.com" } } }).github)
    local second = GitHub.new(config.normalize({ github = { hosts = { "github.other.com" } } }).github)

    ok(
        first:is_valid_host({ host = "github.example.com", owner = "owner", repo = "repo" }),
        "first GitHub instance validates own host"
    )
    ok(
        not first:is_valid_host({ host = "github.other.com", owner = "owner", repo = "repo" }),
        "first GitHub instance rejects second host"
    )
    ok(
        second:is_valid_host({ host = "github.other.com", owner = "owner", repo = "repo" }),
        "second GitHub instance validates own host"
    )
    ok(
        second:is_valid_host({ host = "github.com", owner = "owner", repo = "repo" }),
        "GitHub instance validates default host"
    )

    first.cache.issues[1] = {}
    eq(second.cache.issues[1], nil, "GitHub issue cache is instance-local")
    ok(first.cache.mentions ~= second.cache.mentions, "GitHub mention cache table is instance-local")
    ok(first.cache.pull_requests ~= second.cache.pull_requests, "GitHub PR cache table is instance-local")
end

return T
