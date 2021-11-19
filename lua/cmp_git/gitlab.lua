local utils = require("cmp_git.utils")
local sort = require("cmp_git.sort")
local log = require("cmp_git.log")

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

local get_items = function(callback, glab_args, curl_url, handle_item)
    local glab_job = utils.build_job("glab", callback, glab_args, handle_item)

    curl_args = {
        "-s",
        curl_url,
    }

    if vim.fn.exists("$GITLAB_TOKEN") == 1 then
        local token = vim.fn.getenv("GITLAB_TOKEN")
        local authorization_header = string.format("Authorization: Bearer %s", token)
        table.insert(curl_args, "-H")
        table.insert(curl_args, authorization_header)
    end

    local curl_job = utils.build_job("curl", callback, curl_args, handle_item)

    return utils.chain_fallback(glab_job, curl_job)
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

    local job = get_items(
        function(args)
            callback(args)
            self.cache.issues[bufnr] = args.items
        end,
        {
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
                sortText = sort.get_sort_text(config.sort_by, issue),
                documentation = {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", issue.title, issue.description),
                },
            }
        end
    )
    job:start()
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

    local job = get_items(
        function(args)
            callback(args)
            self.cache.mentions[bufnr] = args.items
        end,
        {
            "api",
            string.format("/projects/%s/users?per_page=%d", id, config.limit),
        },
        string.format("https://%s/api/v4/projects/%s/users?per_page=%d", git_info.host, id, config.limit),
        function(mention)
            return {
                label = string.format("@%s", mention.username),
                filterText = config.filter_fn(trigger_char, mention),
                sortText = sort.get_sort_text(config.sort_by, mention),
                documentation = {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", mention.username, mention.name),
                },
            }
        end
    )
    job:start()

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

    local job = get_items(
        function(args)
            callback(args)
            self.cache.merge_requests[bufnr] = args.items
        end,
        {
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
                sortText = sort.get_sort_text(config.sort_by, mr),
                documentation = {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", mr.title, mr.description),
                },
            }
        end
    )
    job:start()

    return true
end

return GitLab
