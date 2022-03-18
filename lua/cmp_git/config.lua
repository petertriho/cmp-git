local utils = require("cmp_git.utils")

local M = {
    filetypes = { "gitcommit" },
    remotes = { "upstream", "origin" }, -- in order of most to least prioritized
    enableRemoteUrlRewrites = false, -- enable git url rewrites, see https://git-scm.com/docs/git-config#Documentation/git-config.txt-urlltbasegtinsteadOf
    git = {
        commits = {
            limit = 100,
            sort_by = function(commit) -- nil, "sha", "title", "description", "author_name", "author_email", "commit_timestamp", or custom function
                return string.format("%010d", commit.diff)
            end,
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
            sort_by = function(issue) -- nil, "number", "title", "body", or custom function
                return string.format("%010d", os.difftime(os.time(), utils.parse_github_date(issue.updatedAt)))
            end,
            filter_fn = function(trigger_char, issue)
                return string.format("%s %s %s", trigger_char, issue.number, issue.title)
            end,
        },
        mentions = {
            limit = 100,
            sort_by = nil, -- nil, "login", or custom function
            filter_fn = function(trigger_char, mention)
                return string.format("%s %s %s", trigger_char, mention.username)
            end,
        },
        pull_requests = {
            limit = 100,
            state = "open", -- open, closed, merged, all
            sort_by = function(pr) -- nil, "number", "title", "body", or custom function
                return string.format("%010d", os.difftime(os.time(), utils.parse_github_date(pr.updatedAt)))
            end,
            filter_fn = function(trigger_char, pr)
                return string.format("%s %s %s", trigger_char, pr.number, pr.title)
            end,
        },
    },
    gitlab = {
        issues = {
            limit = 100,
            state = "opened", -- opened, closed, all
            sort_by = function(issue) -- nil, "iid", "title", "description", or custom function
                return string.format("%010d", os.difftime(os.time(), utils.parse_gitlab_date(issue.updated_at)))
            end,
            filter_fn = function(trigger_char, issue)
                return string.format("%s %s %s", trigger_char, issue.iid, issue.title)
            end,
        },
        mentions = {
            limit = 100,
            sort_by = nil, -- nil, "username", "name", or custom function
            filter_fn = function(trigger_char, mention)
                return string.format("%s %s", trigger_char, mention.username)
            end,
        },
        merge_requests = {
            limit = 100,
            state = "opened", -- opened, closed, locked, merged
            sort_by = function(mr) -- nil, "iid", "title", "description", or custom function
                return string.format("%010d", os.difftime(os.time(), utils.parse_gitlab_date(mr.updated_at)))
            end,
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
