local command = require("cmp_git.command")

local M = {}

---@param args cmp_git.Provider.CapabilityArgs
function M.complete(args)
    local bufnr = args.bufnr or vim.api.nvim_get_current_buf()
    local runner = args.runner or command

    if args.cache[bufnr] then
        local mentions_cache = args.cache[bufnr]
        args.callback({ items = mentions_cache.items, isIncomplete = mentions_cache.in_progress })
        return
    end

    args.cache[bufnr] = { items = {}, in_progress = true }

    local function fetch_mentions(page, context)
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
            job:start()
        else
            args.cache[bufnr] = nil
        end
    end

    local preflight = args.adapter.mentions_preflight_request
        and args.adapter.mentions_preflight_request(args.git_info, args.trigger_char, args.config)

    if not preflight then
        fetch_mentions(1, nil)
        return
    end

    local job = runner.build_fallback(preflight.commands, function(result, success)
        local context = nil
        if preflight.handle_result then
            context = preflight.handle_result(result, success)
        end
        fetch_mentions(1, context)
    end)

    if job then
        job:start()
    else
        args.cache[bufnr] = nil
    end
end

return M
