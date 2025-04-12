local Job = require("plenary.job")
local utils = require("cmp_git.utils")
local log = require("cmp_git.log")
local format = require("cmp_git.format")

---@class cmp_git.AsyncItemList
---@field in_progress boolean
---@field items cmp_git.CompletionItem[]

---@class cmp_git.Source.GitHub
local GitHub = {
    cache = {
        ---@type table<integer, cmp_git.CompletionItem[]>
        issues = {},
        ---@type table<integer, cmp_git.AsyncItemList>
        mentions = {},
        ---@type table<integer, cmp_git.CompletionItem[]>
        pull_requests = {},
    },
    ---@type cmp_git.Config.GitHub
    ---@diagnostic disable-next-line: missing-fields
    config = {},
}

---@param overrides cmp_git.Config.GitHub
function GitHub.new(overrides)
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
---@param git_host string
---@param path string
local function github_url(git_host, path)
    if git_host == "github.com" then
        return string.format("https://api.github.com/%s", path)
    else
        return string.format("https://%s/api/v3/%s", git_host, path)
    end
end

---@return table<string, string|number>
local function get_gh_env()
    return {
        GITHUB_API_TOKEN = vim.fn.getenv("GITHUB_API_TOKEN"),
        CLICOLOR = 0, -- disables color output to avoid parsing errors
    }
end

