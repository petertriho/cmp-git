---Completion requests from start to the final callback, in a git repository with 1000 commits. Each request runs the
---real git commands and a fake `gh` (see `fixtures.isolate_environment`), so the times include process starts but no
---network. `cold` cases use a new source and an empty cache for each request, and `warm` cases repeat a request that
---the cache can answer. `disk` cases use a new source and the cache files of an earlier request, as in a new session.
local fixtures = require("benchmarks.fixtures")

local COMMITS = 1000

local LINES = {
    "Fix the parser",
    "",
    "See the notes",
    "",
    "Co-authored-by: Ad",
    "Refs: AB",
    "Sig",
}

---@type table<string, { row: integer, line: string, trigger_character?: string }>
local REQUESTS = {
    commits = { row = 3, line = "See :", trigger_character = ":" },
    trailer_keys = { row = 7, line = "Sig" },
    trailer_identities = { row = 5, line = "Co-authored-by: Ad" },
    trailer_values = { row = 6, line = "Refs: AB" },
    github_issues_and_prs = { row = 3, line = "See #", trigger_character = "#" },
    github_mentions = { row = 3, line = "See @", trigger_character = "@" },
}

---Remove the cached items of the providers from memory and from disk. Revisions before the disk cache have no cache
---module, and a new source is cold there.
local function clear_cache()
    local ok, cache = pcall(require, "cmp_git.cache")
    if ok then
        cache.clear_all()
    end
end

---@param name string A key of `REQUESTS`.
---@param mode "cold" | "warm" | "disk"
---@return bench.AsyncCase
local function request_case(name, mode)
    local request = REQUESTS[name]
    return {
        name = string.format("e2e/%s/%s", name, mode),
        async = true,
        setup = function()
            local dir = fixtures.repo(COMMITS)
            return {
                bufnr = fixtures.commit_buffer(dir, LINES),
                core = require("cmp_git.core").new({}),
            }
        end,
        before_each = function(state)
            vim.api.nvim_set_current_buf(state.bufnr)
            if mode == "cold" then
                clear_cache()
            elseif mode == "disk" then
                -- The warm-up run writes the files
                require("cmp_git.cache").forget()
            end
            if mode ~= "warm" then
                state.core = require("cmp_git.core").new({})
            end
        end,
        run = function(state, done)
            state.core:complete({
                trigger_character = request.trigger_character,
                cursor = { row = request.row, character = #request.line },
                line = request.line,
                bufnr = state.bufnr,
            }, function(list)
                if list.isIncomplete then
                    return
                end
                if #list.items == 0 then
                    done("the request gave no items")
                    return
                end
                done()
            end)
        end,
    }
end

---@type bench.Case[]
local cases = {}
for _, name in ipairs({
    "commits",
    "trailer_keys",
    "trailer_identities",
    "trailer_values",
    "github_issues_and_prs",
    "github_mentions",
}) do
    table.insert(cases, request_case(name, "cold"))
    table.insert(cases, request_case(name, "warm"))
end
-- Only the items of the providers have cache files, not the commits and the trailers
for _, name in ipairs({ "github_issues_and_prs", "github_mentions" }) do
    table.insert(cases, request_case(name, "disk"))
end

return cases
