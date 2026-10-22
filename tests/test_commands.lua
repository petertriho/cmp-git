local helpers = require("tests.helpers")
local cache = require("cmp_git.cache")
local commands = require("cmp_git.commands")
local config = require("cmp_git.config")
local Core = require("cmp_git.core")
local Git = require("cmp_git.sources.git")

local eq = helpers.eq
local ok = helpers.ok

local T = helpers.new_set()

local ROOT = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

local remote = { host = "github.com", owner = "owner", repo = "repo" }
local other_remote = { host = "gitlab.com", owner = "group", repo = "project" }
local issues_config = config.normalize({}).github.issues

---An entry of the remote with one item.
---@param git_info cmp_git.GitInfo
---@return cmp_git.CacheEntry
local function cached_entry(git_info)
    local entry = cache.entry(git_info, "github-issues", issues_config)
    entry:set({ { number = 1 } })
    return entry
end

---@param git_info cmp_git.GitInfo
---@return boolean
local function is_cached(git_info)
    cache.forget()
    return cache.entry(git_info, "github-issues", issues_config):get() ~= nil
end

---A git source with cached commits for each buffer.
---@param buffers integer[]
---@return cmp_git.Source.Git
local function git_source(buffers)
    local source = Git.new(config.normalize({}).git)
    for _, bufnr in ipairs(buffers) do
        source.cache_commits[bufnr] = {}
        source.cache_trailer_keys[bufnr] = {}
    end
    return source
end

---The messages of the notifications so far.
---@return string[]
local function messages()
    helpers.flush()
    return vim.tbl_map(function(notification)
        return notification.message
    end, helpers.notifications)
end

---A buffer of a file in a repository with the remote. The cores of earlier cases are collected first, so that only the
---cores of the case discover the remote.
---@param url string
---@return integer bufnr
local function repository_buffer(url)
    collectgarbage("collect")
    local repo = helpers.git_repo({ remotes = { { "origin", url } } })
    vim.cmd.edit(vim.fn.fnameescape(repo.dir .. "/COMMIT_EDITMSG"))
    return vim.api.nvim_get_current_buf()
end

T["the_bang_clears_all_remotes_and_buffers"] = function()
    cached_entry(remote)
    cached_entry(other_remote)
    local source = git_source({ 1, 2 })

    commands.clear_cache(true)

    eq(vim.fn.isdirectory(cache.root()), 0, "the cache directory is removed")
    ok(not is_cached(remote) and not is_cached(other_remote), "no remote has items")
    eq(source.cache_commits, {}, "no buffer has commits")
    eq(source.cache_trailer_keys, {}, "no buffer has trailer keys")
    eq(messages(), { "Cleared the cache of all remotes." }, "the user gets a message")
end

T["without_a_bang_the_command_clears_the_remote_and_the_buffer"] = function()
    local bufnr = repository_buffer("git@github.com:owner/repo.git")
    local other_bufnr = helpers.buffer({})
    cached_entry(remote)
    cached_entry(other_remote)
    local source = git_source({ bufnr, other_bufnr })

    commands.clear_cache(false)
    helpers.wait_for(function()
        return #messages() > 0
    end, "the command ends")

    ok(not is_cached(remote), "the remote of the buffer has no items")
    ok(is_cached(other_remote), "the other remote keeps its items")
    eq(source.cache_commits[bufnr], nil, "the buffer has no commits")
    eq(source.cache_trailer_keys[bufnr], nil, "the buffer has no trailer keys")
    eq(source.cache_commits[other_bufnr], {}, "the other buffer keeps its commits")
    eq(messages(), { "Cleared the cache of github.com/owner/repo." }, "the message names the remote")
end

T["the_remote_comes_from_the_config_of_each_core"] = function()
    local bufnr = repository_buffer("git@work:owner/repo.git")
    local core = Core.new({ ssh_aliases = { work = "github.com" } })
    cached_entry(remote)

    commands.clear_cache(false, bufnr)
    helpers.wait_for(function()
        return #messages() > 0
    end, "the command ends")

    ok(not is_cached(remote), "the SSH alias of the core gives the remote")
    eq(messages(), { "Cleared the cache of github.com/owner/repo." }, "the message names the remote")
    ok(core ~= nil, "the core is alive during the command")
end

T["a_buffer_without_a_remote_clears_its_commits_and_trailers"] = function()
    collectgarbage("collect")
    -- Discovery uses the cwd for a buffer without a file. The case hooks restore it.
    vim.fn.chdir(helpers.tempdir())
    local bufnr = helpers.buffer({})
    cached_entry(remote)
    local source = git_source({ bufnr })

    commands.clear_cache(false, bufnr)
    helpers.wait_for(function()
        return #messages() > 0
    end, "the command ends")

    eq(source.cache_commits[bufnr], nil, "the buffer has no commits")
    ok(is_cached(remote), "the remote keeps its items")
    eq(
        messages(),
        { "Cleared the commits and trailers of the buffer. The buffer has no remote." },
        "the message says that the buffer has no remote"
    )
end

T["the_plugin_file_defines_the_command"] = function()
    helpers.stub(vim.g, "loaded_cmp_git", nil)
    local calls = {}
    helpers.stub(commands, "clear_cache", function(all)
        table.insert(calls, all)
    end)

    dofile(ROOT .. "/plugin/cmp_git.lua")
    vim.cmd("CmpGitClearCache")
    vim.cmd("CmpGitClearCache!")
    vim.api.nvim_del_user_command("CmpGitClearCache")

    eq(calls, { false, true }, "the bang clears all remotes")
    eq(vim.g.loaded_cmp_git, true, "the guard is set")
end

return T
