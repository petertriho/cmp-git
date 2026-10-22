local helpers = require("tests.helpers")
local mention_capability = require("cmp_git.provider.capabilities.mentions")

local eq = helpers.eq

local T = helpers.new_set()

T["mention_capability_preflight_and_pagination"] = function()
    local request_pages = {}
    local runner = {
        build_fallback = function(commands, callback)
            eq(commands[1].exec, "preflight", "mention preflight command forwarded")
            return helpers.fake_job(function()
                callback('{"status":"404"}', true)
            end)
        end,
        build_fallback_list = function(commands, callback, handle_item)
            local page = commands[1].page
            table.insert(request_pages, page)
            return helpers.fake_job(function()
                -- A full first page, so that the second page is requested
                local count = page == 1 and 100 or 1
                local items = {}
                for i = 1, count do
                    table.insert(items, handle_item({ name = page .. "-" .. i }))
                end
                callback({ items = items, isIncomplete = false }, true)
            end)
        end,
    }
    local adapter = {
        mentions_preflight_request = function()
            return {
                commands = { { exec = "preflight", args = {} } },
                handle_result = function(result)
                    local parsed = vim.json.decode(result)
                    return { member_type = parsed.status == "404" and "collaborators" or "contributors" }
                end,
            }
        end,
        mentions_request = function(_git_info, _trigger_char, _config, opts)
            eq(opts.context.member_type, "collaborators", "mention context comes from preflight")
            return {
                commands = { { exec = "mentions", args = {}, page = opts.page } },
                handle_item = function(item)
                    return { label = item.name }
                end,
            }
        end,
    }
    local callback, callbacks = helpers.recorder()

    mention_capability.complete({
        adapter = adapter,
        cache = {},
        callback = callback,
        config = { limit = 200 },
        git_info = {},
        trigger_char = "@",
        runner = runner,
        bufnr = 43,
    })

    eq(table.concat(request_pages, ","), "1,2", "mention capability paginates")
    eq(#callbacks, 2, "mention capability returns partial and final callbacks")
    eq(callbacks[1].isIncomplete, true, "first mention callback is incomplete")
    eq(callbacks[2].isIncomplete, false, "final mention callback is complete")
    eq(#callbacks[2].items, 101, "the final callback has the users of both pages")
end

---@class tests.MentionJob: cmp_git.SystemJob
---@field page integer
---@field page_size integer
---@field cancelled boolean
---@field respond fun(users: string[]?) Complete the job with the users, or fail it when `users` is nil.

---A runner whose jobs wait until the case completes them, with an adapter that makes users from strings.
---@return table runner
---@return table adapter
---@return tests.MentionJob[] jobs The started jobs, in order.
local function manual_provider()
    local jobs = {}
    local runner = {
        build_fallback_list = function(commands, callback, handle_item)
            local job = { command = "fake", page = commands[1].page, page_size = commands[1].page_size }
            function job.start()
                table.insert(jobs, job)
            end
            function job.cancel()
                job.cancelled = true
            end
            function job.respond(users)
                if not users then
                    callback({ items = {}, isIncomplete = false }, false)
                    return
                end
                callback({ items = vim.tbl_map(handle_item, users), isIncomplete = false }, true)
            end
            return job
        end,
    }
    local adapter = {
        mentions_request = function(_git_info, _trigger_char, _config, opts)
            return {
                commands = { { exec = "fake", args = {}, page = opts.page, page_size = opts.page_size } },
                handle_item = function(user)
                    return { label = user }
                end,
            }
        end,
    }
    return runner, adapter, jobs
end

---@param count integer
---@param first? integer
---@return string[]
local function users(count, first)
    local result = {}
    for i = first or 1, (first or 1) + count - 1 do
        table.insert(result, "user" .. i)
    end
    return result
end

---@param list cmp_git.CompletionList
---@return string[]
local function labels(list)
    return vim.tbl_map(function(item)
        return item.label
    end, list.items)
end

---@param runner table
---@param adapter table
---@param cache table
---@param limit integer
---@return cmp_git.CompletionList[] lists
---@return { cancel: fun() }? controller
local function request(runner, adapter, cache, limit)
    local callback, lists = helpers.recorder()
    local controller = mention_capability.complete({
        adapter = adapter,
        cache = cache,
        callback = callback,
        config = { limit = limit },
        git_info = {},
        trigger_char = "@",
        runner = runner,
        bufnr = 7,
    })
    return lists, controller
end

T["fewer_users_than_the_limit_need_one_page"] = function()
    local runner, adapter, jobs = manual_provider()
    local lists = request(runner, adapter, {}, 100)

    jobs[1].respond(users(30))

    eq(#jobs, 1, "a page that is not full is the last one")
    eq(#lists, 1, "one list")
    eq(lists[1].isIncomplete, false, "the list is final")
    eq(#lists[1].items, 30, "all users")
end

T["the_page_size_is_constant_and_the_result_is_cut_to_the_limit"] = function()
    local runner, adapter, jobs = manual_provider()
    local lists = request(runner, adapter, {}, 150)

    jobs[1].respond(users(100))
    jobs[2].respond(users(100, 101))

    eq({ jobs[1].page, jobs[1].page_size }, { 1, 100 }, "the first page")
    eq({ jobs[2].page, jobs[2].page_size }, { 2, 100 }, "the second page has the same size")
    eq(#lists, 2, "a list for each page")
    eq(lists[1].isIncomplete, true, "the first page is incomplete")
    eq(lists[2].isIncomplete, false, "the second page is final")
    eq(labels(lists[2]), users(150), "users 1 to 150")
end

T["a_cancel_removes_the_entry"] = function()
    local runner, adapter, jobs = manual_provider()
    local cache = {}
    local lists, controller = request(runner, adapter, cache, 100)

    helpers.not_nil(controller):cancel()

    eq(jobs[1].cancelled, true, "the job is cancelled")
    eq(cache[7], nil, "the cancelled fetch is not cached")
    eq(lists, {}, "a cancelled request gets no list")

    local next_lists = request(runner, adapter, cache, 100)
    eq(#jobs, 2, "the next request fetches again")
    jobs[2].respond(users(3))
    eq(next_lists, {
        {
            items = vim.tbl_map(function(user)
                return { label = user }
            end, users(3)),
            isIncomplete = false,
        },
    }, "the next request gets the users")
end

T["a_failure_gives_an_empty_list_and_is_not_cached"] = function()
    local runner, adapter, jobs = manual_provider()
    local cache = {}
    local lists = request(runner, adapter, cache, 100)

    jobs[1].respond(nil)

    eq(lists, { { items = {}, isIncomplete = false } }, "one empty list")
    eq(cache[7], nil, "a failure is not cached")

    request(runner, adapter, cache, 100)
    eq(#jobs, 2, "the next request fetches again")
end

T["a_failed_later_page_keeps_the_earlier_users"] = function()
    local runner, adapter, jobs = manual_provider()
    local cache = {}
    local lists = request(runner, adapter, cache, 200)

    jobs[1].respond(users(100))
    jobs[2].respond(nil)

    eq(#lists, 2, "an incomplete list, then the final list")
    eq(lists[2].isIncomplete, false, "the last list is final")
    eq(#lists[2].items, 100, "the users of the first page")
    eq(cache[7], nil, "a failure is not cached")
end

T["no_runnable_command_gives_an_empty_list"] = function()
    local cache = {}
    local runner = {
        build_fallback = function()
            return nil
        end,
        build_fallback_list = function()
            return nil
        end,
    }
    local adapter = {
        mentions_preflight_request = function()
            return { commands = {} }
        end,
        mentions_request = function()
            return { commands = {}, handle_item = function() end }
        end,
    }

    local lists = request(runner, adapter, cache, 100)

    eq(lists, { { items = {}, isIncomplete = false } }, "one empty list")
    eq(cache[7], nil, "nothing is cached")
end

T["a_failed_preflight_still_fetches"] = function()
    local runner, adapter, jobs = manual_provider()
    local preflight_results = {}
    runner.build_fallback = function(_commands, callback)
        return helpers.fake_job(function()
            callback("", false)
        end)
    end
    adapter.mentions_preflight_request = function()
        return {
            commands = {},
            handle_result = function(result, success)
                table.insert(preflight_results, { result, success })
                return { member_type = "contributors" }
            end,
        }
    end

    local lists = request(runner, adapter, {}, 100)
    jobs[1].respond(users(2))

    eq(preflight_results, { { "", false } }, "handle_result gets the failure")
    eq(#lists, 1, "one list")
    eq(#lists[1].items, 2, "the users")
end

T["requests_during_a_fetch_share_it"] = function()
    local runner, adapter, jobs = manual_provider()
    local cache = {}
    local first, first_controller = request(runner, adapter, cache, 300)
    local second = request(runner, adapter, cache, 300)
    eq(#jobs, 1, "the second request does not fetch")
    eq(second, {}, "no users yet")

    jobs[1].respond(users(100))
    local third = request(runner, adapter, cache, 300)
    eq(#third, 1, "a request during the fetch gets the users so far")
    eq(third[1].isIncomplete, true, "and more come")

    -- blink.cmp cancels the request of a list that it no longer shows
    helpers.not_nil(first_controller):cancel()
    eq(jobs[2].cancelled, nil, "the fetch goes on for the other requests")

    jobs[2].respond(users(5, 101))

    for name, lists in pairs({ second = second, third = third }) do
        local final = lists[#lists]
        eq(final.isIncomplete, false, name .. " gets a final list")
        eq(#final.items, 105, name .. " gets all users")
    end
    eq(#first, 1, "the cancelled request gets no more lists")
    eq(#helpers.not_nil(cache[7]).items, 105, "the users are cached")

    local cached = request(runner, adapter, cache, 300)
    eq(#jobs, 2, "a cache hit does not fetch")
    eq(cached[1].isIncomplete, false, "a cache hit is final")
end

return T
