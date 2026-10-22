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

return T
