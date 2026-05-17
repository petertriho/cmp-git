local log = require("cmp_git.log")

local M = {}

---@generic TItem
---@param response string
---@param handle_item fun(item: TItem): cmp_git.CompletionItem
---@param handle_parsed? fun(parsed: any): TItem[]
---@return cmp_git.CompletionItem[]
function M.handle_response(response, handle_item, handle_parsed)
    local items = {}

    local function process_data(ok, parsed)
        if not ok then
            log.warn("Failed to parse api result")
            return
        end

        if handle_parsed then
            parsed = handle_parsed(parsed)
        end

        for _, item in ipairs(parsed) do
            table.insert(items, handle_item(item))
        end
    end

    local ok, parsed = pcall(vim.json.decode, response)
    process_data(ok, parsed)

    return items
end

---@generic TItem
---@param result string
---@param handle_item fun(item: TItem): cmp_git.CompletionItem
---@param handle_parsed? fun(parsed: any): TItem[]
---@return cmp_git.CompletionList
function M.completion_list(result, handle_item, handle_parsed)
    return {
        items = M.handle_response(result, handle_item, handle_parsed),
        isIncomplete = false,
    }
end

return M
