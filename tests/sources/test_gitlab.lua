local helpers = require("tests.helpers")
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

    first.cache.issues[1] = {}
    eq(second.cache.issues[1], nil, "GitLab issue cache is instance-local")
    ok(first.cache.mentions ~= second.cache.mentions, "GitLab mention cache table is instance-local")
    ok(first.cache.merge_requests ~= second.cache.merge_requests, "GitLab MR cache table is instance-local")
end

local git_info = { host = "gitlab.com", owner = "owner", repo = "repo" }
local EMPTY = { items = {}, isIncomplete = false }

---Make PATH a directory with only these commands until the end of the case.
---@param scripts table<string, string> The shell script body of each command, by name.
local function fake_commands(scripts)
    local bin = helpers.tempdir()
    for name, body in pairs(scripts) do
        local path = bin .. "/" .. name
        local file = assert(io.open(path, "w"))
        file:write("#!/bin/sh\n" .. body .. "\n")
        file:close()
        vim.uv.fs_chmod(path, tonumber("755", 8))
    end
    helpers.stub(vim.env, "PATH", bin)
end

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
    fake_commands({ glab = "exit 1", curl = "exit 22" })
    local source = GitLab.new(config.normalize({}).gitlab)
    local bufnr = vim.api.nvim_get_current_buf()

    eq(answers(source, "complete_issues", "#"), { EMPTY }, "issues")
    eq(answers(source, "complete_change_requests", "!"), { EMPTY }, "merge requests")
    eq(answers(source, "complete_mentions", "@"), { EMPTY }, "mentions")
    eq(source.cache.issues[bufnr], nil, "failed issues are not cached")
    eq(source.cache.change_requests[bufnr], nil, "failed merge requests are not cached")
    eq(source.cache.mentions[bufnr], nil, "failed mentions are not cached")
end

T["missing_commands_give_an_empty_list"] = function()
    fake_commands({})
    local source = GitLab.new(config.normalize({}).gitlab)

    eq(answers(source, "complete_issues", "#"), { EMPTY }, "issues")
    eq(answers(source, "complete_change_requests", "!"), { EMPTY }, "merge requests")
    eq(answers(source, "complete_mentions", "@"), { EMPTY }, "mentions")
end

return T
