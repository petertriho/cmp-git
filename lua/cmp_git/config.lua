local format = require("cmp_git.format")
local sort = require("cmp_git.sort")

---@class cmp_git.Config.TriggerAction
---@field debug_name string
---@field trigger_character string
---@field action fun(sources: cmp_git.Sources, trigger_char: string, callback: fun(list: cmp_git.CompletionList), params: cmp.SourceCompletionApiParams, git_info: cmp_git.GitInfo): boolean

---@class cmp_git.Config.NamedTriggerActions
---@field trigger_character string
---@field actions string[]

---@class cmp_git.Config
local defaults = {
    ---@type string[]
    filetypes = { "gitcommit", "octo", "NeogitCommitMessage" },
    ---@type string[]
    remotes = { "upstream", "origin" }, -- in order of most to least prioritized
    ---@type boolean
    enableRemoteUrlRewrites = false, -- enable git url rewrites, see https://git-scm.com/docs/git-config#Documentation/git-config.txt-urlltbasegtinsteadOf
    ---@type table<string, string>
    ssh_aliases = {},
    ---@class cmp_git.Config.Git
    ---@field filter_fn? fun(trigger_char: string, item: cmp_git.Commit): string Compatibility alias for all git capability format.filterText functions.
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
    ---@field filter_fn? fun(trigger_char: string, item: cmp_git.GitHub.Issue | cmp_git.GitHub.Mention | cmp_git.GitHub.PullRequest): string Compatibility alias for all GitHub capability format.filterText functions.
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
            -- Use math.huge to fetch until there are no more results
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
    ---@field filter_fn? fun(trigger_char: string, item: any): string Compatibility alias for all GitLab capability format.filterText functions.
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
    ---@type (cmp_git.Config.NamedTriggerActions|cmp_git.Config.TriggerAction)[]
    trigger_actions = {
        {
            trigger_character = ":",
            actions = { "git_commits" },
        },
        {
            trigger_character = "#",
            actions = { "gitlab_issues", "github_issues_and_change_requests" },
        },
        {
            trigger_character = "@",
            actions = { "gitlab_mentions", "github_mentions" },
        },
        {
            trigger_character = "!",
            actions = { "gitlab_change_requests" },
        },
    },
}

local M = vim.tbl_deep_extend("force", {}, defaults)

local function ensure_contains(list, item)
    if not vim.tbl_contains(list, item) then
        table.insert(list, item)
    end
end

local function apply_filter_fn(provider_config, capability_names)
    if not provider_config.filter_fn then
        return
    end

    for _, capability_name in ipairs(capability_names) do
        local capability = provider_config[capability_name]
        if capability and capability.format then
            capability.format.filterText = provider_config.filter_fn
        end
    end
end

---@param overrides? cmp_git.Config Partial user config.
---@return cmp_git.Config
function M.normalize(overrides)
    local normalized = vim.tbl_deep_extend("force", {}, defaults, overrides or {})

    ensure_contains(normalized.github.hosts, "github.com")
    ensure_contains(normalized.gitlab.hosts, "gitlab.com")

    apply_filter_fn(normalized.git, { "commits" })
    apply_filter_fn(normalized.github, { "issues", "mentions", "pull_requests" })
    apply_filter_fn(normalized.gitlab, { "issues", "mentions", "merge_requests" })

    return normalized
end

return M
