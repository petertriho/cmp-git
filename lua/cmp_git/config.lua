local M = {
    filetypes = { "gitcommit" },
    remotes = { "upstream", "origin" }, -- in order of most to least prioritized
    git = {
        commits = {
            limit = 100,
            filter_fn = function(trigger_char, commit)
                -- If the trigger char is not part of the label, no items will show up
                return string.format("%s %s %s", trigger_char, commit.sha, commit.title)
            end,
        },
    },
    github = {
        issues = {
            filter = "all", -- assigned, created, mentioned, subscribed, all, repos
            limit = 100,
            state = "open", -- open, closed, all
            filter_fn = function(trigger_char, issue)
                return string.format("%s %s %s", trigger_char, issue.number, issue.title)
            end,
        },
        mentions = {
            limit = 100,
            filter_fn = function(trigger_char, mention)
                return string.format("%s %s %s", trigger_char, mention.username)
            end,
        },
        pull_requests = {
            limit = 100,
            state = "open", -- open, closed, merged, all
            filter_fn = function(trigger_char, pr)
                return string.format("%s %s %s", trigger_char, pr.number, pr.title)
            end,
        },
    },
    gitlab = {
        issues = {
            limit = 100,
            state = "opened", -- opened, closed, all
            filter_fn = function(trigger_char, issue)
                return string.format("%s %s %s", trigger_char, issue.iid, issue.title)
            end,
        },
        mentions = {
            limit = 100,
            filter_fn = function(trigger_char, mention)
                return string.format("%s %s", trigger_char, mention.username)
            end,
        },
        merge_requests = {
            limit = 100,
            state = "opened", -- opened, closed, locked, merged
            filter_fn = function(trigger_char, mr)
                return string.format("%s %s %s", trigger_char, mr.iid, mr.title)
            end,
        },
    },
    trigger_actions = {
        {
            debug_name = "git_commits",
            trigger_character = ":",
            action = function(sources, trigger_char, callback, params, git_info)
                return sources.git:get_commits(callback, params, trigger_char)
            end,
        },
        {
            debug_name = "gitlab_issues",
            trigger_character = "#",
            action = function(sources, trigger_char, callback, params, git_info)
                return sources.gitlab:get_issues(callback, git_info, trigger_char)
            end,
        },
        {
            debug_name = "gitlab_mentions",
            trigger_character = "@",
            action = function(sources, trigger_char, callback, params, git_info)
                return sources.gitlab:get_mentions(callback, git_info, trigger_char)
            end,
        },
        {
            debug_name = "gitlab_mrs",
            trigger_character = "!",
            action = function(sources, trigger_char, callback, params, git_info)
                return sources.gitlab:get_merge_requests(callback, git_info, trigger_char)
            end,
        },
        {
            debug_name = "github_issues_and_pr",
            trigger_character = "#",
            action = function(sources, trigger_char, callback, params, git_info)
                return sources.github:get_issues_and_prs(callback, git_info, trigger_char)
            end,
        },
        {
            debug_name = "github_mentions",
            trigger_character = "@",
            action = function(sources, trigger_char, callback, params, git_info)
                return sources.github:get_mentions(callback, git_info, trigger_char)
            end,
        },
    },
}

return M
