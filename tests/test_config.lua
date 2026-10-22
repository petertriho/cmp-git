local helpers = require("tests.helpers")
local config = require("cmp_git.config")
local format = require("cmp_git.format")

local eq = helpers.eq
local neq = helpers.neq
local ok = helpers.ok

local T = helpers.new_set()

T["config_normalize_fills_defaults_and_hosts"] = function()
    local normalized = config.normalize({
        github = {
            issues = {
                limit = 7,
            },
        },
    })

    eq(normalized.github.issues.limit, 7, "normalized config keeps nested override")
    eq(normalized.github.issues.state, "open", "normalized config fills issue defaults")
    eq(type(normalized.github.issues.format.label), "function", "normalized config fills format defaults")
    eq(type(normalized.github.pull_requests.format.label), "function", "normalized config fills sibling defaults")
    ok(vim.tbl_contains(normalized.github.hosts, "github.com"), "normalized config adds github host")
    ok(vim.tbl_contains(normalized.gitlab.hosts, "gitlab.com"), "normalized config adds gitlab host")
end

T["config_normalize_nested_filter_and_sort_overrides"] = function()
    local issue_filter = function()
        return "issue-filter"
    end
    local sort_by = function(issue)
        return issue.title
    end

    local normalized = config.normalize({
        github = {
            issues = {
                sort_by = sort_by,
                format = {
                    filterText = issue_filter,
                },
            },
        },
    })

    eq(normalized.github.issues.format.filterText, issue_filter, "nested issue filter is preserved")
    neq(normalized.github.mentions.format.filterText, issue_filter, "nested issue filter does not affect mentions")
    eq(normalized.github.issues.sort_by, sort_by, "custom sort is preserved")
end

T["config_normalize_provider_filter_alias"] = function()
    local git_filter = function()
        return "git"
    end
    local github_filter = function()
        return "github"
    end
    local gitlab_filter = function()
        return "gitlab"
    end

    local normalized = config.normalize({
        git = {
            filter_fn = git_filter,
        },
        github = {
            filter_fn = github_filter,
        },
        gitlab = {
            filter_fn = gitlab_filter,
        },
    })

    eq(normalized.git.commits.format.filterText, git_filter, "git filter alias applies to commits")
    eq(normalized.github.issues.format.filterText, github_filter, "github filter alias applies to issues")
    eq(normalized.github.mentions.format.filterText, github_filter, "github filter alias applies to mentions")
    eq(normalized.github.pull_requests.format.filterText, github_filter, "github filter alias applies to pull requests")
    eq(normalized.gitlab.issues.format.filterText, gitlab_filter, "gitlab filter alias applies to issues")
    eq(normalized.gitlab.mentions.format.filterText, gitlab_filter, "gitlab filter alias applies to mentions")
    eq(
        normalized.gitlab.merge_requests.format.filterText,
        gitlab_filter,
        "gitlab filter alias applies to merge requests"
    )
end

T["config_normalize_provider_filter_alias_overrides_nested_filter"] = function()
    local nested_filter = function()
        return "nested"
    end
    local provider_filter = function()
        return "provider"
    end

    local normalized = config.normalize({
        github = {
            filter_fn = provider_filter,
            issues = {
                format = {
                    filterText = nested_filter,
                },
            },
        },
    })

    eq(normalized.github.issues.format.filterText, provider_filter, "provider filter alias overrides nested filter")
end

T["config_normalize_filter_alias_does_not_change_defaults"] = function()
    local filter = function()
        return "user"
    end
    config.normalize({ git = { filter_fn = filter }, github = { filter_fn = filter }, gitlab = { filter_fn = filter } })

    local normalized = config.normalize({})
    neq(normalized.git.commits.format.filterText, filter, "git filter alias does not leak into later configs")
    neq(normalized.github.issues.format.filterText, filter, "github filter alias does not leak into later configs")
    neq(normalized.gitlab.mentions.format.filterText, filter, "gitlab filter alias does not leak into later configs")
    neq(format.github.issues.filterText, filter, "filter alias does not change the default formats")
end

T["config_normalize_does_not_leak_hosts_between_instances"] = function()
    local first = config.normalize({
        github = {
            hosts = { "github.example.com" },
        },
    })
    local second = config.normalize({
        github = {
            hosts = { "github.other.com" },
        },
    })

    ok(vim.tbl_contains(first.github.hosts, "github.example.com"), "first normalized config keeps own host")
    ok(not vim.tbl_contains(first.github.hosts, "github.other.com"), "first normalized config rejects second host")
    ok(vim.tbl_contains(second.github.hosts, "github.other.com"), "second normalized config keeps own host")
    ok(vim.tbl_contains(second.github.hosts, "github.com"), "second normalized config keeps default host")
