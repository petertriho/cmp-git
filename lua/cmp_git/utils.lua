local M = {}

M.get_git_info = function()
    local remote_origin_url = vim.fn.system("git config --get remote.origin.url")
    local host, owner, repo

    host, owner, repo = string.match(remote_origin_url, "(github)%.com[/:](.+)/(.+)%.git")

    return { host = host, owner = owner, repo = repo }
end

return M
