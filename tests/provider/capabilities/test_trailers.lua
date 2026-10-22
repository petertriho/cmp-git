local helpers = require("tests.helpers")
local config = require("cmp_git.config")
local Core = require("cmp_git.core")
local trailer_capability = require("cmp_git.provider.capabilities.trailers")

local eq = helpers.eq
local ok = helpers.ok

local T = helpers.new_set()

T["trailer_gating"] = function()
    local trailers_config = config.normalize({}).git.trailers
    local function available(lines, row, line, kind, filetype, custom_config)
        local bufnr = helpers.buffer(lines, filetype)
        local result = trailer_capability.available(custom_config or trailers_config, {
            bufnr = bufnr,
            cursor = { row = row },
            line = line,
        }, kind)
        vim.api.nvim_buf_delete(bufnr, { force = true })
        return result
    end

    ok(available({ "subject", "", "Co" }, 3, "Co", "keys"), "keys after the blank line")
    ok(
        available({ "subject", "", "Signed-off-by: Ada <ada@example.com>", "Co" }, 4, "Co", "keys"),
        "keys after another trailer"
    )
    ok(available({ "subject", "", "Co" }, 3, "Co", "keys", "NeogitCommitMessage"), "keys in Neogit commit messages")
    ok(available({ "subject", "", "Co" }, 3, "Co", "keys", "gitcommit.markdown"), "keys in compound filetype")
    ok(not available({ "Co" }, 1, "Co", "keys"), "no keys on the subject line")
    ok(not available({ "subject", "Co" }, 2, "Co", "keys"), "no keys on row 2")
    ok(not available({ "subject", "", "body text", "Co" }, 4, "Co", "keys"), "no keys inside a paragraph")
    ok(not available({ "subject", "", "Co" }, 3, "Co", "keys", "octo"), "no keys in octo")
    ok(available({ "subject", "", "" }, 3, "Co-authored-by: Ad", "identities"), "identities for an identity key")
    ok(
        available({ "subject", "", "" }, 3, "co-AUTHORED-by: Ad", "identities"),
        "identity keys match case-insensitively"
    )
    ok(not available({ "subject", "", "" }, 3, "Fixes: Ad", "identities"), "no identities for other keys")
    ok(not available({ "subject", "Ad" }, 2, "Co-authored-by: Ad", "identities"), "no identities on row 2")
    ok(available({ "subject", "", "" }, 3, "Assisted-by: Co", "values"), "values for any key")
    ok(available({ "subject", "", "" }, 3, "Fixes: ", "values"), "values for an empty value after a space")
    ok(not available({ "subject", "", "" }, 3, "Fixes:", "values"), "no values right after the colon")
    ok(not available({ "subject", "", "body", "" }, 4, "Fixes: 2", "values"), "no values inside a paragraph")

    local from_first_line = config.normalize({ git = { trailers = { min_line = 1 } } }).git.trailers
    ok(available({ "Co" }, 1, "Co", "keys", nil, from_first_line), "min_line 1 allows the first line")
    ok(available({ "", "Co" }, 2, "Co", "keys", nil, from_first_line), "min_line 1 allows line 2 after a blank line")
    ok(
        not available({ "subject", "Co" }, 2, "Co", "keys", nil, from_first_line),
        "min_line 1 keeps the previous-line check"
    )
    local from_fifth_line = config.normalize({ git = { trailers = { min_line = 5 } } }).git.trailers
    ok(not available({ "subject", "", "" }, 3, "Co", "keys", nil, from_fifth_line), "min_line 5 skips line 3")
    ok(
        not available({ "subject", "", "" }, 3, "Co-authored-by: Ad", "identities", nil, from_fifth_line),
        "min_line applies to identities"
    )
end

