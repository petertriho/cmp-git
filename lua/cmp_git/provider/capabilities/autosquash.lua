local autosquash_lines = require("cmp_git.provider.capabilities.autosquash_lines")
local commits = require("cmp_git.provider.capabilities.commits")
local format = require("cmp_git.format")

local M = {
    prefixes = {},
    commits = {},
}

-- The prefixes that `git rebase --autosquash` reads. Git hard-codes them, so the filter does not follow the config.
local AUTOSQUASH_PREFIXES = { "fixup! ", "squash! ", "amend! " }

---@param title string
---@return boolean
local function is_autosquash_title(title)
    for _, prefix in ipairs(AUTOSQUASH_PREFIXES) do
        if string.sub(title, 1, #prefix) == prefix then
            return true
        end
    end
    return false
end

---The items of the prefix words that start with the text before the cursor. The line check has tested the text.
---@param config cmp_git.Config.GitAutosquashPrefixes
---@param line string
---@return cmp_git.CompletionList
function M.prefixes.list(config, line)
    -- An incomplete list makes the completion engine ask again on the next letter
    if #line < math.max(config.min_length or 1, 1) then
        return { items = {}, isIncomplete = true }
    end

    local prefixes = {}
    for index, word in ipairs(config.words or {}) do
        if string.sub(word, 1, #line) == line then
            ---@class cmp_git.AutosquashPrefix
            local prefix = {
                word = word,
                ---The position of the word in `words`
                index = index,
                ---The adapters open the menu again after the insert, so that the commit list shows at once
                reopen = true,
            }
            prefixes[#prefixes + 1] = prefix
        end
    end

    return { items = format.items(config, nil, prefixes), isIncomplete = false }
end

---The items of the commits that an autosquash commit can target: one for each title, without the autosquash commits.
---@param history cmp_git.Commit[] Newest first, so that a repeated title keeps its newest commit.
---@param config cmp_git.Config.GitAutosquashCommits
---@param trigger_char string?
---@return cmp_git.CompletionItem[]
function M.commits.items(history, config, trigger_char)
    local items = {}
    local seen = {}
    for _, commit in ipairs(history) do
        local title = commit.title
        if not seen[title] and not is_autosquash_title(title) then
            seen[title] = true
            items[#items + 1] = format.item(config, trigger_char, commit)
        end
    end
    return items
end

---@class cmp_git.Provider.AutosquashCommitArgs
---@field cache table<integer, cmp_git.Commit[]> The cache of the `git.commits` history.
---@field callback fun(list: cmp_git.CompletionList)
---@field commits_config cmp_git.Config.GitCommits The request, the parse, and the cache of the history.
---@field config cmp_git.Config.GitAutosquashCommits The items.
---@field line? string The text before the cursor.
---@field runner? table
---@field bufnr? integer

---@param args cmp_git.Provider.AutosquashCommitArgs
---@return cmp_git.SystemJob?
function M.commits.complete(args)
    local config = args.config
    return commits.complete({
        cache = args.cache,
        callback = args.callback,
        config = args.commits_config,
        trigger_char = autosquash_lines.attached_trigger(args.line),
        items = function(history, _commits_config, trigger_char)
            return M.commits.items(history, config, trigger_char)
        end,
        runner = args.runner,
        bufnr = args.bufnr,
    })
end

return M
