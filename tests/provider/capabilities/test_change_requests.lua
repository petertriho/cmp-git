local helpers = require("tests.helpers")
local cache = require("cmp_git.cache")
local config = require("cmp_git.config")
local format = require("cmp_git.format")
local change_request_capability = require("cmp_git.provider.capabilities.change_requests")

local eq = helpers.eq
local neq = helpers.neq

local T = helpers.new_set()

local git_info = { host = "github.com", owner = "owner", repo = "repo" }

---@return cmp_git.Config.GitHub.PullRequest
local function pr_config()
    return config.normalize({}).github.pull_requests
end

local pr = { number = 2, title = "a pull request", body = "", updatedAt = "2024-01-01T00:00:00Z", state = "open" }

local adapter = {
    change_requests_request = function(_git_info, trigger_char, capability_config)
        return {
            commands = { { exec = "fake", args = {} } },
            handle_item = function(item)
                return format.item(capability_config, trigger_char, item)
            end,
        }
    end,
}

local runner = {
    build_fallback_list = function(_commands, callback, handle_item)
        return helpers.fake_job(function()
            callback({ items = { handle_item(vim.deepcopy(pr)) }, isIncomplete = false }, true)
        end)
    end,
}

T["change_request_capability_returns_job"] = function()
    local capability_config = pr_config()
    local callback, lists = helpers.recorder()
    local args = {
        adapter = adapter,
        cache = cache.entry(git_info, "github-pull_requests", capability_config),
        callback = callback,
        config = capability_config,
        git_info = git_info,
        trigger_char = "#",
        runner = runner,
    }

    local job = change_request_capability.complete(args)
    local cached_job = change_request_capability.complete(args)

    neq(job, nil, "change request capability returns started job")
    eq(cached_job, nil, "a cache hit returns no job")
    eq(lists[2].items[1].label, "#2: a pull request", "a hit formats the cached pull request")
end

T["failure_gives_an_empty_list_and_is_not_cached"] = function()
    local runs = 0
    local capability_config = pr_config()
    local callback, lists = helpers.recorder()
    local args = {
        adapter = {
            change_requests_request = function()
                return { commands = {}, handle_item = function() end }
            end,
        },
        cache = cache.entry(git_info, "github-pull_requests", capability_config),
        callback = callback,
        config = capability_config,
        git_info = git_info,
        trigger_char = "#",
        runner = {
            build_fallback_list = function(_commands, list_callback)
                if runs == 2 then
                    return nil
                end
                return helpers.fake_job(function()
                    runs = runs + 1
                    list_callback({ items = {}, isIncomplete = false }, false)
                end)
            end,
        },
    }

    change_request_capability.complete(args)
    change_request_capability.complete(args)
    -- The third request has no runnable command
    change_request_capability.complete(args)

    local empty = { items = {}, isIncomplete = false }
    eq(lists, { empty, empty, empty }, "each request gets one empty list")
    eq(args.cache:get(), nil, "a failure is not cached")
    eq(runs, 2, "the next request tries again")
end

T["a_refresh_gives_the_raw_items"] = function()
    local results = {}

    change_request_capability.refresh({
        adapter = adapter,
        config = pr_config(),
        git_info = git_info,
        trigger_char = "#",
        runner = runner,
    }, function(items)
        table.insert(results, items)
    end)

    eq(results, { { pr } }, "the raw pull requests")
end

return T
