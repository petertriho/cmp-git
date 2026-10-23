local helpers = require("tests.helpers")
local sort = require("cmp_git.sort")

local eq = helpers.eq
local ok = helpers.ok

local T = helpers.new_set()

T["get_sort_text"] = function()
    local item = { title = "title", number = 7 }

    eq(
        sort.get_sort_text(function(issue)
            return "custom " .. issue.title
        end, item),
        "custom title",
        "custom function"
    )
    eq(sort.get_sort_text("title", item), "title", "string key")
    eq(sort.get_sort_text(nil, item), nil, "no sort")
end

T["default_git_sorts"] = function()
    eq(sort.get_sort_text(sort.git.commits, { diff = 42 }), "0000000042", "commits sort by age")

    local used_more = sort.git.trailers.keys({ key = "Fixes", count = 2, builtin_index = 9 })
    local builtin_first = sort.git.trailers.keys({ key = "Signed-off-by", count = 1, builtin_index = 2 })
    local mined = sort.git.trailers.keys({ key = "Change-Id", count = 1 })
    ok(used_more < builtin_first, "trailer keys sort by use count")
    ok(builtin_first < mined, "built-in trailer keys sort before mined keys")

    eq(sort.git.trailers.identities({ diff = -5 }), "0000000000", "future identities sort as now")
    ok(sort.git.trailers.identities({ diff = 5 }) < sort.git.trailers.identities({ diff = 50 }), "recent identities")

    local frequent = sort.git.trailers.values({ key = "Assisted-by", value = "Codex", count = 3, diff = 500 })
    local recent = sort.git.trailers.values({ key = "Assisted-by", value = "Claude", count = 1, diff = 5 })
    local old = sort.git.trailers.values({ key = "Assisted-by", value = "Copilot", count = 1, diff = 50 })
    ok(frequent < recent, "trailer values sort by use count")
    ok(recent < old, "trailer values with the same count sort by age")
end

T["default_provider_sorts"] = function()
    local function recent_first(sort_fn, field, older, newer)
        local older_text = sort_fn({ [field] = older })
        local newer_text = sort_fn({ [field] = newer })
        eq(#older_text, 10, field .. " sort text width")
        ok(newer_text < older_text, field .. " sorts recent items first")
    end

    recent_first(sort.github.issues, "updatedAt", "2020-01-01T00:00:00Z", "2024-01-01T00:00:00Z")
    recent_first(sort.github.pull_requests, "updatedAt", "2020-01-01T00:00:00Z", "2024-01-01T00:00:00Z")
    recent_first(sort.gitlab.issues, "updated_at", "2020-01-01T00:00:00.000Z", "2024-01-01T00:00:00.000Z")
    recent_first(sort.gitlab.merge_requests, "updated_at", "2020-01-01T00:00:00.000Z", "2024-01-01T00:00:00.000Z")
    local without_date = {}
    local old_issue = { updatedAt = "1990-01-01T00:00:00Z" }
    local old_merge_request = { updated_at = "1990-01-01T00:00:00.000Z" }
    ok(sort.github.issues(without_date) > sort.github.issues(old_issue), "an issue without a date sorts last")
    ok(
        sort.gitlab.merge_requests(without_date) > sort.gitlab.merge_requests(old_merge_request),
        "a merge request without a date sorts last"
    )
    eq(sort.github.mentions, nil, "GitHub mentions keep the API order")
    eq(sort.gitlab.mentions, nil, "GitLab mentions keep the API order")
end

-- The sorts read only the date of an item
---@diagnostic disable: missing-fields
T["gitea_and_forgejo_sorts"] = function()
    local sorts = {
        ["gitea issues"] = sort.gitea.issues,
        ["gitea pull requests"] = sort.gitea.pull_requests,
        ["forgejo issues"] = sort.forgejo.issues,
        ["forgejo pull requests"] = sort.forgejo.pull_requests,
    }

    for name, sort_fn in pairs(sorts) do
        -- The servers give the time with the offset of the server
        local older = sort_fn({ updated_at = "2024-01-01T12:00:00+02:00" })
        local newer = sort_fn({ updated_at = "2024-01-01T11:00:00Z" })
        eq(#older, 10, name .. " sort text width")
        ok(newer < older, name .. " sort the last updated first")
        ok(sort_fn({}) > older, name .. " without a date sort last")
    end
    eq(sort.gitea.mentions, nil, "Gitea mentions keep the API order")
    eq(sort.forgejo.mentions, nil, "Forgejo mentions keep the API order")
end

return T
