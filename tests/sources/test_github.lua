local helpers = require("tests.helpers")
local command = require("cmp_git.command")
local config = require("cmp_git.config")
local repository = require("cmp_git.repository")
local GitHub = require("cmp_git.sources.github")

local eq = helpers.eq
local ok = helpers.ok

local T = helpers.new_set()

T["github_instance_state_isolation"] = function()
    local first = GitHub.new(config.normalize({ github = { hosts = { "github.example.com" } } }).github)
    local second = GitHub.new(config.normalize({ github = { hosts = { "github.other.com" } } }).github)

    ok(
        first:is_valid_host({ host = "github.example.com", owner = "owner", repo = "repo" }),
        "first GitHub instance validates own host"
    )
    ok(
        not first:is_valid_host({ host = "github.other.com", owner = "owner", repo = "repo" }),
        "first GitHub instance rejects second host"
    )
    ok(
        second:is_valid_host({ host = "github.other.com", owner = "owner", repo = "repo" }),
        "second GitHub instance validates own host"
    )
    ok(
        second:is_valid_host({ host = "github.com", owner = "owner", repo = "repo" }),
        "GitHub instance validates default host"
    )

    first.cache.issues[1] = {}
    eq(second.cache.issues[1], nil, "GitHub issue cache is instance-local")
    ok(first.cache.mentions ~= second.cache.mentions, "GitHub mention cache table is instance-local")
    ok(first.cache.pull_requests ~= second.cache.pull_requests, "GitHub PR cache table is instance-local")
end

local git_info = { host = "github.com", owner = "owner", repo = "repo" }

---Make PATH a directory with only these commands until the end of the case.
---@param scripts table<string, string> The shell script body of each command, by name.
---@return string bin The directory.
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
    return bin
end

local records = {
    issue = { number = 1, title = "an issue", body = "", updatedAt = "2024-01-01T00:00:00Z" },
    pr = { number = 2, title = "a pull request", body = "", updatedAt = "2024-01-01T00:00:00Z" },
}

---A GitHub source whose `gh` commands give one issue and one pull request. `requests` counts the commands that ran.
---@return cmp_git.Source.GitHub source
---@return { issue: integer, pr: integer } requests
local function fake_github()
    local source = GitHub.new(config.normalize({}).github)
    local requests = { issue = 0, pr = 0 }

    -- No gh on PATH, so that the default repository lookup does not run
    fake_commands({})
    helpers.stub(command, "build_fallback_list", function(commands, callback, handle_item)
        local kind = commands[1].args[1]
        return {
            command = "fake",
            start = function(_, on_complete)
                requests[kind] = requests[kind] + 1
                callback({ items = { handle_item(vim.deepcopy(records[kind])) }, isIncomplete = false }, true)
                if on_complete then
                    on_complete(true)
                end
            end,
        }
    end)

    return source, requests
end

---@param items cmp_git.CompletionItem[]
---@return string[]
local function labels(items)
    return vim.tbl_map(function(item)
        return item.label
    end, items)
end

T["issues_and_change_requests_keep_the_caches_separate"] = function()
    local source, requests = fake_github()
    local callback, lists = helpers.recorder()
    local bufnr = vim.api.nvim_get_current_buf()

    source:complete_issues_and_change_requests(callback, git_info, "#")
    eq(labels(lists[1].items), { "#1: an issue", "#2: a pull request" }, "issues, then pull requests")
    eq(labels(source.cache.issues[bufnr]), { "#1: an issue" }, "the issue cache has no pull requests")

    source:complete_issues_and_change_requests(callback, git_info, "#")
    eq(
        labels(lists[2].items),
        { "#1: an issue", "#2: a pull request" },
        "a cache hit gives the issues and pull requests"
    )

    source:complete_issues(callback, git_info, "#")
    eq(labels(lists[3].items), { "#1: an issue" }, "the issues action gives only issues")
    eq(requests, { issue = 1, pr = 1 }, "each command runs once")
end

