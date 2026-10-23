-- The cache of the GitHub, GitLab, Gitea, and Forgejo items. An entry holds the raw items of one list of one remote,
-- and a file under `stdpath("cache")/cmp-git` keeps them for the next sessions. The items are raw and not completion
-- items, because the formats are user functions, and the sort text depends on the time of the request.
local log = require("cmp_git.log")

local M = {}

-- A file with another version is a miss
local VERSION = 1

-- The cache can hold the issues of private repositories, so only the user can read it
local PRIVATE_DIR = tonumber("700", 8)
local PRIVATE_FILE = tonumber("600", 8)

-- The config fields that change the query of a list. A list with other values has another entry.
local QUERY_FIELDS = { "state", "filter", "limit", "fields" }

---The raw items of one list of one remote, in memory and in a file.
---@class cmp_git.CacheEntry
---@field path string The file of the entry.
---@field dir string The directory of the remote.
---@field items? table[] nil until a fetch or the file gives the items.
---@field fetched_at? integer When the items were fetched, in seconds since the epoch.
---@field failed_at? integer When the last refresh failed, in seconds since the epoch.
---@field loaded boolean The file was read.
---@field refreshing boolean A background refresh runs.
---@field dropped boolean A clear removed the entry, so it keeps no more items.
---@field fetch? cmp_git.Provider.MentionFetch The fetch in progress of the mentions. It is only in memory.
local Entry = {}
Entry.__index = Entry

---@type table<string, cmp_git.CacheEntry> By path.
local entries = {}

---The query hash of each capability config
---@type table<table, string>
local query_hashes = setmetatable({}, { __mode = "k" })

---Encode a name as one path segment. A `/` in a GitLab group or in a host with a path prefix becomes `%2F`, and a `:`
---before a port becomes `%3A`.
---@param name string
---@return string
local function encode(name)
    return (
        string.gsub(name, "[^%w._-]", function(char)
            return string.format("%%%02X", string.byte(char))
        end)
    )
end

---The directory of all cache files.
---@return string
function M.root()
    return vim.fs.joinpath(vim.fn.stdpath("cache") --[[@as string]], "cmp-git")
end

---@param git_info cmp_git.GitInfo
---@return string
local function remote_dir(git_info)
    return vim.fs.joinpath(M.root(), encode(git_info.host), encode(git_info.owner), encode(git_info.repo))
end

---@param config table
---@return string
local function query_hash(config)
    local hash = query_hashes[config]
    if hash == nil then
        local query = {}
        for _, field in ipairs(QUERY_FIELDS) do
            query[field] = config[field]
        end
        -- `vim.inspect` sorts the keys, so equal queries give equal text
        hash = string.sub(vim.fn.sha256(vim.inspect(query)), 1, 16)
        query_hashes[config] = hash
    end
    return hash
end

---@param path string
---@return { fetched_at: integer, items: table[] }?
local function read(path)
    local file = io.open(path, "rb")
    if file == nil then
        return nil
    end
    local content = file:read("*a")
    file:close()

    local ok, data = pcall(vim.json.decode, content or "")
    if
        not ok
        or type(data) ~= "table"
        or data.version ~= VERSION
        or type(data.fetched_at) ~= "number"
        or type(data.items) ~= "table"
        or not vim.islist(data.items)
    then
        log.fmt_debug("Ignoring the cache file %s", path)
        return nil
    end
    return data
end

