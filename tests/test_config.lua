local helpers = require("tests.helpers")
local config = require("cmp_git.config")
local format = require("cmp_git.format")

local eq = helpers.eq
local neq = helpers.neq
local ok = helpers.ok

local T = helpers.new_set()

---@param trigger_actions table[]
---@param action string
---@return integer index
---@return table entry
local function entry_with_action(trigger_actions, action)
    for index, entry in ipairs(trigger_actions) do
        if vim.tbl_contains(entry.actions or {}, action) then
            return index, entry
        end
    end
    error("no entry with the action " .. action)
end

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

T["config_gitea_and_forgejo_defaults"] = function()
    local normalized = config.normalize({})

    for _, provider in ipairs({ "gitea", "forgejo" }) do
        local defaults = normalized[provider]
        eq(
            { defaults.issues.limit, defaults.issues.state },
            { 50, "open" },
            provider .. " issues: one page of the servers"
        )
        eq({ defaults.pull_requests.limit, defaults.pull_requests.state }, { 50, "open" }, provider .. " pull requests")
        eq(defaults.mentions.limit, 100, provider .. " mentions")
        eq(type(defaults.pull_requests.format.label), "function", provider .. " formats")
    end
    eq(normalized.gitea.hosts, { "gitea.com" }, "the default Gitea host")
    eq(normalized.forgejo.hosts, { "codeberg.org" }, "the default Forgejo host")
    eq(
        config.normalize({ gitea = { hosts = { "example.com/gitea" } } }).gitea.hosts,
        { "example.com/gitea", "gitea.com" },
        "a Gitea host with a path prefix"
    )
    neq(normalized.gitea.issues.format, normalized.forgejo.issues.format, "each provider has its own formats")
end

T["config_default_trigger_actions_of_the_hosted_providers"] = function()
    local actions = {}
    for _, entry in ipairs(config.normalize({}).trigger_actions) do
        if entry.trigger_character then
            actions[entry.trigger_character] = entry.actions
        end
    end

    eq(actions["#"], {
        "gitlab_issues",
        "github_issues_and_change_requests",
        "gitea_issues_and_change_requests",
        "forgejo_issues_and_change_requests",
    }, "# completes issues and pull requests")
    eq(actions["@"], { "gitlab_mentions", "github_mentions", "gitea_mentions", "forgejo_mentions" }, "@ mentions")
    eq(
        actions["!"],
        { "gitlab_change_requests", "gitea_change_requests", "forgejo_change_requests" },
        "! completes merge requests and pull requests"
    )
end

