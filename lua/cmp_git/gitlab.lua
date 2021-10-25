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
            "api",
            string.format(
                "/projects/:id/issues?per_page=%s&state=%s",
                source.config.gitlab.issues.limit,
                source.config.gitlab.issues.state
            ),
        }

        used_glab = true
    else
        vim.notify("glab executables not found!")
        return
    end

    command.on_exit = function(job)
        -- TODO: check for empty result?
        local result = job:result()

        local ok, parsed = pcall(vim.json.decode, table.concat(result, ""))
        if not ok then
            vim.notify("Failed to parse github api result")
            return
        end

        local items = {}

        if used_glab then
            for _, issue in ipairs(parsed) do
                if issue.description == vim.NIL then
                    issue.description = ""
                end

                table.insert(items, {
                    label = string.format("#%s", issue.iid),
                    documentation = {
                        kind = "markdown",
                        value = string.format("# %s\n\n%s", issue.title, issue.description),
                    },
                })
            end
        end

        callback({ items = items, isIncomplete = false })

        source.cache_issues[bufnr] = items
    end

    Job:new(command):start()
end

M.get_mentions = function(source, callback, bufnr, owner, repo)
    local command = nil
    local used_glab = false

    if vim.fn.executable("glab") == 1 then
        command = {
            "glab",
            "api",
            "/projects/:id/repository/contributors",
        }

        used_glab = true
    else
        vim.notify("glab executables not found!")
        return
    end

    command.on_exit = function(job)
        -- TODO: check for empty result?
        local result = job:result()

        local ok, parsed = pcall(vim.json.decode, table.concat(result, ""))
        if not ok then
            vim.notify("Failed to parse github api result")
            return
        end

        local items = {}

        if used_glab then
            for _, mention in ipairs(parsed) do
                table.insert(items, {
                    label = string.format("@%s", mention.username),
                    documentation = {
                        kind = "markdown",
                        value = string.format("# %s\n\n%s", mention.username, mention.name),
                    },
                })
            end
        end

        callback({ items = items, isIncomplete = false })

        source.cache_issues[bufnr] = items
    end

    Job:new(command):start()
end

return M
