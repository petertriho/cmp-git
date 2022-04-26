local Job = require("plenary.job")
local log = require("cmp_git.log")
local sort = require("cmp_git.sort")
local format = require("cmp_git.format")

local Git = {
    cache_commits = {},
    config = {},
}

Git.new = function(overrides)
    local self = setmetatable({}, {
        __index = Git,
    })

    self.config = vim.tbl_deep_extend("force", require("cmp_git.config").git, overrides or {})

    if overrides.filter_fn then
        self.config.format.filterText = overrides.filter_fn
    end

    return self
end

local function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local split_by = function(input, sep)
    local t = {}

    while true do
        local s, e = string.find(input, sep)

        if not s then
            break
        end

        local part = string.sub(input, 1, s - 1)
        input = string.sub(input, e + 1)

        table.insert(t, part)
    end

    return t
end

local update_edit_range = function(commits, cursor, offset)
    for k, v in pairs(commits) do
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

        commits[k].textEdit = update
    end
end

local parse_commits = function(trigger_char, callback, config)
    -- Choose unique and long end markers
    local end_part_marker = "###CMP_GIT###"
    local end_entry_marker = "###CMP_GIT_END###"

    -- Extract abbreviated commit sha, subject, body, author name, author email, commit timestamp
    local job = Job:new({
        command = "git",
        args = {
            "log",
            "-n",
            config.limit,
            "--date=unix",
            string.format(
                "--pretty=format:%%h%s%%s%s%%b%s%%cn%s%%ce%s%%cd%s%s",
                end_part_marker,
                end_part_marker,
                end_part_marker,
                end_part_marker,
                end_part_marker,
                end_part_marker,
                end_entry_marker
            ),
        },
        on_exit = vim.schedule_wrap(function(job, code)
            if code ~= 0 then
                log.fmt_debug("%s returned with exit code %d", "git", code)
            else
                log.fmt_debug("%s returned with a result", "git")
                local result = table.concat(job:result(), "")

                local commits = {}

                local entries = split_by(result, end_entry_marker)

                for _, e in ipairs(entries) do
                    local part = split_by(e, end_part_marker)

                    local sha = trim(part[1])
                    local title = trim(part[2])
                    local description = trim(part[3]) or ""
                    local author_name = part[4] or ""
                    local author_mail = part[5] or ""
                    local commit_timestamp = part[6] or ""
                    local diff = os.difftime(os.time(), commit_timestamp)

                    local commit = {
                        sha = sha,
                        title = title,
                        description = description,
                        author_name = author_name,
                        author_mail = author_mail,
                        commit_timestamp = commit_timestamp,
                        diff = diff,
                    }

                    table.insert(commits, format.item(config, trigger_char, commit))
                end

                callback(commits)
            end
        end),
    })

    job:start()
end

function Git:get_commits(callback, params, trigger_char)
    local config = self.config.commits
    local cursor = params.context.cursor
    local offset = params.offset

    local bufnr = vim.api.nvim_get_current_buf()

    if self.cache_commits and self.cache_commits[bufnr] then
        local commits = self.cache_commits[bufnr]
        update_edit_range(commits, cursor, offset)
        callback({ items = commits, isIncomplete = false })
    else
        parse_commits(trigger_char, function(commits)
            update_edit_range(commits, cursor, offset)
            callback({ items = commits, isIncomplete = false })
        end, config)
    end

    return true
end

return Git
