local M = {}

M.get_git_info = function()
    local remote_origin_url = vim.fn.system("git config --get remote.origin.url")
    local clean_remote_origin_url = string.gsub(remote_origin_url, "%.git", "")
    local host, owner, repo

    local is_gitlab_repo = string.find(remote_origin_url, "gitlab")
    local is_github_repo = string.find(remote_origin_url, "github")

    if is_github_repo then
        host, owner, repo = string.match(clean_remote_origin_url, "(github)%.com[/:](.+)/(.+)$")
    elseif is_gitlab_repo then
        host, owner, repo = string.match(clean_remote_origin_url, "(gitlab).*[/:](.+)/(.+)$")
    end

    return { host = host, owner = owner, repo = repo }
end

return M
