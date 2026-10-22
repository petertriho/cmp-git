local M = {}

---@param s string
---@return string
function M.trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

---Split NUL-terminated records. A trailing record without a NUL is dropped.
---@param input string
---@return string[]
function M.split_nul(input)
    local fields = {}
    local start = 1

    while true do
        local pos = string.find(input, "\0", start, true)
        if not pos then
            break
        end

        table.insert(fields, string.sub(input, start, pos - 1))
        start = pos + 1
    end

    return fields
end

---@param c integer|string
local function char_to_hex(c)
    return string.format("%%%02X", string.byte(c))
end

---@param value string
function M.url_encode(value)
    return string.gsub(value, "([^%w _%%%-%.~])", char_to_hex)
end

---@param d string
function M.parse_gitlab_date(d)
    local year, month, day, hours, mins, secs, _, offsethours, offsetmins =
        d:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)%.(%d+)[+-](%d+):(%d+)")

    if hours == nil then
        year, month, day, hours, mins, secs = d:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)%.(%d+)Z")
        offsethours = 0
        offsetmins = 0
    end

    return os.time({
        year = year,
        month = month,
        day = day,
        hour = hours + offsethours,
        min = mins + offsetmins,
        sec = secs,
    })
end

---@param d string
function M.parse_github_date(d)
    local year, month, day, hours, mins, secs = d:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)Z")

    return os.time({
        year = year,
        month = month,
        day = day,
        hour = hours,
        min = mins,
        sec = secs,
    })
end

return M