T["config_normalize_fills_the_cache_ttl"] = function()
    eq(config.normalize({}).cache.ttl, 300, "the default TTL is five minutes")
    eq(config.normalize({ cache = { ttl = 0 } }).cache.ttl, 0, "a user TTL")
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

    local gitea_filter = function()
        return "gitea"
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
        gitea = {
            filter_fn = gitea_filter,
        },
        forgejo = {
            filter_fn = gitea_filter,
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
    for _, provider in ipairs({ "gitea", "forgejo" }) do
        for _, capability in ipairs({ "issues", "mentions", "pull_requests" }) do
            eq(
                normalized[provider][capability].format.filterText,
                gitea_filter,
                provider .. " filter alias applies to " .. capability
            )
        end
    end
    neq(format.gitea.issues.filterText, gitea_filter, "filter alias does not change the Gitea formats")
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

    local keys = entry_with_action(normalized.trigger_actions, "git_trailer_keys")
    eq(
        normalized.trigger_actions[keys + 1].actions,
        { "git_trailer_identities", "git_trailer_values" },
        "trailer values entry follows the keys entry, with identities first"
    )
    eq(normalized.git.trailers.values.limit, 1000, "trailer values scan limit")
    eq(normalized.trigger_actions[keys + 2].trigger_character, ":", "commit trigger follows trailer actions")
    eq(normalized.git.trailers.keys.limit, 100, "trailer keys scan limit")
    eq(normalized.git.trailers.identities.limit, 1000, "trailer identities scan limit")
    eq(normalized.git.trailers.keys.builtin[1], "Co-authored-by", "built-in keys start with Co-authored-by")
    ok(vim.tbl_contains(normalized.git.trailers.keys.builtin, "Fixes"), "built-in keys contain Fixes")
    ok(
        vim.tbl_contains(normalized.git.trailers.identities.keys, "Signed-off-by"),
        "identity keys contain Signed-off-by"
    )
    ok(not vim.tbl_contains(normalized.git.trailers.identities.keys, "Fixes"), "identity keys do not contain Fixes")
    for _, key in ipairs({ "Assisted-by", "Generated-by" }) do
        ok(vim.tbl_contains(normalized.git.trailers.keys.builtin, key), "built-in keys contain " .. key)
        ok(not vim.tbl_contains(normalized.git.trailers.identities.keys, key), "identity keys do not contain " .. key)
    end
    ok(
        vim.tbl_contains(normalized.git.trailers.keys.builtin, "Co-developed-by"),
        "built-in keys contain Co-developed-by"
    )
    ok(
        vim.tbl_contains(normalized.git.trailers.identities.keys, "Co-developed-by"),
        "identity keys contain Co-developed-by"
    )
    eq(normalized.git.trailers.min_line, 3, "trailers start below the subject and its blank line")
    ok(vim.tbl_contains(normalized.git.trailers.filetypes, "gitcommit"), "trailers in gitcommit")
    ok(not vim.tbl_contains(normalized.git.trailers.filetypes, "octo"), "no trailers in octo")
end

T["config_autosquash_defaults"] = function()
    local normalized = config.normalize({})
    local autosquash = normalized.git.autosquash

    eq(autosquash.filetypes, { "gitcommit", "NeogitCommitMessage" }, "autosquash in commit messages")
    eq(type(autosquash.commits.format.insertText), "function", "the commit format")
    eq(type(autosquash.commits.sort_by), "function", "the commit sort")

    eq(autosquash.prefixes.words, { "fixup", "squash", "amend" }, "the prefix words of git")
    eq(autosquash.prefixes.min_length, 2, "the prefix words show from the second letter")
    eq(type(autosquash.prefixes.format.insertText), "function", "the prefix format")
    eq(type(autosquash.prefixes.sort_by), "function", "the prefix sort")

    local _, keys_entry = entry_with_action(normalized.trigger_actions, "git_trailer_keys")
    local prefixes_entry = normalized.trigger_actions[1]
    eq(prefixes_entry.actions, { "git_autosquash_prefixes" }, "the prefix entry comes first")
    eq(prefixes_entry.pattern, keys_entry.pattern, "the prefix entry shares the pattern of the trailer keys")
    eq(prefixes_entry.keyword_pattern, nil, "the prefix entry adds no keyword pattern")

    local entry = normalized.trigger_actions[2]
    eq(entry.actions, { "git_autosquash" }, "the commit list entry follows")
    eq(entry.pattern, [[^\%(fixup\|squash\|amend\)!\s*\zs.*]], "the commit list starts after the prefix")
    eq(
        entry.keyword_pattern,
        [[^\%(fixup\|squash\|amend\)\%(\zs!\S*\|!\s*\zs.*\)]],
        "the keyword starts at a `!` that the typed text touches"
    )
    eq(entry_with_action(normalized.trigger_actions, "git_trailer_keys"), 3, "the trailer entries follow")
    for _, field in ipairs({ "pattern", "keyword_pattern" }) do
        eq(entry[field]:find([[\@<=]], 1, true), nil, field .. " has no lookbehind")
    end
end

T["config_autosquash_partial_overrides_keep_the_defaults"] = function()
    local words = config.normalize({ git = { autosquash = { prefixes = { words = { "fixup" } } } } }).git.autosquash
    eq(words.prefixes.words, { "fixup" }, "a word list replaces the default words")
    eq(words.prefixes.min_length, 2, "a word list keeps the minimum length")
    eq(type(words.prefixes.format.label), "function", "a word list keeps the format")
    eq(words.filetypes, { "gitcommit", "NeogitCommitMessage" }, "a word list keeps the filetypes")

    local min_length = config.normalize({ git = { autosquash = { prefixes = { min_length = 1 } } } }).git.autosquash
    eq(min_length.prefixes.min_length, 1, "a minimum length")
    eq(min_length.prefixes.words, { "fixup", "squash", "amend" }, "a minimum length keeps the words")
    eq(type(min_length.commits.format.label), "function", "a minimum length keeps the commit format")
end

T["config_autosquash_empty_lists_replace_the_defaults"] = function()
    local autosquash =
        config.normalize({ git = { autosquash = { filetypes = {}, prefixes = { words = {} } } } }).git.autosquash

    eq(autosquash.filetypes, {}, "no filetypes turn off autosquash completion")
    eq(autosquash.prefixes.words, {}, "no words turn off the prefix words")
end

T["config_trailer_value_pattern_has_no_lookbehind"] = function()
    local _, value_entry = entry_with_action(config.normalize({}).trigger_actions, "git_trailer_values")

    -- A lookbehind makes Vim use its backtracking engine, which is slow on long lines
    eq(value_entry.pattern:find([[\@<=]], 1, true), nil, "value pattern has no lookbehind")
    eq(value_entry.keyword_pattern:find([[\@<=]], 1, true), nil, "value keyword pattern has no lookbehind")
end

T["config_normalize_upgrades_the_lookbehind_value_pattern"] = function()
    local lookbehind = [[\%(^[[:alnum:]-]\+:\s*\)\@<=\%([^[:space:]<>:#@!][^<>:#@!]*\%(<[^>]*\)\?\)\?]]
    local user_entry = { pattern = lookbehind, actions = { "git_trailer_values" } }
    local custom_entry = { pattern = [[^Refs:\s*\zs\S*]], actions = { "git_trailer_values" } }
    local _, defaults = entry_with_action(config.normalize({}).trigger_actions, "git_trailer_values")

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
