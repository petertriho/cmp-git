local helpers = require("tests.helpers")
local cache = require("cmp_git.cache")
local config = require("cmp_git.config")
local format = require("cmp_git.format")
local issue_capability = require("cmp_git.provider.capabilities.issues")

local eq = helpers.eq
local neq = helpers.neq

local T = helpers.new_set()

local git_info = { host = "github.com", owner = "owner", repo = "repo" }

---@param number integer
---@return cmp_git.GitHub.Issue
local function issue(number)
    return { number = number, title = "issue " .. number, body = "", updatedAt = "2024-01-01T00:00:00Z", state = "open" }
end

---An adapter that formats its items like the real adapters, and counts its requests.
---@return table adapter
---@return { count: integer } requests
local function counting_adapter()
    local requests = { count = 0 }
    return {
        issues_request = function(_git_info, trigger_char, capability_config)
            requests.count = requests.count + 1
            return {
                commands = { { exec = "fake", args = { "issues" } } },
                handle_item = function(item)
                    return format.item(capability_config, trigger_char, item)
                end,
            }
        end,
    },
        requests
end

---A runner whose jobs give the issues at once.
---@param issues cmp_git.GitHub.Issue[]
---@return table runner
---@return { count: integer } runs
local function answering_runner(issues)
    local runs = { count = 0 }
    return {
        build_fallback_list = function(commands, callback, handle_item)
            runs.count = runs.count + 1
            eq(commands[1].exec, "fake", "issue capability forwards commands")
            return helpers.fake_job(function()
                callback({ items = vim.tbl_map(handle_item, vim.deepcopy(issues)), isIncomplete = false }, true)
            end)
        end,
    },
        runs
end

---@param overrides table
---@return cmp_git.Provider.CapabilityArgs args
---@return cmp_git.CompletionList[] lists
local function capability_args(overrides)
    local callback, lists = helpers.recorder()
    local issues_config = config.normalize({}).github.issues
    return vim.tbl_extend("force", {
        cache = cache.entry(git_info, "github-issues", issues_config),
        callback = callback,
        config = issues_config,
        git_info = git_info,
        trigger_char = "#",
    }, overrides),
        lists
end

T["issue_capability_uses_cache_and_runner"] = function()
    local adapter, requests = counting_adapter()
    local runner, runs = answering_runner({ issue(1) })
    local args, lists = capability_args({ adapter = adapter, runner = runner })

    local job = issue_capability.complete(args)
    local cached_job = issue_capability.complete(args)

    eq(requests.count, 1, "issue capability requests once")
    eq(runs.count, 1, "issue capability runs once")
    eq(#lists, 2, "issue capability callbacks on miss and hit")
    eq(lists[2].items[1].label, "#1: issue 1", "a hit formats the cached issue")
    eq(lists[2].items[1].data, issue(1), "a hit gives the raw issue in data")
    neq(job, nil, "issue capability returns started job")
    eq(cached_job, nil, "issue capability cache hit returns no job")
end

T["a_hit_formats_the_items_for_its_request"] = function()
    local adapter = counting_adapter()
    local runner = answering_runner({ issue(1), issue(2) })
    local args, lists = capability_args({ adapter = adapter, runner = runner })
    issue_capability.complete(args)

    -- A new session, so that the items come from the file
    cache.forget()
    local custom = config.normalize({
        github = {
            issues = {
                format = {
                    label = function(_trigger_char, item)
                        return "custom " .. item.number
                    end,
                },
            },
        },
    }).github.issues
    args.config = custom
    args.cache = cache.entry(git_info, "github-issues", custom)
    args.trigger_char = "!"
    issue_capability.complete(args)

    eq(#lists, 2, "a list for each request")
    eq(
        vim.tbl_map(function(item)
            return item.label
        end, lists[2].items),
        { "custom 1", "custom 2" },
        "the format of the request"
    )
    eq(lists[2].items[1].filterText, "! 1 issue 1", "the trigger character of the request")
end

local EMPTY = { items = {}, isIncomplete = false }

---@param runner table
---@return cmp_git.Provider.CapabilityArgs args
---@return cmp_git.CompletionList[] lists
local function failing_args(runner)
    return capability_args({
        adapter = {
            issues_request = function()
                return { commands = {}, handle_item = function() end }
            end,
        },
        runner = runner,
    })
end

T["failure_gives_an_empty_list_and_is_not_cached"] = function()
    local runs = 0
    local args, lists = failing_args({
        build_fallback_list = function(_commands, callback)
            return helpers.fake_job(function()
                runs = runs + 1
                callback({ items = {}, isIncomplete = false }, false)
            end)
        end,
    })

    issue_capability.complete(args)
    issue_capability.complete(args)

    eq(lists, { EMPTY, EMPTY }, "each request gets one empty list")
    eq(args.cache:get(), nil, "a failure is not cached")
    eq(vim.fn.filereadable(args.cache.path), 0, "a failure writes no file")
    eq(runs, 2, "the next request tries again")
end

T["no_runnable_command_gives_an_empty_list"] = function()
    local args, lists = failing_args({
        build_fallback_list = function()
            return nil
        end,
    })

    eq(issue_capability.complete(args), nil, "no job")
    eq(lists, { EMPTY }, "one empty list")
    eq(args.cache:get(), nil, "nothing is cached")
end

T["a_refresh_gives_the_raw_items"] = function()
    local adapter = counting_adapter()
    local runner = answering_runner({ issue(1) })
    local results = {}

    issue_capability.refresh({
        adapter = adapter,
        config = config.normalize({}).github.issues,
        git_info = git_info,
        trigger_char = "#",
        runner = runner,
    }, function(items)
        table.insert(results, items)
    end)

    eq(results, { { issue(1) } }, "the raw issues")

    local failed = {}
    issue_capability.refresh({
        adapter = adapter,
        config = config.normalize({}).github.issues,
        git_info = git_info,
        trigger_char = "#",
        runner = {
            build_fallback_list = function()
                return nil
            end,
        },
    }, function(items)
        table.insert(failed, items == nil)
    end)
    eq(failed, { true }, "nil when no command can run")
end

return T
