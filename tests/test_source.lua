local helpers = require("tests.helpers")
local Source = require("cmp_git.source")

local eq = helpers.eq
local neq = helpers.neq
local ok = helpers.ok

local T = helpers.new_set()

T["trigger_action_fallback_for_hash"] = function()
    local source = Source.new({
        trigger_actions = {
            { trigger_character = "#", actions = { "gitlab_issues", "github_issues_and_prs" } },
        },
    })
    local calls = {}
    source.sources.gitlab = {
        complete_issues = function()
            table.insert(calls, "gitlab")
            return false
        end,
    }
    source.sources.github = {
        complete_issues_and_change_requests = function()
            table.insert(calls, "github")
            return true
        end,
    }

    source:_run_trigger_actions("#", function() end, {}, {})

    eq(table.concat(calls, ","), "gitlab,github", "hash trigger falls back in configured order")
end

T["trigger_action_ordering_for_at"] = function()
    local source = Source.new({
        trigger_actions = {
            { trigger_character = "@", actions = { "gitlab_mentions", "github_mentions" } },
        },
    })
    local calls = {}
    source.sources.gitlab = {
        complete_mentions = function()
            table.insert(calls, "gitlab")
            return false
        end,
    }
    source.sources.github = {
        complete_mentions = function()
            table.insert(calls, "github")
            return true
        end,
    }

    source:_run_trigger_actions("@", function() end, {}, {})

    eq(table.concat(calls, ","), "gitlab,github", "at trigger falls back in configured order")
end

T["trigger_action_first_handled_wins"] = function()
    local source = Source.new({
        trigger_actions = {
            { trigger_character = "#", actions = { "gitlab_issues", "github_issues_and_prs" } },
        },
    })
    local calls = {}
    source.sources.gitlab = {
        complete_issues = function()
            table.insert(calls, "gitlab")
            return true
        end,
    }
    source.sources.github = {
        complete_issues_and_change_requests = function()
            table.insert(calls, "github")
            return true
        end,
    }

    source:_run_trigger_actions("#", function() end, {}, {})

    eq(table.concat(calls, ","), "gitlab", "first handled trigger action wins")
end

T["preferred_trigger_action_names"] = function()
    local source = Source.new({
        trigger_actions = {
            { trigger_character = "#", actions = { "github_issues" } },
            { trigger_character = "!", actions = { "gitlab_change_requests" } },
        },
    })
    local calls = {}
    source.sources.github = {
        complete_issues = function()
            table.insert(calls, "github_issues")
            return true
        end,
    }
    source.sources.gitlab = {
        complete_change_requests = function()
            table.insert(calls, "gitlab_change_requests")
            return true
        end,
    }

    source:_run_trigger_actions("#", function() end, {}, {})
    source:_run_trigger_actions("!", function() end, {}, {})

    eq(table.concat(calls, ","), "github_issues,gitlab_change_requests", "preferred action names route")
end

T["legacy_trigger_action_aliases"] = function()
    local source = Source.new({
        trigger_actions = {
            { trigger_character = "#", actions = { "github_issues_and_prs" } },
            { trigger_character = "!", actions = { "gitlab_mrs" } },
        },
    })
    local calls = {}
    source.sources.github = {
        complete_issues_and_change_requests = function()
            table.insert(calls, "github_combined")
            return true
        end,
    }
    source.sources.gitlab = {
        complete_change_requests = function()
            table.insert(calls, "gitlab_cr")
            return true
        end,
    }

    source:_run_trigger_actions("#", function() end, {}, {})
    source:_run_trigger_actions("!", function() end, {}, {})

    eq(table.concat(calls, ","), "github_combined,gitlab_cr", "legacy aliases route")
end

T["legacy_trigger_action_arguments"] = function()
    local received = nil
    local callback = function() end
    local params = { context = {} }
    local git_info = { host = "github.com" }
    local source = Source.new({
        trigger_actions = {
            {
                debug_name = "legacy",
                trigger_character = "#",
                action = function(sources, trigger_char, actual_callback, actual_params, actual_git_info)
                    received = {
                        sources = sources,
                        trigger_char = trigger_char,
                        callback = actual_callback,
                        params = actual_params,
                        git_info = actual_git_info,
                    }
                    return true
                end,
            },
        },
    })

    source:_run_trigger_actions("#", callback, params, git_info)

    neq(received, nil, "legacy trigger action runs")
    ok(received.sources == source.sources, "legacy trigger action receives sources")
    eq(received.trigger_char, "#", "legacy trigger action receives trigger character")
    ok(received.callback == callback, "legacy trigger action receives callback")
    ok(received.params == params, "legacy trigger action receives params")
    ok(received.git_info == git_info, "legacy trigger action receives git info")
end

T["source_new_uses_normalized_config"] = function()
    local source = Source.new({
        github = {
            issues = {
                limit = 5,
            },
        },
    })

    eq(source.config.github.issues.limit, 5, "source config keeps normalized override")
    eq(source.sources.github.config.issues.limit, 5, "github source receives normalized override")
    eq(
        type(source.sources.github.config.pull_requests.format.label),
        "function",
        "github source receives normalized defaults"
    )
    ok(
        source.sources.github:is_valid_host({ host = "github.com", owner = "owner", repo = "repo" }),
        "github source receives normalized default host"
    )
end

return T
