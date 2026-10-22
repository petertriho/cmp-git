local remote_url = require("cmp_git.repository.remote_url")

local M = {}

---@alias cmp_git.GitInfo cmp_git.RepositoryMetadata

---@alias cmp_git.RemoteUrlKind "configured" | "rewritten"

---What discovery found for one buffer. A field is nil until the git process that gives it exits.
---@class cmp_git.RepositoryState
---@field dir string? The buffer directory when discovery started.
---@field nvim_cwd string Neovim's cwd when discovery started.
---@field cwd string? The directory in which discovery found the repository.
---@field is_repo boolean?
---@field checked_at number? When discovery found no repository, in `vim.uv.now()` milliseconds.
---@field config_path string? The config file of the repository.
---@field config_stamp string? The stamp of the config file when discovery found the repository.
---@field remote_urls table<cmp_git.RemoteUrlKind, table<string, string>> The URL of each remote, by remote name.
---@field waiting table<string, fun()[]> The callbacks that wait for a running git process, by step.

-- `git init` in the directory or in any parent makes a directory part of a repository, and one stat cannot see
-- that, so discovery checks a directory outside a repository again after this time
local NOT_A_REPOSITORY_TTL_MS = 5000

---The discovery state of each buffer. The buffer directory and Neovim's cwd are part of the key, see `matches`.
---@type table<integer, cmp_git.RepositoryState>
local states = {}

vim.api.nvim_create_autocmd("BufWipeout", {
    group = vim.api.nvim_create_augroup("cmp_git.repository", { clear = true }),
    desc = "Forget the cmp-git repository of the buffer",
    callback = function(args)
        states[args.buf] = nil
    end,
})

---@param cmd string[]
---@param cwd string
---@param on_complete fun(success: boolean, stdout: string): nil
---@return nil
local function run_async(cmd, cwd, on_complete)
    local ok = pcall(vim.system, cmd, { text = true, cwd = cwd }, function(result)
        vim.schedule(function()
            on_complete(result.code == 0, result.stdout or "")
        end)
    end)
    if not ok then
        -- `vim.system` throws when git is not installed or when `cwd` was removed
        vim.schedule(function()
            on_complete(false, "")
        end)
    end
end

---@param bufnr integer?
---@return integer
local function resolve_bufnr(bufnr)
    if bufnr == nil or bufnr == 0 then
        return vim.api.nvim_get_current_buf()
    end
    return bufnr
end

---@param bufnr integer
---@return string? dir The directory of the buffer file, nil when it has none or the directory does not exist.
local function buffer_dir(bufnr)
    if vim.bo[bufnr].filetype == "octo" then
        return nil
    end

    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == "" then
        return nil
    end

    local dir = vim.fn.fnamemodify(name, ":p:h")
    -- `vim.system` throws for a `cwd` that does not exist, for example for a new file in a new directory
    if vim.fn.isdirectory(dir) ~= 1 then
        return nil
    end
    return dir
end

---@param path string?
---@return string? stamp A value that changes when git writes the file.
local function file_stamp(path)
    local stat = path and vim.uv.fs_stat(path)
    if not stat then
        return nil
    end
    return string.format("%d.%d:%d:%d", stat.mtime.sec, stat.mtime.nsec, stat.ino, stat.size)
end

---@param state cmp_git.RepositoryState
---@param dir string?
---@return boolean
local function matches(state, dir)
    if state.dir ~= dir then
        return false
    end

    -- Neovim's cwd matters unless the repository is in the buffer directory
    return (dir ~= nil and state.cwd == dir) or state.nvim_cwd == vim.fn.getcwd()
end

---The directory in which the commands for the buffer run. It always exists.
---@param bufnr? integer The buffer, by default the current one.
---@return string
function M.get_cwd(bufnr)
    bufnr = resolve_bufnr(bufnr)
    -- The buffer of a request can be wiped while the request waits for git
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return vim.fn.getcwd()
    end
    local dir = buffer_dir(bufnr)
    local state = states[bufnr]
    -- The commands must see the repository that discovery found, which can be in Neovim's cwd
    if state ~= nil and state.cwd ~= nil and matches(state, dir) then
        return state.cwd
    end
    return dir or vim.fn.getcwd()
end

---@param state cmp_git.RepositoryState
---@return boolean
local function is_fresh(state)
    if state.is_repo == false then
        return vim.uv.now() - state.checked_at < NOT_A_REPOSITORY_TTL_MS
    end
    if state.is_repo == true then
        -- Git writes the config file when a remote is added, removed, or changed
        return file_stamp(state.config_path) == state.config_stamp
    end
    return true
end

---@param bufnr integer
---@return cmp_git.RepositoryState
local function get_state(bufnr)
    local dir = buffer_dir(bufnr)
    local state = states[bufnr]
    if state ~= nil and matches(state, dir) and is_fresh(state) then
        return state
    end

    state = { dir = dir, nvim_cwd = vim.fn.getcwd(), remote_urls = {}, waiting = {} }
    states[bufnr] = state
    return state
