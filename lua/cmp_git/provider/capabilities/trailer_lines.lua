---The checks of the line at the cursor for trailer completion. Core runs them on each request, and they are apart from
---the trailer capability, so that a request that trailer completion declines does not load the log parsers.
local M = {}

---@param filetypes string[]
---@param filetype string
---@return boolean
local function filetype_matches(filetypes, filetype)
    if vim.tbl_contains(filetypes, filetype) then
        return true
    end

    for ft in string.gmatch(filetype, "[^%.]+") do
        if vim.tbl_contains(filetypes, ft) then
            return true
        end
    end

    return false
end

---@param keys string[]
---@param key string
---@return boolean
local function contains_key(keys, key)
    key = key:lower()
    for _, candidate in ipairs(keys) do
        if candidate:lower() == key then
            return true
        end
    end
    return false
end

---@param line string?
---@return string?
function M.line_key(line)
    return line and string.match(line, "^([%w-]+):")
end

---The trigger character to give to the identities and values formats: `:` when the value touches the colon, else
---nil.
---@param line string?
---@return string?
function M.attached_trigger(line)
    return line and string.match(line, "^[%w-]+(:)%S*$")
end

---Trailer completion is only offered in commit messages, from `config.min_line` (by default below the subject and
---its blank line), at the start of a trailer block or after another trailer.
---@param config cmp_git.Config.GitTrailers
---@param context { bufnr?: integer, cursor?: { row?: integer }, line?: string }
---@param kind "keys" | "identities" | "values"
---@return boolean
function M.available(config, context, kind)
    local row = context.cursor and context.cursor.row
    if not row or row < (config.min_line or 1) then
        return false
    end

    -- Core asks each kind on each request, so the checks of the line come before the reads of the buffer
    if kind == "identities" then
        local key = M.line_key(context.line)
        if key == nil or not contains_key(config.identities.keys or {}, key) then
            return false
        end
    elseif kind == "values" then
        -- `Key:` alone falls through to the `:` trigger, so `Fixes:` still completes commits
        if M.line_key(context.line) == nil or string.match(context.line, "^[%w-]+:$") then
            return false
        end
    end

    local bufnr = context.bufnr or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return false
    end

    -- `vim.bo[bufnr]` makes a new table on each read
    local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
    if not filetype_matches(config.filetypes or {}, filetype) then
        return false
    end

    -- Line 1 has no previous line, so it counts as blank. A negative index would count from the buffer end.
    local previous = row > 1 and vim.api.nvim_buf_get_lines(bufnr, row - 2, row - 1, false)[1] or ""
    return previous:match("^%s*$") ~= nil or previous:match("^[%w-]+:%s*%S") ~= nil
end

return M
