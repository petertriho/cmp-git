local helpers = require("tests.helpers")
local cache = require("cmp_git.cache")

local eq = helpers.eq
local neq = helpers.neq
local ok = helpers.ok

local T = helpers.new_set()

local remote = { host = "github.com", owner = "owner", repo = "repo" }
local config = { state = "open", limit = 100, fields = { "title", "number" } }

---@param path string
---@return integer mode The permission bits.
local function mode(path)
    return require("bit").band(helpers.not_nil(vim.uv.fs_stat(path), path .. " exists").mode, tonumber("777", 8))
end

---@param path string
---@param content string
local function write_file(path, content)
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    local file = assert(io.open(path, "wb"))
    file:write(content)
    file:close()
end

T["the_same_arguments_give_the_same_entry"] = function()
    local entry = cache.entry(remote, "github-issues", config)

    ok(cache.entry(vim.deepcopy(remote), "github-issues", vim.deepcopy(config)) == entry, "equal arguments")
    neq(cache.entry(remote, "github-pull_requests", config).path, entry.path, "another kind")
    neq(cache.entry(remote, "github-issues", { state = "all", limit = 100 }).path, entry.path, "another state")
    neq(cache.entry(remote, "github-issues", { state = "open", limit = 5 }).path, entry.path, "another limit")
    eq(
        cache.entry(remote, "github-issues", vim.tbl_extend("force", config, { format = {} })).path,
        entry.path,
        "a field that does not change the query"
    )
end

T["each_remote_has_its_own_directory"] = function()
    local function dir(host, owner, repo)
        return cache.entry({ host = host, owner = owner, repo = repo }, "gitlab-issues", config).dir
    end

    eq(dir("github.com", "owner", "repo"), cache.root() .. "/github.com/owner/repo", "a readable path")
    neq(dir("example.com/gitlab", "a", "r"), dir("example.com", "gitlab/a", "r"), "a path prefix is not a group")
    eq(dir("example.com:8443", "a/b", "r"), cache.root() .. "/example.com%3A8443/a%2Fb/r", "ports and subgroups")
    eq(vim.fn.stdpath("cache") .. "/cmp-git", cache.root(), "the cache directory of Neovim")
end

T["a_new_session_reads_the_items_from_the_file"] = function()
    local items = { { number = 1, title = "an issue", body = vim.NIL, labels = { "bug" } } }
    cache.entry(remote, "github-issues", config):set(items)

    cache.forget()
    local entry = cache.entry(remote, "github-issues", config)
    eq(entry:get(), items, "the items of the file, with null as vim.NIL")
    ok(math.abs(helpers.not_nil(entry.fetched_at) - os.time()) <= 1, "the time of the fetch")
end

T["only_the_user_can_read_the_files"] = function()
    local entry = cache.entry({ host = "example.com/gitlab", owner = "a/b", repo = "r" }, "gitlab-issues", config)
    entry:set({})

    eq(mode(entry.path), tonumber("600", 8), "the file")
    for _, dir in ipairs({ entry.dir, vim.fs.dirname(entry.dir), cache.root() }) do
        eq(mode(dir), tonumber("700", 8), dir)
    end
    eq(vim.fn.glob(entry.dir .. "/*.tmp.*"), "", "no temporary file stays")
end

T["a_file_that_is_not_an_entry_is_a_miss"] = function()
    local files = {
        ["invalid JSON"] = "{",
        ["another version"] = vim.json.encode({ version = 2, fetched_at = 1, items = {} }),
        ["no time"] = vim.json.encode({ version = 1, items = {} }),
        ["no list"] = vim.json.encode({ version = 1, fetched_at = 1, items = { a = 1 } }),
        ["not an object"] = "[]",
    }
    for name, content in pairs(files) do
        cache.forget()
        local entry = cache.entry(remote, "github-issues", config)
        write_file(entry.path, content)

        eq(entry:get(), nil, name)

        entry:set({ { number = 2 } })
        cache.forget()
        eq(
            cache.entry(remote, "github-issues", config):get(),
            { { number = 2 } },
            name .. ": the next fetch replaces it"
        )
    end
end

