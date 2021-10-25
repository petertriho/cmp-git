local M = {}

M.get_gitlab_info = function(url)
    return string.match(url, "(gitlab).*[/:](.+)/(.+)%.git")
end

M.get_github_info = function(url)
    return string.match(url, "(github)%.com[/:](.+)/(.+)%.git")
end

M.get_git_info = function()
    local remote_origin_url = vim.fn.system("git config --get remote.origin.url")
    local host, owner, repo

    local is_gitlab_repo = string.find(remote_origin_url, "gitlab")
    local is_github_repo = string.find(remote_origin_url, "github")

    if is_github_repo then
        host, owner, repo = M.get_github_info(remote_origin_url)
    elseif is_gitlab_repo then
        host, owner, repo = M.get_gitlab_info(remote_origin_url)
    end

    return { host = host, owner = owner, repo = repo }
end

return M
