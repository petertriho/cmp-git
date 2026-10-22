local helpers = require("tests.helpers")
local change_request_capability = require("cmp_git.provider.capabilities.change_requests")

local eq = helpers.eq
local neq = helpers.neq

local T = helpers.new_set()

T["change_request_capability_returns_job"] = function()
    local runner = {
        build_fallback_list = function(_commands, callback, handle_item)
            return helpers.fake_job(function()
                callback({ items = { handle_item({ name = "pr" }) }, isIncomplete = false }, true)
            end)
        end,
    }
    local adapter = {
        change_requests_request = function()
            return {
                commands = { { exec = "fake", args = {} } },
                handle_item = function(item)
                    return { label = item.name }
                end,
            }
        end,
    }

    local job = change_request_capability.complete({
        adapter = adapter,
        cache = {},
        callback = function() end,
        config = {},
        git_info = {},
        trigger_char = "#",
        runner = runner,
        bufnr = 45,
    })

    neq(job, nil, "change request capability returns started job")
end

T["failure_gives_an_empty_list_and_is_not_cached"] = function()
    local runs = 0
    local cache = {}
    local callback, lists = helpers.recorder()
    local args = {
        adapter = {
            change_requests_request = function()
                return { commands = {}, handle_item = function() end }
            end,
        },
        cache = cache,
        callback = callback,
        config = {},
        git_info = {},
        trigger_char = "#",
        runner = {
            build_fallback_list = function(_commands, list_callback)
                if runs == 2 then
                    return nil
                end
                return helpers.fake_job(function()
                    runs = runs + 1
                    list_callback({ items = {}, isIncomplete = false }, false)
                end)
            end,
        },
        bufnr = 46,
    }

    change_request_capability.complete(args)
    change_request_capability.complete(args)
    -- The third request has no runnable command
    change_request_capability.complete(args)

    local empty = { items = {}, isIncomplete = false }
    eq(lists, { empty, empty, empty }, "each request gets one empty list")
    eq(cache[46], nil, "a failure is not cached")
    eq(runs, 2, "the next request tries again")
end

return T
