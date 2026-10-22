local helpers = require("tests.helpers")
local config = require("cmp_git.config")
local Git = require("cmp_git.sources.git")

local eq = helpers.eq
local ok = helpers.ok

local T = helpers.new_set()

T["git_instance_state_isolation"] = function()
    local first = Git.new(config.normalize({}).git)
    local second = Git.new(config.normalize({}).git)

    first.cache_commits[1] = { { label = "first" } }

    eq(second.cache_commits[1], nil, "Git commit cache is instance-local")
    ok(first.cache_commits ~= second.cache_commits, "Git commit cache table is instance-local")
    ok(first.cache_trailer_keys ~= second.cache_trailer_keys, "Git trailer key cache is instance-local")
    ok(
        first.cache_trailer_identities ~= second.cache_trailer_identities,
        "Git trailer identities cache is instance-local"
    )
    ok(first.cache_trailer_values ~= second.cache_trailer_values, "Git trailer values cache is instance-local")
end

return T
