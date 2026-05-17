local format = require("cmp_git.format")

local M = {}

local function github_url(git_host, path)
    if git_host == "github.com" then
        return string.format("https://api.github.com/%s", path)
    end

    return string.format("https://%s/api/v3/%s", git_host, path)
end

local function env()
    return {
        GITHUB_API_TOKEN = vim.fn.getenv("GITHUB_API_TOKEN"),
        CLICOLOR = 0,
    }
end

local function curl_args(curl_url)
    local args = {
        "-s",
        "-L",
        "-H",
        "'Accept: application/vnd.github.v3+json'",
        curl_url,
    }

    if vim.fn.exists("$GITHUB_API_TOKEN") == 1 then
        local token = vim.fn.getenv("GITHUB_API_TOKEN")
        table.insert(args, "-H")
        table.insert(args, string.format("Authorization: token %s", token))
    end

    return args
end

local function normalize_body(item)
    if item.body ~= vim.NIL then
        item.body = string.gsub(item.body or "", "\r", "")
    else
        item.body = ""
    end

    if not item.updatedAt then
        item.updatedAt = item.updated_at
    end
end

function M.issues_request(git_info, trigger_char, config)
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

    return {
        commands = {
            { exec = "gh", args = gh_args, env = env() },
            { exec = "curl", args = curl_args(github_url(git_info.host, curl_path)) },
        },
        handle_item = function(issue)
            normalize_body(issue)
            return format.item(config, trigger_char, issue)
        end,
    }
end

function M.change_requests_request(git_info, trigger_char, config)
    return {
        commands = {
            {
                exec = "gh",
                args = {
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
                env = env(),
            },
            {
                exec = "curl",
                args = curl_args(
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
                    )
                ),
            },
        },
        handle_item = function(pr)
            normalize_body(pr)
            return format.item(config, trigger_char, pr)
        end,
    }
end

function M.mentions_preflight_request(git_info)
    return {
        commands = {
            {
                exec = "gh",
                args = {
                    "api",
                    string.format("repos/%s/%s/collaborators/testing/permission", git_info.owner, git_info.repo),
                    "--hostname",
                    git_info.host,
                },
                env = env(),
            },
            {
                exec = "curl",
                args = curl_args(
                    github_url(
                        git_info.host,
                        string.format("repos/%s/%s/collaborators/testing/permission", git_info.owner, git_info.repo)
                    )
                ),
            },
        },
        handle_result = function(result)
            local ok, parsed = pcall(vim.json.decode, result)
            local member_type = "contributors"
            if ok then
                member_type = (parsed.status ~= "403" and parsed.status ~= "401") and "collaborators" or "contributors"
            end
            return { member_type = member_type }
        end,
    }
end

function M.mentions_request(git_info, trigger_char, config, opts)
    local member_type = opts.context and opts.context.member_type or "contributors"
    return {
        commands = {
            {
                exec = "gh",
                args = {
                    "api",
                    string.format(
                        "repos/%s/%s/%s?per_page=%d&page=%d",
                        git_info.owner,
                        git_info.repo,
                        member_type,
                        opts.page_size,
                        opts.page
                    ),
                    "--hostname",
                    git_info.host,
                },
                env = env(),
            },
            {
                exec = "curl",
                args = curl_args(
                    github_url(
                        git_info.host,
                        string.format(
                            "%s/%s/%s?per_page=%d&page=%d",
                            git_info.owner,
                            git_info.repo,
                            member_type,
                            opts.page_size,
                            opts.page
                        )
                    )
                ),
            },
        },
        handle_item = function(mention)
            return format.item(config, trigger_char, mention)
        end,
        handle_parsed = function(parsed)
            if parsed["mentionableUsers"] then
                return parsed["mentionableUsers"]
            end
            return parsed
        end,
    }
end

return M
