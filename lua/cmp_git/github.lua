local Job = require("plenary.job")
local utils = require("cmp_git.utils")
local sort = require("cmp_git.sort")

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

    self.config = vim.tbl_extend("force", require("cmp_git.config").github, overrides or {})

    return self
end

local get_command = function(callback, gh_command, curl_url, handle_item)
    local command = nil

    if false and vim.fn.executable("gh") == 1 and gh_command then
        command = gh_command
    elseif vim.fn.executable("curl") == 1 and curl_url then
        command = {
            "curl",
            "-s",
            "-H",
            "'Accept: application/vnd.github.v3+json'",
            curl_url,
        }

        if vim.fn.exists("$GITHUB_API_TOKEN") == 1 then
            local token = vim.fn.getenv("GITHUB_API_TOKEN")
            local authorization_header = string.format("Authorization: token %s", token)
            table.insert(command, "-H")
            table.insert(command, authorization_header)
        end
    else
        vim.notify("gh and curl executables not found!")
        return
    end

    command.cwd = utils.get_cwd()
    command.on_exit = vim.schedule_wrap(function(job)
        local result = table.concat(job:result(), "")

        local items = utils.handle_response(result, handle_item)

        callback({ items = items, isIncomplete = false })
    end)

    return command
end

local get_pull_requests_job = function(callback, git_info, trigger_char, config)
    return Job:new(get_command(
        callback,
        {
            "gh",
            "pr",
            "list",
            "--repo",
            string.format("%s/%s", git_info.owner, git_info.repo),
            "--limit",
            config.limit,
            "--state",
            config.state,
            "--json",
            "title,number,body,updatedAt",
        },
        string.format(
            "https://api.github.com/repos/%s/%s/pulls?state=%s&per_page=%d&page=%d",
            git_info.owner,
            git_info.repo,
            config.state,
            config.limit,
            1
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

            return {
                label = string.format("#%s: %s", pr.number, pr.title),
                insertText = string.format("#%s", pr.number),
                filterText = config.filter_fn(trigger_char, pr),
                sortText = sort.get_sort_text(config.sort_by, pr),
                documentation = {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", pr.title, pr.body),
                },
                data = pr,
            }
        end
    ))
end

local get_issues_job = function(callback, git_info, trigger_char, config)
    return Job:new(get_command(
        callback,
        {
            "gh",
            "issue",
            "list",
            "--repo",
            string.format("%s/%s", git_info.owner, git_info.repo),
            "--limit",
            config.limit,
            "--state",
            config.state,
            "--json",
            "title,number,body,updatedAt",
        },
        string.format(
            "https://api.github.com/repos/%s/%s/issues?filter=%s&state=%s&per_page=%d&page=%d",
            git_info.owner,
            git_info.repo,
            config.filter,
            config.state,
            config.limit,
            1
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

            return {
                label = string.format("#%s: %s", issue.number, issue.title),
                insertText = string.format("#%s", issue.number),
                filterText = config.filter_fn(trigger_char, issue),
                sortText = sort.get_sort_text(config.sort_by, issue),
                documentation = {
                    kind = "markdown",
                    value = string.format("# %s\n\n%s", issue.title, issue.body),
                },
            }
        end
    ))
end

local _get_issues = function(self, callback, git_info, trigger_char, config)
    local bufnr = vim.api.nvim_get_current_buf()

    if self.cache.issues[bufnr] then
        callback({ items = self.cache.issues[bufnr], isIncomplete = false })
        return nil
    end

    config = vim.tbl_extend("force", self.config.issues, config or {})

    local issues_job = get_issues_job(function(args)
        self.cache.issues[bufnr] = args.items
        callback(args)
    end, git_info, trigger_char, config)

    return issues_job
end

local _get_pull_requests = function(self, callback, git_info, trigger_char, config)
    local bufnr = vim.api.nvim_get_current_buf()

    if self.cache.pull_requests[bufnr] then
        callback({ items = self.cache.pull_requests[bufnr], isIncomplete = false })
        return nil
    end

    config = vim.tbl_extend("force", self.config.pull_requests, config or {})

    local pr_job = get_pull_requests_job(function(args)
        self.cache.pull_requests[bufnr] = args.items
        callback(args)
    end, git_info, trigger_char, config)

    return pr_job
end

function GitHub:get_issues(callback, git_info, trigger_char, config)
    if git_info.host ~= "github.com" or git_info.owner == nil or git_info.repo == nil then
        return false
    end

    local job = _get_issues(self, callback, git_info, trigger_char, config)

    if job then
        job:start()
    end

    return true
end

function GitHub:get_pull_requests(callback, git_info, trigger_char, config)
    if git_info.host ~= "github.com" or git_info.owner == nil or git_info.repo == nil then
        return false
    end

    local job = _get_pull_requests(self, callback, git_info, trigger_char, config)

    if job then
        job:start()
    end

    return true
end

function GitHub:get_issues_and_prs(callback, git_info, trigger_char, config)
    local bufnr = vim.api.nvim_get_current_buf()

    if self.cache.issues[bufnr] and self.cache.pull_requests[bufnr] then
        local issues = self.cache.issues[bufnr]
        local prs = self.cache.pull_requests[bufnr]

        local merged = vim.list_extend(issues, prs)

        callback({ items = merged, isIncomplete = false })
    else
        if git_info.host ~= "github.com" then
            vim.notify("Can't fetch Github issues or pull requests, not a github repository")
            return false
        elseif git_info.owner == nil and git_info.repo == nil then
            vim.notify("Can't figure out git repository or owner")
            return false
        end

        local issue_config = config and config.issues or {}
        local pr_config = config and config.pull_requests or {}
        local issues = {}

        local issues_job = _get_issues(self, function(args)
            issues = args.items
            self.cache.issues[bufnr] = args.items
        end, git_info, trigger_char, issue_config)

        local pull_requests_job = _get_pull_requests(self, function(args)
            local prs = args.items
            self.cache.pull_requests[bufnr] = args.items

            local merged = vim.list_extend(issues, prs)

            callback({ items = merged, isIncomplete = false })
        end, git_info, trigger_char, pr_config)

        Job.chain(issues_job, pull_requests_job)
    end

    return true
end

function GitHub:get_mentions(callback, git_info, trigger_char, config)
    if git_info.host ~= "github.com" or git_info.owner == nil or git_info.repo == nil then
        return false
    end

    local bufnr = vim.api.nvim_get_current_buf()

    if self.cache.mentions[bufnr] then
        callback({ items = self.cache.mentions[bufnr], isIncomplete = false })
        return true
    end

    config = vim.tbl_extend("force", self.config.mentions, config or {})

    Job
        :new(get_command(
            function(args)
                callback(args)
                self.cache.mentions[bufnr] = args.items
            end,
            nil,
            string.format(
                "https://api.github.com/repos/%s/%s/contributors?per_page=%d&page=%d",
                git_info.owner,
                git_info.repo,
                config.limit,
                1
            ),
            function(mention)
                return {
                    label = string.format("@%s", mention.login),
                    insertText = string.format("@%s", mention.number),
                    sortText = sort.get_sort_text(config.sort_by, mention),
                    data = mention,
                }
            end
        ))
        :start()

    return true
end

return GitHub
