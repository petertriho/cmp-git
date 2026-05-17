local commits = require("cmp_git.provider.capabilities.commits")

---@class cmp_git.Source.Git
local Git = {}

---@param overrides cmp_git.Config.Git
function Git.new(overrides)
    local self = setmetatable({}, {
        __index = Git,
    })

    ---@type table<integer, cmp_git.Commit[]>
    self.cache_commits = {}

    self.config = overrides or {}

    return self
end

---@param items cmp_git.CompletionItem[]
local function update_edit_range(items, cursor, _offset)
    for k, v in pairs(items) do
        local sha = v.insertText

        local update = {
            range = {
                start = {
                    line = cursor.row - 1,
                    character = cursor.character - 1,
                },
                ["end"] = {
                    line = cursor.row - 1,
                    character = cursor.character + string.len(sha),
                },
            },
            newText = sha,
        }

        items[k].textEdit = update
    end
end

Git._update_edit_range = update_edit_range

---@param callback fun(commits: cmp_git.CompletionList)
---@param trigger_char string
function Git:get_commits(callback, params, trigger_char)
    local config = self.config.commits
    local cursor = params.context.cursor
    local bufnr = vim.api.nvim_get_current_buf()

    commits.complete({
        cache = self.cache_commits,
        callback = function(list)
            update_edit_range(list.items, cursor, params.offset)
            callback(list)
        end,
        config = config,
        trigger_char = trigger_char,
        bufnr = bufnr,
    })

    return true
end

return Git
