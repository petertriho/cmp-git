local log = require("cmp_git.log")

local M = {}

---@generic TItem
---@param response string
---@param handle_item fun(item: TItem): cmp_git.CompletionItem
---@param handle_parsed? fun(parsed: any): TItem[]?
---@return cmp_git.CompletionItem[] items
---@return boolean ok false when the response is not JSON, or not a list after `handle_parsed`.
function M.handle_response(response, handle_item, handle_parsed)
    local ok, parsed = pcall(vim.json.decode, response)
    if not ok then
        log.warn("Failed to parse api result")
        return {}, false
    end

    if handle_parsed then
        parsed = handle_parsed(parsed)
    end

    -- An error object or `null` must not look like a list without items, because the caller caches an empty list
    if not vim.islist(parsed) then
        log.debug("The api result is not a list")
        return {}, false
    end

    local items = {}
    for _, item in ipairs(parsed) do
        table.insert(items, handle_item(item))
    end
    return items, true
end

---@generic TItem
---@param result string
---@param handle_item fun(item: TItem): cmp_git.CompletionItem
---@param handle_parsed? fun(parsed: any): TItem[]?
---@return cmp_git.CompletionList list
---@return boolean ok false when the result is not JSON, or not a list after `handle_parsed`. Then the list is empty.
function M.completion_list(result, handle_item, handle_parsed)
    local items, ok = M.handle_response(result, handle_item, handle_parsed)
    return { items = items, isIncomplete = false }, ok
end

return M
