local helpers = require("tests.helpers")
local repository = require("cmp_git.repository")

local eq = helpers.eq

local T = helpers.new_set()

local function require_git()
    if vim.fn.executable("git") ~= 1 then
        helpers.skip("git is not installed")
    end
end

---@return boolean
local function is_git_repo()
    local result
    repository.is_git_repo(function(value)
        result = value
    end)
    helpers.wait_for(function()
        return result ~= nil
    end, "is_git_repo calls back")
    return result
end

---@param opts? { remotes?: string[], enableRemoteUrlRewrites?: boolean, ssh_aliases?: table<string, string> }
---@return cmp_git.RepositoryMetadata
local function discover(opts)
    opts = opts or {}
    local metadata
    repository.discover(opts.remotes or { "upstream", "origin" }, {
        enableRemoteUrlRewrites = opts.enableRemoteUrlRewrites or false,
        ssh_aliases = opts.ssh_aliases or {},
        on_complete = function(result)
            metadata = result
        end,
    })
    helpers.wait_for(function()
        return metadata ~= nil
    end, "discover calls back")
    return metadata
end

---Make a buffer with the name `path` current, as if the file was open.
---@param path string
---@param filetype? string
local function edit(path, filetype)
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.bo[bufnr].swapfile = false
    vim.api.nvim_buf_set_name(bufnr, path)
    vim.api.nvim_set_current_buf(bufnr)
    if filetype then
        vim.bo[bufnr].filetype = filetype
    end
end

T["is_git_repo_in_work_tree"] = function()
    require_git()
    local repo = helpers.git_repo()
    vim.fn.mkdir(repo.dir .. "/sub", "p")
    vim.fn.chdir(repo.dir .. "/sub")

    eq(is_git_repo(), true, "a subdirectory of a work tree is in a repository")
end

T["is_git_repo_outside_repository"] = function()
    require_git()
    vim.fn.chdir(helpers.tempdir())

    eq(is_git_repo(), false, "a directory outside a repository")
end

T["is_git_repo_inside_git_dir"] = function()
    require_git()
    local repo = helpers.git_repo()
    vim.fn.chdir(repo.dir .. "/.git")

    eq(is_git_repo(), true, "the .git directory is in a repository")
end

T["is_git_repo_uses_buffer_directory"] = function()
    require_git()
    local repo = helpers.git_repo()
    vim.fn.chdir(helpers.tempdir())
    edit(repo.dir .. "/notes.md", "markdown")

    eq(is_git_repo(), true, "the buffer directory is checked before the cwd")
end

T["is_git_repo_falls_back_to_cwd"] = function()
    require_git()
    local repo = helpers.git_repo()
    edit(helpers.tempdir() .. "/notes.md", "markdown")
    vim.fn.chdir(repo.dir)

    eq(is_git_repo(), true, "the cwd is checked when the buffer directory is not in a repository")
end

T["discover_first_remote_matches"] = function()
    require_git()
    local repo = helpers.git_repo({
        remotes = {
            { "origin", "git@github.com:fork-owner/repo.git" },
            { "upstream", "https://github.com/owner/repo.git" },
        },
    })
    vim.fn.chdir(repo.dir)

    eq(discover(), { host = "github.com", owner = "owner", repo = "repo" }, "the first configured remote wins")
end

T["discover_falls_back_to_next_remote"] = function()
    require_git()
    local repo = helpers.git_repo({ remotes = { { "origin", "git@gitlab.com:group/project.git" } } })
    vim.fn.chdir(repo.dir)

    eq(discover(), { host = "gitlab.com", owner = "group", repo = "project" }, "a missing remote falls back")
end

T["discover_skips_unparsable_remote"] = function()
    require_git()
    local repo = helpers.git_repo({
        remotes = {
            { "upstream", "/srv/git/project.git" },
            { "origin", "https://github.com/owner/repo.git" },
        },
    })
    vim.fn.chdir(repo.dir)

    eq(discover(), { host = "github.com", owner = "owner", repo = "repo" }, "a local path remote falls back")
end

T["discover_without_matching_remote"] = function()
    require_git()
    local repo = helpers.git_repo({ remotes = { { "fork", "https://github.com/owner/repo.git" } } })
    vim.fn.chdir(repo.dir)

    eq(discover().host, nil, "no configured remote, no host")
end

T["discover_with_remote_url_rewrites"] = function()
    require_git()
    local repo = helpers.git_repo({ remotes = { { "origin", "work:owner/repo" } } })
    repo.git("config", "url.https://github.example.com/.insteadOf", "work:")
    vim.fn.chdir(repo.dir)

    eq(discover().host, "work", "the configured URL without rewrites")
    eq(
        discover({ enableRemoteUrlRewrites = true }),
        { host = "github.example.com", owner = "owner", repo = "repo" },
        "the rewritten URL"
    )
end

T["discover_with_ssh_aliases"] = function()
    require_git()
    local repo = helpers.git_repo({ remotes = { { "origin", "git@github-work:owner/repo.git" } } })
    vim.fn.chdir(repo.dir)

    eq(discover().host, "github-work", "the alias without ssh_aliases")
    eq(
        discover({ ssh_aliases = { ["github-work"] = "github.com" } }),
        { host = "github.com", owner = "owner", repo = "repo" },
        "the aliased host"
    )
end

T["discover_octo_buffer"] = function()
    local octo_config = { values = { github_hostname = "" } }
    helpers.stub(package.loaded, "octo.config", octo_config)
    vim.fn.chdir(helpers.tempdir())
    edit("octo://owner/repo/issue/12", "octo")

    eq(discover(), { host = "github.com", owner = "owner", repo = "repo" }, "octo buffer on github.com")

    octo_config.values.github_hostname = "github.example.com"
    eq(discover().host, "github.example.com", "octo buffer on an enterprise host")
end

T["discover_falls_back_to_cwd"] = function()
    require_git()
    local repo = helpers.git_repo({ remotes = { { "origin", "https://github.com/owner/repo.git" } } })
    edit(helpers.tempdir() .. "/notes.md", "markdown")
    vim.fn.chdir(repo.dir)

    eq(discover(), { host = "github.com", owner = "owner", repo = "repo" }, "the cwd repository")
end

T["discover_uses_buffer_directory"] = function()
    require_git()
    local buffer_repo = helpers.git_repo({ remotes = { { "origin", "https://github.com/buffer/repo.git" } } })
    local cwd_repo = helpers.git_repo({ remotes = { { "origin", "https://github.com/cwd/repo.git" } } })
    vim.fn.chdir(cwd_repo.dir)
    edit(buffer_repo.dir .. "/notes.md", "markdown")

    eq(discover().owner, "buffer", "the buffer repository wins over the cwd repository")
end

T["discover_inside_git_dir"] = function()
    require_git()
    local repo = helpers.git_repo({ remotes = { { "origin", "https://github.com/owner/repo.git" } } })
    vim.fn.chdir(helpers.tempdir())
    edit(repo.dir .. "/.git/COMMIT_EDITMSG", "gitcommit")

    eq(discover(), { host = "github.com", owner = "owner", repo = "repo" }, "a commit message in .git")
end

return T
