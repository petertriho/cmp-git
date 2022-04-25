local utils = require("cmp_git.utils")

local M = {
    git = {
        commits = function(commit) -- nil, "sha", "title", "description", "author_name", "author_email", "commit_timestamp", or custom function
            return string.format("%010d", commit.diff)
        end,
    },
    github = {
        issues = function(issue) -- nil, "number", "title", "body", or custom function
            return string.format("%010d", os.difftime(os.time(), utils.parse_github_date(issue.updatedAt)))
        end,
        mentions = nil, -- nil, "login", or custom function
        pull_requests = function(pr) -- nil, "number", "title", "body", or custom function
            return string.format("%010d", os.difftime(os.time(), utils.parse_github_date(pr.updatedAt)))
        end,
    },
    gitlab = {
        issues = function(issue) -- nil, "iid", "title", "description", or custom function
            return string.format("%010d", os.difftime(os.time(), utils.parse_gitlab_date(issue.updated_at)))
        end,
        mentions = nil, -- nil, "username", "name", or custom function
        merge_requests = function(mr) -- nil, "iid", "title", "description", or custom function
            return string.format("%010d", os.difftime(os.time(), utils.parse_gitlab_date(mr.updated_at)))
        end,
    },
}

M.get_sort_text = function(config_val, item)
    if type(config_val) == "function" then
        return config_val(item)
    elseif type(config_val) == "string" then
        return item[config_val]
    end

    return nil
end

return M
