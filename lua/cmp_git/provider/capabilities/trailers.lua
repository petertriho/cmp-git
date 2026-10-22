local command = require("cmp_git.command")
local format = require("cmp_git.format")
local utils = require("cmp_git.utils")

local UNIT_SEPARATOR = "\031"
local KEY_PATTERN = "^[%w-]+$"

local find = string.find
local lower = string.lower
local match = string.match
local sub = string.sub
local trim_range = utils.trim_range

local M = {
    keys = {},
    identities = {},
    values = {},
}

---@class cmp_git.TrailerValue
---@field key string Casing of the first record.
---@field value string
---@field count integer
---@field timestamp integer?
---@field diff number Seconds since the most recent use.

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

---Calls `on_field` for each field of `output`, a `git log` output whose records end with NUL and whose fields end
---with the unit separator or the NUL of the record. Each record has at least one field, which can be empty. A
---trailing record without a NUL is dropped, like `utils.split_nul` does. The fields are read in place, so that a
---parse makes no table or string for each record.
---@param output string
---@param on_field fun(first: integer, last: integer, index: integer) The field is `output:sub(first, last)`, and
---`index` counts the fields of the record from 1.
local function each_field(output, on_field)
    local first = 1
    local index = 1
    local record_end = find(output, "\0", 1, true)
    -- The next separator at or after `first`. It can be in a later record, so it is kept until a field reaches it,
    -- and each byte is searched once.
    local separator = 0

    while record_end do
        if separator < first then
            separator = find(output, UNIT_SEPARATOR, first, true) or math.huge
        end

        if separator < record_end then
            on_field(first, separator - 1, index)
            first = separator + 1
            index = index + 1
        else
            on_field(first, record_end - 1, index)
            first = record_end + 1
            index = 1
            record_end = find(output, "\0", first, true)
        end
    end
end

---Parses the identity that `^%s*(.-)%s*<([^>]+)>` would match, without the whitespace around the name and the email.
---Unlike the pattern, which is quadratic on long runs of whitespace, it takes linear time.
---@param value string
---@return string? name nil when there is no identity. The name and the email can be empty.
---@return string email
local function parse_ident(value)
    local from = 1

    while true do
        local open = find(value, "<", from, true)
        if not open then
            return nil, ""
        end

        local close = find(value, ">", open + 1, true)
        -- A later `<` has no `>` after it either
        if not close then
            return nil, ""
        end

        -- `[^>]+` needs one character, so `<>` is part of the name, and a later `<` can start the email
        if close > open + 1 then
            return sub(value, trim_range(value, 1, open - 1)), sub(value, trim_range(value, open + 1, close - 1))
        end

        from = close + 1
    end
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
    local bufnr = context.bufnr or vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return false
    end

    if not filetype_matches(config.filetypes or {}, vim.bo[bufnr].filetype) then
        return false
    end

    local row = context.cursor and context.cursor.row
    if not row or row < (config.min_line or 1) then
        return false
    end

    -- Line 1 has no previous line, so it counts as blank. A negative index would count from the buffer end.
    local previous = row > 1 and vim.api.nvim_buf_get_lines(bufnr, row - 2, row - 1, false)[1] or ""
    if not previous:match("^%s*$") and not previous:match("^[%w-]+:%s*%S") then
        return false
    end

    if kind == "identities" then
        local key = M.line_key(context.line)
        return key ~= nil and contains_key(config.identities.keys or {}, key)
    end

    if kind == "values" then
        -- `Key:` alone falls through to the `:` trigger, so `Fixes:` still completes commits
        return M.line_key(context.line) ~= nil and not string.match(context.line, "^[%w-]+:$")
    end

    return true
end

---@param config cmp_git.Config.GitTrailerKeys
---@return cmp_git.CommandSpec
function M.keys.request(config)
    return {
        exec = "git",
        args = {
            "log",
            "-n",
            tostring(config.limit),
            "--format=%(trailers:keyonly,separator=%x1f)%x00",
        },
    }
end

