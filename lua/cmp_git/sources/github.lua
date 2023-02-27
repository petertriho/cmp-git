local Job = require("plenary.job")
local utils = require("cmp_git.utils")
local sort = require("cmp_git.sort")
local log = require("cmp_git.log")
local format = require("cmp_git.format")

local GitHub = {
    cache = {
        issues = {},
        mentions = {},
        pull_requests = {},
    },
    config = {},
}

GitHub.new = function(overrides)
    local self = setmetatable({}, {
        __index = GitHub,
    })

    self.config = vim.tbl_deep_extend("force", require("cmp_git.config").github, overrides or {})

    if overrides.filter_fn then
        self.config.format.filterText = overrides.filter_fn
    end

    table.insert(self.config.hosts, "github.com")
    GitHub.config = self.config
    return self
end

-- build a github api url
local github_url = function(git_host, path)
    local url = ""
    if git_host == "github.com" then
        url = "https://api.github.com"
    else
        url = string.format("https://%s/api/v3/%s", git_host, path)
    end
    return url
end

local get_items = function(callback, gh_args, curl_url, handle_item, handle_parsed)
    local gh_job = utils.build_job("gh", callback, gh_args, handle_item, handle_parsed)

    curl_args = {
        "curl",
        "-s",
        "-L",
        "-H",
        "'Accept: application/vnd.github.v3+json'",
        curl_url,
    }

    if vim.fn.exists("$GITHUB_API_TOKEN") == 1 then
        local token = vim.fn.getenv("GITHUB_API_TOKEN")
        local authorization_header = string.format("Authorization: token %s", token)
        table.insert(curl_args, "-H")
        table.insert(curl_args, authorization_header)
    end

    local curl_job = utils.build_job("curl", callback, curl_args, handle_item, handle_parsed)

    return utils.chain_fallback(gh_job, curl_job)
end

local get_pull_requests_job = function(callback, git_info, trigger_char, config)
    return get_items(
        callback,
        {
            "pr",
            "list",
            "--repo",
            string.format("%s/%s/%s", git_info.host, git_info.owner, git_info.repo),
            "--limit",
            config.limit,
            "--state",
            config.state,
            "--json",
            table.concat(config.fields, ","),
        },
        github_url(
            git_info.host,
            string.format(
                "repos/%s/%s/pulls?state=%s&per_page=%d&page=%d",
                git_info.owner,
                git_info.repo,
                config.state,
                config.limit,
                1
            )
        ),
        function(pr)
            if pr.body ~= vim.NIL then
                pr.body = string.gsub(pr.body or "", "\r", "")
            else
                pr.body = ""
            end

            if not pr.updatedAt then
                pr.updatedAt = pr.updated_at
            end

            return format.item(config, trigger_char, pr)
        end
    )
end

local get_issues_job = function(callback, git_info, trigger_char, config)
    return get_items(
        callback,
        {
            "issue",
            "list",
            "--repo",
            string.format("%s/%s/%s", git_info.host, git_info.owner, git_info.repo),
            "--limit",
            config.limit,
            "--state",
            config.state,
            "--json",
            table.concat(config.fields, ","),
        },
        github_url(
            git_info.host,
            string.format(
                "repos/%s/%s/issues?filter=%s&state=%s&per_page=%d&page=%d",
                git_info.owner,
                git_info.repo,
                config.filter,
                config.state,
                config.limit,
                1
            )
        ),
        function(issue)
            if issue.body ~= vim.NIL then
                issue.body = string.gsub(issue.body or "", "\r", "")
            else
                issue.body = ""
            end

            if not issue.updatedAt then
                issue.updatedAt = issue.updated_at
            end

            return format.item(config, trigger_char, issue)
        end
    )
end

function GitHub:is_valid_host(git_info)
    if
        git_info.host == nil
        or git_info.owner == nil
        or git_info.repo == nil
        or not vim.tbl_contains(GitHub.config.hosts, git_info.host)
    then
        return false
    end
    return true