T["issues_and_change_requests_after_a_cached_change_request"] = function()
    local source, requests = fake_github()
    local callback, lists = helpers.recorder()

    source:complete_change_requests(callback, git_info, "#")
    source:complete_issues_and_change_requests(callback, git_info, "#")

    eq(#lists, 2, "one list for each request")
    eq(
        labels(lists[2].items),
        { "#1: an issue", "#2: a pull request" },
        "the cached pull requests come after the issues"
    )
    eq(requests, { issue = 1, pr = 1 }, "each command runs once")
end

---@class tests.GitHubJob: cmp_git.SystemJob
---@field started boolean
---@field cancelled boolean
---@field respond fun(success: boolean) Complete the job with its record, or fail it.

---A GitHub source whose `gh` jobs wait until the case completes them.
---@return cmp_git.Source.GitHub source
---@return table<string, tests.GitHubJob> jobs The last job of each kind, `issue` or `pr`.
local function manual_github()
    local source = GitHub.new(config.normalize({}).github)
    local jobs = {}

    -- No gh on PATH, so that the default repository lookup does not run
    fake_commands({})
    helpers.stub(command, "build_fallback_list", function(commands, callback, handle_item)
        local kind = commands[1].args[1]
        local job = { command = "fake", started = false, cancelled = false }
        function job.start()
            job.started = true
        end
        function job.cancel()
            job.cancelled = true
        end
        function job.respond(success)
            if success then
                callback({ items = { handle_item(vim.deepcopy(records[kind])) }, isIncomplete = false }, true)
            else
                callback({ items = {}, isIncomplete = false }, false)
            end
        end
        jobs[kind] = job
        return job
    end)

    return source, jobs
end

T["issues_and_change_requests_start_at_once"] = function()
    local source, jobs = manual_github()
    local callback, lists = helpers.recorder()

    source:complete_issues_and_change_requests(callback, git_info, "#")
    eq({ jobs.issue.started, jobs.pr.started }, { true, true }, "both commands run at once")

    jobs.pr.respond(true)
    eq(#lists, 0, "the list waits for the issues")
    jobs.issue.respond(true)

    eq(#lists, 1, "one list")
    eq(labels(lists[1].items), { "#1: an issue", "#2: a pull request" }, "issues, then pull requests")
end

T["issues_and_change_requests_keep_the_items_of_a_request_that_succeeds"] = function()
    for _, failed in ipairs({ "issue", "pr" }) do
        local source, jobs = manual_github()
        local callback, lists = helpers.recorder()

        source:complete_issues_and_change_requests(callback, git_info, "#")
        jobs.issue.respond(failed ~= "issue")
        jobs.pr.respond(failed ~= "pr")

        eq(#lists, 1, failed .. " failed: one list")
        eq(
            labels(lists[1].items),
            failed == "issue" and { "#2: a pull request" } or { "#1: an issue" },
            failed .. " failed: the items of the other request"
        )
    end
end

T["issues_and_change_requests_cancel_both"] = function()
    local source, jobs = manual_github()
    local callback, lists = helpers.recorder()

    local _, controller = source:complete_issues_and_change_requests(callback, git_info, "#")
    helpers.not_nil(controller):cancel()

    eq({ jobs.issue.cancelled, jobs.pr.cancelled }, { true, true }, "both jobs are cancelled")
    eq(lists, {}, "a cancelled request gets no list")
end

---A GitHub source whose jobs answer at once and record the repository that they ask for. With `default_repo`, a fake
---`gh repo set-default --view` prints it and records the directory that it runs in.
---@param default_repo? string nil for no gh on PATH.
---@return cmp_git.Source.GitHub source
---@return string[] repos The `owner/repo` of each job, in order.
---@return fun(): string[] gh_calls The directories of the `gh repo set-default` calls so far.
local function recording_github(default_repo)
    local log_path = helpers.tempdir() .. "/gh_calls"
    local scripts = {}
    if default_repo then
        scripts.gh = table.concat({
            'if [ "$1 $2 $3" != "repo set-default --view" ]; then exit 1; fi',
            string.format("pwd -P >> '%s'", log_path),
            string.format("printf '%%s\\n' '%s'", default_repo),
        }, "\n")
    end
    fake_commands(scripts)

    local repos = {}
    ---@param args string[]
    local function record(args)
        -- `gh issue list --repo host/owner/repo` or `gh api repos/owner/repo/...`
        if args[1] == "api" then
            table.insert(repos, args[2]:match("^repos/([^/]+/[^/]+)/"))
        else
            table.insert(repos, args[4]:match("^[^/]+/(.+)$"))
        end
    end
    helpers.stub(command, "build_fallback_list", function(commands, callback)
        record(commands[1].args)
        return helpers.fake_job(function()
            callback({ items = {}, isIncomplete = false }, true)
        end)
    end)
    helpers.stub(command, "build_fallback", function(commands, callback)
        record(commands[1].args)
        return helpers.fake_job(function()
            callback("", false)
        end)
    end)

    local function gh_calls()
        if vim.fn.filereadable(log_path) == 0 then
            return {}
        end
        return vim.fn.readfile(log_path)
    end

    return GitHub.new(config.normalize({}).github), repos, gh_calls
end

local REQUESTS = { "complete_issues", "complete_change_requests", "complete_issues_and_change_requests" }

---A new git info for each request, so that a change by one request cannot reach the next one.
---@return cmp_git.GitInfo
local function remote()
    return { host = "github.com", owner = "owner", repo = "repo" }
end

T["the_default_repository_is_looked_up_once_without_blocking"] = function()
    local source, repos, gh_calls = recording_github("upstream/project")
    local cwd = helpers.tempdir()
    helpers.stub(repository, "get_cwd", function()
        return cwd
    end)
    local callback, lists = helpers.recorder()

    local info = remote()
    eq(source:complete_issues(callback, info, "#"), true, "the host is handled")
    eq(#lists, 0, "the request does not wait for gh")
    helpers.wait_for(function()
        return #lists == 1
    end, "the issues answer")
    eq(repos, { "upstream/project" }, "the issues come from the default repository")
    eq(info, remote(), "the git info of the caller does not change")
    eq(gh_calls(), { cwd }, "gh runs in the directory of the buffer")

    -- A buffer without cached lists, so that the requests need the repository
    vim.api.nvim_set_current_buf(helpers.buffer({}, "markdown"))
    source:complete_mentions(callback, remote(), "@")
    source:complete_issues_and_change_requests(callback, remote(), "#")

    eq(#lists, 3, "the known default repository answers at once")
    eq(#repos, 5, "issues, mention preflight, mentions, issues, pull requests")
    for i, repo in ipairs(repos) do
        eq(repo, "upstream/project", "request " .. i .. " uses the default repository")
    end
    eq(gh_calls(), { cwd }, "gh runs once for the repository")
end

T["requests_during_the_lookup_share_it"] = function()
    local source, repos, gh_calls = recording_github("upstream/project")
    local callback, lists = helpers.recorder()

    source:complete_issues(callback, remote(), "#")
    source:complete_mentions(callback, remote(), "@")
    helpers.wait_for(function()
        return #lists == 2
    end, "both requests answer")

    eq(#gh_calls(), 1, "one gh call")
    eq(repos, { "upstream/project", "upstream/project", "upstream/project" }, "the default repository")
end

T["without_a_default_repository_the_remote_is_used"] = function()
    local source, repos, gh_calls = recording_github("")
    local callback, lists = helpers.recorder()

    source:complete_issues(callback, remote(), "#")
    helpers.wait_for(function()
        return #lists == 1
    end, "the issues answer")
    vim.api.nvim_set_current_buf(helpers.buffer({}, "markdown"))
    source:complete_issues(callback, remote(), "#")

    eq(#lists, 2, "the second request answers at once")
    eq(repos, { "owner/repo", "owner/repo" }, "the remote repository")
    eq(#gh_calls(), 1, "gh runs once")
end

T["a_cache_hit_does_not_run_gh"] = function()
    local source, repos = recording_github("upstream/project")
    local bufnr = vim.api.nvim_get_current_buf()
    source.cache.issues[bufnr] = {}
    source.cache.change_requests[bufnr] = {}
    source.cache.mentions[bufnr] = { items = {}, in_progress = false }
    local callback, lists = helpers.recorder()

    for _, method in ipairs(vim.list_extend({ "complete_mentions" }, REQUESTS)) do
        source[method](source, callback, remote(), "#")
    end

    eq(#lists, 4, "each cache hit answers at once")
    eq(repos, {}, "no command runs")
    eq(source.default_repos, {}, "no lookup starts")
end

T["without_gh_the_remote_is_used"] = function()
    local source, repos = recording_github(nil)
    local callback, lists = helpers.recorder()

    for _, method in ipairs(REQUESTS) do
        vim.api.nvim_set_current_buf(helpers.buffer({}, "markdown"))
        source[method](source, callback, remote(), "#")
    end

    eq(#lists, 3, "each request answers at once")
    eq(repos, { "owner/repo", "owner/repo", "owner/repo", "owner/repo" }, "the remote repository")
end

T["an_octo_buffer_keeps_its_repository"] = function()
    local source, repos, gh_calls = recording_github("upstream/project")
    vim.api.nvim_set_current_buf(helpers.buffer({}, "octo"))
    local callback, lists = helpers.recorder()

    source:complete_issues(callback, remote(), "#")
    source:complete_mentions(callback, remote(), "@")

    eq(#lists, 2, "each request answers at once")
    eq(repos, { "owner/repo", "owner/repo", "owner/repo" }, "the repository of the octo buffer")
    eq(gh_calls(), {}, "gh does not run")
end

T["a_cancel_during_the_lookup_starts_no_request"] = function()
    local source, repos = recording_github("upstream/project")
    local callback, lists = helpers.recorder()

    local _, controller = source:complete_issues(callback, remote(), "#")
    helpers.not_nil(controller):cancel()
    helpers.wait_for(function()
        local lookup = source.default_repos["github.com/owner/repo"]
        return lookup ~= nil and lookup.done
    end, "the lookup ends")

    eq(repos, {}, "no request starts")
    eq(lists, {}, "a cancelled request gets no list")
end

T["requests_cache_under_the_request_buffer"] = function()
    local source = recording_github()
    local request_bufnr = helpers.buffer({}, "markdown")
    local current_bufnr = helpers.buffer({}, "markdown")
    vim.api.nvim_set_current_buf(current_bufnr)
    local callback, lists = helpers.recorder()

    for _, request in ipairs(REQUESTS) do
        source[request](source, callback, remote(), "#", request_bufnr)
    end
    helpers.wait_for(function()
        return #lists == #REQUESTS
    end, "the requests answer")

    ok(source.cache.issues[request_bufnr] ~= nil, "the issues are cached for the request buffer")
    ok(source.cache.change_requests[request_bufnr] ~= nil, "the pull requests are cached for the request buffer")
    eq(source.cache.issues[current_bufnr], nil, "the current buffer gets no issues")
    eq(source.cache.change_requests[current_bufnr], nil, "the current buffer gets no pull requests")
end

return T