T["a_miss_reads_the_file_once"] = function()
    local entry = cache.entry(remote, "github-issues", config)
    eq(entry:get(), nil, "no file")

    write_file(entry.path, vim.json.encode({ version = 1, fetched_at = os.time(), items = { {} } }))
    eq(entry:get(), nil, "the entry does not read the file again")
end

T["stale_items_refresh_once_in_the_background"] = function()
    local entry = cache.entry(remote, "github-issues", config)
    local starts = {}
    local function start(done)
        table.insert(starts, done)
    end

    entry:refresh(0, start)
    eq(#starts, 0, "an entry without items does not refresh")

    entry:set({ { number = 1 } })
    entry:refresh(300, start)
    eq(#starts, 0, "fresh items do not refresh")

    entry.fetched_at = os.time() - 300
    ok(entry:is_stale(300), "items of the age of the TTL are stale")
    entry:refresh(300, start)
    entry:refresh(300, start)
    eq(#starts, 1, "one refresh runs at a time")
    eq(entry:get(), { { number = 1 } }, "the stale items stay during the refresh")

    starts[1]({ { number = 2 } })
    eq(entry:get(), { { number = 2 } }, "the refresh stores its items")
    ok(not entry:is_stale(300), "the new items are fresh")
    cache.forget()
    eq(cache.entry(remote, "github-issues", config):get(), { { number = 2 } }, "and writes them")

    entry:refresh(math.huge, start)
    eq(#starts, 1, "math.huge never refreshes")
end

T["a_failed_refresh_keeps_the_items_and_waits_a_ttl"] = function()
    local entry = cache.entry(remote, "github-issues", config)
    entry:set({ { number = 1 } })
    entry.fetched_at = os.time() - 1000
    local starts = 0
    local function fail(done)
        starts = starts + 1
        done(nil)
    end

    entry:refresh(300, fail)
    eq(entry:get(), { { number = 1 } }, "the items stay")
    entry:refresh(300, fail)
    eq(starts, 1, "the next refresh waits")

    entry.failed_at = os.time() - 300
    entry:refresh(300, fail)
    eq(starts, 2, "a refresh runs again after the TTL")
end

T["a_clear_removes_one_remote"] = function()
    local other = { host = "gitlab.com", owner = "group", repo = "project" }
    local entry = cache.entry(remote, "github-issues", config)
    local other_entry = cache.entry(other, "gitlab-issues", config)
    entry:set({ { number = 1 } })
    other_entry:set({ { iid = 1 } })

    cache.clear_remote(vim.deepcopy(remote))

    eq(vim.fn.isdirectory(entry.dir), 0, "the directory of the remote is removed")
    eq(vim.fn.filereadable(other_entry.path), 1, "the other remote keeps its file")
    ok(cache.entry(remote, "github-issues", config) ~= entry, "a request after the clear gets a new entry")
    eq(cache.entry(remote, "github-issues", config):get(), nil, "and no items")
    ok(cache.entry(other, "gitlab-issues", config) == other_entry, "the other remote keeps its entry")

    -- A fetch that started before the clear
    entry:set({ { number = 2 } })
    entry:refresh(0, function(done)
        done({ { number = 3 } })
    end)
    eq(vim.fn.isdirectory(entry.dir), 0, "a fetch that ends after the clear writes no file")
end

T["a_clear_of_all_removes_the_cache_directory"] = function()
    local entry = cache.entry(remote, "github-issues", config)
    entry:set({ { number = 1 } })

    cache.clear_all()

    eq(vim.fn.isdirectory(cache.root()), 0, "the directory is removed")
    eq(cache.entry(remote, "github-issues", config):get(), nil, "no items")
    entry:set({ { number = 2 } })
    eq(vim.fn.isdirectory(cache.root()), 0, "a fetch that ends after the clear writes no file")
end

T["a_failed_write_keeps_the_items_in_memory"] = function()
    -- A file where the cache directory must be
    write_file(cache.root(), "")
    local entry = cache.entry(remote, "github-issues", config)

    entry:set({ { number = 1 } })

    eq(entry:get(), { { number = 1 } }, "the items stay in memory")
end

return T
