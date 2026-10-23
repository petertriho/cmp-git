local helpers = require("tests.helpers")
local command = require("cmp_git.command")
local repository = require("cmp_git.repository")

local eq = helpers.eq

local T = helpers.new_set()

T["missing_executable"] = function()
    local job = command.build({ exec = "cmp-git-missing-executable", args = {} }, function() end)
    eq(job, nil, "missing executable returns nil")
end

T["fallback"] = function()
    local result
    local first = command.build({ exec = "sh", args = { "-c", "exit 7" } }, function()
        result = "first-callback"
    end)
    local second = command.build({ exec = "sh", args = { "-c", "printf fallback" } }, function(stdout, success)
        result = { stdout = stdout, success = success }
    end)

    local job = helpers.not_nil(command.fallback(first, second), "fallback job is created")
    job:start()

    helpers.wait_for(function()
        return type(result) == "table"
    end, "fallback job completes")

    eq(result.stdout, "fallback", "fallback stdout")
    eq(result.success, true, "fallback success")
end

---@param code integer
---@return cmp_git.CommandSpec
local function exit_with(code)
    return { exec = "sh", args = { "-c", "exit " .. code } }
end

T["fallback_reports_the_last_failure"] = function()
    for count = 1, 3 do
        local specs = {}
        for i = 1, count do
            table.insert(specs, exit_with(i))
        end
        local calls = {}
        local completed
        local job = helpers.not_nil(command.build_fallback(specs, function(stdout, success)
            table.insert(calls, { stdout = stdout, success = success })
        end))

        job:start(function(success)
            completed = success
        end)
        helpers.wait_for(function()
            return completed ~= nil
        end, "the fallback completes")

        eq(calls, { { stdout = "", success = false } }, count .. " failed commands give one failure callback")
        eq(completed, false, count .. " failed commands fail the job")
    end
end

T["fallback_list_reports_the_last_failure"] = function()
    local calls = {}
    local job = helpers.not_nil(command.build_fallback_list({ exit_with(1), exit_with(2) }, function(list, success)
        table.insert(calls, { list = list, success = success })
    end, function(item)
        return item
    end))
    job:start()
    helpers.wait_for(function()
        return #calls > 0
    end, "the fallback completes")
    helpers.flush()

    eq(calls, { { list = { items = {}, isIncomplete = false }, success = false } }, "one empty list")
end

T["fallback_skips_a_missing_executable"] = function()
    local calls = {}
    local job = helpers.not_nil(
        command.build_fallback(
            { exit_with(1), { exec = "cmp-git-missing-executable", args = {} } },
            function(_, success)
                table.insert(calls, success)
            end
        )
    )
    job:start()
    helpers.wait_for(function()
        return #calls > 0
    end, "the fallback completes")
    helpers.flush()

    eq(calls, { false }, "the first command reports its failure when the second cannot run")
end

T["command_fallback_cancels_active_job"] = function()
    local first_cancelled = false
    local second_started = false
    local first = {
        command = "first",
        start = function() end,
        cancel = function()
            first_cancelled = true
        end,
    }
    local second = {
        command = "second",
        start = function()
            second_started = true
        end,
    }

    local job = helpers.not_nil(command.fallback(first, second))
    job:start()
    job:cancel()

    eq(first_cancelled, true, "fallback cancellation cancels active job")
    eq(second_started, false, "fallback cancellation does not start later job")
end

T["command_build_cancel_suppresses_callback"] = function()
    local called = false
    local job = helpers.not_nil(
        command.build({ exec = "sh", args = { "-c", "sleep 0.2; printf done" } }, function()
            called = true
        end),
        "cancellable command job is created"
    )
    job:start()
    job:cancel()
    vim.wait(350)

    eq(called, false, "cancelled command suppresses callback")
end

