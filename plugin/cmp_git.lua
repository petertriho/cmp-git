if vim.g.loaded_cmp_git then
    return
end
vim.g.loaded_cmp_git = true

-- The command loads its module when it runs, so that startup loads no cmp-git module
vim.api.nvim_create_user_command("CmpGitClearCache", function(opts)
    require("cmp_git.commands").clear_cache(opts.bang)
end, {
    bang = true,
    desc = "Clear the cmp-git cache of the remote of the current buffer, or with ! of all remotes",
})
