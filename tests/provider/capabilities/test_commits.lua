local helpers = require("tests.helpers")
local commit_capability = require("cmp_git.provider.capabilities.commits")

local eq = helpers.eq
local ok = helpers.ok

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

T["commit_capability_parse_dedents_the_body"] = function()
    local function description(body)
        local raw = commit_record("abcdef1234567890", "subject", body, "Ada", "ada@example.com", 1234567890)
        return commit_capability.parse(raw, commit_test_config())[1].description
    end

    eq(
        description("  ## what\n  - a\n\n  ## how\n  - enable it if\n    it is on PATH\n"),
        "## what\n- a\n\n## how\n- enable it if\n  it is on PATH",
        "a body that is indented as a whole keeps its relative indentation"
    )
    eq(description("  first\n    second"), "first\n  second", "the first line has the shared indentation")
    eq(description("    first\n  second"), "  first\nsecond", "a later line has the shared indentation")
    eq(description("\t\tfirst\n\t\t\tsecond"), "first\n\tsecond", "tabs are an indentation")
    eq(description("first\n  second"), "first\n  second", "a first line without indentation")
    eq(description("  first\nsecond"), "first\nsecond", "a later line without indentation")
    eq(description("\tfirst\n  second"), "first\n  second", "a tab and a space do not match")
    eq(description("  first\n \t \n\n  second"), "first\n\n\nsecond", "lines with only whitespace become empty")
    eq(
        description("first\n \t \n  second"),
        "first\n \t \n  second",
        "lines with only whitespace stay without a dedent"
    )
    eq(description("\n \n\t\n  first\n  second\n\n"), "first\nsecond", "blank lines around the body are removed")
    eq(description(" \r first\n  second"), "first\n second", "the indentation starts after other whitespace")
    eq(description(""), "", "an empty body")
    eq(description(" \n\t "), "", "a body with only whitespace")
end

-- The parser before it read the fields in place, with the dedent of the body. The test below checks that the new
-- parser gives the same output.
local function old_trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

