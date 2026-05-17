package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

local utils = require("cmp_git.utils")
local log = require("cmp_git.log")

local failures = {}

local function assert_eq(actual, expected, message)
    if actual ~= expected then
        table.insert(
            failures,
            string.format("%s: expected %s, got %s", message, vim.inspect(expected), vim.inspect(actual))
        )
    end
end

local function assert_true(value, message)
    if not value then
        table.insert(failures, message)
    end
end

local function wait_for(predicate, message)
    local ok = vim.wait(2000, predicate, 10)
    assert_true(ok, message)
end

local function test_handle_response()
    local items = utils.handle_response('[{"name":"one"}]', function(item)
        return { label = item.name }
    end)
    assert_eq(#items, 1, "valid JSON item count")
    assert_eq(items[1].label, "one", "valid JSON item mapping")

    local mapped = utils.handle_response('{"items":[{"name":"two"}]}', function(item)
        return { label = item.name }
    end, function(parsed)
        return parsed.items
    end)
    assert_eq(#mapped, 1, "mapped JSON item count")
    assert_eq(mapped[1].label, "two", "mapped JSON item mapping")

    local empty = utils.handle_response("[]", function(item)
        return item
    end)
    assert_eq(#empty, 0, "empty JSON item count")

    local invalid = utils.handle_response("not json", function(item)
        return item
    end)
    assert_eq(#invalid, 0, "invalid JSON item count")
end

local function test_missing_executable()
    local job = utils.build_simple_job("cmp-git-missing-executable", {}, nil, function() end)
    assert_eq(job, nil, "missing executable returns nil")
end

local function test_fallback()
    local result
    local first = utils.build_simple_job("sh", { "-c", "exit 7" }, nil, function()
        result = "first-callback"
    end)
    local second = utils.build_simple_job("sh", { "-c", "printf fallback" }, nil, function(stdout, success)
        result = { stdout = stdout, success = success }
    end)

    local job = utils.chain_fallback(first, second)
    assert_true(job ~= nil, "fallback job is created")
    job:start()

    wait_for(function()
        return type(result) == "table"
    end, "fallback job completes")

    assert_eq(result.stdout, "fallback", "fallback stdout")
    assert_eq(result.success, true, "fallback success")
end

local function test_build_job()
    local list
    local job = utils.build_job("sh", { "-c", 'printf \'[{"name":"item"}]\'' }, nil, function(result)
        list = result
    end, function(item)
        return { label = item.name }
    end)

    assert_true(job ~= nil, "json job is created")
    job:start()

    wait_for(function()
        return list ~= nil
    end, "json job completes")

    assert_eq(#list.items, 1, "json job item count")
    assert_eq(list.items[1].label, "item", "json job item label")
    assert_eq(list.isIncomplete, false, "json job completion flag")
end

local function test_logger()
    log.debug("debug message")
    log.fmt_debug("debug %s", "message")
    log.warn("warn message")
    vim.wait(20)
    assert_true(true, "logger calls do not throw")
end

test_handle_response()
test_missing_executable()
test_fallback()
test_build_job()
test_logger()

if #failures > 0 then
    for _, failure in ipairs(failures) do
        vim.api.nvim_err_writeln(failure)
    end
    os.exit(1)
end

print("cmp-git tests passed")