end

---Run `step` and then call `callback`. A call while the step runs waits for the same run, so that concurrent
---requests start one process.
---@param state cmp_git.RepositoryState
---@param name string
---@param step fun(state: cmp_git.RepositoryState, done: fun()): nil
---@param callback fun(): nil
---@return nil
local function run_step(state, name, step, callback)
    local waiting = state.waiting[name]
    if waiting ~= nil then
        table.insert(waiting, callback)
        return
    end

    waiting = { callback }
    state.waiting[name] = waiting
    step(state, function()
        state.waiting[name] = nil
        for _, waiter in ipairs(waiting) do
            waiter()
        end
    end)
end

---@param path string
---@return boolean
local function is_absolute(path)
    return path:sub(1, 1) == "/" or path:match("^%a:[/\\]") ~= nil
end

---Find the repository of the buffer directory, or else of Neovim's cwd.
---@param state cmp_git.RepositoryState
---@param done fun()
---@return nil
local function find_repository(state, done)
    local candidates = {} ---@type string[]
    if state.dir ~= nil then
        table.insert(candidates, state.dir)
    end
    if state.nvim_cwd ~= state.dir then
        table.insert(candidates, state.nvim_cwd)
    end

    local index = 0
    local function check_next()
        index = index + 1
        local cwd = candidates[index]
        if cwd == nil then
            state.is_repo = false
            state.checked_at = vim.uv.now()
            done()
            return
        end

        local cmd = { "git", "rev-parse", "--is-inside-work-tree", "--is-inside-git-dir", "--git-common-dir" }
        run_async(cmd, cwd, function(success, stdout)
            local lines = vim.split(stdout, "\n", { trimempty = true })
            -- Inside `.git`, only the second line (`--is-inside-git-dir`) is true
            if not success or (lines[1] ~= "true" and lines[2] ~= "true") or lines[3] == nil then
                check_next()
                return
            end

            -- A linked worktree has its config in the common directory. The path is relative to `cwd`.
            local common_dir = is_absolute(lines[3]) and lines[3] or (cwd .. "/" .. lines[3])
            state.cwd = cwd
            state.config_path = common_dir .. "/config"
            state.config_stamp = file_stamp(state.config_path)
            state.is_repo = true
            done()
        end)
    end
    check_next()
end

---@param state cmp_git.RepositoryState
---@param callback fun(): nil
---@return nil
local function with_repository(state, callback)
    if state.is_repo ~= nil then
        callback()
        return
    end
    run_step(state, "repository", find_repository, callback)
end

---@param stdout string The output of `git config -z --get-regexp`.
---@return table<string, string>
local function parse_configured_urls(stdout)
    local urls = {}
    for entry in vim.gsplit(stdout, "\0", { plain = true, trimempty = true }) do
        local key, url = entry:match("^([^\n]*)\n(.*)$")
        local name = key and key:match("^remote%.(.+)%.url$")
        if name ~= nil then
            -- The last URL wins, as with `git config --get`
            urls[name] = url
        end
    end
    return urls
end

---@param stdout string The output of `git remote -v`.
---@return table<string, string>
local function parse_rewritten_urls(stdout)
    local urls = {}
    for line in vim.gsplit(stdout, "\n", { plain = true, trimempty = true }) do
        -- The fetch URL is the one that `git remote get-url` prints
        local name, url = line:match("^(%S+)\t(.*) %(fetch%)$")
        if name ~= nil then
            urls[name] = url
        end
    end
    return urls
end

---@param state cmp_git.RepositoryState
---@param kind cmp_git.RemoteUrlKind
---@param callback fun(urls: table<string, string>): nil
---@return nil
local function with_remote_urls(state, kind, callback)
    local function call()
        callback(state.remote_urls[kind])
    end
    if state.remote_urls[kind] ~= nil then
        call()
        return
    end

    run_step(state, kind, function(_, done)
        -- One process gives the URLs of all remotes. Only `git remote` applies the `url.<base>.insteadOf` rewrites.
        local cmd = { "git", "config", "-z", "--get-regexp", [[^remote\..*\.url$]] }
        local parse = parse_configured_urls
        if kind == "rewritten" then
            cmd = { "git", "remote", "-v" }
            parse = parse_rewritten_urls
        end

        run_async(cmd, state.cwd, function(_, stdout)
            state.remote_urls[kind] = parse(stdout)
            done()
        end)
    end, call)
end

