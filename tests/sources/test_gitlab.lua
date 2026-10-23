local helpers = require("tests.helpers")
local cache = require("cmp_git.cache")
local config = require("cmp_git.config")
local GitLab = require("cmp_git.sources.gitlab")

local eq = helpers.eq
local ok = helpers.ok

local T = helpers.new_set()

T["gitlab_instance_state_isolation"] = function()
    local first = GitLab.new(config.normalize({ gitlab = { hosts = { "gitlab.example.com" } } }).gitlab)
    local second = GitLab.new(config.normalize({ gitlab = { hosts = { "gitlab.other.com" } } }).gitlab)

    ok(
        first:is_valid_host({ host = "gitlab.example.com", owner = "owner", repo = "repo" }),
        "first GitLab instance validates own host"
    )
    ok(
        not first:is_valid_host({ host = "gitlab.other.com", owner = "owner", repo = "repo" }),
        "first GitLab instance rejects second host"
    )
    ok(
        second:is_valid_host({ host = "gitlab.other.com", owner = "owner", repo = "repo" }),
        "second GitLab instance validates own host"
    )
    ok(
        second:is_valid_host({ host = "gitlab.com", owner = "owner", repo = "repo" }),
        "GitLab instance validates default host"
    )
end

local git_info = { host = "gitlab.com", owner = "owner", repo = "repo" }
local EMPTY = { items = {}, isIncomplete = false }

---Run a request of the source and return the lists that it gave.
---@param source cmp_git.Source.Gitlab
---@param method string
---@param trigger_char string
---@return cmp_git.CompletionList[]
local function answers(source, method, trigger_char)
    local callback, lists = helpers.recorder()
    local handled = source[method](source, callback, git_info, trigger_char)
    eq(handled, true, method .. " handles the host")
    helpers.wait_for(function()
        return #lists > 0
    end, method .. " answers")
    helpers.flush()
    return lists
end

T["failed_commands_give_an_empty_list"] = function()
    helpers.fake_commands({ glab = "exit 1", curl = "exit 22" })
    local source = GitLab.new(config.normalize({}).gitlab)

    eq(answers(source, "complete_issues", "#"), { EMPTY }, "issues")
    eq(answers(source, "complete_change_requests", "!"), { EMPTY }, "merge requests")
    eq(answers(source, "complete_mentions", "@"), { EMPTY }, "mentions")
    eq(source:_entry("issues", git_info):get(), nil, "failed issues are not cached")
    eq(source:_entry("merge_requests", git_info):get(), nil, "failed merge requests are not cached")
    eq(source:_entry("mentions", git_info):get(), nil, "failed mentions are not cached")
end

T["missing_commands_give_an_empty_list"] = function()
    helpers.fake_commands({})
    local source = GitLab.new(config.normalize({}).gitlab)

    eq(answers(source, "complete_issues", "#"), { EMPTY }, "issues")
    eq(answers(source, "complete_change_requests", "!"), { EMPTY }, "merge requests")
    eq(answers(source, "complete_mentions", "@"), { EMPTY }, "mentions")
end

---@param list cmp_git.CompletionList
---@return string[]
local function labels(list)
    return vim.tbl_map(function(item)
        return item.label
    end, list.items)
end

T["glab_items_are_cached_for_the_next_session"] = function()
    helpers.fake_commands({
        glab = [[printf '%s' '[{"iid":1,"title":"an issue","description":null,"updated_at":"2024-01-01T00:00:00Z"}]']],
    })
    local source = GitLab.new(config.normalize({}).gitlab)
    eq(labels(answers(source, "complete_issues", "#")[1]), { "#1: an issue" }, "the issues of glab")

    cache.forget()
    helpers.fake_commands({ glab = "exit 1" })
    local callback, lists = helpers.recorder()
    GitLab.new(config.normalize({}).gitlab):complete_issues(callback, git_info, "#")

    eq(#lists, 1, "a new session answers at once")
    eq(labels(lists[1]), { "#1: an issue" }, "with the issues of the file")
    eq(lists[1].items[1].data.description, "", "the null description of the API is still empty")
end

T["stale_items_refresh_in_the_background"] = function()
    helpers.fake_commands({
        glab = [[printf '%s' '[{"iid":2,"title":"a new issue","description":"","updated_at":"2024-01-01T00:00:00Z"}]']],
    })
    local source = GitLab.new(config.normalize({}).gitlab, { ttl = 60 })
    local entry = source:_entry("issues", git_info)
    entry:set({ { iid = 1, title = "an issue", description = "", updated_at = "2024-01-01T00:00:00Z" } })
    entry.fetched_at = os.time() - 60
    local callback, lists = helpers.recorder()

    source:complete_issues(callback, git_info, "#")
    eq(labels(lists[1]), { "#1: an issue" }, "the request answers at once with the stale items")

    helpers.wait_for(function()
        return not entry.refreshing
    end, "the refresh ends")
    source:complete_issues(callback, git_info, "#")
    eq(labels(lists[2]), { "#2: a new issue" }, "the next request gets the new items")
end

return T
