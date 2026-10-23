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

---@class tests.DiscoverOptions
---@field remotes? string[]
---@field enableRemoteUrlRewrites? boolean
---@field ssh_aliases? table<string, string>
---@field hosts? string[]

---@param opts? tests.DiscoverOptions
---@return cmp_git.RepositoryMetadata
local function discover(opts)
    opts = opts or {}
    local metadata
    repository.discover(opts.remotes or { "upstream", "origin" }, {
        enableRemoteUrlRewrites = opts.enableRemoteUrlRewrites or false,
        ssh_aliases = opts.ssh_aliases or {},
        hosts = opts.hosts,
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

---Make a new buffer without a name current. Discovery caches its result for each buffer, so this keeps the result of
---an earlier case for the same directory out of the case.
local function new_buffer()
    vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(false, true))
end

---Record the commands that start a process, until the end of the case.
---@return string[][] commands
local function record_processes()
    local commands = {}
    local system = vim.system
    helpers.stub(vim, "system", function(cmd, ...)
        table.insert(commands, cmd)
        return system(cmd, ...)
    end)
    return commands
end

---@param commands string[][]
---@return string[] lines Each command as one line, to show in a failure.
local function command_lines(commands)
    return vim.tbl_map(function(cmd)
        return table.concat(cmd, " ")
    end, commands)
end

T["is_git_repo_in_work_tree"] = function()
    require_git()
    local repo = helpers.git_repo()
    vim.fn.mkdir(repo.dir .. "/sub", "p")
    new_buffer()
    vim.fn.chdir(repo.dir .. "/sub")

    eq(is_git_repo(), true, "a subdirectory of a work tree is in a repository")
end

T["is_git_repo_outside_repository"] = function()
    require_git()
    new_buffer()
    vim.fn.chdir(helpers.tempdir())

    eq(is_git_repo(), false, "a directory outside a repository")
end

T["is_git_repo_inside_git_dir"] = function()
    require_git()
    local repo = helpers.git_repo()
    new_buffer()
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

T["get_cwd_buffer_in_missing_directory"] = function()
    require_git()
    local repo = helpers.git_repo({ remotes = { { "origin", "https://github.com/owner/repo.git" } } })
    vim.fn.chdir(repo.dir)
    edit(helpers.tempdir() .. "/new/dir/notes.md", "markdown")

    eq(repository.get_cwd(), repo.dir, "a directory that does not exist falls back to the cwd")
    eq(is_git_repo(), true, "the cwd repository")
    eq(discover(), { host = "github.com", owner = "owner", repo = "repo", scheme = "https" }, "the cwd repository")
end

---Run `git rev-parse --show-toplevel` as the completion commands run.
---@return string? toplevel
local function command_toplevel()
    local result
    local job = require("cmp_git.command").build(
        { exec = "git", args = { "rev-parse", "--show-toplevel" } },
        function(stdout)
            result = vim.trim(stdout)
        end
    )
    helpers.not_nil(job, "git command"):start()
    helpers.wait_for(function()
        return result ~= nil
    end, "the command calls back")
    return result
end

T["get_cwd_is_the_repository_directory"] = function()
    require_git()
    local repo = helpers.git_repo()
    edit(helpers.tempdir() .. "/notes.md", "markdown")
    vim.fn.chdir(repo.dir)

    eq(is_git_repo(), true, "the cwd repository")
    eq(repository.get_cwd(), repo.dir, "the directory where discovery found the repository")
    eq(command_toplevel(), repo.dir, "the commands run in the repository")
end

T["get_cwd_is_the_buffer_repository_directory"] = function()
    require_git()
    local repo = helpers.git_repo()
    local other = helpers.git_repo()
    vim.fn.chdir(other.dir)
    edit(repo.dir .. "/notes.md", "markdown")

    eq(is_git_repo(), true, "the buffer repository")
    eq(repository.get_cwd(), repo.dir, "the buffer directory")
    eq(command_toplevel(), repo.dir, "the commands run in the buffer repository")
end

T["discover_first_remote_matches"] = function()
    require_git()
    local repo = helpers.git_repo({
        remotes = {
            { "origin", "git@github.com:fork-owner/repo.git" },
            { "upstream", "https://github.com/owner/repo.git" },
        },
    })
    new_buffer()
    vim.fn.chdir(repo.dir)

    eq(
        discover(),
        { host = "github.com", owner = "owner", repo = "repo", scheme = "https" },
        "the first configured remote wins"
    )
end

T["discover_falls_back_to_next_remote"] = function()
    require_git()
    local repo = helpers.git_repo({ remotes = { { "origin", "git@gitlab.com:group/project.git" } } })
    new_buffer()
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
    new_buffer()
    vim.fn.chdir(repo.dir)

    eq(
        discover(),
        { host = "github.com", owner = "owner", repo = "repo", scheme = "https" },
        "a local path remote falls back"
    )
end

T["discover_without_matching_remote"] = function()
    require_git()
    local repo = helpers.git_repo({ remotes = { { "fork", "https://github.com/owner/repo.git" } } })
    new_buffer()
    vim.fn.chdir(repo.dir)

    eq(discover().host, nil, "no configured remote, no host")
end

T["discover_with_remote_url_rewrites"] = function()
    require_git()
    local repo = helpers.git_repo({ remotes = { { "origin", "work:owner/repo" } } })
    repo.git("config", "url.https://github.example.com/.insteadOf", "work:")
    new_buffer()
    vim.fn.chdir(repo.dir)

    eq(discover().host, "work", "the configured URL without rewrites")
    eq(
        discover({ enableRemoteUrlRewrites = true }),
        { host = "github.example.com", owner = "owner", repo = "repo", scheme = "https" },
        "the rewritten URL"
    )
end

T["discover_with_ssh_aliases"] = function()
    require_git()
    local repo = helpers.git_repo({ remotes = { { "origin", "git@github-work:owner/repo.git" } } })
    new_buffer()
    vim.fn.chdir(repo.dir)

    eq(discover().host, "github-work", "the alias without ssh_aliases")
    eq(
        discover({ ssh_aliases = { ["github-work"] = "github.com" } }),
        { host = "github.com", owner = "owner", repo = "repo" },
        "the aliased host"
    )
end

T["discover_with_ssh_aliases_as_plain_strings"] = function()
    require_git()
    local repo = helpers.git_repo({ remotes = { { "origin", "git@gh+work:owner/repo.git" } } })
    new_buffer()
    vim.fn.chdir(repo.dir)

    eq(discover({ ssh_aliases = { ["gh+work"] = "github.com" } }).host, "github.com", "an alias with a +")
    eq(discover({ ssh_aliases = { ["gh+work"] = "git%1.example.com" } }).host, "git%1.example.com", "a host with a %")
    eq(discover({ ssh_aliases = { ["gh.work"] = "github.com" } }).host, "gh+work", "a . in an alias is not a pattern")
end

---Make the cwd a repository with the remote `origin`, in a new buffer.
---@param url string
local function with_origin(url)
    require_git()
    local repo = helpers.git_repo({ remotes = { { "origin", url } } })
    new_buffer()
    vim.fn.chdir(repo.dir)
end

T["discover_with_host_prefix"] = function()
    with_origin("https://example.com/gitlab/group/repo.git")
    local hosts = { "github.com", "gitlab.com", "example.com/gitlab" }

    eq(
        discover(),
        { host = "example.com", owner = "gitlab/group", repo = "repo", scheme = "https" },
        "the URL without hosts"
    )
    eq(
        discover({ hosts = hosts }),
        { host = "example.com/gitlab", owner = "group", repo = "repo", scheme = "https" },
        "the prefix moves from the owner to the host"
    )
    eq(discover().owner, "gitlab/group", "the prefix does not change the cache")
end

T["discover_with_host_prefix_of_several_segments"] = function()
    with_origin("https://example.com/tools/gitlab/group/repo.git")

    eq(
        discover({ hosts = { "example.com/tools/gitlab" } }),
        { host = "example.com/tools/gitlab", owner = "group", repo = "repo", scheme = "https" },
        "a prefix with two segments"
    )
end

T["discover_with_longest_host_prefix"] = function()
    with_origin("https://example.com/gitlab/internal/group/repo.git")
    local expected = { host = "example.com/gitlab/internal", owner = "group", repo = "repo", scheme = "https" }

    eq(
        discover({ hosts = { "example.com/gitlab", "example.com/gitlab/internal" } }),
        expected,
        "the longer prefix last"
    )
    eq(
        discover({ hosts = { "example.com/gitlab/internal", "example.com/gitlab" } }),
        expected,
        "the longer prefix first"
    )
end

T["discover_with_host_prefix_and_subgroups"] = function()
    with_origin("https://example.com/gitlab/group/sub/repo.git")

    eq(
        discover({ hosts = { "example.com/gitlab" } }),
        { host = "example.com/gitlab", owner = "group/sub", repo = "repo", scheme = "https" },
        "the subgroups stay in the owner"
    )
end

T["discover_with_host_prefix_and_port"] = function()
    with_origin("https://example.com:8443/gitlab/group/repo.git")

    eq(
        discover({ hosts = { "example.com/gitlab", "example.com:8443/gitlab" } }),
        { host = "example.com:8443/gitlab", owner = "group", repo = "repo", scheme = "https" },
        "the entry with the port"
    )
    eq(
        discover({ hosts = { "example.com/gitlab" } }),
        { host = "example.com:8443", owner = "gitlab/group", repo = "repo", scheme = "https" },
        "an entry without the port does not apply"
    )
end

T["discover_with_host_prefix_and_ipv6_address"] = function()
    with_origin("https://[::1]:8443/gitlab/group/repo.git")

    eq(
        discover({ hosts = { "[::1]:8443/gitlab" } }),
        { host = "[::1]:8443/gitlab", owner = "group", repo = "repo", scheme = "https" },
        "an IPv6 address is not a pattern"
    )
end

T["discover_keeps_the_scheme_of_an_http_remote"] = function()
    with_origin("http://127.0.0.1:3000/gitea/owner/repo.git")

    eq(
        discover({ hosts = { "127.0.0.1:3000/gitea" } }),
        { host = "127.0.0.1:3000/gitea", owner = "owner", repo = "repo", scheme = "http" },
        "the scheme stays with a host prefix"
    )
end

T["discover_ssh_remote_with_host_prefix"] = function()
    with_origin("git@example.com:group/repo.git")
    local expected = { host = "example.com/gitlab", owner = "group", repo = "repo" }

    eq(discover({ hosts = { "github.com", "gitlab.com", "example.com/gitlab" } }), expected, "the only prefixed entry")
    eq(discover({ hosts = { "example.com/gitlab", "example.com/gitlab" } }), expected, "the same entry two times")
    eq(
        discover({ hosts = { "example.com/gitlab", "example.com/tools/gitlab" } }),
        { host = "example.com", owner = "group", repo = "repo" },
        "two prefixed entries"
    )
end

T["discover_ssh_alias_with_host_prefix"] = function()
    with_origin("git@gitlab-work:group/repo.git")

    eq(
        discover({ ssh_aliases = { ["gitlab-work"] = "example.com" }, hosts = { "example.com/gitlab" } }),
        { host = "example.com/gitlab", owner = "group", repo = "repo" },
        "the prefix applies to the real host"
    )
end

T["discover_with_plain_host_and_host_prefix"] = function()
    with_origin("git@example.com:group/repo.git")

    eq(
        discover({ hosts = { "example.com", "example.com/gitlab" } }),
        { host = "example.com", owner = "group", repo = "repo" },
        "the plain host is an instance too"
    )
end

T["discover_with_owner_equal_to_host_prefix"] = function()
    with_origin("https://example.com/gitlab/repo.git")

    eq(
        discover({ hosts = { "example.com", "example.com/gitlab" } }),
        { host = "example.com", owner = "gitlab", repo = "repo", scheme = "https" },
        "no owner is left after the prefix"
    )
    eq(
        discover({ hosts = { "example.com/gitlab" } }),
        { host = "example.com/gitlab", owner = "gitlab", repo = "repo", scheme = "https" },
        "the only prefixed entry keeps the owner"
    )
end

T["discover_with_host_prefix_of_other_host"] = function()
    with_origin("https://gitlab.com/gitlab/group/repo.git")

    eq(
        discover({ hosts = { "github.com", "gitlab.com", "example.com/gitlab", "gitlab.co/gitlab" } }),
        { host = "gitlab.com", owner = "gitlab/group", repo = "repo", scheme = "https" },
        "the entries of other hosts do not apply"
    )
    eq(discover({ hosts = { "gitlabXcom/gitlab" } }).host, "gitlab.com", "a . in a host is not a pattern")
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

    eq(discover(), { host = "github.com", owner = "owner", repo = "repo", scheme = "https" }, "the cwd repository")
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

    eq(
        discover(),
        { host = "github.com", owner = "owner", repo = "repo", scheme = "https" },
        "a commit message in .git"
    )
end

---What core does for each completion request.
---@param opts? tests.DiscoverOptions
---@return cmp_git.RepositoryMetadata?
local function request(opts)
    if not is_git_repo() then
        return nil
    end
    return discover(opts)
end

T["discovery_runs_git_without_a_shell"] = function()
    require_git()
    local repo = helpers.git_repo({ remotes = { { "origin", "work:owner/repo" } } })
    new_buffer()
    vim.fn.chdir(repo.dir)
    local commands = record_processes()

    request()
    request({ enableRemoteUrlRewrites = true })

    helpers.ok(#commands > 0, "discovery runs git")
    for _, cmd in ipairs(commands) do
        eq(cmd[1], "git", "git runs without sh: " .. table.concat(cmd, " "))
    end
end

T["discovery_starts_two_processes"] = function()
    require_git()
    local repo = helpers.git_repo({ remotes = { { "origin", "https://github.com/owner/repo.git" } } })
    local bare = helpers.git_repo()
    vim.fn.chdir(helpers.tempdir())

    edit(repo.dir .. "/notes.md", "markdown")
    local commands = record_processes()
    eq(request(), { host = "github.com", owner = "owner", repo = "repo", scheme = "https" }, "the second remote")
    eq(#commands, 2, "a request in a new buffer: " .. vim.inspect(command_lines(commands)))

    edit(bare.dir .. "/notes.md", "markdown")
    commands = record_processes()
    eq(request(), {}, "a repository without remotes")
    eq(#commands, 2, "a repository without remotes: " .. vim.inspect(command_lines(commands)))

    edit(repo.dir .. "/other.md", "markdown")
    commands = record_processes()
    eq(request({ enableRemoteUrlRewrites = true }).owner, "owner", "the URL from git remote")
    eq(#commands, 2, "URL rewrites: " .. vim.inspect(command_lines(commands)))
end

T["discovery_repeated_request_starts_no_process"] = function()
    require_git()
    local repo = helpers.git_repo({ remotes = { { "origin", "work:owner/repo" } } })
    repo.git("config", "url.https://github.example.com/.insteadOf", "work:")
    edit(repo.dir .. "/notes.md", "markdown")
    local expected = request()
    local rewritten = request({ enableRemoteUrlRewrites = true })
    local commands = record_processes()

    eq(request(), expected, "the same repository")
    eq(request({ enableRemoteUrlRewrites = true }), rewritten, "the same rewritten repository")
    eq(request({ ssh_aliases = { work = "github.com" } }).host, "github.com", "ssh_aliases apply to the cache")
    eq(request().host, "work", "ssh_aliases do not change the cache")
    eq(#commands, 0, "repeated requests: " .. vim.inspect(command_lines(commands)))
end

T["discovery_outside_repository_starts_no_process"] = function()
    require_git()
    local dir = helpers.tempdir()
    new_buffer()
    vim.fn.chdir(dir)
    eq(is_git_repo(), false, "a directory outside a repository")
    local commands = record_processes()

    eq(is_git_repo(), false, "still outside a repository")
    eq(discover(), {}, "no repository")
    eq(#commands, 0, "repeated requests: " .. vim.inspect(command_lines(commands)))

    vim.system({ "git", "init", "-q" }, { cwd = dir }):wait()
    local now = vim.uv.now()
    helpers.stub(vim.uv, "now", function()
        return now + 60 * 1000
    end)
    eq(is_git_repo(), true, "a directory outside a repository is checked again later, after git init")
end

T["discovery_concurrent_requests_share_processes"] = function()
    require_git()
    local repo = helpers.git_repo({ remotes = { { "origin", "https://github.com/owner/repo.git" } } })
    edit(repo.dir .. "/notes.md", "markdown")
    local commands = record_processes()

    local results = {}
    for _ = 1, 3 do
        repository.discover({ "upstream", "origin" }, {
            enableRemoteUrlRewrites = false,
            ssh_aliases = {},
            on_complete = function(metadata)
                table.insert(results, metadata)
            end,
        })
    end
    helpers.wait_for(function()
        return #results == 3
    end, "each discover calls back")

    for _, metadata in ipairs(results) do
        eq(
            metadata,
            { host = "github.com", owner = "owner", repo = "repo", scheme = "https" },
            "each request gets the repository"
        )
    end
    helpers.ok(results[1] ~= results[2], "each request gets its own table, because callers change it")
    eq(#commands, 2, "concurrent requests: " .. vim.inspect(command_lines(commands)))
end

T["discovery_octo_buffer_starts_no_process"] = function()
    helpers.stub(package.loaded, "octo.config", { values = { github_hostname = "" } })
    vim.fn.chdir(helpers.tempdir())
    edit("octo://owner/repo/issue/12", "octo")
    local commands = record_processes()

    eq(request(), { host = "github.com", owner = "owner", repo = "repo" }, "the repository of the buffer name")
    eq(#commands, 0, "an octo buffer: " .. vim.inspect(command_lines(commands)))
end

T["discovery_again_when_buffer_directory_changes"] = function()
    require_git()
    local first = helpers.git_repo({ remotes = { { "origin", "https://github.com/first/repo.git" } } })
    local second = helpers.git_repo({ remotes = { { "origin", "https://github.com/second/repo.git" } } })
    edit(first.dir .. "/notes.md", "markdown")
    eq(request().owner, "first", "the first repository")

    vim.api.nvim_buf_set_name(0, second.dir .. "/notes.md")
    eq(request().owner, "second", "the buffer is now in the second repository")
end

T["discovery_again_when_cwd_changes"] = function()
    require_git()
    local first = helpers.git_repo({ remotes = { { "origin", "https://github.com/first/repo.git" } } })
    local second = helpers.git_repo({ remotes = { { "origin", "https://github.com/second/repo.git" } } })
    new_buffer()
    vim.fn.chdir(first.dir)
    eq(request().owner, "first", "the first repository")

    vim.fn.chdir(second.dir)
    eq(request().owner, "second", "the cwd is now the second repository")
end

T["discovery_again_when_remotes_change"] = function()
    require_git()
    local repo = helpers.git_repo({ remotes = { { "origin", "https://github.com/fork/repo.git" } } })
    edit(repo.dir .. "/notes.md", "markdown")
    eq(request().owner, "fork", "the origin remote")

    repo.git("remote", "add", "upstream", "https://github.com/owner/repo.git")
    eq(request().owner, "owner", "the new upstream remote comes first")
end

T["discovery_remote_name_with_a_dot"] = function()
    require_git()
    local repo = helpers.git_repo({ remotes = { { "my.fork", "https://github.com/fork/repo.git" } } })
    edit(repo.dir .. "/notes.md", "markdown")

    eq(request({ remotes = { "my.fork" } }).owner, "fork", "the configured URL")
    eq(request({ remotes = { "my.fork" }, enableRemoteUrlRewrites = true }).owner, "fork", "the URL from git remote")
end

T["discovery_reads_remotes_of_the_found_repository"] = function()
    require_git()
    local buffer_repo = helpers.git_repo()
    local cwd_repo = helpers.git_repo({ remotes = { { "origin", "https://github.com/cwd/repo.git" } } })
    vim.fn.chdir(cwd_repo.dir)
    edit(buffer_repo.dir .. "/notes.md", "markdown")

    eq(request(), {}, "the remotes of another repository do not apply")
end

T["a_wiped_buffer_has_no_repository"] = function()
    require_git()
    local repo = helpers.git_repo({ remotes = { { "origin", "https://github.com/owner/repo.git" } } })
    vim.fn.chdir(repo.dir)
    local bufnr = helpers.buffer({}, "markdown")
    vim.api.nvim_buf_delete(bufnr, { force = true })

    local results = {}
    repository.is_git_repo(function(value)
        results.is_git_repo = value
    end, bufnr)
    repository.discover({ "origin" }, {
        bufnr = bufnr,
        enableRemoteUrlRewrites = false,
        ssh_aliases = {},
        on_complete = function(metadata)
            results.discover = metadata
        end,
    })

    eq(results, { is_git_repo = false, discover = {} }, "a wiped buffer answers at once, without a repository")
    eq(repository.get_cwd(bufnr), repo.dir, "the commands of a wiped buffer run in the cwd")
end

return T