---@param on_result fun(is_git_repo: boolean): nil
---@param bufnr? integer The buffer, by default the current one.
---@return nil
function M.is_git_repo(on_result, bufnr)
    bufnr = resolve_bufnr(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        on_result(false)
        return
    end
    -- An octo buffer gets its repository from its name
    if vim.bo[bufnr].filetype == "octo" then
        on_result(true)
        return
    end

    local state = get_state(bufnr)
    with_repository(state, function()
        on_result(state.is_repo == true)
    end)
end

---@param metadata cmp_git.RepositoryMetadata
---@param ssh_aliases table<string, string>?
---@return cmp_git.RepositoryMetadata
local function apply_ssh_aliases(metadata, ssh_aliases)
    if metadata.host == nil or ssh_aliases == nil then
        return metadata
    end

    -- A plain lookup, because an alias or a host can have Lua pattern characters, such as `+` or `%`
    local host = ssh_aliases[metadata.host]
    if host ~= nil then
        metadata.host = host
    end

    return metadata
end

---Give the metadata the host entry of an instance under a path prefix, such as `example.com/gitlab`. The URL path of
---such an instance starts with the prefix, which is then not part of the owner.
---@param metadata cmp_git.RepositoryMetadata
---@param hosts string[]? The configured hosts.
---@return cmp_git.RepositoryMetadata
local function apply_host_prefixes(metadata, hosts)
    local host, owner = metadata.host, metadata.owner
    if host == nil or owner == nil or hosts == nil then
        return metadata
    end

    -- Plain comparisons, because a host can have Lua pattern characters, such as `.`, `-`, or `[`
    local host_slash = host .. "/"
    local has_plain_host = false
    local prefixed_entry ---@type string?
    local has_other_prefixed_entries = false
    local match_prefix ---@type string?
    for _, entry in ipairs(hosts) do
        if entry == host then
            has_plain_host = true
        elseif #entry > #host_slash and entry:sub(1, #host_slash) == host_slash then
            -- The GitHub and GitLab lists can both have the same entry
            if prefixed_entry == nil then
                prefixed_entry = entry
            elseif entry ~= prefixed_entry then
                has_other_prefixed_entries = true
            end

            local prefix = entry:sub(#host_slash + 1)
            -- The longest prefix wins, and an owner must be left after it
            if
                #owner > #prefix + 1
                and owner:sub(1, #prefix + 1) == prefix .. "/"
                and (match_prefix == nil or #prefix > #match_prefix)
            then
                match_prefix = prefix
            end
        end
    end

    if match_prefix ~= nil then
        metadata.host = host_slash .. match_prefix
        metadata.owner = owner:sub(#match_prefix + 2)
    elseif prefixed_entry ~= nil and not has_other_prefixed_entries and not has_plain_host then
        -- The path of an SSH remote has no prefix, for example `git@example.com:group/repo.git`
        metadata.host = prefixed_entry
    end

    return metadata
end

---@param bufnr integer
---@return cmp_git.RepositoryMetadata?
local function discover_octo(bufnr)
    if vim.bo[bufnr].filetype ~= "octo" then
        return nil
    end

    local host = require("octo.config").values.github_hostname or ""
    if host == "" then
        host = "github.com"
    end

    local owner, repo = string.match(vim.api.nvim_buf_get_name(bufnr), "^octo://([^/]+)/([^/]+)")
    return { host = host, owner = owner, repo = repo }
end

---@class cmp_git.DiscoverOptions
---@field enableRemoteUrlRewrites boolean
---@field ssh_aliases {[string]: string}
---@field hosts? string[] The configured GitHub and GitLab hosts. An entry can have a path prefix.
---@field on_complete fun(metadata: cmp_git.RepositoryMetadata): nil
---@field bufnr? integer The buffer, by default the current one.

---The repository of the first remote in `remotes` that has a supported URL. The result is a new table for each
---call, because callers change it.
---@param remotes string|string[]
---@param opts cmp_git.DiscoverOptions
---@return nil
function M.discover(remotes, opts)
    opts = opts or {}
    if type(remotes) == "string" then
        remotes = { remotes }
    end
    local bufnr = resolve_bufnr(opts.bufnr)

    ---@param metadata cmp_git.RepositoryMetadata
    local function complete(metadata)
        opts.on_complete(apply_host_prefixes(apply_ssh_aliases(metadata, opts.ssh_aliases), opts.hosts))
    end

    if not vim.api.nvim_buf_is_valid(bufnr) then
        complete({})
        return
    end

    local octo_metadata = discover_octo(bufnr)
    if octo_metadata ~= nil then
        complete(octo_metadata)
        return
    end

    local state = get_state(bufnr)
    with_repository(state, function()
        if not state.is_repo then
            complete({})
            return
        end

        with_remote_urls(state, opts.enableRemoteUrlRewrites and "rewritten" or "configured", function(urls)
            for _, remote in ipairs(remotes) do
                local metadata = remote_url.parse(urls[remote])
                if metadata.host ~= nil and metadata.owner ~= nil and metadata.repo ~= nil then
                    complete(metadata)
                    return
                end
            end
            complete({})
        end)
    end)
end

return M
