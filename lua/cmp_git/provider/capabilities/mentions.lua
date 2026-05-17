local command = require("cmp_git.command")

local M = {}

---@param args cmp_git.Provider.CapabilityArgs
function M.complete(args)
    local bufnr = args.bufnr or vim.api.nvim_get_current_buf()
    local runner = args.runner or command
    local state = { cancelled = false, active = nil }
    local controller = {
        command = "mentions",
        cancel = function()
            state.cancelled = true
            if state.active and state.active.cancel then
                state.active:cancel()
            end
        end,
    }

    if args.cache[bufnr] then
        local mentions_cache = args.cache[bufnr]
        args.callback({ items = mentions_cache.items, isIncomplete = mentions_cache.in_progress })
        return nil
    end

    args.cache[bufnr] = { items = {}, in_progress = true }

    local function fetch_mentions(page, context)
        if state.cancelled then
            return
        end

        local mentions_cache = args.cache[bufnr]
        local remaining = args.config.limit - #mentions_cache.items
        if remaining <= 0 then
            mentions_cache.in_progress = false
            args.callback({ items = mentions_cache.items, isIncomplete = false })
            return
        end

        local page_size = math.min(remaining, 100)
        local request = args.adapter.mentions_request(args.git_info, args.trigger_char, args.config, {
            context = context,
            page = page,
            page_size = page_size,
        })

        local job = runner.build_fallback_list(request.commands, function(list)
            if state.cancelled then
                return
            end

            vim.list_extend(mentions_cache.items, list.items)

            if args.adapter.mentions_has_more then
                mentions_cache.in_progress =
                    args.adapter.mentions_has_more(list, mentions_cache.items, args.config, context)
            else
                mentions_cache.in_progress = #list.items ~= 0 and #mentions_cache.items < args.config.limit
            end

            args.callback({ items = mentions_cache.items, isIncomplete = mentions_cache.in_progress })

            if mentions_cache.in_progress then
                fetch_mentions(page + 1, context)
            end
        end, request.handle_item, request.handle_parsed)

        if job then
            state.active = job
            job:start()
        else
            args.cache[bufnr] = nil
        end
    end

    local preflight = args.adapter.mentions_preflight_request
        and args.adapter.mentions_preflight_request(args.git_info, args.trigger_char, args.config)

    if not preflight then
        fetch_mentions(1, nil)
        return controller
    end

    local job = runner.build_fallback(preflight.commands, function(result, success)
        if state.cancelled then
            return
        end

        local context = nil
        if preflight.handle_result then
            context = preflight.handle_result(result, success)
        end
        fetch_mentions(1, context)
    end)

    if job then
        state.active = job
        job:start()
    else
        args.cache[bufnr] = nil
    end

    return controller
end

return M
