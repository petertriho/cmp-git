local utils = require("cmp_git.utils")

local M = {}

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

M.update_edit_range = function(commits, cursor, offset)
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

M.get_git_commits = function(source, callback, bufnr, cursor, offset)
    -- Choose unique and long end markers
    local end_part_marker = "###CMP_GIT###"
    local end_entry_marker = "###CMP_GIT_END###"

    -- Extract abbreviated commit sha, subject, body, author name, author email, commit timestamp
    local command = string.format(
        'git log -n %d --pretty=format:"%%h%s%%s%s%%b%s%%cn%s%%ce%s%%cD%s%s"',
        source.config.git.commits.limit,
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
        local commit_time = part[6] or ""

        table.insert(commits, {
            label = string.format("%s: %s", sha, title),
            insertText = sha,
            documentation = {
                kind = "markdown",
                value = string.format(
                    "# %s\n\n%s\n\nCommited by %s (%s) on %s",
                    title,
                    description,
                    author_name,
                    author_mail,
                    commit_time
                ),
            },
            data = {
                sha = sha,
                title = title,
                description = description,
                author_name = author_name,
                author_mail = author_mail,
                commit_time = commit_time,
            },
        })
    end

    M.update_edit_range(commits, cursor, offset)

    callback({ items = commits, isIncomplete = false })

    source.cache_commits[bufnr] = commits
end

return M
