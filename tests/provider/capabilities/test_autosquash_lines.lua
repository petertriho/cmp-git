local helpers = require("tests.helpers")
local config = require("cmp_git.config")
local autosquash_lines = require("cmp_git.provider.capabilities.autosquash_lines")

local eq = helpers.eq
local ok = helpers.ok

local T = helpers.new_set()

---@param lines string[]
---@param row integer
---@param line string
---@param kind "prefixes" | "commits"
---@param filetype? string
---@param overrides? table The `git.autosquash` overrides.
---@return boolean
local function available(lines, row, line, kind, filetype, overrides)
    local bufnr = helpers.buffer(lines, filetype)
    return autosquash_lines.available(config.normalize({ git = { autosquash = overrides } }).git.autosquash, {
        bufnr = bufnr,
        cursor = { row = row },
        line = line,
    }, kind)
end

T["autosquash_commits_gating"] = function()
    ok(available({ "fixup!" }, 1, "fixup!", "commits"), "commits on line 1")
    ok(available({ "fixup!" }, 1, "fixup!", "commits", "NeogitCommitMessage"), "commits in Neogit commit messages")
    ok(available({ "fixup!" }, 1, "fixup!", "commits", "gitcommit.markdown"), "commits in a compound filetype")
    ok(not available({ "subject", "", "fixup!" }, 3, "fixup!", "commits"), "no commits on line 3")
    ok(not available({ "subject", "fixup!" }, 2, "fixup!", "commits"), "no commits on line 2")
    ok(not available({ "fixup!" }, 1, "fixup!", "commits", "octo"), "no commits in octo")
    ok(not available({ "fixup!" }, 1, "fixup!", "commits", "markdown"), "no commits in other filetypes")
    ok(available({ "fixup! feat: x" }, 1, "fixup! feat: x", "commits"), "commits after a prefix and a title")
    ok(not available({ "Fix the parser" }, 1, "Fix the parser", "commits"), "no commits without a prefix")
    ok(not available({ "feat: x!" }, 1, "feat: x!", "commits"), "no commits for a `!` after other text")
    ok(not available({ "!x" }, 1, "!x", "commits"), "no commits for a `!` without letters")
    ok(
        not autosquash_lines.available(config.normalize({}).git.autosquash, { line = "fixup!" }, "commits"),
        "no commits without a cursor"
    )
end

T["autosquash_prefixes_gating"] = function()
    ok(available({ "f" }, 1, "f", "prefixes"), "a letter that starts a word")
    ok(available({ "fi" }, 1, "fi", "prefixes"), "letters that start a word")
    ok(available({ "fixup" }, 1, "fixup", "prefixes"), "a full word")
    ok(available({ "sq" }, 1, "sq", "prefixes"), "squash")
    ok(available({ "am" }, 1, "am", "prefixes"), "amend")
    ok(available({ "fi" }, 1, "fi", "prefixes", "gitcommit.markdown"), "a compound filetype")
    ok(not available({ "fe" }, 1, "fe", "prefixes"), "letters that start no word")
    ok(not available({ "Fi" }, 1, "Fi", "prefixes"), "the words match case-sensitively")
    ok(not available({ "fixups" }, 1, "fixups", "prefixes"), "letters after a full word")
    ok(not available({ "" }, 1, "", "prefixes"), "no letters")
    ok(not available({ "fi-" }, 1, "fi-", "prefixes"), "a character that is not a letter")
    ok(not available({ "fixup!" }, 1, "fixup!", "prefixes"), "a prefix with its `!`")
    ok(not available({ " fi" }, 1, " fi", "prefixes"), "a space before the letters")
    ok(not available({ "subject", "", "fi" }, 3, "fi", "prefixes"), "no prefixes on line 3")
    ok(not available({ "fi" }, 1, "fi", "prefixes", "octo"), "no prefixes in octo")
    ok(not available({ "sq" }, 1, "sq", "prefixes", nil, { prefixes = { words = { "fixup" } } }), "only the words")
    ok(available({ "re" }, 1, "re", "prefixes", nil, { prefixes = { words = { "reword" } } }), "a word of the user")
end

T["autosquash_attached_trigger"] = function()
    eq(autosquash_lines.attached_trigger("fixup!"), "!", "the text touches the `!`")
    eq(autosquash_lines.attached_trigger("fixup!feat"), "!", "the title touches the `!`")
    eq(autosquash_lines.attached_trigger("fixup! "), nil, "a space after the `!`")
    eq(autosquash_lines.attached_trigger("fixup! feat"), nil, "a title after the space")
    eq(autosquash_lines.attached_trigger("squash! fixup! x"), nil, "a repeated prefix after the space")
    eq(autosquash_lines.attached_trigger(nil), nil, "no line")
end

return T
