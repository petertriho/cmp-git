local utils = require("cmp_git.utils")
local sort = require("cmp_git.sort")

local Git = {
    cache_commits = {},
    config = {},
}

Git.new = function(overrides)
    local self = setmetatable({}, {
        __index = Git,
    })

    self.config = vim.tbl_extend("force", require("cmp_git.config").git, overrides or {})

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

Git.update_edit_range = function(commits, cursor, offset)
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

local parse_commits = function(trigger_char, config)
    -- Choose unique and long end markers
    local end_part_marker = "###CMP_GIT###"
    local end_entry_marker = "###CMP_GIT_END###"

    -- Extract abbreviated commit sha, subject, body, author name, author email, commit timestamp
    local command = string.format(
        'git log -n %d --date=unix --pretty=format:"%%h%s%%s%s%%b%s%%cn%s%%ce%s%%cd%s%s"',
        config.limit,
        end_part_marker,
        end_part_marker,
        end_part_marker,
        end_part_marker,
        end_part_marker,
        end_part_marker,
        end_entry_marker
    )

    local raw_output = utils.run_in_cwd(utils.get_cwd(), function()
        return vim.fn.system(command)
    end)
    local commits = {}

    local entries = split_by(raw_output, end_entry_marker)

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

        table.insert(commits, {
            label = string.format("%s: %s", sha, title),
            filterText = config.filter_fn(trigger_char, commit),
            insertText = sha,
            sortText = sort.get_sort_text(config.sort_by, commit),
            documentation = {
                kind = "markdown",
                value = string.format(
                    "# %s\n\n%s\n\nCommited by %s (%s) on %s",
                    title,
                    description,
                    author_name,
                    author_mail,
                    os.date("%c", commit_timestamp)
                ),
            },
            data = commit,
        })
    end

    return commits
end

function Git:get_commits(callback, params, trigger_char, config)
    local cursor = params.context.cursor
    local offset = params.offset

    config = vim.tbl_extend("force", self.config.commits, config or {})

    local bufnr = vim.api.nvim_get_current_buf()

    local commits
    if self.cache_commits and self.cache_commits[bufnr] then
        commits = self.cache_commits[bufnr]
    else
        commits = parse_commits(trigger_char, config)
    end

    self.update_edit_range(commits, cursor, offset)

    callback({ items = commits, isIncomplete = false })

    return true
end

return Git
