local format = require("cmp_git.format")
local sort = require("cmp_git.sort")

---@class cmp_git.Config.TriggerAction
---@field debug_name string
---@field trigger_character string
---@field action fun(sources: cmp_git.Sources, trigger_char: string, callback: fun(list: cmp_git.CompletionList), params: cmp.SourceCompletionApiParams, git_info: cmp_git.GitInfo): boolean

---@class cmp_git.Config
local M = {
    ---@type string[]
    filetypes = { "gitcommit", "octo", "NeogitCommitMessage" },
    ---@type string[]
    remotes = { "upstream", "origin" }, -- in order of most to least prioritized
    ---@type boolean
    enableRemoteUrlRewrites = false, -- enable git url rewrites, see https://git-scm.com/docs/git-config#Documentation/git-config.txt-urlltbasegtinsteadOf
    ---@type table<string, string>
    ssh_aliases = {},
    ---@class cmp_git.Config.Git
    ---@field filter_fn? fun(trigger_char: string, item: cmp_git.Commit): string
    ---@field format? cmp_git.FormatConfig<cmp_git.Commit>
    git = {
        ---@class cmp_git.Config.GitCommits
        commits = {
            limit = 100,
            sort_by = sort.git.commits,
            format = format.git.commits,
            sha_length = 7,
        },
    },
    ---@class cmp_git.Config.GitHub
    ---@field format? cmp_git.FormatConfig<cmp_git.GitHub.Issue | cmp_git.GitHub.Mention | cmp_git.GitHub.PullRequest>
    ---@field filter_fn? fun(trigger_char: string, item: cmp_git.GitHub.Issue | cmp_git.GitHub.Mention | cmp_git.GitHub.PullRequest): string
    github = {
        ---@type string[]
        hosts = {},
        ---@class cmp_git.Config.GitHub.Issue
        issues = {
            ---@type string[]
            fields = { "title", "number", "body", "updatedAt", "state" },
            ---Filter by preconfigured options ('all', 'assigned', 'created', 'mentioned')
            ---@type 'all' | 'assigned' | 'created' | 'mentioned'
            filter = "all",
            limit = 100,
            ---@type 'open' | 'closed' | 'all'
            state = "open",
            sort_by = sort.github.issues,
            format = format.github.issues,
        },
        mentions = {
            limit = 100,
            sort_by = sort.github.mentions,
            format = format.github.mentions,
        },
        ---@class cmp_git.Config.GitHub.PullRequest
        pull_requests = {
            ---@type string[]
            fields = { "title", "number", "body", "updatedAt", "state" },
            limit = 100,
            state = "open", -- open, closed, merged, all
            sort_by = sort.github.pull_requests,
            format = format.github.pull_requests,
        },
    },
    ---@class cmp_git.Config.Gitlab
    ---@field filter_fn? fun(trigger_char: string, item: any): string
    ---@field format? cmp_git.FormatConfig<any>
    gitlab = {
        hosts = {},
        issues = {
            limit = 100,
            state = "opened", -- opened, closed, all
            sort_by = sort.gitlab.issues,
            format = format.gitlab.issues,
        },
        mentions = {
            limit = 100,
            sort_by = sort.gitlab.mentions,
            format = format.gitlab.mentions,
        },
        merge_requests = {
            limit = 100,
            state = "opened", -- opened, closed, locked, merged
            sort_by = sort.gitlab.merge_requests,
            format = format.gitlab.merge_requests,
        },
    },
    ---@type cmp_git.Config.TriggerAction[]
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
