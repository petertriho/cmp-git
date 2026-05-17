local command = require("cmp_git.command")
local format = require("cmp_git.format")

local M = {}

---@param s string
---@return string
local function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

---@param input string
---@return string[]
local function split_nul(input)
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

---@param config cmp_git.Config.GitCommits
---@return cmp_git.CommandSpec
function M.request(config)
    return {
        exec = "git",
        args = {
            "log",
            "-n",
            tostring(config.limit),
            "--date=unix",
            "--pretty=format:%H%x00%s%x00%b%x00%cn%x00%ce%x00%cd%x00",
        },
    }
end

---@param result string
---@param config cmp_git.Config.GitCommits
---@return cmp_git.Commit[]
function M.parse(result, config)
    local fields = split_nul(result)
    local commits = {}

    for i = 1, #fields, 6 do
        if fields[i + 5] then
            local timestamp = tonumber(trim(fields[i + 5])) or 0
            ---@class cmp_git.Commit
            local commit = {
                sha = trim(fields[i]):sub(1, config.sha_length),
                title = trim(fields[i + 1]),
                description = trim(fields[i + 2]),
                author_name = fields[i + 3] or "",
                author_mail = fields[i + 4] or "",
                commit_timestamp = timestamp,
                diff = os.difftime(os.time(), timestamp),
            }

            table.insert(commits, commit)
        end
    end

    return commits
end

---@param commits cmp_git.Commit[]
---@param config cmp_git.Config.GitCommits
---@param trigger_char string
---@return cmp_git.CompletionItem[]
function M.items(commits, config, trigger_char)
    local items = {}
    for _, commit in ipairs(commits) do
        table.insert(items, format.item(config, trigger_char, commit))
    end
    return items
end

---@class cmp_git.Provider.CommitCapabilityArgs
---@field cache table<integer, cmp_git.Commit[]>
---@field callback fun(list: cmp_git.CompletionList)
---@field config cmp_git.Config.GitCommits
---@field trigger_char string
---@field runner? table
---@field bufnr? integer

---@param args cmp_git.Provider.CommitCapabilityArgs
---@return cmp_git.SystemJob?
function M.job(args)
    local bufnr = args.bufnr or vim.api.nvim_get_current_buf()

    if args.cache[bufnr] then
        args.callback({ items = M.items(args.cache[bufnr], args.config, args.trigger_char), isIncomplete = false })
        return nil
    end

    local runner = args.runner or command
    return runner.build(M.request(args.config), function(result, success)
        if not success then
            return
        end

        local parsed = M.parse(result, args.config)
        args.cache[bufnr] = parsed
        args.callback({ items = M.items(parsed, args.config, args.trigger_char), isIncomplete = false })
    end)
end

---@param args cmp_git.Provider.CommitCapabilityArgs
function M.complete(args)
    local job = M.job(args)
    if job then
        job:start()
    end
end

return M
