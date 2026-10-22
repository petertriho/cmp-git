local command = require("cmp_git.command")
local format = require("cmp_git.format")

local M = {}

---@class cmp_git.Provider.ListRequest
---@field commands cmp_git.CommandSpec[]
---@field handle_item fun(item: any): cmp_git.CompletionItem
---@field handle_parsed? fun(parsed: any): any[]? A result that is not a list is a failure.

---The arguments of a refresh. A refresh only fills the cache, so it has no callback.
---@class cmp_git.Provider.RefreshArgs
---@field adapter table
---@field config table
---@field git_info cmp_git.GitInfo
---@field trigger_char string
---@field runner? table

---@class cmp_git.Provider.CapabilityArgs: cmp_git.Provider.RefreshArgs
---@field cache cmp_git.CacheEntry
---@field callback fun(list: cmp_git.CompletionList)

---A capability module, such as this one.
---@class cmp_git.Provider.Capability
---@field complete fun(args: cmp_git.Provider.CapabilityArgs): table?
---@field refresh fun(args: cmp_git.Provider.RefreshArgs, done: fun(items: table[]?))

---The raw items of the completion items. `format.item` keeps the raw item in `data`.
---@param items cmp_git.CompletionItem[]
---@return table[]
function M.raw_items(items)
    local raw = {}
    for index, item in ipairs(items) do
        raw[index] = item.data
    end
    return raw
end

---Give the cached items to the callback, formatted for this request.
---@param args cmp_git.Provider.CapabilityArgs
---@return boolean hit
function M.from_cache(args)
    local items = args.cache:get()
    if items == nil then
        return false
    end

    args.callback({ items = format.items(args.config, args.trigger_char, items), isIncomplete = false })
    return true
end

---Make the job of a list request. The callback gets exactly one list, also when the commands fail or cannot run. A
---failure gives an empty list and is not cached, so that the next request tries again.
---@param args cmp_git.Provider.CapabilityArgs
---@param request cmp_git.Provider.ListRequest
---@return cmp_git.SystemJob? job nil when the callback already has its list.
function M.list_job(args, request)
    local runner = args.runner or command
    local job = runner.build_fallback_list(request.commands, function(list, success)
        if not success then
            args.callback({ items = {}, isIncomplete = false })
            return
        end

        args.cache:set(M.raw_items(list.items))
        args.callback(list)
    end, request.handle_item, request.handle_parsed)

    if not job then
        args.callback({ items = {}, isIncomplete = false })
    end
    return job
end

---Start a list request for the cache only.
---@param runner? table
---@param request cmp_git.Provider.ListRequest
---@param done fun(items: table[]?) Gets the raw items, or nil when the request fails or cannot run.
function M.fetch(runner, request, done)
    local job = (runner or command).build_fallback_list(request.commands, function(list, success)
        done(success and M.raw_items(list.items) or nil)
    end, request.handle_item, request.handle_parsed)

    if not job then
        done(nil)
        return
    end
    job:start()
end

---@param args cmp_git.Provider.CapabilityArgs
---@return cmp_git.SystemJob?
function M.job(args)
    if M.from_cache(args) then
        return nil
    end

    return M.list_job(args, args.adapter.issues_request(args.git_info, args.trigger_char, args.config))
end

---@param args cmp_git.Provider.CapabilityArgs
function M.complete(args)
    local job = M.job(args)
    if job then
        job:start()
    end
    return job
end

---@param args cmp_git.Provider.RefreshArgs
---@param done fun(items: table[]?)
function M.refresh(args, done)
    M.fetch(args.runner, args.adapter.issues_request(args.git_info, args.trigger_char, args.config), done)
end

return M
