local Job = require("plenary.job")
local utils = require("cmp_git.utils")

local GitLab = {
    cache = {
        issues = {},
        mentions = {},
        merge_requests = {},
    },
    config = {},
}

GitLab.new = function(overrides)
    local self = setmetatable({}, {
        __index = GitLab,
    })

    self.config = vim.tbl_extend("force", require("cmp_git.config").gitlab, overrides or {})

    return self
end

local get_project_id = function(git_info)
    return utils.url_encode(string.format("%s/%s", git_info.owner, git_info.repo))
end

local get_items = function(callback, glab_command, curl_url, handle_item)
    local command = nil

    if vim.fn.executable("glab") == 1 and glab_command then
        command = glab_command
    elseif vim.fn.executable("curl") == 1 and curl_url then
        command = {
            "curl",
            "-s",
            curl_url,
        }

        if vim.fn.exists("$GITLAB_TOKEN") == 1 then
            local token = vim.fn.getenv("GITLAB_TOKEN")
            local authorization_header = string.format("Authorization: Bearer %s", token)
            table.insert(command, "-H")
            table.insert(command, authorization_header)
        end
    else
        vim.notify("glab and curl executables not found!")
        return
    end

    command.cwd = utils.get_cwd()
    command.on_exit = vim.schedule_wrap(function(job)
        local result = table.concat(job:result(), "")

        local items = utils.handle_response(result, handle_item)

        callback({ items = items, isIncomplete = false })
    end)

    Job:new(command):start()
end

function GitLab:get_issues(callback, git_info, trigger_char, config)
    if git_info.host == nil or git_info.host == "github.com" or git_info.owner == nil or git_info.repo == nil then
        return false
    end

    local bufnr = vim.api.nvim_get_current_buf()

    if self.cache.issues[bufnr] then
        callback({ items = self.cache.issues[bufnr], isIncomplete = false })
        return true
    end

    config = vim.tbl_extend("force", self.config.issues, config or {})
    local id = get_project_id(git_info)

    get_items(
        function(args)
            callback(args)
            self.cache.issues[bufnr] = args.items
        end,
        {
            "glab",
            "api",
            string.format("/projects/%s/issues?per_page=%d&state=%s", id, config.limit, config.state),
        },
        string.format(
            "https://%s/api/v4/projects/%s/issues?per_page=%d&state=%s",
            git_info.host,
            id,
            config.limit,
            config.state
        ),
        function(issue)
            if issue.description == vim.NIL then
                issue.description = ""
            end

            return {
                label = string.format("#%s: %s", issue.iid, issue.title),
                insertText = string.format("#%s", issue.iid),
                filterText = config.filter_fn(trigger_char, issue),
                documentation = {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", issue.title, issue.description),
                },
            }
        end
    )
    return true
end

function GitLab:get_mentions(callback, git_info, trigger_char, config)
    if git_info.host == nil or git_info.host == "github.com" or git_info.owner == nil or git_info.repo == nil then
        return false
    end

    local bufnr = vim.api.nvim_get_current_buf()

    if self.cache.mentions[bufnr] then
        callback({ items = self.cache.mentions[bufnr], isIncomplete = false })
        return true
    end

    config = vim.tbl_extend("force", self.config.mentions, config or {})
    local id = get_project_id(git_info)

    get_items(
        function(args)
            callback(args)
            self.cache.mentions[bufnr] = args.items
        end,
        {
            "glab",
            "api",
            string.format("/projects/%s/users?per_page=%d", id, config.limit),
        },
        string.format("https://%s/api/v4/projects/%s/users?per_page=%d", git_info.host, id, config.limit),
        function(mention)
            return {
                label = string.format("@%s", mention.username),
                filterText = config.filter_fn(trigger_char, mention),
                documentation = {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", mention.username, mention.name),
                },
            }
        end
    )

    return true
end

function GitLab:get_merge_requests(callback, git_info, trigger_char, config)
    if git_info.host == nil or git_info.host == "github.com" or git_info.owner == nil or git_info.repo == nil then
        return false
    end

    local bufnr = vim.api.nvim_get_current_buf()

    if self.cache.merge_requests[bufnr] then
        callback({ items = self.cache.merge_requests[bufnr], isIncomplete = false })
        return true
    end
    
    config = vim.tbl_extend("force", self.config.merge_requests, config or {})
    local id = get_project_id(git_info)

    get_items(
        function(args)
            callback(args)
            self.cache.merge_requests[bufnr] = args.items
        end,
        {
            "glab",
            "api",
            string.format("/projects/%s/merge_requests?per_page=%d&state=%s", id, config.limit, config.state),
        },
        string.format(
            "https://%s/api/v4/projects/%s/merge_requests?per_page=%d&state=%s",
            git_info.host,
            id,
            config.limit,
            config.state
        ),

        function(mr)
            return {
                label = string.format("!%s: %s", mr.iid, mr.title),
                insertText = string.format("!%s", mr.iid),
                filterText = config.filter_fn(trigger_char, mr),
                documentation = {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", mr.title, mr.description),
                },
            }
        end
    )

    return true
end

return GitLab
