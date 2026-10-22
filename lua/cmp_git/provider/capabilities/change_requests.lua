local issues = require("cmp_git.provider.capabilities.issues")

local M = {}

---@param args cmp_git.Provider.CapabilityArgs
---@return cmp_git.SystemJob?
function M.job(args)
    local bufnr = args.bufnr or vim.api.nvim_get_current_buf()

    if args.cache[bufnr] then
        args.callback({ items = args.cache[bufnr], isIncomplete = false })
        return nil
    end

    return issues.list_job(args, args.adapter.change_requests_request(args.git_info, args.trigger_char, args.config))
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
