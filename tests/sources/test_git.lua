local helpers = require("tests.helpers")
local config = require("cmp_git.config")
local Core = require("cmp_git.core")
local Git = require("cmp_git.sources.git")
local command = require("cmp_git.command")

local eq = helpers.eq
local ok = helpers.ok

local T = helpers.new_set()

T["git_instance_state_isolation"] = function()
    local first = Git.new(config.normalize({}).git)
    local second = Git.new(config.normalize({}).git)

    first.cache_commits[1] = { { label = "first" } }

    eq(second.cache_commits[1], nil, "Git commit cache is instance-local")
    ok(first.cache_commits ~= second.cache_commits, "Git commit cache table is instance-local")
    ok(first.cache_trailer_keys ~= second.cache_trailer_keys, "Git trailer key cache is instance-local")
    ok(
        first.cache_trailer_identities ~= second.cache_trailer_identities,
        "Git trailer identities cache is instance-local"
    )
    ok(first.cache_trailer_values ~= second.cache_trailer_values, "Git trailer values cache is instance-local")
end

---Starts the requests that a commit message buffer can make, and records the lists that each one gives.
---@param git cmp_git.Source.Git
---@return table<string, cmp_git.CompletionList[]> lists
local function request_all(git)
    local bufnr = helpers.buffer({ "feat: subject", "", "" })
    local lists = { commits = {}, keys = {}, identities = {}, values = {} }
    local function context(line)
        return { bufnr = bufnr, cursor = { row = 3, character = #line }, line = line }
    end
    local function record(name)
        return function(list)
            table.insert(lists[name], list)
        end
    end

    ok(git:get_commits(record("commits"), context("See :"), ":"), "commits are handled")
    ok(git:get_trailer_keys(record("keys"), context("Si")), "trailer keys are handled")
    ok(git:get_trailer_identities(record("identities"), context("Co-authored-by: Te")), "identities are handled")
    ok(git:get_trailer_values(record("values"), context("Assisted-by: C")), "trailer values are handled")
    return lists
end

---@param list cmp_git.CompletionList
---@return string[]
local function labels(list)
    local result = {}
    for _, item in ipairs(list.items) do
        table.insert(result, item.label)
    end
    return result
end

T["git_requests_answer_in_a_repository_without_commits"] = function()
    if vim.fn.executable("git") ~= 1 then
        helpers.skip("git is not installed")
    end

    local repo = helpers.git_repo()
    vim.env.GIT_AUTHOR_NAME = "Test Self"
    vim.env.GIT_AUTHOR_EMAIL = "self@example.com"
    vim.fn.chdir(repo.dir)

    local git_config = config.normalize({}).git
    local git = Git.new(git_config)
    local lists = request_all(git)
    helpers.wait_for(function()
        return #lists.commits > 0 and #lists.keys > 0 and #lists.identities > 0 and #lists.values > 0
    end, "each request calls back")
    helpers.flush()

    eq(lists.commits, { { items = {}, isIncomplete = false } }, "commits give one final empty list")
    eq(#lists.keys, 1, "trailer keys call back once")
    eq(#lists.keys[1].items, #git_config.trailers.keys.builtin, "trailer keys give the built-in keys")
    eq(#lists.identities, 1, "identities call back once")
    eq(labels(lists.identities[1]), { "Test Self <self@example.com>" }, "identities give your identity")
    eq(lists.values, { { items = {}, isIncomplete = false } }, "trailer values give one final empty list")

    eq(next(git.cache_commits), nil, "commits are not cached")
    eq(next(git.cache_trailer_keys), nil, "trailer keys are not cached")
    eq(next(git.cache_trailer_identities), nil, "identities are not cached")
    eq(next(git.cache_trailer_values), nil, "trailer values are not cached")
end

T["git_autosquash_commits_reuse_the_commit_history"] = function()
    if vim.fn.executable("git") ~= 1 then
        helpers.skip("git is not installed")
    end

    local repo = helpers.git_repo()
    repo.commit("feat: add parser (#12)")
    repo.commit("fixup! feat: add parser (#12)")
    repo.commit("docs: describe the parser")
    vim.fn.chdir(repo.dir)
    local git = Git.new(config.normalize({}).git)
    local bufnr = helpers.buffer({ "fixup!" })

    local commits = {}
    git:get_commits(function(list)
        table.insert(commits, list)
    end, { bufnr = bufnr }, ":")
    helpers.wait_for(function()
        return #commits > 0
    end, "the commits call back")

    local builds = 0
    helpers.stub(command, "build", function()
        builds = builds + 1
    end)
    local callback, lists = helpers.recorder()
    local handled = git:get_autosquash_commits(callback, {
        bufnr = bufnr,
        cursor = { row = 1, character = 6 },
        line = "fixup!",
    })

    ok(handled, "the commit list is handled")
    eq(builds, 0, "the commit list after a `:` request starts no git process")
    eq(#lists, 1, "the commit list calls back at once")
    eq(labels(lists[1]), { "docs: describe the parser", "feat: add parser (#12)" }, "the titles, newest first")
    eq(lists[1].items[1].insertText, " docs: describe the parser", "the title touches the `!`")
end

T["git_autosquash_prefixes"] = function()
    local git = Git.new(config.normalize({}).git)
    local callback, lists = helpers.recorder()

    ok(git:get_autosquash_prefixes(callback, { cursor = { row = 1, character = 2 }, line = "sq" }), "handled")
    eq(#lists, 1, "the prefixes call back at once")
    eq(labels(lists[1]), { "squash!" }, "the prefix of the letters")
end

---The commands and the subjects of a `git rebase -i` todo list, such as `fixup -C amend! fix: x`.
---@param todo string
---@return string[]
local function todo_steps(todo)
    local steps = {}
    for _, line in ipairs(vim.split(todo, "\n")) do
        if line ~= "" and not line:find("^#") then
            local step, rest = line:match("^(%a+)%s+(.*)$")
            local option = rest:match("^%-[Cc]%s+")
            if option then
                step = step .. " " .. vim.trim(option)
                rest = rest:sub(#option + 1)
            end
            -- Git 2.4x and later put `# ` before the subject
            local subject = rest:match("^%x+%s+(.*)$"):gsub("^# ", "")
            table.insert(steps, step .. " " .. subject)
        end
    end
    return steps
end

T["git_autosquash_subjects_match_the_rebase_rules"] = function()
    if vim.fn.executable("git") ~= 1 then
        helpers.skip("git is not installed")
    end

    local repo = helpers.git_repo()
    local function commit(file, message, body)
        vim.fn.writefile({ message }, repo.dir .. "/" .. file, "a")
        repo.git("add", file)
        repo.git("commit", "-q", "--no-verify", "-m", message, body and "-m" or nil, body)
    end
    commit("base.txt", "chore: start")
    local base = vim.trim(repo.git("rev-parse", "HEAD"))
    commit("parser.lua", "feat: add parser (#12)")
    commit("README.md", "docs: describe the parser")
    commit("input.lua", "fix: handle empty input")

    local core = Core.new({})
    -- Each line is typed in a new commit message, and its item is the commit with the title of `target`
    local cases = {
        { line = "fixup!", trigger = "!", target = "feat: add parser (#12)", file = "parser.lua" },
        { line = "squash! do", target = "docs: describe the parser", file = "README.md" },
        { line = "amend!fi", trigger = "!", target = "fix: handle empty input", file = "input.lua" },
    }
    for _, case in ipairs(cases) do
        local bufnr = helpers.buffer({ case.line })
        vim.api.nvim_buf_set_name(bufnr, repo.dir .. "/.git/COMMIT_EDITMSG")
        local callback, lists = helpers.recorder()
        core:complete({
            trigger_character = case.trigger,
            cursor = { row = 1, character = #case.line },
            line = case.line,
            bufnr = bufnr,
        }, callback)
        helpers.wait_for(function()
            return #lists > 0
        end, vim.inspect(case.line) .. " answers")

        local item = vim.iter(lists[1].items):find(function(candidate)
            return candidate.label == case.target
        end)
        helpers.not_nil(item, vim.inspect(case.line) .. " offers " .. case.target)
        local range = item.textEdit.range
        vim.api.nvim_buf_set_text(bufnr, 0, range.start.character, 0, range["end"].character, { item.textEdit.newText })
        local subject = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
        vim.api.nvim_buf_delete(bufnr, { force = true })

        local prefix = case.line:match("^%a+!")
        eq(subject, prefix .. " " .. case.target, vim.inspect(case.line) .. " completes the subject")
        -- Git stops the rebase when the new message of an `amend!` commit is empty
        commit(case.file, subject, prefix == "amend!" and "fix: handle empty and blank input" or nil)
    end

    local todo = helpers.tempdir() .. "/todo"
    local editor = helpers.tempdir() .. "/save-todo"
    vim.fn.writefile({ "#!/bin/sh", string.format('cp "$1" %s', vim.fn.shellescape(todo)) }, editor)
    vim.uv.fs_chmod(editor, tonumber("755", 8))
    local result = vim.system({
        "git",
        "-C",
        repo.dir,
        "-c",
        "user.name=Ada Lovelace",
        "-c",
        "user.email=ada@example.com",
        "rebase",
        "-i",
        "--autosquash",
        base,
    }, { text = true, env = { GIT_SEQUENCE_EDITOR = editor, GIT_EDITOR = "true" } }):wait()

    eq(result.code, 0, "the rebase succeeds: " .. (result.stderr or ""))
    eq(todo_steps(table.concat(vim.fn.readfile(todo), "\n")), {
        "pick feat: add parser (#12)",
        "fixup fixup! feat: add parser (#12)",
        "pick docs: describe the parser",
        "squash squash! docs: describe the parser",
        "pick fix: handle empty input",
        "fixup -C amend! fix: handle empty input",
    }, "each autosquash commit comes right after its target")
    eq(vim.fn.isdirectory(repo.dir .. "/.git/rebase-merge"), 0, "no rebase is in progress")
    eq(
        vim.split(vim.trim(repo.git("log", "--format=%s", base .. "..HEAD")), "\n"),
        { "fix: handle empty and blank input", "docs: describe the parser", "feat: add parser (#12)" },
        "the rebase folds each autosquash commit into its target"
    )
end

T["git_commit_documentation_keeps_the_body_layout"] = function()
    if vim.fn.executable("git") ~= 1 then
        helpers.skip("git is not installed")
    end

    -- The body of issue #54. It is indented as a whole, and one line is indented more.
    local repo = helpers.git_repo()
    repo.commit(table.concat({
        "chore(astronvim): auto install Treesitter language packs",
        "",
        "  ## what",
        "  - auto install Treesitter language packs",
        "",
        "  ## how",
        "  - enable config `auto_install` if `tree-sitter` is installed and",
        "    available on PATH",
    }, "\n"))
    vim.fn.chdir(repo.dir)

    local git = Git.new(config.normalize({}).git)
    local line = "See :"
    local context = {
        bufnr = helpers.buffer({ "feat: subject", "", line }),
        cursor = { row = 3, character = #line },
        line = line,
    }
    local lists = {}
    git:get_commits(function(list)
        table.insert(lists, list)
    end, context, ":")
    helpers.wait_for(function()
        return #lists > 0
    end, "commits call back")

    eq(#lists, 1, "commits call back once")
    eq(#lists[1].items, 1, "commits give the commit")
    local item = lists[1].items[1]
    eq(item.documentation, {
        kind = "markdown",
        value = table.concat({
            "# chore(astronvim): auto install Treesitter language packs",
            "",
            "## what",
            "- auto install Treesitter language packs",
            "",
            "## how",
            "- enable config `auto_install` if `tree-sitter` is installed and",
            "  available on PATH",
            "",
            "Authored by Ada Lovelace (ada@example.com), committed on " .. os.date("%c", item.data.commit_timestamp),
        }, "\n"),
    }, "the documentation keeps the lines of the body without their shared indentation")
end

T["git_requests_answer_without_git"] = function()
    -- `command.build` gives no job when git is not installed
    helpers.stub(vim.fn, "executable", function()
        return 0
    end)

    local git_config = config.normalize({}).git
    local lists = request_all(Git.new(git_config))

    eq(lists.commits, { { items = {}, isIncomplete = false } }, "commits give one final empty list")
    eq(#lists.keys, 1, "trailer keys call back once")
    eq(#lists.keys[1].items, #git_config.trailers.keys.builtin, "trailer keys give the built-in keys")
    eq(lists.identities, { { items = {}, isIncomplete = false } }, "identities give one final empty list")
    eq(lists.values, { { items = {}, isIncomplete = false } }, "trailer values give one final empty list")
end

return T