---Write the file through a temporary file and a rename, so that a reader never gets a part of it. Between two Neovim
---processes, the last writer wins.
---@param path string
---@param dir string
---@param data table
local function write(path, dir, data)
    -- `mkdir` gives the mode to each directory that it makes
    if vim.fn.isdirectory(dir) == 0 then
        pcall(vim.fn.mkdir, dir, "p", PRIVATE_DIR)
    end

    local tmp = string.format("%s.tmp.%d", path, vim.uv.os_getpid())
    local fd, open_err = vim.uv.fs_open(tmp, "w", PRIVATE_FILE)
    if fd == nil then
        log.fmt_debug("Cannot write the cache file %s: %s", tmp, open_err)
        return
    end
    local written, write_err = vim.uv.fs_write(fd, vim.json.encode(data))
    vim.uv.fs_close(fd)

    local renamed, rename_err = nil, nil
    if written ~= nil then
        renamed, rename_err = vim.uv.fs_rename(tmp, path)
    end
    if not renamed then
        log.fmt_debug("Cannot write the cache file %s: %s", path, write_err or rename_err)
        vim.uv.fs_unlink(tmp)
    end
end

---@param path string
local function remove(path)
    local ok, err = pcall(vim.fs.rm, path, { recursive = true, force = true })
    if not ok then
        log.fmt_debug("Cannot remove %s: %s", path, err)
    end
end

---The entry of a list of a remote. The same arguments give the same entry until a clear.
---@param git_info cmp_git.GitInfo The remote. It needs `host`, `owner`, and `repo`.
---@param kind string The list, such as `github-issues`.
---@param config table The capability config. Its query fields are part of the key.
---@return cmp_git.CacheEntry
function M.entry(git_info, kind, config)
    local dir = remote_dir(git_info)
    local path = vim.fs.joinpath(dir, string.format("%s-%s.json", kind, query_hash(config)))
    local entry = entries[path]
    if entry == nil then
        entry = setmetatable({ path = path, dir = dir, loaded = false, refreshing = false, dropped = false }, Entry)
        entries[path] = entry
    end
    return entry
end

---The raw items, or nil on a miss. The first call reads the file.
---@return table[]?
function Entry:get()
    if not self.loaded then
        self.loaded = true
        local data = read(self.path)
        if data ~= nil then
            self.items = data.items
            self.fetched_at = data.fetched_at
        end
    end
    return self.items
end

---Keep the items in memory and in the file. A dropped entry keeps nothing, so that a fetch that started before a clear
---does not bring the items back.
---@param items table[]
function Entry:set(items)
    if self.dropped then
        return
    end

    self.loaded = true
    self.items = items
    self.fetched_at = os.time()
    self.failed_at = nil
    write(self.path, self.dir, { version = VERSION, fetched_at = self.fetched_at, items = items })
end

---True when the items are older than `ttl` seconds, and no refresh failed in the last `ttl` seconds.
---@param ttl number
---@return boolean
function Entry:is_stale(ttl)
    if self.items == nil or self.fetched_at == nil then
        return false
    end

    local now = os.time()
    return now - self.fetched_at >= ttl and (self.failed_at == nil or now - self.failed_at >= ttl)
end

---Start a background refresh when the items are stale and no refresh runs. A failure keeps the items.
---@param ttl number
---@param start fun(done: fun(items: table[]?)) Fetches the items. It calls `done` once with them, or with nil when the
---fetch fails.
function Entry:refresh(ttl, start)
    if self.refreshing or self.dropped or not self:is_stale(ttl) then
        return
    end

    self.refreshing = true
    start(function(items)
        self.refreshing = false
        if items ~= nil then
            self:set(items)
        else
            self.failed_at = os.time()
        end
    end)
end

---Remove the entries and the files of the remote.
---@param git_info cmp_git.GitInfo
function M.clear_remote(git_info)
    local dir = remote_dir(git_info)
    for path, entry in pairs(entries) do
        if entry.dir == dir then
            entry.dropped = true
            entries[path] = nil
        end
    end
    remove(dir)
end

---Remove all entries and the cache directory.
function M.clear_all()
    M.forget()
    remove(M.root())
end

---Remove the entries from memory and keep the files. A fetch that runs keeps nothing, and the next request reads the
---files again, as in a new session.
function M.forget()
    for _, entry in pairs(entries) do
        entry.dropped = true
    end
    entries = {}
end

return M
