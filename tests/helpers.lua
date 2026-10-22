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

---An empty directory that the case hooks delete.
---@return string path The resolved path, so that it compares equal to `getcwd()`.
function M.tempdir()
    case.temp_count = case.temp_count + 1
    local dir = string.format("%s/%d", temp_root, case.temp_count)
    vim.fn.mkdir(dir, "p")
    return assert(vim.uv.fs_realpath(dir))
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
        notify = vim.notify,
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
    vim.env.GIT_CONFIG_GLOBAL = "/dev/null"
    vim.env.GIT_CONFIG_NOSYSTEM = "1"
    -- A temporary directory outside a repository must not resolve to a repository above it
    vim.env.GIT_CEILING_DIRECTORIES = vim.uv.fs_realpath(temp_root)

    for key in pairs(M.notifications) do
        M.notifications[key] = nil
    end
    vim.notify = function(message, level, opts)
        table.insert(M.notifications, { message = message, level = level, opts = opts })
    end
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

    for _, name in ipairs(ENV_NAMES) do
        -- A nil value unsets the variable
        vim.env[name] = case.env[name]
    end

    vim.notify = case.notify
    vim.fn.delete(temp_root, "rf")
end

---The test set for a file. Its hooks isolate each case.
---@return table
function M.new_set()
    return MiniTest.new_set({
        hooks = {
            pre_case = setup_case,
            post_case = teardown_case,
        },
    })
end

return M