---The body without the indentation that all its lines with text share, written with line lists instead of the index
---arithmetic of the parser. Without a shared indentation, it is the trimmed body.
local function old_body(s)
    local trimmed = old_trim(s)
    -- The spaces and tabs right before the first byte that is not whitespace
    local indent = s:match("([ \t]*)%S") or ""
    local lines = vim.split(indent .. trimmed, "\n", { plain = true })
    local margin
    for _, line in ipairs(lines) do
        if line:find("%S") then
            local lead = line:match("^[ \t]*")
            margin = margin or lead
            while lead:sub(1, #margin) ~= margin do
                margin = margin:sub(1, -2)
            end
        end
    end
    if not margin or margin == "" then
        return trimmed
    end
    for i, line in ipairs(lines) do
        lines[i] = line:find("%S") and line:sub(#margin + 1) or ""
    end
    return table.concat(lines, "\n")
end

local function old_split_nul(input)
    local fields = {}
    local start = 1
    while true do
        local pos = string.find(input, "\0", start, true)
        if not pos then
            break
        end
        table.insert(fields, string.sub(input, start, pos - 1))
        start = pos + 1
    end
    return fields
end

local function old_parse(result, config)
    local fields = old_split_nul(result)
    local commits = {}

    for i = 1, #fields, 6 do
        if fields[i + 5] then
            local timestamp = tonumber(old_trim(fields[i + 5])) or 0
            table.insert(commits, {
                sha = old_trim(fields[i]):sub(1, config.sha_length),
                title = old_trim(fields[i + 1]),
                description = old_body(fields[i + 2]),
                author_name = fields[i + 3] or "",
                author_mail = fields[i + 4] or "",
                commit_timestamp = timestamp,
                diff = os.difftime(os.time(), timestamp),
            })
        end
    end

    return commits
end

---A deterministic random generator, so that a failure can be reproduced.
---@param seed integer
---@return fun(n: integer): integer random A number from 1 to n.
local function random_generator(seed)
    return function(n)
        seed = seed * 16807 % 2147483647
        return seed % n + 1
    end
end

T["commit_capability_parse_matches_the_old_parser"] = function()
    helpers.stub(os, "time", function()
        return 1700000000
    end)

    local random = random_generator(42)
    local function pick(list)
        return list[random(#list)]
    end
    local fragments = {
        "",
        " ",
        "\t",
        "\r\n",
        "\n",
        "fix: subject",
        "  padded subject  ",
        "body line one\nbody line two\n",
        "body\r\n\r\nCo-authored-by: Ada <ada@example.com>\r\n",
        "Ünïcödé",
        "\031",
        "a" .. string.rep(" ", 50) .. "b",
        "  ## what\n  - a\n \t \n    b\n",
        "  indented\n",
        "\n  - after a blank line\n    more\n",
        "\t- tab line\n",
        "   \n",
    }
    local function text()
        local parts = {}
        for i = 1, random(3) - 1 do
            parts[i] = pick(fragments)
        end
        return table.concat(parts)
    end
    local shas = { "", "abcdef1234567890abcdef1234567890abcdef12", " abc ", "\nabcdef1234567890", "a b c d e f g h" }
    local timestamps = { "1700000000", " 1700000000 ", "\n1699990000\r", "", "abc", "1e3", "-5" }

    for _ = 1, 300 do
        local commits = {}
        for i = 1, random(5) - 1 do
            commits[i] = table.concat({ pick(shas), text(), text(), text(), text(), pick(timestamps), "" }, "\0")
        end
        -- `--pretty=format:` puts a newline between commits. The last commit can lack fields.
        local output = table.concat(commits, pick({ "\n", "" })) .. pick({ "", "dangling\0", "a\0b\0c\0d\0e" })

        for _, sha_length in ipairs({ 7, 0, 40, 100 }) do
            local config = { sha_length = sha_length }
            eq(
                commit_capability.parse(output, config),
                old_parse(output, config),
                string.format("parse of %s with sha_length %d", vim.inspect(output), sha_length)
            )
        end
    end
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
            eq(spec.bufnr, 44, "commit capability command runs in the repository of the request buffer")
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

T["commit_capability_items_function_reuses_the_cached_history"] = function()
    local builds = 0
    local raw = commit_record("abcdef1234567890", "cache me", "body", "Author", "author@example.com", 1234567890)
    local runner = {
        build = function(_spec, callback)
            builds = builds + 1
            return helpers.fake_job(function()
                callback(raw, true)
            end)
        end,
    }
    local cache = {}
    local seen = {}
    local function titles(commits, config, trigger_char)
        table.insert(seen, { config = config, trigger_char = trigger_char })
        return vim.tbl_map(function(commit)
            return { label = commit.title }
        end, commits)
    end
    local config = commit_test_config()
    local callback, lists = helpers.recorder()

    commit_capability.complete({
        cache = cache,
        callback = callback,
        config = config,
        trigger_char = ":",
        runner = runner,
        bufnr = 46,
    })
    commit_capability.complete({
        cache = cache,
        callback = callback,
        config = config,
        items = titles,
        runner = runner,
        bufnr = 46,
    })

    eq(builds, 1, "the cached history starts no new process")
    eq(lists[1].items[1].label, ":abcdef1: cache me", "the default items function")
    eq(lists[2], { items = { { label = "cache me" } }, isIncomplete = false }, "the items function makes the items")
    eq(#seen, 1, "the items function runs for its own request only")
    ok(seen[1].config == config, "the items function gets the config")
    eq(seen[1].trigger_char, nil, "the items function gets the trigger character")

    commit_capability.complete({
        cache = {},
        callback = callback,
        config = config,
        items = titles,
        runner = runner,
        bufnr = 47,
    })
    eq(builds, 2, "an empty cache starts git log")
    eq(lists[3].items[1].label, "cache me", "the items function makes the items of a new history")
end

T["commit_capability_answers_failures_without_caching"] = function()
    local builds = 0
    local failing_runner = {
        build = function(_spec, callback)
            builds = builds + 1
            return helpers.fake_job(function()
                -- As in a repository without commits
                callback("", false)
            end)
        end,
    }
    local callback, lists = helpers.recorder()
    local args = {
        cache = {},
        callback = callback,
        config = commit_test_config(),
        trigger_char = ":",
        runner = failing_runner,
        bufnr = 45,
    }

    commit_capability.complete(args)
    eq(lists, { { items = {}, isIncomplete = false } }, "failed log gives one final empty list")
    eq(args.cache[45], nil, "failed log is not cached")
    commit_capability.complete(args)
    eq(builds, 2, "the next request runs git log again")
    eq(#lists, 2, "the next request calls back again")

    callback, lists = helpers.recorder()
    args.callback = callback
    -- As when git is not installed
    args.runner = {
        build = function()
            return nil
        end,
    }
    eq(commit_capability.complete(args), nil, "no job without git")
    eq(lists, { { items = {}, isIncomplete = false } }, "no git gives one final empty list")
end

return T