end

function GitHub:_get_issues(callback, git_info, trigger_char)
    local config = self.config.issues
    local bufnr = vim.api.nvim_get_current_buf()

    if self.cache.issues[bufnr] then
        callback({ items = self.cache.issues[bufnr], isIncomplete = false })
        return nil
    end

    local issues_job = get_issues_job(function(args)
        self.cache.issues[bufnr] = args.items
        callback(args)
    end, git_info, trigger_char, config)

    return issues_job
end

function GitHub:_get_pull_requests(callback, git_info, trigger_char)
    local config = self.config.pull_requests
    local bufnr = vim.api.nvim_get_current_buf()

    if self.cache.pull_requests[bufnr] then
        callback({ items = self.cache.pull_requests[bufnr], isIncomplete = false })
        return nil
    end

    local pr_job = get_pull_requests_job(function(args)
        self.cache.pull_requests[bufnr] = args.items
        callback(args)
    end, git_info, trigger_char, config)

    return pr_job
end

function GitHub:get_issues(callback, git_info, trigger_char)
    if not GitHub:is_valid_host(git_info) then
        return false
    end

    local job = self:_get_issues(callback, git_info, trigger_char)

    if job then
        job:start()
    end

    return true
end

function GitHub:get_pull_requests(callback, git_info, trigger_char)
    if not GitHub:is_valid_host(git_info) then
        return false
    end

    local job = self:_get_pull_requests(callback, git_info, trigger_char)

    if job then
        job:start()
    end

    return true
end

function GitHub:get_issues_and_prs(callback, git_info, trigger_char)
    if not GitHub:is_valid_host(git_info) then
        return false
    end

    local bufnr = vim.api.nvim_get_current_buf()

    if self.cache.issues[bufnr] and self.cache.pull_requests[bufnr] then
        local issues = self.cache.issues[bufnr]
        local prs = self.cache.pull_requests[bufnr]

        local items = {}
        items = vim.list_extend(items, issues)
        items = vim.list_extend(items, prs)

        log.fmt_debug("Got %d issues and prs from cache", #items)
        callback({ items = issues, isIncomplete = false })
    else
        local items = {}

        local issues_job = self:_get_issues(function(args)
            items = args.items
            self.cache.issues[bufnr] = args.items
        end, git_info, trigger_char)

        local pull_requests_job = self:_get_pull_requests(function(args)
            local prs = args.items
            self.cache.pull_requests[bufnr] = args.items

            items = vim.list_extend(items, prs)

            log.fmt_debug("Got %d issues and prs from GitHub", #items)
            callback({ items = items, isIncomplete = false })
        end, git_info, trigger_char)

        Job.chain(issues_job, pull_requests_job)
    end

    return true
end

function GitHub:get_mentions(callback, git_info, trigger_char)
    if not GitHub:is_valid_host(git_info) then
        return false
    end

    local config = self.config.mentions
    local bufnr = vim.api.nvim_get_current_buf()

    if self.cache.mentions[bufnr] then
        callback({ items = self.cache.mentions[bufnr], isIncomplete = false })
        return true
    end

    local job = get_items(
        function(args)
            callback(args)
            self.cache.mentions[bufnr] = args.items
        end,
        {
            "api",
            string.format("repos/%s/%s/contributors", git_info.owner, git_info.repo),
            "--hostname",
            git_info.host,
        },
        github_url(
            git_info.host,
            string.format("%s/%s/contributors?per_page=%d&page=%d", git_info.owner, git_info.repo, config.limit, 1)
        ),
        function(mention)
            return format.item(config, trigger_char, mention)
        end,
        function(parsed)
            if parsed["mentionableUsers"] then
                return parsed["mentionableUsers"]
            end
            return parsed
        end
    )
    job:start()

    return true
end

return GitHub
