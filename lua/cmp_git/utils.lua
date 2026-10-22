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

---@param digits string
---@return integer
local function to_integer(digits)
    -- The date pattern captures only digits
    return tonumber(digits) --[[@as integer]]
end

---Seconds since the Unix epoch for a date and time in UTC. `os.time` would read the fields as local time.
---@param year integer
---@param month integer
---@param day integer
---@param hour integer
---@param min integer
---@param sec integer
---@return integer
local function utc_time(year, month, day, hour, min, sec)
    -- Days since 1970-01-01 from the days_from_civil algorithm, https://howardhinnant.github.io/date_algorithms.html
    if month <= 2 then
        year = year - 1
    end
    local era = math.floor(year / 400)
    local year_of_era = year - era * 400
    local day_of_year = math.floor((153 * ((month + 9) % 12) + 2) / 5) + day - 1
    local day_of_era = year_of_era * 365 + math.floor(year_of_era / 4) - math.floor(year_of_era / 100) + day_of_year
    local days = era * 146097 + day_of_era - 719468

    return days * 86400 + hour * 3600 + min * 60 + sec
end

---Seconds since the Unix epoch for an ISO 8601 date and time with `Z` or a UTC offset, such as
---`2024-01-02T03:04:05Z` or `2024-01-02T03:04:05.678+05:30`.
---@param value any
---@return integer timestamp 0 when the value is not such a date, so that the item sorts as the oldest.
local function parse_date(value)
    if type(value) ~= "string" then
        return 0
    end

    local year, month, day, hour, min, sec, zone = value:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)%.?%d*(.*)$")
    if not year then
        return 0
    end

    local offset = 0
    if zone ~= "Z" then
        local sign, offset_hours, offset_mins = zone:match("^([+-])(%d%d):?(%d%d)$")
        if not sign then
            return 0
        end
        offset = (to_integer(offset_hours) * 3600 + to_integer(offset_mins) * 60) * (sign == "-" and -1 or 1)
    end

    local time = utc_time(
        to_integer(year),
        to_integer(month),
        to_integer(day),
        to_integer(hour),
        to_integer(min),
        to_integer(sec)
    )
    return time - offset
end

---@param d string|vim.NIL|nil A JSON null is `vim.NIL`.
---@return integer timestamp 0 when the value is not a date.
function M.parse_gitlab_date(d)
    return parse_date(d)
end

---@param d string|vim.NIL|nil A JSON null is `vim.NIL`.
---@return integer timestamp 0 when the value is not a date.
function M.parse_github_date(d)
    return parse_date(d)
end

return M
