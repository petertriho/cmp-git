local Job = require("plenary.job")

local M = {}

M.get_issues = function(source, callback, bufnr, owner, repo)
    local command = nil
    local used_glab = false

    if vim.fn.executable("glab") == 1 then
        -- NOTE: glab doesn't provide any json output, so we have to live with a reduced set of info
        -- see https://github.com/profclems/glab/issues/828
        command = {
            "glab",
            "issue",
            "list",
            "--per-page", -- this is a little cheating but w/e
            source.config.gitlab.issues.limit,
        }

        if source.config.gitlab.issues.state == "all" or source.config.gitlab.issues.state == "closed" then
            table.insert(command, "--" .. source.config.gitlab.issues.state)
        end

        used_glab = true
    else
        vim.notify("glab executables not found!")
        return
    end

    command.on_exit = function(job)
        -- TODO: check for empty result?
        local result = job:result()

        local items = {}

        if used_glab then
            -- Remove the first two and last, as it's not usefull info here
            table.remove(result, 1)
            table.remove(result, 2)
            table.remove(result)

            for _, issue_raw in ipairs(result) do
                local split_glab_issue = function(str)
                    split_line = {}

                    for part in issue_raw:gmatch("([^\t]*)\t?") do
                        if part ~= "" then
                            table.insert(split_line, part)
                        end
                    end
                    return { number = split_line[1], title = split_line[2] }
                end

                -- Format returned by glab is '#<number>\t<title>\t<lables>\t<creation-date>'
                local issue = split_glab_issue(issue_raw)

                -- just in case I forgot some line
                if next(issue) ~= nil then
                    table.insert(items, {
                        label = string.format("%s", issue.number),
                        documentation = {
                            kind = "markdown",
                            value = string.format("# %s", issue.title),
                        },
                    })
                end
            end
        end

        callback({ items = items, isIncomplete = false })

        source.cache_issues[bufnr] = items
    end

    Job:new(command):start()
end

return M
