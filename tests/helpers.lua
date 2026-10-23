local MiniTest = require("mini.test")

local M = {}

local expect = MiniTest.expect

M.skip = MiniTest.skip

---@param actual any
---@param expected any
---@param reason? string Shown when the expectation fails.
function M.eq(actual, expected, reason)
    expect.equality(actual, expected, { fail_reason = reason })
end

---@param actual any
---@param unexpected any
---@param reason? string Shown when the expectation fails.
function M.neq(actual, unexpected, reason)
    expect.no_equality(actual, unexpected, { fail_reason = reason })
end

---@generic T
---@param value T?
---@param reason? string Shown when the expectation fails.
---@return T value The value, typed as not nil.
function M.not_nil(value, reason)
    expect.no_equality(value, nil, { fail_reason = reason })
    return value
end

---@param value any
---@param reason? string Shown when the expectation fails.
function M.ok(value, reason)
    expect.equality(value and true or false, true, { fail_reason = reason })
end

---@param predicate fun(): boolean
---@param reason string
function M.wait_for(predicate, reason)
    if not vim.wait(5000, predicate, 10) then
        error("Timed out: " .. reason, 2)
    end
end

---Run the pending `vim.schedule` callbacks.
function M.flush()
    -- A scheduled callback can schedule another one
    for _ = 1, 3 do
        vim.wait(0)
    end
end

---The `vim.notify` calls of the current case. `log` calls `vim.notify` from a scheduled callback, so call `M.flush`
---before reading them.
---@type { message: string, level: integer?, opts: table? }[]
M.notifications = {}

---A callback that records each list it receives.
---@return fun(list: cmp_git.CompletionList) callback
---@return cmp_git.CompletionList[] lists
function M.recorder()
    local lists = {}
    return function(list)
        table.insert(lists, list)
    end, lists
end

---A job that runs `on_start` in place of a process.
---@param on_start? fun()
---@return cmp_git.SystemJob
function M.fake_job(on_start)
    return {
        command = "fake",
        start = function()
            if on_start then
                on_start()
            end
        end,
    }
end

---A scratch buffer for the trailer and routing tests.
---@param lines string[]
---@param filetype? string Defaults to `gitcommit`.
---@return integer bufnr
function M.buffer(lines, filetype)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].filetype = filetype or "gitcommit"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    return bufnr
end

---Variables that the code under test or git reads. The case hooks restore them.
local ENV_NAMES = {
    "GITHUB_API_TOKEN",
    "GITLAB_TOKEN",
    "GIT_AUTHOR_NAME",
    "GIT_AUTHOR_EMAIL",
    "GIT_CEILING_DIRECTORIES",
    "GIT_CONFIG_GLOBAL",
    "GIT_CONFIG_NOSYSTEM",
    "GIT_DIR",
    "GIT_INDEX_FILE",
    "GIT_WORK_TREE",
    "HOME",
    "XDG_CACHE_HOME",
    "XDG_CONFIG_HOME",
}

local temp_root = vim.fn.tempname()
local case = {}

---Replace `target[key]` until the end of the current case.
---@param target table
---@param key any
---@param value any
function M.stub(target, key, value)
    local original = target[key]
    table.insert(case.restores, function()
        target[key] = original
    end)
    target[key] = value
end

---Run `fn` at the end of the current case, in reverse order with the restores of `M.stub`.
---@param fn fun()
function M.defer(fn)
    table.insert(case.restores, fn)
end

---An empty directory that the case hooks delete.
---@return string path The resolved path, so that it compares equal to `getcwd()`.
function M.tempdir()
    case.temp_count = case.temp_count + 1
    local dir = string.format("%s/%d", temp_root, case.temp_count)
    vim.fn.mkdir(dir, "p")
    return assert(vim.uv.fs_realpath(dir))
end

