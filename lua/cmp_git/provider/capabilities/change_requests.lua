local command = require("cmp_git.command")

local M = {}

---@param args cmp_git.Provider.CapabilityArgs
---@return cmp_git.SystemJob?
function M.job(args)
    local bufnr = args.bufnr or vim.api.nvim_get_current_buf()

    if args.cache[bufnr] then
        args.callback({ items = args.cache[bufnr], isIncomplete = false })
        return nil
    end

    local request = args.adapter.change_requests_request(args.git_info, args.trigger_char, args.config)
    local runner = args.runner or command
    return runner.build_fallback_list(request.commands, function(list)
        args.cache[bufnr] = list.items
        args.callback(list)
    end, request.handle_item, request.handle_parsed)
end

---@param args cmp_git.Provider.CapabilityArgs
function M.complete(args)
    local job = M.job(args)
    if job then
        job:start()
    end
end

return M
