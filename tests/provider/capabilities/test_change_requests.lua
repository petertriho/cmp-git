local helpers = require("tests.helpers")
local change_request_capability = require("cmp_git.provider.capabilities.change_requests")

local neq = helpers.neq

local T = helpers.new_set()

T["change_request_capability_returns_job"] = function()
    local runner = {
        build_fallback_list = function(_commands, callback, handle_item)
            return helpers.fake_job(function()
                callback({ items = { handle_item({ name = "pr" }) }, isIncomplete = false })
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

return T
