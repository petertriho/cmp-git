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
                callback({ items = { handle_item({ name = "one" }) }, isIncomplete = false })
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

return T
