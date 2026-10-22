local helpers = require("tests.helpers")
local config = require("cmp_git.config")
local GitLab = require("cmp_git.sources.gitlab")

local eq = helpers.eq
local ok = helpers.ok

local T = helpers.new_set()

T["gitlab_instance_state_isolation"] = function()
    local first = GitLab.new(config.normalize({ gitlab = { hosts = { "gitlab.example.com" } } }).gitlab)
    local second = GitLab.new(config.normalize({ gitlab = { hosts = { "gitlab.other.com" } } }).gitlab)

    ok(
        first:is_valid_host({ host = "gitlab.example.com", owner = "owner", repo = "repo" }),
        "first GitLab instance validates own host"
    )
    ok(
        not first:is_valid_host({ host = "gitlab.other.com", owner = "owner", repo = "repo" }),
        "first GitLab instance rejects second host"
    )
    ok(
        second:is_valid_host({ host = "gitlab.other.com", owner = "owner", repo = "repo" }),
        "second GitLab instance validates own host"
    )
    ok(
        second:is_valid_host({ host = "gitlab.com", owner = "owner", repo = "repo" }),
        "GitLab instance validates default host"
    )

    first.cache.issues[1] = { { label = "first" } }
    eq(second.cache.issues[1], nil, "GitLab issue cache is instance-local")
    ok(first.cache.mentions ~= second.cache.mentions, "GitLab mention cache table is instance-local")
    ok(first.cache.merge_requests ~= second.cache.merge_requests, "GitLab MR cache table is instance-local")
end

return T
