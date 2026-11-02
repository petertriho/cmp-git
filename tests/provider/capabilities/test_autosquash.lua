local helpers = require("tests.helpers")
local config = require("cmp_git.config")
local autosquash = require("cmp_git.provider.capabilities.autosquash")

local eq = helpers.eq
local ok = helpers.ok

local T = helpers.new_set()

---@param sha string
---@param title string
---@param diff integer
---@return cmp_git.Commit
local function commit(sha, title, diff)
    return {
        sha = sha,
        title = title,
        description = "",
        author_name = "Ada Lovelace",
        author_mail = "ada@example.com",
        commit_timestamp = 1700000000 - diff,
        diff = diff,
    }
end

-- Newest first, as `git log` gives them
local HISTORY = {
    commit("1111111", "fixup! feat: add parser", 1),
    commit("2222222", "feat: add parser", 2),
    commit("3333333", "squash! docs: describe the parser", 3),
    commit("4444444", "amend! feat: add parser", 4),
    commit("5555555", "docs: describe the parser", 5),
    commit("6666666", "feat: add parser", 6),
    commit("7777777", "fixup!no space", 7),
    commit("8888888", "Fixup! capital", 8),
}

---Complete the line with the cached history and the default config.
---@param line string
---@return cmp_git.CompletionList list
---@return integer builds The processes that the request started.
local function complete(line)
    local defaults = config.normalize({}).git
    local builds = 0
    local callback, lists = helpers.recorder()
    autosquash.commits.complete({
        cache = { [12] = HISTORY },
        callback = callback,
        commits_config = defaults.commits,
        config = defaults.autosquash.commits,
        line = line,
        runner = {
            build = function()
                builds = builds + 1
            end,
        },
        bufnr = 12,
    })
    eq(#lists, 1, "one list for " .. vim.inspect(line))
    return lists[1], builds
end

T["autosquash_commits_hide_autosquash_commits_and_repeated_titles"] = function()
    local list, builds = complete("fixup! ")

    eq(builds, 0, "the cached history starts no process")
    eq(list.isIncomplete, false, "the list is final")
    eq(
        vim.tbl_map(function(item)
            return item.label
        end, list.items),
        {
            "feat: add parser",
            "docs: describe the parser",
            "fixup!no space",
            "Fixup! capital",
        },
        "only the titles that git does not read as autosquash commits, once each, newest first"
    )
    eq(list.items[1].data.sha, "2222222", "a repeated title keeps the newest commit")
    ok(list.items[1].sortText < list.items[2].sortText, "the newest commit sorts first")
end

T["autosquash_commits_attached_trigger"] = function()
    local attached = complete("fixup!").items[1]
    eq(attached.insertText, " feat: add parser", "the title touches the `!`, so the insert adds a space")
    eq(attached.filterText, "! feat: add parser", "the filter starts at the `!`")
    eq(complete("fixup!fe").items[1].insertText, " feat: add parser", "typed text that touches the `!`")

    local spaced = complete("fixup! fe").items[1]
    eq(spaced.insertText, "feat: add parser", "after the space, the insert is the title")
    eq(spaced.filterText, "feat: add parser", "after the space, the filter is the title")
end

---@param line string
---@param overrides? table The `git.autosquash.prefixes` overrides.
---@return cmp_git.CompletionList
local function prefixes(line, overrides)
    local prefixes_config =
        config.normalize({ git = { autosquash = { prefixes = overrides } } }).git.autosquash.prefixes
    return autosquash.prefixes.list(prefixes_config, line)
end

T["autosquash_prefixes"] = function()
    eq(prefixes("f"), { items = {}, isIncomplete = true }, "fewer letters than the minimum ask again")

    local list = prefixes("fi")
    eq(list.isIncomplete, false, "the list is final")
    eq(#list.items, 1, "one item for fixup")
    local item = list.items[1]
    eq({ item.label, item.insertText, item.filterText }, { "fixup!", "fixup! ", "fixup" }, "the fixup item")
    eq({ item.data.word, item.data.index, item.data.reopen }, { "fixup", 1, true }, "the item fields and the marker")

    eq(prefixes("am").items[1].data.index, 3, "the index is the position of the word")
    eq(prefixes("f", { min_length = 1 }).items[1].label, "fixup!", "a minimum length of 1")
    eq(prefixes("f", { min_length = 0 }).items[1].label, "fixup!", "a minimum length below 1 acts as 1")
    eq(prefixes("", { min_length = 0 }), { items = {}, isIncomplete = true }, "no letters ask again")
    eq(prefixes("fixup", { min_length = 9 }), { items = {}, isIncomplete = true }, "a full word below the minimum")
    eq(prefixes("sq", { words = { "fixup" } }).items, {}, "only the words")

    local both = prefixes("s", { words = { "squash", "sign", "fixup" }, min_length = 1 })
    eq(
        vim.tbl_map(function(prefix)
            return prefix.label
        end, both.items),
        { "squash!", "sign!" },
        "each word that starts with the letters"
    )
    ok(both.items[1].sortText < both.items[2].sortText, "the items keep the order of the words")
end

return T
