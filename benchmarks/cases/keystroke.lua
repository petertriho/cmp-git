---Work that runs while the user types: the checks that nvim-cmp and blink.cmp make on each keystroke, and requests
---that cmp-git declines without starting a process.
local fixtures = require("benchmarks.fixtures")

local LINES = {
    "Fix the parser",
    "",
    "Body text",
    "",
    "Co-authored-by: Ada Lovelace <ada@example.com>",
}

local function noop() end

---nvim-cmp finds the keyword start on each keystroke with the source's keyword pattern. It compiles the regex once
---(`cmp.utils.pattern.offset`).
---@param line string
---@return bench.SyncCase
local function keyword_offset(name, line)
    return {
        name = "keystroke/keyword_offset/" .. name,
        setup = function()
            local core = require("cmp_git.core").new({})
            return { regex = vim.regex([[\%(]] .. core:get_keyword_pattern() .. [[\)\m$]]), line = line }
        end,
        run = function(state)
            state.regex:match_str(state.line)
        end,
    }
end

---An nvim-cmp request from `cmp.Source.complete`.
---@param line string
---@param row integer
---@return cmp_git.CmpCompletionParams
local function cmp_params(line, row)
    return {
        context = {
            cursor_before_line = line,
            cursor = { row = row, col = #line + 1, character = #line },
        },
        completion_context = { triggerKind = 1 },
    }
end

---@type bench.Case[]
return {
    {
        name = "keystroke/is_available",
        setup = function()
            fixtures.scratch_buffer(LINES)
            return require("cmp_git.core").new({})
        end,
        run = function(core)
            core:is_available()
        end,
    },
    keyword_offset("prose_80", fixtures.prose(80)),
    keyword_offset("prose_300", fixtures.prose(300)),
    keyword_offset("prose_1000", fixtures.prose(1000)),
    keyword_offset("trailer_value", "Co-authored-by: Ada Lov"),
    {
        -- The first word of the subject matches the trailer key pattern, but trailers start below the subject
        name = "keystroke/nvim_cmp/complete_declined",
        setup = function()
            fixtures.scratch_buffer(LINES)
            return { source = require("cmp_git.source").new({}), params = cmp_params("Fix", 1) }
        end,
        run = function(state)
            state.source:complete(state.params, noop)
        end,
    },
    {
        name = "keystroke/nvim_cmp/complete_declined_prose_300",
        setup = function()
            local line = fixtures.prose(300)
            fixtures.scratch_buffer({ "Fix the parser", "", line })
            return { source = require("cmp_git.source").new({}), params = cmp_params(line, 3) }
        end,
        run = function(state)
            state.source:complete(state.params, noop)
        end,
    },
    {
        name = "keystroke/blink/get_completions_declined",
        setup = function()
            local bufnr = fixtures.scratch_buffer(LINES)
            return {
                source = require("cmp_git.blink").new({}),
                ctx = {
                    bufnr = bufnr,
                    line = "Fix the parser",
                    cursor = { 1, 3 },
                    trigger = { kind = "keyword" },
                },
            }
        end,
        run = function(state)
            local cancel = state.source:get_completions(state.ctx, noop)
            cancel()
        end,
    },
}
