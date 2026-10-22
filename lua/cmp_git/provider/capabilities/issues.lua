local command = require("cmp_git.command")

local M = {}

---@class cmp_git.Provider.ListRequest
---@field commands cmp_git.CommandSpec[]
---@field handle_item fun(item: any): cmp_git.CompletionItem
---@field handle_parsed? fun(parsed: any): any[]? A result that is not a list is a failure.

---@class cmp_git.Provider.CapabilityArgs
---@field adapter table
---@field cache table<integer, cmp_git.CompletionItem[]>
---@field callback fun(list: cmp_git.CompletionList)
---@field config table
---@field git_info cmp_git.GitInfo
---@field trigger_char string
---@field runner? table
---@field bufnr? integer

---Make the job of a list request. The callback gets exactly one list, also when the commands fail or cannot run. A
---failure gives an empty list and is not cached, so that the next request tries again.
---@param args cmp_git.Provider.CapabilityArgs
---@param request cmp_git.Provider.ListRequest
---@return cmp_git.SystemJob? job nil when the callback already has its list.
function M.list_job(args, request)
    local bufnr = args.bufnr or vim.api.nvim_get_current_buf()
    local runner = args.runner or command
    local job = runner.build_fallback_list(request.commands, function(list, success)
        if not success then
            args.callback({ items = {}, isIncomplete = false })
            return
        end

        args.cache[bufnr] = list.items
        args.callback(list)
    end, request.handle_item, request.handle_parsed)

    if not job then
        args.callback({ items = {}, isIncomplete = false })
    end
    return job
end

---@param args cmp_git.Provider.CapabilityArgs
---@return cmp_git.SystemJob?
function M.job(args)
    local bufnr = args.bufnr or vim.api.nvim_get_current_buf()

    if args.cache[bufnr] then
        args.callback({ items = args.cache[bufnr], isIncomplete = false })
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

return M