T["build_job"] = function()
    local list
    local job = helpers.not_nil(
        command.build_list({ exec = "sh", args = { "-c", 'printf \'[{"name":"item"}]\'' } }, function(result)
            list = result
        end, function(item)
            return { label = item.name }
        end),
        "json job is created"
    )
    job:start()

    helpers.wait_for(function()
        return list ~= nil
    end, "json job completes")

    eq(#list.items, 1, "json job item count")
    eq(list.items[1].label, "item", "json job item label")
    eq(list.isIncomplete, false, "json job completion flag")
end

T["build_list_reports_an_error_object"] = function()
    local calls = {}
    local job = helpers.not_nil(
        command.build_list(
            { exec = "sh", args = { "-c", 'printf \'{"message":"Bad credentials"}\'' } },
            function(list, success)
                table.insert(calls, { list = list, success = success })
            end,
            function(item)
                return item
            end
        )
    )
    job:start()
    helpers.wait_for(function()
        return #calls > 0
    end, "the job completes")

    eq(calls, { { list = { items = {}, isIncomplete = false }, success = false } }, "an error object is a failure")
end

T["fallback_list_runs_the_next_command_after_an_error_object"] = function()
    local calls = {}
    local job = helpers.not_nil(command.build_fallback_list({
        { exec = "sh", args = { "-c", 'printf \'{"message":"Bad credentials"}\'' } },
        { exec = "sh", args = { "-c", "printf '[\"item\"]'" } },
    }, function(list, success)
        table.insert(calls, {
            labels = vim.tbl_map(function(item)
                return item.label
            end, list.items),
            success = success,
        })
    end, function(item)
        return { label = item }
    end))
    job:start()
    helpers.wait_for(function()
        return #calls > 0
    end, "the fallback completes")
    helpers.flush()

    eq(calls, { { labels = { "item" }, success = true } }, "the list of the second command, and no empty list")
end

T["build_list_reports_a_failure"] = function()
    local calls = {}
    local job = helpers.not_nil(command.build_list(exit_with(1), function(list, success)
        table.insert(calls, { list = list, success = success })
    end, function(item)
        return item
    end))
    job:start()
    helpers.wait_for(function()
        return #calls > 0
    end, "the job completes")

    eq(
        calls,
        { { list = { items = {}, isIncomplete = false }, success = false } },
        "a failed command gives an empty list"
    )
end

T["spawn_error_is_a_failed_command"] = function()
    helpers.stub(repository, "get_cwd", function()
        return helpers.tempdir() .. "/missing"
    end)
    local result
    local completed
    local job = helpers.not_nil(command.build({ exec = "sh", args = { "-c", "printf out" } }, function(stdout, success)
        result = { stdout = stdout, success = success }
    end))

    job:start(function(success)
        completed = success
    end)
    helpers.wait_for(function()
        return completed ~= nil
    end, "the job completes")

    eq(result, { stdout = "", success = false }, "the callback gets a failure")
    eq(completed, false, "the job fails")
end

T["stdin"] = function()
    local seen
    local job =
        helpers.not_nil(command.build({ exec = "sh", args = { "-c", "cat" }, stdin = "from stdin\n" }, function(stdout)
            seen = stdout
        end))
    job:start()
    helpers.wait_for(function()
        return seen ~= nil
    end, "the command completes")

    eq(seen, "from stdin\n", "the command reads the stdin of the spec")
end

T["env_adds_to_the_environment"] = function()
    helpers.stub(vim.env, "CMP_GIT_TEST_INHERITED", "inherited")
    local seen
    local job = helpers.not_nil(command.build({
        exec = "sh",
        args = { "-c", 'printf "%s %s" "$CMP_GIT_TEST_INHERITED" "$CMP_GIT_TEST_ADDED"' },
        env = { CMP_GIT_TEST_ADDED = 1 },
    }, function(stdout)
        seen = stdout
    end))
    job:start()
    helpers.wait_for(function()
        return seen ~= nil
    end, "the command completes")

    eq(seen, "inherited 1", "the command gets the variables of Neovim and of the spec")
end

T["build_runs_in_the_repository_of_the_spec_buffer"] = function()
    local dir = helpers.tempdir()
    local seen
    helpers.stub(repository, "get_cwd", function(bufnr)
        seen = bufnr
        return dir
    end)
    local result
    local job = helpers.not_nil(command.build({ exec = "sh", args = { "-c", "pwd -P" }, bufnr = 42 }, function(stdout)
        result = stdout
    end))

    job:start()
    helpers.wait_for(function()
        return result ~= nil
    end, "the job completes")

    eq(seen, 42, "the directory comes from the buffer of the spec")
    eq(vim.trim(result), dir, "the command runs in that directory")
end

return T
