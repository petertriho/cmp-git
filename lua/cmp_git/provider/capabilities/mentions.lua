local command = require("cmp_git.command")

local M = {}

---The most users that the REST APIs give on one page.
local MAX_PAGE_SIZE = 100

---The mentions of a buffer. While `in_progress`, `items` has the pages so far and `fetch` gets more.
---@class cmp_git.AsyncItemList
---@field in_progress boolean
---@field items cmp_git.CompletionItem[]
---@field fetch? cmp_git.Provider.MentionFetch

---The requests that wait for the pages of a buffer. They share one fetch.
---@class cmp_git.Provider.MentionFetch
---@field subscribers { callback: fun(list: cmp_git.CompletionList) }[]
---@field active? cmp_git.SystemJob
---@field cancelled boolean

---@class cmp_git.Provider.MentionCapabilityArgs: cmp_git.Provider.CapabilityArgs
---@field cache table<integer, cmp_git.AsyncItemList>

---@param subscribers { callback: fun(list: cmp_git.CompletionList) }[]
---@param list cmp_git.CompletionList
local function notify(subscribers, list)
    -- A copy, because a callback can cancel its request
    for _, subscriber in ipairs(vim.list_extend({}, subscribers)) do
        subscriber.callback(list)
    end
end

---Add a request to the fetch of the entry. The fetch stops when all its requests are cancelled.
---@param cache table<integer, cmp_git.AsyncItemList>
---@param bufnr integer
---@param entry cmp_git.AsyncItemList
---@param fetch cmp_git.Provider.MentionFetch The fetch of the entry.
---@param callback fun(list: cmp_git.CompletionList)
local function subscribe(cache, bufnr, entry, fetch, callback)
    local subscriber = { callback = callback }
    table.insert(fetch.subscribers, subscriber)

    return {
        command = "mentions",
        cancel = function()
            for i, other in ipairs(fetch.subscribers) do
                if other == subscriber then
                    table.remove(fetch.subscribers, i)
                    break
                end
            end
            if #fetch.subscribers > 0 or fetch.cancelled or not entry.in_progress then
                return
            end

            -- Otherwise the entry stays in progress, and later requests wait for pages that never come
            fetch.cancelled = true
            if cache[bufnr] == entry then
                cache[bufnr] = nil
            end
            if fetch.active and fetch.active.cancel then
                fetch.active:cancel()
            end
        end,
    }
end

---@param args cmp_git.Provider.MentionCapabilityArgs
---@param bufnr integer
---@param entry cmp_git.AsyncItemList
---@param fetch cmp_git.Provider.MentionFetch The fetch of the entry.
local function start_fetch(args, bufnr, entry, fetch)
    local runner = args.runner or command
    local limit = args.config.limit
    -- A constant page size, so that page N starts after the users of the pages before it
    local page_size = math.min(limit, MAX_PAGE_SIZE)

    ---@param success boolean
    local function finish(success)
        entry.in_progress = false
        entry.fetch = nil
        -- A failure is not cached, so that the next request tries again. The pages before it are still shown.
        if not success and args.cache[bufnr] == entry then
            args.cache[bufnr] = nil
        end
        local subscribers = fetch.subscribers
        fetch.subscribers = {}
        notify(subscribers, { items = entry.items, isIncomplete = false })
    end

    if limit < 1 then
        finish(true)
        return
    end

    local function fetch_page(page, context)
        local request = args.adapter.mentions_request(args.git_info, args.trigger_char, args.config, {
            context = context,
            page = page,
            page_size = page_size,
        })

        local job = runner.build_fallback_list(request.commands, function(list, success)
            if fetch.cancelled then
                return
            end
            if not success then
                finish(false)
                return
            end

            local items = vim.list_extend(vim.list_extend({}, entry.items), list.items)
            local has_more
            if args.adapter.mentions_has_more then
                has_more = args.adapter.mentions_has_more(list, items, args.config, context)
            else
                -- A page that is not full is the last one. Asking for the next page would wait for an empty one.
                has_more = #list.items >= page_size
            end
            if #items >= limit then
                has_more = false
                for i = #items, limit + 1, -1 do
                    items[i] = nil
                end
            end
            entry.items = items

            if not has_more then
                finish(true)
                return
            end

            notify(fetch.subscribers, { items = items, isIncomplete = true })
            fetch_page(page + 1, context)
        end, request.handle_item, request.handle_parsed)

        if not job then
            finish(false)
            return
        end
        fetch.active = job
        job:start()
    end

    local preflight = args.adapter.mentions_preflight_request
        and args.adapter.mentions_preflight_request(args.git_info, args.trigger_char, args.config)
    if not preflight then
        fetch_page(1, nil)
        return
    end

    local job = runner.build_fallback(preflight.commands, function(result, success)
        if fetch.cancelled then
            return
        end

        -- `handle_result` also gets a failed preflight, and chooses the users to ask for
        local context = nil
        if preflight.handle_result then
            context = preflight.handle_result(result, success)
        end
        fetch_page(1, context)
    end)

    if not job then
        fetch_page(1, nil)
        return
    end
    fetch.active = job
    job:start()
end

---Give the mentions of the buffer. The callback gets a list with `isIncomplete = true` for each page before the last,
---then exactly one list with `isIncomplete = false`, unless the request is cancelled.
---@param args cmp_git.Provider.MentionCapabilityArgs
---@return { command: string, cancel: fun() }? controller nil when the callback already has its final list.
function M.complete(args)
    local bufnr = args.bufnr or vim.api.nvim_get_current_buf()
    local entry = args.cache[bufnr]

    if entry and not entry.in_progress then
        args.callback({ items = entry.items, isIncomplete = false })
        return nil
    end

    if entry then
        if #entry.items > 0 then
            args.callback({ items = entry.items, isIncomplete = true })
        end
        return subscribe(args.cache, bufnr, entry, entry.fetch --[[@as cmp_git.Provider.MentionFetch]], args.callback)
    end

    local fetch = { subscribers = {}, cancelled = false }
    entry = { items = {}, in_progress = true, fetch = fetch }
    args.cache[bufnr] = entry
    local controller = subscribe(args.cache, bufnr, entry, fetch, args.callback)
    start_fetch(args, bufnr, entry, fetch)
    return controller
end

return M
