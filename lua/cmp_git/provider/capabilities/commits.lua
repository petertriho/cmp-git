local command = require("cmp_git.command")
local format = require("cmp_git.format")
local utils = require("cmp_git.utils")

local M = {}

local find = string.find
local sub = string.sub
local trim_range = utils.trim_range

-- The NUL-terminated fields of each commit in the `M.request` format
local FIELDS = 6

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
            "--pretty=format:%H%x00%s%x00%b%x00%aN%x00%aE%x00%cd%x00",
        },
    }
end

---@param s string
---@param first integer
---@param last integer
---@return string
local function trimmed(s, first, last)
    return sub(s, trim_range(s, first, last))
end

---@param result string
---@param config cmp_git.Config.GitCommits
---@return cmp_git.Commit[]
function M.parse(result, config)
    local commits = {}
    local now = os.time()
    local sha_length = config.sha_length
    -- The position of the NUL after each field of the current commit. The fields are read in place, so that each
    -- field is copied once, after the trim.
    local stops = {}
    local start = 1

    while true do
        local from = start
        for field = 1, FIELDS do
            local stop = find(result, "\0", from, true)
            -- A trailing commit without all its fields is dropped
            if not stop then
                return commits
            end
            stops[field] = stop
            from = stop + 1
        end

        -- `--pretty=format:` puts a newline between commits, so the sha starts with whitespace
        local sha_first, sha_last = trim_range(result, start, stops[1] - 1)
        local sha
        if sha_length >= 0 then
            sha = sub(result, sha_first, math.min(sha_last, sha_first + sha_length - 1))
        else
            sha = sub(result, sha_first, sha_last):sub(1, sha_length)
        end

        -- `tonumber` ignores surrounding whitespace
        local timestamp = tonumber(sub(result, stops[5] + 1, stops[6] - 1)) or 0
        ---@class cmp_git.Commit
        local commit = {
            sha = sha,
            title = trimmed(result, stops[1] + 1, stops[2] - 1),
            description = trimmed(result, stops[2] + 1, stops[3] - 1),
            author_name = sub(result, stops[3] + 1, stops[4] - 1),
            author_mail = sub(result, stops[4] + 1, stops[5] - 1),
            commit_timestamp = timestamp,
            diff = os.difftime(now, timestamp),
        }
        commits[#commits + 1] = commit

        start = stops[FIELDS] + 1
    end
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

    -- A failure, such as a repository without commits or no git, must still answer. Else blink.cmp holds back the
    -- items of all sources until its timeout. It is not cached, so that the next request tries again.
    local function fail()
        args.callback({ items = {}, isIncomplete = false })
    end

    local runner = args.runner or command
    local job = runner.build(M.request(args.config), function(result, success)
        if not success then
            fail()
            return
        end

        local parsed = M.parse(result, args.config)
        args.cache[bufnr] = parsed
        args.callback({ items = M.items(parsed, args.config, args.trigger_char), isIncomplete = false })
    end)

    if not job then
        fail()
    end
    return job
end

---@param args cmp_git.Provider.CommitCapabilityArgs
function M.complete(args)
    local job = M.job(args)
    if job then
        job:start()
    end
    return job
end

return M