---@param result string
---@param config cmp_git.Config.GitTrailerKeys
---@return cmp_git.TrailerKey[]
function M.keys.parse(result, config)
    local keys = {}
    local by_key = {}

    for index, key in ipairs(config.builtin or {}) do
        if not by_key[key:lower()] then
            ---@class cmp_git.TrailerKey
            local trailer = {
                key = key,
                count = 0,
                ---@type integer?
                builtin_index = index,
            }
            by_key[key:lower()] = trailer
            table.insert(keys, trailer)
        end
    end

    -- The lowercase form of each key as written, so that each casing is lowered once
    local ids = {}

    each_field(result, function(first, last)
        first, last = trim_range(result, first, last)
        local _, key_last = find(result, "^[%w-]+", first)
        -- Skips git versions that print the unknown `%(trailers:keyonly)` placeholder as text
        if first > last or key_last ~= last then
            return
        end

        local key = sub(result, first, last)
        local id = ids[key]
        if not id then
            id = lower(key)
            ids[key] = id
        end

        local trailer = by_key[id]
        if not trailer then
            trailer = { key = key, count = 0 }
            by_key[id] = trailer
            keys[#keys + 1] = trailer
        end
        trailer.count = trailer.count + 1
    end)

    return keys
end

---@param config cmp_git.Config.GitTrailerIdentities
---@return cmp_git.CommandSpec
function M.identities.request(config)
    local options = {}
    for _, key in ipairs(config.keys or {}) do
        if key:match(KEY_PATTERN) then
            table.insert(options, "key=" .. key)
        end
    end

    local trailers = ""
    if #options > 0 then
        trailers = "%(trailers:" .. table.concat(options, ",") .. ",unfold,separator=%x1f)"
    end

    return {
        exec = "git",
        args = {
            "log",
            "-n",
            tostring(config.limit),
            "--format=%at%x1f%aN%x1f%aE%x1f" .. trailers .. "%x00",
        },
    }
end

---@return cmp_git.CommandSpec
function M.identities.ident_request()
    return {
        exec = "git",
        args = { "var", "GIT_AUTHOR_IDENT" },
    }
end

---@param log_result string Output of `identities.request`.
---@param ident_result string Output of `identities.ident_request`.
---@return cmp_git.TrailerIdentity[]
function M.identities.parse(log_result, ident_result)
    local now = os.time()
    local identities = {}
    local by_email = {}
    -- The log repeats a few identities many times, and a repeat from the log changes nothing. These skip a repeat
    -- before the parse of its trailer value or the lowercase copy of its email.
    local known_values = {}
    local known_emails = {}

    ---@param name string Without surrounding whitespace.
    ---@param email string Without surrounding whitespace.
    ---@param timestamp integer?
    ---@param source string
    ---@param is_self boolean
    local function add(name, email, timestamp, source, is_self)
        if name == "" or email == "" or (known_emails[email] and not is_self) then
            return
        end
        known_emails[email] = true

        -- The log is newest first, so the first record for an email has the most recent name
        local id = lower(email)
        local existing = by_email[id]
        if existing then
            existing.is_self = existing.is_self or is_self
            return
        end

        ---@class cmp_git.TrailerIdentity
        local entry = {
            name = name,
            email = email,
            ---@type integer?
            timestamp = timestamp,
            -- Your identity without history sorts first, because Signed-off-by usually names you
            diff = timestamp and os.difftime(now, timestamp) or 0,
            source = source, -- "author", the trailer key, or "self"
            is_self = is_self,
        }
        by_email[id] = entry
        identities[#identities + 1] = entry
    end

    -- The fields of the current record: the time, the author name and email, then the trailers
    local time_first, time_last, author_first, author_last = 1, 0, 1, 0
    local timestamp

    ---@param first integer
    ---@param last integer
    local function add_trailer(first, last)
        local key, value_first = match(log_result, "^%s*([%w-]+):()", first)
        if not key then
            return
        end

        local value = sub(log_result, value_first, last)
        if known_values[value] then
            return
        end
        known_values[value] = true

        local name, email = parse_ident(value)
        if name then
            add(name, email, timestamp, key, false)
        end
    end

    each_field(log_result, function(first, last, index)
        if index == 1 then
            time_first, time_last = first, last
        elseif index == 2 then
            author_first, author_last = first, last
        elseif index == 3 then
            -- `tonumber` ignores the newline that ends the previous record
            timestamp = tonumber(sub(log_result, time_first, time_last))
            local name = sub(log_result, trim_range(log_result, author_first, author_last))
            add(name, sub(log_result, trim_range(log_result, first, last)), timestamp, "author", false)
        else
            add_trailer(first, last)
        end
    end)

    local name, email = parse_ident(ident_result)
    if name then
        add(name, email, nil, "self", true)
    end

    return identities
end

---@param config cmp_git.Config.GitTrailerValues
---@return cmp_git.CommandSpec
function M.values.request(config)
    return {
        exec = "git",
        args = {
            "log",
            "-n",
            tostring(config.limit),
            "--format=%at%x1f%(trailers:only,unfold,separator=%x1f)%x00",
        },
    }
end

---@param result string
---@return table<string, cmp_git.TrailerValue[]> values by lowercase key, newest first
function M.values.parse(result)
    local now = os.time()
    local by_key = {}
    local by_value = {}
    -- The lowercase form of each key as written, so that each casing is lowered once
    local ids = {}
    local timestamp

    each_field(result, function(first, last, index)
        if index == 1 then
            -- `tonumber` ignores the newline that ends the previous record
            timestamp = tonumber(sub(result, first, last))
            return
        end

        local key, value_first = match(result, "^%s*([%w-]+):()", first)
        if not key then
            return
        end
        local value_last
        value_first, value_last = trim_range(result, value_first, last)
        if value_first > value_last then
            return
        end

        local id = ids[key]
        if not id then
            id = lower(key)
            ids[key] = id
            by_key[id] = by_key[id] or {}
            by_value[id] = by_value[id] or {}
        end

        local value = sub(result, value_first, value_last)
        local entry = by_value[id][value]
        if not entry then
            entry = {
                key = key,
                value = value,
                count = 0,
                timestamp = timestamp,
                diff = timestamp and os.difftime(now, timestamp) or 0,
            }
            by_value[id][value] = entry
            local values = by_key[id]
            values[#values + 1] = entry
        end
        entry.count = entry.count + 1
    end)

    return by_key
end

---False when the cached history has no values for the key of the line. Unknown, so true, before the first fetch.
---@param cache table<integer, table<string, cmp_git.TrailerValue[]>>
---@param context { bufnr?: integer, line?: string }
---@return boolean
function M.values.may_have(cache, context)
    local cached = cache[context.bufnr or vim.api.nvim_get_current_buf()]
    if not cached then
        return true
    end

    local key = M.line_key(context.line)
    return key ~= nil and cached[key:lower()] ~= nil
end

---@generic TItem
---@param records TItem[]
---@param config { format: cmp_git.FormatConfig<TItem>, sort_by: string | fun(item: TItem): string }
---@param trigger_char string?
---@return cmp_git.CompletionItem[]
local function items(records, config, trigger_char)
    local result = {}
    for _, record in ipairs(records) do
        table.insert(result, format.item(config, trigger_char, record))
    end
    return result
end

M.keys.items = items
M.identities.items = items

---@param by_key table<string, cmp_git.TrailerValue[]>
---@param key string
---@param config cmp_git.Config.GitTrailerValues
---@param trigger_char string?
---@return cmp_git.CompletionItem[]
function M.values.items(by_key, key, config, trigger_char)
    return items(by_key[key:lower()] or {}, config, trigger_char)
end

---@class cmp_git.Provider.TrailerCapabilityArgs
---@field cache table<integer, any[]>
---@field callback fun(list: cmp_git.CompletionList)
---@field config { format: cmp_git.FormatConfig<any>, sort_by: string | fun(item: any): string }
---@field trigger_char string?
---@field runner? table
---@field bufnr? integer

---@class cmp_git.Provider.TrailerKeyArgs: cmp_git.Provider.TrailerCapabilityArgs
---@field config cmp_git.Config.GitTrailerKeys

---@class cmp_git.Provider.TrailerIdentityArgs: cmp_git.Provider.TrailerCapabilityArgs
---@field config cmp_git.Config.GitTrailerIdentities

---@class cmp_git.Provider.TrailerValueArgs: cmp_git.Provider.TrailerCapabilityArgs
---@field cache table<integer, table<string, cmp_git.TrailerValue[]>>
---@field config cmp_git.Config.GitTrailerValues
---@field key string

---@param args cmp_git.Provider.TrailerCapabilityArgs
---@return boolean hit
local function complete_from_cache(args)
    local bufnr = args.bufnr or vim.api.nvim_get_current_buf()
    if not args.cache[bufnr] then
        return false
    end

    args.callback({ items = items(args.cache[bufnr], args.config, args.trigger_char), isIncomplete = false })
    return true
end

---@param args cmp_git.Provider.TrailerKeyArgs
---@return cmp_git.SystemJob?
function M.keys.job(args)
    if complete_from_cache(args) then
        return nil
    end

    local bufnr = args.bufnr or vim.api.nvim_get_current_buf()
    local runner = args.runner or command
    return runner.build(M.keys.request(args.config), function(result, success)
        -- A failed log (for example, a repository without commits) still gives the built-in keys
        local parsed = M.keys.parse(success and result or "", args.config)
        args.cache[bufnr] = parsed
        args.callback({ items = items(parsed, args.config, args.trigger_char), isIncomplete = false })
    end)
end

---@param args cmp_git.Provider.TrailerIdentityArgs
---@return cmp_git.SystemJob?
function M.identities.job(args)
    if complete_from_cache(args) then
        return nil
    end

    local bufnr = args.bufnr or vim.api.nvim_get_current_buf()
    local runner = args.runner or command
    local state = { cancelled = false, active = nil }

    local function finish(log_result, ident_result)
        local parsed = M.identities.parse(log_result, ident_result)
        args.cache[bufnr] = parsed
        args.callback({ items = items(parsed, args.config, args.trigger_char), isIncomplete = false })
    end

    -- A failed log (for example, a repository without commits) still gives your identity
    local log_job = runner.build(M.identities.request(args.config), function(log_result, log_success)
        if state.cancelled then
            return
        end

        log_result = log_success and log_result or ""
        local ident_job = runner.build(M.identities.ident_request(), function(ident_result, ident_success)
            if state.cancelled then
                return
            end
            finish(log_result, ident_success and ident_result or "")
        end)

        if ident_job then
            state.active = ident_job
            ident_job:start()
        else
            finish(log_result, "")
        end
    end)

    if not log_job then
        return nil
    end

    return {
        command = log_job.command,
        start = function()
            state.active = log_job
            log_job:start()
        end,
        cancel = function()
            state.cancelled = true
            if state.active and state.active.cancel then
                state.active:cancel()
            end
        end,
    }
end

---@param args cmp_git.Provider.TrailerValueArgs
---@return cmp_git.SystemJob?
function M.values.job(args)
    local bufnr = args.bufnr or vim.api.nvim_get_current_buf()
    local function respond(by_key)
        args.callback({
            items = M.values.items(by_key, args.key, args.config, args.trigger_char),
            isIncomplete = false,
        })
    end

    if args.cache[bufnr] then
        respond(args.cache[bufnr])
        return nil
    end

    local runner = args.runner or command
    return runner.build(M.values.request(args.config), function(result, success)
        local parsed = M.values.parse(success and result or "")
        args.cache[bufnr] = parsed
        respond(parsed)
    end)
end

---@param args cmp_git.Provider.TrailerKeyArgs
function M.keys.complete(args)
    local job = M.keys.job(args)
    if job then
        job:start()
    end
    return job
end

---@param args cmp_git.Provider.TrailerIdentityArgs
function M.identities.complete(args)
    local job = M.identities.job(args)
    if job then
        job:start()
    end
    return job
end

---@param args cmp_git.Provider.TrailerValueArgs
function M.values.complete(args)
    local job = M.values.job(args)
    if job then
        job:start()
    end
    return job
end

return M
