local helpers = require("tests.helpers")
local config = require("cmp_git.config")
local format = require("cmp_git.format")

local eq = helpers.eq
local ok = helpers.ok

local T = helpers.new_set()

local defaults = config.normalize({})

---@param item cmp_git.CompletionItem
local function fields(item)
    return {
        label = item.label,
        insertText = item.insertText,
        filterText = item.filterText,
        documentation = item.documentation.value,
    }
end

T["git_commits"] = function()
    local commit = {
        sha = "abcdef1234567890",
        title = "feat: add a thing",
        description = "Body text",
        author_name = "Ada Lovelace",
        author_mail = "ada@example.com",
        commit_timestamp = 1234567890,
        diff = 5,
    }
    local item = format.item(defaults.git.commits, ":", commit)

    eq(fields(item), {
        label = "abcdef1: feat: add a thing",
        insertText = "abcdef1234567890",
        filterText = ": abcdef1 feat: add a thing",
        documentation = "# feat: add a thing\n\nBody text\n\nAuthored by Ada Lovelace (ada@example.com), committed on "
            .. os.date("%c", 1234567890),
    })
    eq(item.documentation.kind, "markdown", "documentation is markdown")
    eq(item.sortText, "0000000005", "sort text comes from sort_by")
    ok(item.data == commit, "data is the commit")
end

T["github_issues"] = function()
    local item = format.item(defaults.github.issues, "#", {
        number = 12,
        title = "Crash on start",
        body = "Steps",
        updatedAt = "2024-01-01T00:00:00Z",
    })

    eq(fields(item), {
        label = "#12: Crash on start",
        insertText = "#12",
        filterText = "# 12 Crash on start",
        documentation = "# Crash on start\n\nSteps",
    })
end

T["github_mentions"] = function()
    local item = format.item(defaults.github.mentions, "@", { login = "octocat" })

    eq(fields(item), {
        label = "@octocat",
        insertText = "@octocat",
        filterText = "@octocat",
        documentation = "# octocat",
    })
    eq(item.sortText, nil, "mentions have no sort text")
end

T["github_pull_requests"] = function()
    local item = format.item(defaults.github.pull_requests, "#", {
        number = 34,
        title = "Fix crash",
        body = "Fixes #12",
        updatedAt = "2024-01-01T00:00:00Z",
    })

    eq(fields(item), {
        label = "#34: Fix crash",
        insertText = "#34",
        filterText = "# 34 Fix crash",
        documentation = "# Fix crash\n\nFixes #12",
    })
end

T["gitlab_issues"] = function()
    local item = format.item(defaults.gitlab.issues, "#", {
        iid = 5,
        title = "Slow pipeline",
        description = "Details",
        updated_at = "2024-01-01T00:00:00.000Z",
    })

    eq(fields(item), {
        label = "#5: Slow pipeline",
        insertText = "#5",
        filterText = "# 5 Slow pipeline",
        documentation = "# Slow pipeline\n\nDetails",
    })
end

T["gitlab_mentions"] = function()
    local item = format.item(defaults.gitlab.mentions, "@", { username = "ada", name = "Ada Lovelace" })

    eq(fields(item), {
        label = "@ada",
        insertText = "@ada",
        filterText = "@ ada",
        documentation = "# ada\n\nAda Lovelace",
    })
end

T["gitlab_merge_requests"] = function()
    local item = format.item(defaults.gitlab.merge_requests, "!", {
        iid = 8,
        title = "Speed up pipeline",
        description = "Closes #5",
        updated_at = "2024-01-01T00:00:00.000Z",
    })

    eq(fields(item), {
        label = "!8: Speed up pipeline",
        insertText = "!8",
        filterText = "! 8 Speed up pipeline",
        documentation = "# Speed up pipeline\n\nCloses #5",
    })
end

return T
