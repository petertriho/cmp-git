local utils = require("cmp_git.utils")
local sort = require("cmp_git.sort")
local log = require("cmp_git.log")
local format = require("cmp_git.format")

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

    self.config = vim.tbl_deep_extend("force", require("cmp_git.config").gitlab, overrides or {})

    if overrides.filter_fn then
        self.config.format.filterText = overrides.filter_fn
    end

    table.insert(self.config.hosts, "gitlab.com")
    GitLab.config = self.config
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

function GitLab:is_valid_host(git_info)
    if
        git_info.host == nil
        or git_info.owner == nil
        or git_info.repo == nil
        or not vim.tbl_contains(GitLab.config.hosts, git_info.host)
    then
        return false
    end
    return true
end

function GitLab:get_issues(callback, git_info, trigger_char)
    if not GitLab:is_valid_host(git_info) then
        return false
    end

    local config = self.config.issues
    local bufnr = vim.api.nvim_get_current_buf()

    if self.cache.issues[bufnr] then
        local items = self.cache.issues[bufnr]
        log.fmt_debug("Got %d issues from cache", #items)
        callback({ items = items, isIncomplete = false })
        return true
    end

    local id = get_project_id(git_info)

    local job = get_items(
        function(args)
            log.fmt_debug("Got %d issues from GitLab", #args.items)
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

            return format.item(config, trigger_char, issue)
        end
    )
    job:start()
    return true
end

function GitLab:get_mentions(callback, git_info, trigger_char)
    if not GitLab:is_valid_host(git_info) then
        return false
    end

    local config = self.config.mentions
    local bufnr = vim.api.nvim_get_current_buf()

    if self.cache.mentions[bufnr] then
        callback({ items = self.cache.mentions[bufnr], isIncomplete = false })
        return true
    end

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
            return format.item(config, trigger_char, mention)
        end
    )
    job:start()

    return true
end

function GitLab:get_merge_requests(callback, git_info, trigger_char)
    if not GitLab:is_valid_host(git_info) then
        return false
    end

    local config = self.config.merge_requests
    local bufnr = vim.api.nvim_get_current_buf()

    if self.cache.merge_requests[bufnr] then
        local items = self.cache.merge_requests[bufnr]
        log.fmt_debug("Got %d MRs from cache", #items)
        callback({ items = items, isIncomplete = false })
        return true
    end

    local id = get_project_id(git_info)

    local job = get_items(
        function(args)
            log.fmt_debug("Got %d MRs from GitLab", #args.items)
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
            return format.item(config, trigger_char, mr)
        end
    )
    job:start()

    return true
end

return GitLab