---@return string[]
local function get_curl_args(curl_url)
    local curl_args = {
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

    return curl_args
end

---Used for fetching non-list data from GitHub
---@param callback fun(result: string, success: boolean): nil
---@param gh_args string[]
---@param curl_url string
---@return nil
local function fetch_data(callback, gh_args, curl_url)
    local gh_job = utils.build_simple_job("gh", gh_args, get_gh_env(), callback)

    local curl_job = utils.build_simple_job("curl", get_curl_args(curl_url), nil, callback)

    utils.chain_fallback(gh_job, curl_job):start()
end

---@generic TItem
---@param callback fun(list: cmp_git.CompletionList)
---@param gh_args string[]
---@param curl_url string
---@param handle_item fun(item: TItem): cmp_git.CompletionItem
---@param handle_parsed? fun(parsed: any): TItem[]
local function get_items(callback, gh_args, curl_url, handle_item, handle_parsed)
    local gh_job = utils.build_job("gh", gh_args, get_gh_env(), callback, handle_item, handle_parsed)

    local curl_job = utils.build_job("curl", get_curl_args(curl_url), nil, callback, handle_item, handle_parsed)

    return utils.chain_fallback(gh_job, curl_job)
end

---Reference: https://docs.github.com/en/rest/pulls/pulls?apiVersion=2022-11-28#list-pull-requests
---@class cmp_git.GitHub.PullRequest
---@field number integer
---@field title string
---@field body string
---@field updatedAt string

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@param config cmp_git.Config.GitHub.PullRequest
local function get_pull_requests_job(callback, git_info, trigger_char, config)
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

---Reference: https://docs.github.com/en/rest/issues/issues?apiVersion=2022-11-28#list-repository-issues
---@class cmp_git.GitHub.Issue
---@field number integer
---@field title string
---@field body string
---@field updatedAt string
---@field updated_at string

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@param config cmp_git.Config.GitHub.Issue
local function get_issues_job(callback, git_info, trigger_char, config)
    local gh_args = {
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
    }
    local curl_path = string.format(
        "repos/%s/%s/issues?state=%s&per_page=%d&page=%d",
        git_info.owner,
        git_info.repo,
        config.state,
        config.limit,
        1
    )
    if config.filter == "mentioned" then
        gh_args = vim.list_extend(gh_args, { "--mention", "@me" })
        curl_path = string.format("%s&mentioned=@me", curl_path)
    elseif config.filter == "assigned" then
        gh_args = vim.list_extend(gh_args, { "--assignee", "@me" })
        curl_path = string.format("%s&assignee=@me", curl_path)
    elseif config.filter == "created" then
        gh_args = vim.list_extend(gh_args, { "--author", "@me" })
        curl_path = string.format("%s&creator=@me", curl_path)
    end
    return get_items(
        callback,
        gh_args,
        github_url(git_info.host, curl_path),
        function(issue) ---@param issue cmp_git.GitHub.Issue
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

---@param git_info cmp_git.GitInfo
local function use_gh_default_repo_if_set(git_info)
    local gh_default_repo = vim.fn.system({ "gh", "repo", "set-default", "--view" })
    if vim.v.shell_error ~= 0 then
        return git_info
    end
    local owner, repo = string.match(vim.fn.trim(gh_default_repo), "^(.+)/(.+)$")
    if owner ~= nil and repo ~= nil then
        git_info.owner = owner
        git_info.repo = repo
    end
    return git_info
end

---@param git_info cmp_git.GitInfo
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

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
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

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
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

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
function GitHub:get_issues(callback, git_info, trigger_char)
    if not GitHub:is_valid_host(git_info) then
        return false
    end

    git_info = use_gh_default_repo_if_set(git_info)

    local job = self:_get_issues(callback, git_info, trigger_char)

    if job then
        job:start()
    end

    return true
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
function GitHub:get_pull_requests(callback, git_info, trigger_char)
    if not GitHub:is_valid_host(git_info) then
        return false
    end

    git_info = use_gh_default_repo_if_set(git_info)

    local job = self:_get_pull_requests(callback, git_info, trigger_char)

    if job then
        job:start()
    end

    return true
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
function GitHub:get_issues_and_prs(callback, git_info, trigger_char)
    if not GitHub:is_valid_host(git_info) then
        return false
    end

    git_info = use_gh_default_repo_if_set(git_info)

    local bufnr = vim.api.nvim_get_current_buf()

    if self.cache.issues[bufnr] and self.cache.pull_requests[bufnr] then
        local issues = self.cache.issues[bufnr]
        local prs = self.cache.pull_requests[bufnr]

        ---@type cmp_git.CompletionItem[]
        local items = {}
        items = vim.list_extend(items, issues)
        items = vim.list_extend(items, prs)

        log.fmt_debug("Got %d issues and prs from cache", #items)
        callback({ items = issues, isIncomplete = false })
    else
        ---@type cmp_git.CompletionItem[]
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

---Reference: https://docs.github.com/en/rest/repos/repos?apiVersion=2022-11-28#list-repository-contributors
---@class cmp_git.GitHub.Mention
---@field login string

---@param callback fun(list: cmp_git.CompletionList): nil
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@param member_type 'collaborators' | 'contributors'
function GitHub:_get_mentions(callback, git_info, trigger_char, member_type)
    local config = self.config.mentions
    local bufnr = vim.api.nvim_get_current_buf()

    ---@param page integer
    local function fetch_mentions(page)
        local page_size = math.min(config.limit - #self.cache.mentions[bufnr].items, 100)
        local job = get_items(
            function(args)
                local mentionsCache = self.cache.mentions[bufnr]
                vim.list_extend(mentionsCache.items, args.items)
                -- Go until there are no more items or we've reached the limit
                mentionsCache.in_progress = #args.items ~= 0 and #mentionsCache.items < config.limit
                if mentionsCache.in_progress then
                    fetch_mentions(page + 1)
                end
                -- Do not wait for all pages to be fetched to give back results
                callback({ items = mentionsCache.items, isIncomplete = mentionsCache.in_progress })
            end,
            {
                "api",
                string.format(
                    "repos/%s/%s/%s?per_page=%d&page=%d",
                    git_info.owner,
                    git_info.repo,
                    member_type,
                    page_size,
                    page
                ),
                "--hostname",
                git_info.host,
            },
            github_url(
                git_info.host,
                string.format(
                    "%s/%s/%s?per_page=%d&page=%d",
                    git_info.owner,
                    git_info.repo,
                    member_type,
                    page_size,
                    page
                )
            ),
            ---@param mention cmp_git.GitHub.Mention
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
    end

    fetch_mentions(1)
end

---@param callback fun(list: cmp_git.CompletionList)
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@return boolean
function GitHub:get_mentions(callback, git_info, trigger_char)
    if not GitHub:is_valid_host(git_info) then
        return false
    end

    local bufnr = vim.api.nvim_get_current_buf()

    if self.cache.mentions[bufnr] then
        local mentionsCache = self.cache.mentions[bufnr]
        -- Immediately return in progress results to prevent multiple concurrent requests
        callback({ items = mentionsCache.items, isIncomplete = mentionsCache.in_progress })
        return true
    end

    self.cache.mentions[bufnr] = { items = {}, in_progress = true }
    fetch_data(
        function(result)
            local ok, parsed = pcall(vim.json.decode, result)
            local member_type = "contributors"
            if ok then
                -- If the user has permission to see the collaborators, use the collaborators endpoint
                -- Note that "404" is considered a success, since the dummy user likely doesn't exist
                member_type = (parsed.status ~= "403" and parsed.status ~= "401") and "collaborators" or "contributors"
            end
            self:_get_mentions(callback, git_info, trigger_char, member_type)
        end,
        {
            "api",
            -- Using a dummy username to check if the user has permission to see the collaborators
            string.format("repos/%s/%s/collaborators/testing/permission", git_info.owner, git_info.repo),
            "--hostname",
            git_info.host,
        },
        github_url(
            git_info.host,
            string.format("repos/%s/%s/collaborators/testing/permission", git_info.owner, git_info.repo)
        )
    )

    return true
end

return GitHub
