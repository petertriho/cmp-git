local helpers = require("tests.helpers")
local mention_capability = require("cmp_git.provider.capabilities.mentions")

local eq = helpers.eq

local T = helpers.new_set()

T["mention_capability_preflight_and_pagination"] = function()
    local request_pages = {}
    local runner = {
        build_fallback = function(commands, callback)
            eq(commands[1].exec, "preflight", "mention preflight command forwarded")
            return helpers.fake_job(function()
                callback('{"status":"404"}', true)
            end)
        end,
        build_fallback_list = function(commands, callback, handle_item)
            local page = commands[1].page
            table.insert(request_pages, page)
            return helpers.fake_job(function()
                local raw_items = page == 1 and { { name = "one" } } or {}
                local items = {}
                for _, item in ipairs(raw_items) do
                    table.insert(items, handle_item(item))
                end
                callback({ items = items, isIncomplete = false })
            end)
        end,
    }
    local adapter = {
        mentions_preflight_request = function()
            return {
                commands = { { exec = "preflight", args = {} } },
                handle_result = function(result)
                    local parsed = vim.json.decode(result)
                    return { member_type = parsed.status == "404" and "collaborators" or "contributors" }
                end,
            }
        end,
        mentions_request = function(_git_info, _trigger_char, _config, opts)
            eq(opts.context.member_type, "collaborators", "mention context comes from preflight")
            return {
                commands = { { exec = "mentions", args = {}, page = opts.page } },
                handle_item = function(item)
                    return { label = item.name }
                end,
            }
        end,
    }
    local callback, callbacks = helpers.recorder()

    mention_capability.complete({
        adapter = adapter,
        cache = {},
        callback = callback,
        config = { limit = 2 },
        git_info = {},
        trigger_char = "@",
        runner = runner,
        bufnr = 43,
    })

    eq(table.concat(request_pages, ","), "1,2", "mention capability paginates")
    eq(#callbacks, 2, "mention capability returns partial and final callbacks")
    eq(callbacks[1].isIncomplete, true, "first mention callback is incomplete")
    eq(callbacks[2].isIncomplete, false, "final mention callback is complete")
end

return T
