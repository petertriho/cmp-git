---The checks of the line at the cursor for autosquash completion. Core runs them on each request, and they are apart
---from the autosquash capability, so that a request that autosquash completion declines does not load it.
local trailer_lines = require("cmp_git.provider.capabilities.trailer_lines")

local M = {}

---The trigger character to give to the commit format: `!` when the typed text touches the `!` of the prefix
---(`fixup!` or `fixup!feat`), else nil.
---@param line string?
---@return string?
function M.attached_trigger(line)
    return line and string.match(line, "^%a+(!)%S*$")
end

---@param words string[]
---@param text string
---@return boolean
local function starts_a_word(words, text)
    for _, word in ipairs(words) do
        if string.sub(word, 1, #text) == text then
            return true
        end
    end
    return false
end

---Autosquash completion is only offered on the subject line (line 1) of a commit message. The prefix words also need
---only letters before the cursor, and the letters must start a word. Git reads only lowercase prefixes, so the words
---match case-sensitively. The commit list needs a line that starts with letters and `!`.
---@param config cmp_git.Config.GitAutosquash
---@param context { bufnr?: integer, cursor?: { row?: integer }, line?: string }
---@param kind "prefixes" | "commits"
---@return boolean
function M.available(config, context, kind)
    if not context.cursor or context.cursor.row ~= 1 then
        return false
    end

    -- Core asks on each request on line 1, so the checks of the line come before the reads of the buffer
    local line = context.line
    if not line then
        return false
    end
    if kind == "prefixes" then
        if not string.find(line, "^%a+$") or not starts_a_word(config.prefixes.words or {}, line) then
            return false
        end
    elseif not string.find(line, "^%a+!") then
        -- The commit list follows a prefix of letters and `!`, as git reads it and as `M.attached_trigger` assumes.
        -- The pattern of the entry chooses the prefixes.
        return false
    end

    local bufnr = context.bufnr or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return false
    end

    -- `vim.bo[bufnr]` makes a new table on each read
    local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
    return trailer_lines.filetype_matches(config.filetypes or {}, filetype)
end

return M