---Make PATH a directory with only these commands until the end of the case. The scripts can use only the builtins of
---`sh`.
---@param scripts table<string, string> The shell script body of each command, by name.
---@return string bin The directory.
function M.fake_commands(scripts)
    local bin = M.tempdir()
    for name, body in pairs(scripts) do
        local path = bin .. "/" .. name
        local file = assert(io.open(path, "w"))
        file:write("#!/bin/sh\n" .. body .. "\n")
        file:close()
        vim.uv.fs_chmod(path, tonumber("755", 8))
    end
    M.stub(vim.env, "PATH", bin)
    return bin
end

---@class tests.GitRepo
---@field dir string
---@field git fun(...: string): string Runs git in the repository and returns stdout.
---@field commit fun(message: string)

---A git repository in a temporary directory. The case hooks isolate git from the user and system config.
---@param opts? { remotes?: string[][] } Remotes as `{ name, url }` pairs, in order.
---@return tests.GitRepo
function M.git_repo(opts)
    opts = opts or {}
    local dir = M.tempdir()
    local repo = { dir = dir }

    function repo.git(...)
        local args = { "git", "-C", dir, "-c", "user.name=Ada Lovelace", "-c", "user.email=ada@example.com", ... }
        local result = vim.system(args, { text = true }):wait()
        if result.code ~= 0 then
            error(string.format("%s failed: %s", table.concat(args, " "), result.stderr), 2)
        end
        return result.stdout
    end

    function repo.commit(message)
        repo.git("commit", "-q", "--allow-empty", "--no-verify", "-m", message)
    end

    repo.git("-c", "init.defaultBranch=main", "init", "-q")
    for _, remote in ipairs(opts.remotes or {}) do
        repo.git("remote", "add", remote[1], remote[2])
    end

    return repo
end

local function setup_case()
    case = {
        restores = {},
        temp_count = 0,
        cwd = vim.fn.getcwd(),
        bufnr = vim.api.nvim_get_current_buf(),
        buffers = {},
        env = {},
    }

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        case.buffers[bufnr] = true
    end

    for _, name in ipairs(ENV_NAMES) do
        case.env[name] = vim.env[name]
        vim.env[name] = nil
    end
    vim.fn.mkdir(temp_root .. "/home", "p")
    vim.env.HOME = temp_root .. "/home"
    -- The disk cache of the GitHub and GitLab items goes to `stdpath("cache")`
    vim.env.XDG_CACHE_HOME = temp_root .. "/cache"
    vim.env.GIT_CONFIG_GLOBAL = "/dev/null"
    vim.env.GIT_CONFIG_NOSYSTEM = "1"
    -- A temporary directory outside a repository must not resolve to a repository above it
    vim.env.GIT_CEILING_DIRECTORIES = vim.uv.fs_realpath(temp_root)

    for key in pairs(M.notifications) do
        M.notifications[key] = nil
    end
    M.stub(vim, "notify", function(message, level, opts)
        table.insert(M.notifications, { message = message, level = level, opts = opts })
    end)
end

local function teardown_case()
    M.flush()

    if vim.api.nvim_buf_is_valid(case.bufnr) then
        vim.api.nvim_set_current_buf(case.bufnr)
    end
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if not case.buffers[bufnr] then
            vim.api.nvim_buf_delete(bufnr, { force = true })
        end
    end

    vim.fn.chdir(case.cwd)

    for i = #case.restores, 1, -1 do
        case.restores[i]()
    end

    -- The entries are shared by all sources. Dropped entries keep nothing, so a fetch of this case that ends later
    -- does not write into the next case.
    local cache = package.loaded["cmp_git.cache"]
    if cache then
        cache.forget()
    end

    for _, name in ipairs(ENV_NAMES) do
        -- A nil value unsets the variable
        vim.env[name] = case.env[name]
    end

    vim.fn.delete(temp_root, "rf")
end

---The test set for a file. Its hooks isolate each case.
---@param hooks? { pre_once?: fun(), post_once?: fun() } Run once before the first case and after the last case.
---@return table
function M.new_set(hooks)
    hooks = hooks or {}
    return MiniTest.new_set({
        hooks = {
            pre_once = hooks.pre_once,
            pre_case = setup_case,
            post_case = teardown_case,
            post_once = hooks.post_once,
        },
    })
end

return M
