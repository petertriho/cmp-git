local format = require("cmp_git.format")
local sort = require("cmp_git.sort")

---@class cmp_git.Config.TriggerAction
---@field debug_name string
---@field trigger_character string
---@field action fun(sources: cmp_git.Sources, trigger_char: string, callback: fun(list: cmp_git.CompletionList), params: cmp_git.CmpCompletionParams, git_info: cmp_git.GitInfo): boolean

---@class cmp_git.Config.NamedTriggerActions
---@field trigger_character string
---@field actions string[]

---@class cmp_git.Config.PatternTriggerActions
---@field pattern string Vim regex (magic mode) that must match up to the cursor. The match start is the start of the replaced text.
---@field keyword_pattern? string Vim regex that cmp-git adds to the nvim-cmp keyword pattern in place of `pattern`. nvim-cmp filters the items on the text from the start of the match.
---@field actions string[]

-- Keep these in sync with the trailer entries in the README.
local TRAILER_KEY_PATTERN = [[^[[:alnum:]-]\+]]
-- The value cannot contain `:#@!` outside `<...>`. nvim-cmp starts the keyword at the leftmost match, so a looser
-- value would hide the other triggers in body lines such as `Note: see #12`.
local TRAILER_VALUE = [[\%([^[:space:]<>:#@!][^<>:#@!]*\%(<[^>]*\)\?\)\?]]
-- `\zs` and not a lookbehind, because a lookbehind makes Vim use its backtracking engine. Its time grows with the
-- square of the line length, and nvim-cmp matches the keyword pattern on each keystroke.
local TRAILER_VALUE_PATTERN = [[^[[:alnum:]-]\+:\s*\zs]] .. TRAILER_VALUE
-- Vim gives the match that begins first, and `\zs` moves only the start that it reports. The value match begins at the
-- line start, before the `:` trigger match, so the keyword of `Key:` or `Key:value` would start after the colon. The
-- identities and values formats filter on the colon, so the first branch starts the keyword at the colon.
local TRAILER_VALUE_KEYWORD_PATTERN = [[^[[:alnum:]-]\+\zs:\S*\|]] .. TRAILER_VALUE_PATTERN
-- The value pattern of earlier versions. It matches the same text as `TRAILER_VALUE_PATTERN`, slowly. The docs tell
-- users who set their own `trigger_actions` to copy the default entries, so `normalize` replaces it.
local LEGACY_TRAILER_VALUE_PATTERN = [[\%(^[[:alnum:]-]\+:\s*\)\@<=]] .. TRAILER_VALUE

local IDENTITY_TRAILER_KEYS = {
    "Co-authored-by",
    "Signed-off-by",
    "Reviewed-by",
    "Acked-by",
    "Tested-by",
    "Reported-by",
    "Suggested-by",
    "Helped-by",
}

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
    ---@field filter_fn? fun(trigger_char: string, item: cmp_git.Commit): string Compatibility alias for the commits format.filterText function. It does not apply to trailers.
    git = {
        ---@class cmp_git.Config.GitCommits
        commits = {
            limit = 100,
            sort_by = sort.git.commits,
            format = format.git.commits,
            sha_length = 7,
        },
        ---@class cmp_git.Config.GitTrailers
        trailers = {
            ---@type string[]
            filetypes = { "gitcommit", "NeogitCommitMessage" },
            ---First line where trailers complete. Line 1 is the subject and line 2 is the blank line after it.
            ---@type integer
            min_line = 3,
            ---@class cmp_git.Config.GitTrailerKeys
            keys = {
                ---@type string[]
                builtin = vim.list_extend(vim.deepcopy(IDENTITY_TRAILER_KEYS), { "Fixes", "Closes", "Refs" }),
                limit = 100, -- commits scanned for keys
                sort_by = sort.git.trailers.keys,
                format = format.git.trailers.keys,
            },
            ---@class cmp_git.Config.GitTrailerIdentities
            identities = {
                ---Trailer keys whose values are completed with `Name <email>`
                ---@type string[]
                keys = vim.deepcopy(IDENTITY_TRAILER_KEYS),
                limit = 1000, -- commits scanned for identities
                sort_by = sort.git.trailers.identities,
                format = format.git.trailers.identities,
            },
            ---Earlier values of the current key, for keys that `identities` does not handle
            ---@class cmp_git.Config.GitTrailerValues
            values = {
                limit = 1000, -- commits scanned for values
                sort_by = sort.git.trailers.values,
                format = format.git.trailers.values,
            },
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
    ---@field filter_fn? fun(trigger_char: string, item: cmp_git.GitLab.Issue | cmp_git.GitLab.Mention | cmp_git.GitLab.MergeRequest): string Compatibility alias for all GitLab capability format.filterText functions.
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
    ---@type (cmp_git.Config.NamedTriggerActions|cmp_git.Config.PatternTriggerActions|cmp_git.Config.TriggerAction)[]
    trigger_actions = {
        {
            pattern = TRAILER_KEY_PATTERN,
            actions = { "git_trailer_keys" },
        },
        {
            pattern = TRAILER_VALUE_PATTERN,
            keyword_pattern = TRAILER_VALUE_KEYWORD_PATTERN,
            actions = { "git_trailer_identities", "git_trailer_values" },
        },
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

---@param trigger_action table
---@return table
local function upgrade_trigger_action(trigger_action)
    if trigger_action.pattern ~= LEGACY_TRAILER_VALUE_PATTERN or trigger_action.keyword_pattern ~= nil then
        return trigger_action
    end

    -- A new table, because the entry can be a table of the user config
    return vim.tbl_extend("force", trigger_action, {
        pattern = TRAILER_VALUE_PATTERN,
        keyword_pattern = TRAILER_VALUE_KEYWORD_PATTERN,
    })
end

---@param overrides? cmp_git.Config Partial user config.
---@return cmp_git.Config
function M.normalize(overrides)
    -- `tbl_deep_extend` keeps references to nested tables that only one side has, so copy the defaults before
    -- `apply_filter_fn` writes into them
    local normalized = vim.tbl_deep_extend("force", vim.deepcopy(defaults), overrides or {})

    ensure_contains(normalized.github.hosts, "github.com")
    ensure_contains(normalized.gitlab.hosts, "gitlab.com")

    apply_filter_fn(normalized.git, { "commits" })
    apply_filter_fn(normalized.github, { "issues", "mentions", "pull_requests" })
    apply_filter_fn(normalized.gitlab, { "issues", "mentions", "merge_requests" })

    normalized.trigger_actions = vim.tbl_map(upgrade_trigger_action, normalized.trigger_actions)

    return normalized
end

return M