T["trailer_keys_parse_and_sort"] = function()
    local result = table.concat({
        "Signed-off-by\031co-authored-by\0",
        "\nChange-Id\0",
        "\nsigned-off-by\0",
        "\n%(trailers:keyonly,separator=%x1f)\0",
        "\n\0",
    })
    local keys = trailer_capability.keys.parse(result, { builtin = { "Co-authored-by", "Signed-off-by", "Fixes" } })
    local by_key = {}
    for _, trailer in ipairs(keys) do
        by_key[trailer.key] = trailer
    end

    eq(#keys, 4, "trailer key count")
    eq(by_key["Signed-off-by"].count, 2, "trailer keys count case-insensitively")
    eq(by_key["Co-authored-by"].count, 1, "built-in trailer key casing wins")
    eq(by_key["Change-Id"].count, 1, "mined trailer key count")
    eq(by_key["Change-Id"].builtin_index, nil, "mined trailer key has no built-in index")
    eq(by_key["Fixes"].count, 0, "unused built-in trailer key is kept")

    local items = trailer_capability.keys.items(keys, config.normalize({}).git.trailers.keys, nil)
    table.sort(items, function(a, b)
        return a.sortText < b.sortText
    end)
    local labels = {}
    for _, item in ipairs(items) do
        table.insert(labels, item.label)
    end
    eq(table.concat(labels, ","), "Signed-off-by,Co-authored-by,Change-Id,Fixes", "trailer key sort order")
    eq(items[1].insertText, "Signed-off-by: ", "trailer key insert text")
end

-- The parsers before they read the fields in place. The tests below check that the new parsers give the same output.
local old = {}

function old.trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function old.split_nul(input)
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

function old.parse_ident(value)
    local name, email = string.match(value, "^%s*(.-)%s*<([^>]+)>")
    if not name or name == "" or old.trim(email) == "" then
        return nil, nil
    end
    return name, old.trim(email)
end

function old.keys_parse(result, keys_config)
    local keys = {}
    local by_key = {}

    for index, key in ipairs(keys_config.builtin or {}) do
        if not by_key[key:lower()] then
            local trailer = { key = key, count = 0, builtin_index = index }
            by_key[key:lower()] = trailer
            table.insert(keys, trailer)
        end
    end

    for _, record in ipairs(old.split_nul(result)) do
        for _, key in ipairs(vim.split(record, "\031", { plain = true })) do
            key = old.trim(key)
            if key:match("^[%w-]+$") then
                local trailer = by_key[key:lower()]
                if not trailer then
                    trailer = { key = key, count = 0 }
                    by_key[key:lower()] = trailer
                    table.insert(keys, trailer)
                end
                trailer.count = trailer.count + 1
            end
        end
    end

    return keys
end

function old.identities_parse(log_result, ident_result)
    local now = os.time()
    local identities = {}
    local by_email = {}

    local function add(name, email, timestamp, source, is_self)
        name = old.trim(name)
        email = old.trim(email)
        if name == "" or email == "" then
            return
        end

        local existing = by_email[email:lower()]
        if existing then
            existing.is_self = existing.is_self or is_self
            return
        end

        local entry = {
            name = name,
            email = email,
            timestamp = timestamp,
            diff = timestamp and os.difftime(now, timestamp) or 0,
            source = source,
            is_self = is_self,
        }
        by_email[email:lower()] = entry
        table.insert(identities, entry)
    end

    for _, record in ipairs(old.split_nul(log_result)) do
        local fields = vim.split(record, "\031", { plain = true })
        if #fields >= 3 then
            local timestamp = tonumber(old.trim(fields[1]))
            add(fields[2], fields[3], timestamp, "author", false)

            for i = 4, #fields do
                local key, value = string.match(fields[i], "^%s*([%w-]+):%s*(.-)%s*$")
                local name, email = old.parse_ident(value or "")
                if name and email then
                    add(name, email, timestamp, key, false)
                end
            end
        end
    end

    local name, email = old.parse_ident(ident_result)
    if name and email then
        add(name, email, nil, "self", true)
    end

    return identities
end

function old.values_parse(result)
    local now = os.time()
    local by_key = {}
    local by_value = {}

    for _, record in ipairs(old.split_nul(result)) do
        local fields = vim.split(record, "\031", { plain = true })
        local timestamp = tonumber(old.trim(fields[1] or ""))

        for i = 2, #fields do
            local key, value = string.match(fields[i], "^%s*([%w-]+):%s*(.-)%s*$")
            if key and value ~= "" then
                local id = key:lower()
                by_key[id] = by_key[id] or {}
                by_value[id] = by_value[id] or {}

                local entry = by_value[id][value]
                if not entry then
                    entry = {
                        key = key,
                        value = value,
                        count = 0,
                        timestamp = timestamp,
                        diff = timestamp and os.difftime(now, timestamp) or 0,
                    }
                    by_value[id][value] = entry
                    table.insert(by_key[id], entry)
                end
                entry.count = entry.count + 1
            end
        end
    end

    return by_key
end

---Random `git log` outputs in the formats of the trailer requests, with the edge cases that the parsers handle.
---@param seed integer
---@return fun(): string log An output of `identities.request` or `values.request`.
---@return fun(): string keys_log An output of `keys.request`.
---@return fun(): string ident An output of `identities.ident_request`.
local function trailer_outputs(seed)
    -- A deterministic generator, so that a failure can be reproduced
    local function random(n)
        seed = seed * 16807 % 2147483647
        return seed % n + 1
    end
    local function pick(list)
        return list[random(#list)]
    end

    local times = { "1700000000", "\n1700000000", " 1699990000 ", "", "abc", "\n" }
    local names = { "Ada Lovelace", " Ada  Lovelace ", "", "Grace Hopper", "Me", "\t" }
    local emails = { "ada@example.com", "ADA@Example.com", " grace@example.com ", "", "me@example.com", "x" }
    local keys = { "Co-authored-by", "co-AUTHORED-by", "Signed-off-by", "Fixes", "Assisted-by", "bad key", " Refs" }
    local separators = { ":", ": ", ":  ", " :", ":\t" }
    local values = {
        "",
        " ",
        "Ada Lovelace <ada@example.com>",
        "Ada <ADA@Example.com>",
        "Grace Hopper <grace@example.com>",
        "  Grace   Hopper  <  grace@example.com  >  ",
        "<nameless@example.com>",
        "No Email",
        "Ada <>",
        "Ada < >",
        "A <> B <b@example.com>",
        "a > b <c@example.com> <d@example.com>",
        "x <y",
        "#123",
        '29c8d7267dd7 ("fix: snippet: edit range")',
        "Codex",
        "Codex\r",
        "value with spaces  \r\n",
        "folded\n value",
        "Ünïcödé <ü@example.com>",
    }

    local function trailer()
        return pick(keys) .. pick(separators) .. pick(values)
    end

    local function output(fields)
        local records = {}
        for i = 1, random(6) - 1 do
            -- `--format=` ends each record with a newline
            records[i] = table.concat(fields(), "\031") .. "\0" .. pick({ "\n", "" })
        end
        -- A trailing record without a NUL is dropped
        return table.concat(records) .. pick({ "", "", "1700000000\031Ada\031ada@example.com" })
    end

    local function log()
        return output(function()
            local fields = { pick(times) }
            for i = 2, random(6) do
                fields[i] = i == 2 and random(2) == 1 and pick(names)
                    or i == 3 and random(2) == 1 and pick(emails)
                    or trailer()
            end
            return fields
        end)
    end

    local key_names = {
        "Signed-off-by",
        " co-authored-by ",
        "Change-Id",
        "%(trailers:keyonly,separator=%x1f)",
        "",
        "\n",
        "bad key",
        "Fixes\r",
        "FIXES",
    }
    local function keys_log()
        return output(function()
            local fields = {}
            for i = 1, random(4) do
                fields[i] = pick(key_names)
            end
            return fields
        end)
    end

    local idents = {
        "",
        "Me <me@example.com> 1 +0000\n",
        "Ada Lovelace <ADA@example.com> 1 +0000",
        " Spaced  Name <  spaced@example.com > 1 +0000\n",
        "garbage",
    }
    local function ident()
        return pick(idents)
    end

    return log, keys_log, ident
end

T["trailer_parsers_match_the_old_parsers"] = function()
    helpers.stub(os, "time", function()
        return 1700000000
    end)

    local log, keys_log, ident = trailer_outputs(7)
    local keys_config = { builtin = { "Co-authored-by", "Signed-off-by", "fixes", "Fixes" } }
    for _ = 1, 300 do
        local output = log()
        local ident_output = ident()
        local reason = vim.inspect(output) .. " and " .. vim.inspect(ident_output)
        eq(
            trailer_capability.identities.parse(output, ident_output),
            old.identities_parse(output, ident_output),
            "identities of " .. reason
        )
        eq(trailer_capability.values.parse(output), old.values_parse(output), "values of " .. vim.inspect(output))

        output = keys_log()
        eq(
            trailer_capability.keys.parse(output, keys_config),
            old.keys_parse(output, keys_config),
            "keys of " .. vim.inspect(output)
        )
    end
end

T["trailer_parsers_take_linear_time"] = function()
    -- The old patterns took about 3 s for each of these values
    local run = string.rep(" ", 32000)
    local start = os.clock()

    local by_key = trailer_capability.values.parse("1\031Refs: a" .. run .. "b" .. run .. "\0")
    eq(by_key["refs"][1].value, "a" .. run .. "b", "value with a long run of spaces")

    local identities = trailer_capability.identities.parse(
        "1\031Ada\031ada@example.com\031Co-authored-by: Grace" .. run .. "Hopper" .. run .. "<grace@example.com>\0",
        ""
    )
    eq(identities[2].name, "Grace" .. run .. "Hopper", "identity name with a long run of spaces")
    ok(os.clock() - start < 0.25, "trailers with long runs of spaces parse fast")
end

T["trailer_identities_request"] = function()
    local spec = trailer_capability.identities.request({
        keys = { "Co-authored-by", "bad key", "Signed-off-by" },
        limit = 5,
    })

    eq(spec.exec, "git", "trailer identities command exec")
    eq(spec.args[3], "5", "trailer identities command limit")
    eq(
        spec.args[4],
        "--format=%at%x1f%aN%x1f%aE%x1f%(trailers:key=Co-authored-by,key=Signed-off-by,unfold,separator=%x1f)%x00",
        "trailer identities command format"
    )
end

T["trailer_identities_parse"] = function()
    local now = os.time()
    local log_result = table.concat({
        tostring(now - 10)
            .. "\031Ada Lovelace\031ada@example.com"
            .. "\031Co-authored-by: Grace Hopper <grace@example.com>"
            .. "\031Signed-off-by: Ada Lovelace <ADA@example.com>\0",
        "\n" .. tostring(now - 20) .. "\031Ada L\031ada@example.com\031Co-authored-by: no email here\0",
        "\n" .. tostring(now - 30) .. "\031Me\031me@example.com\031\0",
        "\n",
    })
    local identities = trailer_capability.identities.parse(log_result, "Me Myself <ME@example.com> 1792648118 +1100\n")

    eq(#identities, 3, "trailer identities dedupe by email")
    eq(identities[1].name, "Ada Lovelace", "trailer identities keep the most recent name")
    eq(identities[1].source, "author", "trailer identities record the author source")
    eq(identities[2].email, "grace@example.com", "trailer identities include trailer values")
    eq(identities[2].source, "Co-authored-by", "trailer identities record the trailer key")
    ok(identities[2].diff >= 10, "trailer identities use the commit time")
    eq(identities[3].name, "Me", "your identity in history keeps the history record")
    eq(identities[3].is_self, true, "your identity in history is marked")

    local only_self = trailer_capability.identities.parse("", "Solo <solo@example.com> 1 +0000")
    eq(#only_self, 1, "your identity without history is added")
    eq(only_self[1].is_self, true, "your identity without history is marked")
    eq(only_self[1].diff, 0, "your identity without history sorts first")
    eq(only_self[1].source, "self", "your identity without history has the self source")
end

T["trailer_capabilities_use_cache_and_runner"] = function()
    local builds = {}
    local runner = {
        build = function(spec, callback)
            table.insert(builds, spec.args[1])
            return helpers.fake_job(function()
                if spec.args[1] == "var" then
                    callback("Me <me@example.com> 1 +0000", true)
                else
                    -- A history without trailers
                    callback("", true)
                end
            end)
        end,
    }
    local trailers_config = config.normalize({}).git.trailers

    local key_callback, key_lists = helpers.recorder()
    local key_args = {
        cache = {},
        callback = key_callback,
        config = trailers_config.keys,
        runner = runner,
        bufnr = 50,
    }
    trailer_capability.keys.complete(key_args)
    trailer_capability.keys.complete(key_args)

    eq(table.concat(builds, ","), "log", "trailer keys run once")
    eq(#key_lists, 2, "trailer keys callback on miss and hit")
    eq(#key_lists[1].items, #trailers_config.keys.builtin, "history without trailers gives the built-in keys")

    builds = {}
    local identities_callback, identities_lists = helpers.recorder()
    local identities_args = {
        cache = {},
        callback = identities_callback,
        config = trailers_config.identities,
        runner = runner,
        bufnr = 51,
    }
    trailer_capability.identities.complete(identities_args)
    trailer_capability.identities.complete(identities_args)

    eq(table.concat(builds, ","), "log,var", "trailer identities run log and var once")
    eq(#identities_lists, 2, "trailer identities callback on miss and hit")
    eq(identities_lists[1].items[1].label, "Me <me@example.com>", "history without authors gives your identity")
end

---A runner whose commands give the outputs of a history with one commit by Ada, or fail.
---@param fails { log?: boolean, var?: boolean, build?: boolean } The commands that fail. `build` gives no job, as when
---git is not installed.
---@return table runner
---@return string[] builds The commands of the jobs that the runner made.
local function failing_runner(fails)
    local builds = {}
    local runner = {
        build = function(spec, callback)
            if fails.build then
                return nil
            end

            local name = spec.args[1]
            table.insert(builds, name)
            return helpers.fake_job(function()
                if fails[name] then
                    callback("", false)
                elseif name == "var" then
                    callback("Me <me@example.com> 1 +0000\n", true)
                else
                    callback("1700000000\031Ada\031ada@example.com\031Assisted-by: Codex\0\n", true)
                end
            end)
        end,
    }
    return runner, builds
end

T["trailer_capabilities_answer_failures_without_caching"] = function()
    local trailers_config = config.normalize({}).git.trailers

    ---Runs a request two times, and checks that each request ends with one final list and that nothing is cached.
    ---@return string[] labels The labels of the first list.
    local function complete(kind, fails, expected_builds)
        local runner, builds = failing_runner(fails)
        local callback, lists = helpers.recorder()
        local args = {
            cache = {},
            callback = callback,
            config = trailers_config[kind],
            key = "Assisted-by",
            runner = runner,
            bufnr = 54,
        }
        local reason = string.format("%s with %s", kind, vim.inspect(fails))

        trailer_capability[kind].complete(args)
        eq(#lists, 1, reason .. " calls back once")
        eq(lists[1].isIncomplete, false, reason .. " gives a final list")
        eq(args.cache[54], nil, reason .. " is not cached")

        trailer_capability[kind].complete(args)
        eq(#lists, 2, reason .. " calls back again")
        eq(table.concat(builds, ","), expected_builds, reason .. " runs again")

        local labels = {}
        for _, item in ipairs(lists[1].items) do
            table.insert(labels, item.label)
        end
        return labels
    end

    eq(
        #complete("keys", { log = true }, "log,log"),
        #trailers_config.keys.builtin,
        "failed log gives the built-in keys"
    )
    eq(#complete("keys", { build = true }, ""), #trailers_config.keys.builtin, "no git gives the built-in keys")

    eq(complete("identities", { log = true }, "log,var,log,var"), { "Me <me@example.com>" }, "failed log")
    eq(complete("identities", { var = true }, "log,var,log,var"), { "Ada <ada@example.com>" }, "failed git var")
    eq(complete("identities", { log = true, var = true }, "log,var,log,var"), {}, "failed log and git var")
    eq(complete("identities", { build = true }, ""), {}, "no git gives no identities")

    eq(complete("values", { log = true }, "log,log"), {}, "failed log gives no values")
    eq(complete("values", { build = true }, ""), {}, "no git gives no values")
end

---A runner whose jobs answer when the test calls their callbacks.
---@return table runner
---@return { started: string[], cancelled: string[], answer: table<string, fun(result: string, success: boolean)> } jobs
local function manual_runner()
    local jobs = { started = {}, cancelled = {}, answer = {} }
    local runner = {
        build = function(spec, callback)
            local name = spec.args[1]
            return {
                command = spec.exec,
                start = function()
                    table.insert(jobs.started, name)
                    jobs.answer[name] = callback
                end,
                cancel = function()
                    table.insert(jobs.cancelled, name)
                end,
            }
        end,
    }
    return runner, jobs
end

T["trailer_identities_run_log_and_var_at_once"] = function()
    local runner, jobs = manual_runner()
    local callback, lists = helpers.recorder()
    local args = {
        cache = {},
        callback = callback,
        config = config.normalize({}).git.trailers.identities,
        runner = runner,
        bufnr = 55,
    }
    trailer_capability.identities.complete(args)

    eq(jobs.started, { "log", "var" }, "git log and git var start before either answers")
    jobs.answer.var("Me <me@example.com> 1 +0000\n", true)
    eq(#lists, 0, "the list waits for git log")
    jobs.answer.log("1700000000\031Ada\031ada@example.com\0\n", true)

    eq(#lists, 1, "one list when both answer")
    local labels = {}
    for _, item in ipairs(lists[1].items) do
        table.insert(labels, item.label)
    end
    eq(labels, { "Ada <ada@example.com>", "Me <me@example.com>" }, "the list has the log and your identity")
    ok(args.cache[55] ~= nil, "the result of both commands is cached")
end

T["trailer_identities_job_cancel"] = function()
    local runner, jobs = manual_runner()
    local callback, lists = helpers.recorder()
    local args = {
        cache = {},
        callback = callback,
        config = config.normalize({}).git.trailers.identities,
        runner = runner,
        bufnr = 52,
    }
    local job = helpers.not_nil(trailer_capability.identities.complete(args))

    jobs.answer.var("Me <me@example.com> 1 +0000\n", true)
    job:cancel()
    jobs.answer.log("", true)

    eq(jobs.cancelled, { "log", "var" }, "cancel stops both commands")
    eq(#lists, 0, "cancelled trailer identities job does not call back")
    eq(args.cache[52], nil, "cancelled trailer identities job does not cache")
end

T["trailer_capabilities_with_git"] = function()
    if vim.fn.executable("git") ~= 1 then
        helpers.skip("git is not installed")
    end

    local repo = helpers.git_repo()
    repo.commit("feat: first\n\nCo-authored-by: Grace Hopper <grace@example.com>\nChange-Id: I1234\nAssisted-by: Codex")

    vim.env.GIT_AUTHOR_NAME = "Test Self"
    vim.env.GIT_AUTHOR_EMAIL = "self@example.com"
    vim.fn.chdir(repo.dir)

    local trailers_config = config.normalize({}).git.trailers
    local key_list, identities_list, values_list
    trailer_capability.keys.complete({
        cache = {},
        callback = function(list)
            key_list = list
        end,
        config = trailers_config.keys,
        bufnr = 60,
    })
    trailer_capability.identities.complete({
        cache = {},
        callback = function(list)
            identities_list = list
        end,
        config = trailers_config.identities,
        bufnr = 61,
    })
    trailer_capability.values.complete({
        cache = {},
        callback = function(list)
            values_list = list
        end,
        config = trailers_config.values,
        key = "assisted-by",
        bufnr = 62,
    })
    helpers.wait_for(function()
        return key_list ~= nil and identities_list ~= nil and values_list ~= nil
    end, "trailer capabilities complete with git")

    local keys = {}
    for _, item in ipairs(key_list.items) do
        keys[item.label] = item.data.count
    end
    eq(keys["Change-Id"], 1, "git trailer keys include mined keys")
    eq(keys["Co-authored-by"], 1, "git trailer keys count built-in keys")

    local identities = {}
    for _, item in ipairs(identities_list.items) do
        identities[item.label] = item.data
    end
    ok(identities["Ada Lovelace <ada@example.com>"] ~= nil, "git trailer identities include authors")
    eq(
        identities["Grace Hopper <grace@example.com>"] and identities["Grace Hopper <grace@example.com>"].source,
        "Co-authored-by",
        "git trailer identities include trailer values"
    )
    eq(
        identities["Test Self <self@example.com>"] and identities["Test Self <self@example.com>"].is_self,
        true,
        "git trailer identities include your identity"
    )
    eq(values_list.items[1] and values_list.items[1].label, "Codex", "git trailer values")
end

T["trailer_values_request_and_parse"] = function()
    local spec = trailer_capability.values.request({ limit = 7 })
    eq(spec.args[3], "7", "trailer values command limit")
    eq(spec.args[4], "--format=%at%x1f%(trailers:only,unfold,separator=%x1f)%x00", "trailer values command format")

    local now = os.time()
    local result = table.concat({
        tostring(now - 10)
            .. '\031Assisted-by: Codex\031Fixes: 29c8d7267dd7 ("fix: snippet edit range")'
            .. "\031Co-authored-by: Grace Hopper <grace@example.com>\0",
        "\n" .. tostring(now - 20) .. "\031assisted-by: Codex\031Assisted-by: claude-code Opus 5\031Ref:\0",
        "\n",
    })
    local by_key = trailer_capability.values.parse(result)

    eq(#by_key["assisted-by"], 2, "trailer values dedupe by value")
    eq(by_key["assisted-by"][1].key, "Assisted-by", "trailer values keep the first key casing")
    eq(by_key["assisted-by"][1].count, 2, "trailer values count across key casing")
    eq(by_key["fixes"][1].value, '29c8d7267dd7 ("fix: snippet edit range")', "trailer values keep colons")
    eq(by_key["co-authored-by"][1].value, "Grace Hopper <grace@example.com>", "trailer values keep identities")
    eq(by_key["ref"], nil, "trailer values skip empty values")

    local items = trailer_capability.values.items(by_key, "Assisted-By", config.normalize({}).git.trailers.values, nil)
    table.sort(items, function(a, b)
        return a.sortText < b.sortText
    end)
    eq(items[1].label, "Codex", "trailer values sort by use count")
    eq(items[2].label, "claude-code Opus 5", "trailer values for the key only")
    eq(#items, 2, "trailer values filter by key")
end

T["trailer_values_cache_and_fall_through"] = function()
    local builds = 0
    local runner = {
        build = function(_spec, callback)
            builds = builds + 1
            return helpers.fake_job(function()
                -- A history without trailers
                callback("1700000000\0\n", true)
            end)
        end,
    }
    local callback, lists = helpers.recorder()
    local args = {
        cache = {},
        callback = callback,
        config = config.normalize({}).git.trailers.values,
        key = "Assisted-by",
        runner = runner,
        bufnr = 53,
    }

    ok(trailer_capability.values.may_have(args.cache, { bufnr = 53, line = "Assisted-by: C" }), "unknown cache")
    trailer_capability.values.complete(args)
    trailer_capability.values.complete(args)

    eq(builds, 1, "trailer values run once")
    eq(#lists, 2, "trailer values callback on miss and hit")
    eq(#lists[1].items, 0, "history without trailers gives no trailer values")
    ok(
        not trailer_capability.values.may_have(args.cache, { bufnr = 53, line = "Assisted-by: C" }),
        "cached history without values for the key"
    )

    local core = Core.new({})
    local bufnr = helpers.buffer({ "feat: subject", "", "Note: plain text" })
    local context = { cursor = { row = 3, character = 16 }, line = "Note: plain text", bufnr = bufnr }
    eq(#core:_route(context), 1, "body line with a key routes to values before the first fetch")
    core.sources.git.cache_trailer_values[bufnr] = {}
    eq(#core:_route(context), 0, "body line without history values falls through")
end

T["trailer_commands_run_in_the_repository_of_the_request_buffer"] = function()
    local seen = {}
    local runner = {
        build = function(spec, callback)
            table.insert(seen, { spec.args[1], spec.bufnr })
            return helpers.fake_job(function()
                callback("", true)
            end)
        end,
    }
    local trailers = config.normalize({}).git.trailers
    for _, kind in ipairs({ "keys", "identities", "values" }) do
        trailer_capability[kind].complete({
            cache = {},
            callback = function() end,
            config = trailers[kind],
            runner = runner,
            bufnr = 61,
            key = "Assisted-by",
        })
    end

    eq(seen, { { "log", 61 }, { "log", 61 }, { "var", 61 }, { "log", 61 } }, "each command gets the request buffer")
end

return T