end

T["config_trailer_defaults"] = function()
    local normalized = config.normalize({})

    eq(normalized.trigger_actions[1].actions[1], "git_trailer_keys", "trailer keys action is first")
    eq(normalized.trigger_actions[2].actions[1], "git_trailer_identities", "trailer identities action is second")
    eq(normalized.trigger_actions[2].actions[2], "git_trailer_values", "trailer values action follows identities")
    eq(normalized.git.trailers.values.limit, 1000, "trailer values scan limit")
    eq(normalized.trigger_actions[3].trigger_character, ":", "commit trigger follows trailer actions")
    eq(normalized.git.trailers.keys.limit, 100, "trailer keys scan limit")
    eq(normalized.git.trailers.identities.limit, 1000, "trailer identities scan limit")
    eq(normalized.git.trailers.keys.builtin[1], "Co-authored-by", "built-in keys start with Co-authored-by")
    ok(vim.tbl_contains(normalized.git.trailers.keys.builtin, "Fixes"), "built-in keys contain Fixes")
    ok(
        vim.tbl_contains(normalized.git.trailers.identities.keys, "Signed-off-by"),
        "identity keys contain Signed-off-by"
    )
    ok(not vim.tbl_contains(normalized.git.trailers.identities.keys, "Fixes"), "identity keys do not contain Fixes")
    eq(normalized.git.trailers.min_line, 3, "trailers start below the subject and its blank line")
    ok(vim.tbl_contains(normalized.git.trailers.filetypes, "gitcommit"), "trailers in gitcommit")
    ok(not vim.tbl_contains(normalized.git.trailers.filetypes, "octo"), "no trailers in octo")
end

T["config_trailer_value_pattern_has_no_lookbehind"] = function()
    local value_entry = config.normalize({}).trigger_actions[2]

    -- A lookbehind makes Vim use its backtracking engine, which is slow on long lines
    eq(value_entry.pattern:find([[\@<=]], 1, true), nil, "value pattern has no lookbehind")
    eq(value_entry.keyword_pattern:find([[\@<=]], 1, true), nil, "value keyword pattern has no lookbehind")
end

T["config_normalize_upgrades_the_lookbehind_value_pattern"] = function()
    local lookbehind = [[\%(^[[:alnum:]-]\+:\s*\)\@<=\%([^[:space:]<>:#@!][^<>:#@!]*\%(<[^>]*\)\?\)\?]]
    local user_entry = { pattern = lookbehind, actions = { "git_trailer_values" } }
    local custom_entry = { pattern = [[^Refs:\s*\zs\S*]], actions = { "git_trailer_values" } }
    local defaults = config.normalize({}).trigger_actions[2]

    local normalized = config.normalize({ trigger_actions = { user_entry, custom_entry } })

    eq(normalized.trigger_actions[1].pattern, defaults.pattern, "lookbehind pattern becomes the default pattern")
    eq(normalized.trigger_actions[1].keyword_pattern, defaults.keyword_pattern, "upgrade adds the keyword pattern")
    eq(normalized.trigger_actions[1].actions, { "git_trailer_values" }, "upgrade keeps the actions")
    eq(user_entry.pattern, lookbehind, "upgrade does not change the user config")
    eq(user_entry.keyword_pattern, nil, "upgrade does not add fields to the user config")
    ok(normalized.trigger_actions[2] == custom_entry, "other pattern entries are kept")
end

T["config_git_filter_alias_skips_trailers"] = function()
    local git_filter = function()
        return "git"
    end
    local normalized = config.normalize({ git = { filter_fn = git_filter } })

    eq(normalized.git.commits.format.filterText, git_filter, "git filter alias applies to commits")
    neq(normalized.git.trailers.keys.format.filterText, git_filter, "git filter alias does not apply to trailer keys")
    neq(
        normalized.git.trailers.identities.format.filterText,
        git_filter,
        "git filter alias does not apply to trailer identities"
    )
    neq(
        normalized.git.trailers.values.format.filterText,
        git_filter,
        "git filter alias does not apply to trailer values"
    )
end

return T
