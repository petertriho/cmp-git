---Work that runs on the main thread for each completion request: routing, parsing command output, and making the
---completion items. Cache hits make the items again, so the `items` cases are the cost of a cached request.
local fixtures = require("benchmarks.fixtures")

local COMMITS = 1000

---Remove the cmp-git modules from the module cache, so that the next `require` loads them again.
local function unload()
    for name in pairs(package.loaded) do
        if name == "cmp_git" or name:find("^cmp_git%.") then
            package.loaded[name] = nil
        end
    end
end

---@type bench.Case[]
return {
    {
        name = "request/route/trailer_key",
        setup = function()
            local bufnr = fixtures.scratch_buffer({ "Fix the parser", "", "Body text", "", "Sig" })
            return {
                core = require("cmp_git.core").new({}),
                context = { bufnr = bufnr, cursor = { row = 5, character = 3 }, line = "Sig" },
            }
        end,
        run = function(state)
            state.core:_route(state.context)
        end,
    },
    {
        name = "request/route/trailer_value",
        setup = function()
            local bufnr = fixtures.scratch_buffer({ "Fix the parser", "", "Body text", "", "Co-authored-by: Ad" })
            return {
                core = require("cmp_git.core").new({}),
                context = { bufnr = bufnr, cursor = { row = 5, character = 18 }, line = "Co-authored-by: Ad" },
            }
        end,
        run = function(state)
            state.core:_route(state.context)
        end,
    },
    {
        name = "request/commits/parse_1000",
        setup = function()
            return {
                output = fixtures.commits_log(fixtures.commits(COMMITS)),
                config = require("cmp_git.config").normalize({}).git.commits,
            }
        end,
        run = function(state)
            require("cmp_git.provider.capabilities.commits").parse(state.output, state.config)
        end,
    },
    {
        name = "request/commits/items_100",
        setup = function()
            local commits = require("cmp_git.provider.capabilities.commits")
            local config = require("cmp_git.config").normalize({}).git.commits
            return {
                commits = commits,
                config = config,
                parsed = commits.parse(fixtures.commits_log(fixtures.commits(100)), config),
            }
        end,
        run = function(state)
            state.commits.items(state.parsed, state.config, ":")
        end,
    },
    {
        name = "request/trailers/keys_parse_100",
        setup = function()
            return {
                output = fixtures.trailer_keys_log(fixtures.commits(100)),
                config = require("cmp_git.config").normalize({}).git.trailers.keys,
            }
        end,
        run = function(state)
            require("cmp_git.provider.capabilities.trailers").keys.parse(state.output, state.config)
        end,
    },
    {
        name = "request/trailers/identities_parse_1000",
        setup = function()
            return { output = fixtures.trailer_identities_log(fixtures.commits(COMMITS)) }
        end,
        run = function(state)
            require("cmp_git.provider.capabilities.trailers").identities.parse(
                state.output,
                "Bench User <bench@example.com> 1700000000 +0000\n"
            )
        end,
    },
    {
        name = "request/trailers/identities_items_1000",
        setup = function()
            local trailers = require("cmp_git.provider.capabilities.trailers")
            return {
                trailers = trailers,
                config = require("cmp_git.config").normalize({}).git.trailers.identities,
                parsed = trailers.identities.parse(fixtures.trailer_identities_log(fixtures.commits(COMMITS)), ""),
            }
        end,
        run = function(state)
            state.trailers.identities.items(state.parsed, state.config, nil)
        end,
    },
    {
        name = "request/trailers/values_parse_1000",
        setup = function()
            return { output = fixtures.trailer_values_log(fixtures.commits(COMMITS)) }
        end,
        run = function(state)
            require("cmp_git.provider.capabilities.trailers").values.parse(state.output)
        end,
    },
    {
        name = "request/github/issues_100",
        setup = function()
            local config = require("cmp_git.config").normalize({}).github.issues
            local git_info = { host = "github.com", owner = "owner", repo = "repo" }
            return {
                json = fixtures.github_issues_json(100),
                request = require("cmp_git.provider.adapters.github").issues_request(git_info, "#", config),
            }
        end,
        run = function(state)
            require("cmp_git.response").completion_list(
                state.json,
                state.request.handle_item,
                state.request.handle_parsed
            )
        end,
    },
    {
        name = "request/github/mentions_100",
        setup = function()
            local config = require("cmp_git.config").normalize({}).github.mentions
            local git_info = { host = "github.com", owner = "owner", repo = "repo" }
            local adapter = require("cmp_git.provider.adapters.github")
            return {
                json = fixtures.github_mentions_json(100),
                request = adapter.mentions_request(git_info, "@", config, { page = 1, page_size = 100 }),
            }
        end,
        run = function(state)
            require("cmp_git.response").completion_list(
                state.json,
                state.request.handle_item,
                state.request.handle_parsed
            )
        end,
    },
    {
        name = "request/gitlab/merge_requests_100",
        setup = function()
            local config = require("cmp_git.config").normalize({}).gitlab.merge_requests
            local git_info = { host = "gitlab.com", owner = "owner", repo = "repo" }
            return {
                json = fixtures.gitlab_merge_requests_json(100),
                request = require("cmp_git.provider.adapters.gitlab").change_requests_request(git_info, "!", config),
            }
        end,
        run = function(state)
            require("cmp_git.response").completion_list(
                state.json,
                state.request.handle_item,
                state.request.handle_parsed
            )
        end,
    },
    {
        name = "request/text_edits_100",
        setup = function()
            local list = require("cmp_git.response").completion_list(fixtures.github_issues_json(100), function(item)
                return { label = "#" .. item.number, insertText = "#" .. item.number }
            end)
            return {
                apply = require("cmp_git.core").apply_text_edits,
                items = list.items,
                context = { cursor = { row = 3, character = 7 }, line = "See #12", trigger_character = "#" },
            }
        end,
        run = function(state)
            state.apply(state.items, state.context)
        end,
    },
    {
        name = "startup/require",
        run = function()
            unload()
            require("cmp_git.source")
            require("cmp_git.blink")
        end,
    },
    {
        -- What `setup` costs: the modules of the nvim-cmp source and a new source
        name = "startup/setup",
        run = function()
            unload()
            require("cmp_git.source").new({})
        end,
    },
    {
        -- All the code, also the modules that load on the first request that needs them
        name = "startup/require_all",
        setup = function()
            local modules = {}
            for _, path in ipairs(vim.api.nvim_get_runtime_file("lua/cmp_git/**/*.lua", true)) do
                local name = path:match("/lua/(cmp_git/.*)%.lua$"):gsub("/init$", ""):gsub("/", ".")
                if not vim.tbl_contains(modules, name) then
                    table.insert(modules, name)
                end
            end
            return { modules = modules }
        end,
        run = function(state)
            unload()
            for _, name in ipairs(state.modules) do
                require(name)
            end
        end,
    },
    {
        name = "startup/new_source",
        run = function()
            require("cmp_git.source").new({})
        end,
    },
    {
        name = "startup/new_source_with_overrides",
        run = function()
            require("cmp_git.source").new({
                filetypes = { "gitcommit", "markdown" },
                github = { hosts = { "github.example.com" }, issues = { limit = 50 } },
                git = { commits = { limit = 200 } },
            })
        end,
    },
    {
        -- The overhead of the measurement loop. Results near this value are at the resolution of the harness.
        name = "harness/noop",
        run = function() end,
    },
}
