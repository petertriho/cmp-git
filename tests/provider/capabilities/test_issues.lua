local helpers = require("tests.helpers")
local issue_capability = require("cmp_git.provider.capabilities.issues")

local eq = helpers.eq
local neq = helpers.neq

local T = helpers.new_set()

T["issue_capability_uses_cache_and_runner"] = function()
    local callback_count = 0
    local last_list
    local request_count = 0
    local runner_count = 0
    local adapter = {
        issues_request = function()
            request_count = request_count + 1
            return {
                commands = { { exec = "fake", args = { "issues" } } },
                handle_item = function(item)
                    return { label = item.name }
                end,
            }
        end,
    }
    local runner = {
        build_fallback_list = function(commands, callback, handle_item)
            runner_count = runner_count + 1
            eq(commands[1].exec, "fake", "issue capability forwards commands")
            return helpers.fake_job(function()
                callback({ items = { handle_item({ name = "one" }) }, isIncomplete = false }, true)
            end)
        end,
    }
    local args = {
        adapter = adapter,
        cache = {},
        callback = function(list)
            callback_count = callback_count + 1
            last_list = list
        end,
        config = {},
        git_info = {},
        trigger_char = "#",
        runner = runner,
        bufnr = 42,
    }

    local job = issue_capability.complete(args)
    local cached_job = issue_capability.complete(args)

    eq(request_count, 1, "issue capability requests once")
    eq(runner_count, 1, "issue capability runs once")
    eq(callback_count, 2, "issue capability callbacks on miss and hit")
    eq(last_list.items[1].label, "one", "issue capability caches mapped items")
    neq(job, nil, "issue capability returns started job")
    eq(cached_job, nil, "issue capability cache hit returns no job")
end

local EMPTY = { items = {}, isIncomplete = false }

---@param runner table
---@return cmp_git.Provider.CapabilityArgs args
---@return cmp_git.CompletionList[] lists
local function failing_args(runner)
    local callback, lists = helpers.recorder()
    return {
        adapter = {
            issues_request = function()
                return { commands = {}, handle_item = function() end }
            end,
        },
        cache = {},
        callback = callback,
        config = {},
        git_info = {},
        trigger_char = "#",
        runner = runner,
        bufnr = 42,
    },
        lists
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
    eq(args.cache[42], nil, "a failure is not cached")
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
    eq(args.cache[42], nil, "nothing is cached")
end

return T
