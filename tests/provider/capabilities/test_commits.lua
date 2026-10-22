local helpers = require("tests.helpers")
local commit_capability = require("cmp_git.provider.capabilities.commits")

local eq = helpers.eq

local T = helpers.new_set()

local function commit_test_config()
    return {
        limit = 100,
        sha_length = 7,
        sort_by = function(commit)
            return commit.sha
        end,
        format = {
            label = function(trigger_char, commit)
                return string.format("%s%s: %s", trigger_char, commit.sha, commit.title)
            end,
            filterText = function(trigger_char, commit)
                return string.format("%s %s %s", trigger_char, commit.sha, commit.title)
            end,
            insertText = function(_, commit)
                return commit.sha
            end,
            documentation = function(_, commit)
                return { kind = "markdown", value = commit.description }
            end,
        },
    }
end

local function commit_record(sha, title, description, author_name, author_mail, timestamp)
    return table.concat({ sha, title, description, author_name, author_mail, tostring(timestamp) }, "\0") .. "\0"
end

T["commit_capability_parse_nul_records"] = function()
    local commits = commit_capability.parse(
        commit_record(
            "abcdef1234567890",
            " subject with spaces ",
            "body line one\nbody line two",
            "Ada Lovelace",
            "ada@example.com",
            1234567890
        ),
        commit_test_config()
    )

    eq(#commits, 1, "commit parser item count")
    eq(commits[1].sha, "abcdef1", "commit parser truncates sha")
    eq(commits[1].title, "subject with spaces", "commit parser trims title")
    eq(commits[1].description, "body line one\nbody line two", "commit parser keeps multiline body")
    eq(commits[1].author_name, "Ada Lovelace", "commit parser author name")
    eq(commits[1].author_mail, "ada@example.com", "commit parser author mail")
    eq(commits[1].commit_timestamp, 1234567890, "commit parser numeric timestamp")
    eq(type(commits[1].diff), "number", "commit parser diff shape")
end

T["commit_capability_parse_marker_collision_and_malformed_records"] = function()
    local raw = commit_record(
        "1111111222222222",
        "subject with ###CMP_GIT### marker",
        "body with ###CMP_GIT_END### marker",
        "Grace Hopper",
        "grace@example.com",
        1234567890
    ) .. "dangling\0record\0without\0all\0fields\0"

    local commits = commit_capability.parse(raw, commit_test_config())

    eq(#commits, 1, "commit parser skips malformed trailing record")
    eq(commits[1].title, "subject with ###CMP_GIT### marker", "commit parser allows old part marker text")
    eq(commits[1].description, "body with ###CMP_GIT_END### marker", "commit parser allows old entry marker text")
end

T["commit_capability_maps_items_without_cmp_params"] = function()
    local items = commit_capability.items({
        {
            sha = "abcdef1",
            title = "mapped commit",
            description = "mapped docs",
            author_name = "Linus",
            author_mail = "linus@example.com",
            commit_timestamp = 1234567890,
            diff = 1,
        },
    }, commit_test_config(), ":")

    eq(#items, 1, "commit mapper item count")
    eq(items[1].label, ":abcdef1: mapped commit", "commit mapper label")
    eq(items[1].filterText, ": abcdef1 mapped commit", "commit mapper filter text")
    eq(items[1].insertText, "abcdef1", "commit mapper insert text")
    eq(items[1].documentation.value, "mapped docs", "commit mapper documentation")
end

T["commit_capability_uses_parsed_cache_and_runner"] = function()
    local callback_count = 0
    local runner_count = 0
    local last_list
    local cache = {}
    local raw = commit_record("abcdef1234567890", "cache me", "body", "Author", "author@example.com", 1234567890)
    local runner = {
        build = function(spec, callback)
            runner_count = runner_count + 1
            eq(spec.exec, "git", "commit capability command exec")
            eq(spec.args[1], "log", "commit capability command action")
            eq(spec.args[3], "100", "commit capability command limit")
            eq(
                spec.args[5],
                "--pretty=format:%H%x00%s%x00%b%x00%aN%x00%aE%x00%cd%x00",
                "commit capability command format"
            )
            return helpers.fake_job(function()
                callback(raw, true)
            end)
        end,
    }
    local args = {
        cache = cache,
        callback = function(list)
            callback_count = callback_count + 1
            last_list = list
        end,
        config = commit_test_config(),
        trigger_char = ":",
        runner = runner,
        bufnr = 44,
    }

    commit_capability.complete(args)
    commit_capability.complete(args)

    eq(runner_count, 1, "commit capability runs once")
    eq(callback_count, 2, "commit capability callbacks on miss and hit")
    eq(cache[44][1].sha, "abcdef1", "commit capability caches parsed commits")
    eq(cache[44][1].label, nil, "commit capability does not cache completion items")
    eq(last_list.items[1].label, ":abcdef1: cache me", "commit capability maps cached commits")
end

return T
