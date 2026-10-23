local helpers = require("tests.helpers")
local remote_url = require("cmp_git.repository.remote_url")

local eq = helpers.eq

local T = helpers.new_set()

T["parse_remote_url"] = function()
    local ssh = remote_url.parse("git@github.com:owner/repo.git")
    eq(ssh.host, "github.com", "ssh remote host")
    eq(ssh.owner, "owner", "ssh remote owner")
    eq(ssh.repo, "repo", "ssh remote repo")

    local https = remote_url.parse("https://gitlab.com/group/project.git")
    eq(https.host, "gitlab.com", "https remote host")
    eq(https.owner, "group", "https remote owner")
    eq(https.repo, "project", "https remote repo")

    local ssh_url = remote_url.parse("ssh://git@example.com/owner/repo.git")
    eq(ssh_url.host, "example.com", "ssh url remote host")
    eq(ssh_url.owner, "owner", "ssh url remote owner")
    eq(ssh_url.repo, "repo", "ssh url remote repo")

    local alias = remote_url.parse("github-work:owner/repo.git")
    eq(alias.host, "github-work", "alias remote host")
    eq(alias.owner, "owner", "alias remote owner")
    eq(alias.repo, "repo", "alias remote repo")
end

T["parse_remote_url_repo_with_git_in_name"] = function()
    eq(
        remote_url.parse("https://github.com/user/user.github.io.git"),
        { host = "github.com", owner = "user", repo = "user.github.io", scheme = "https" },
        "only a trailing .git is removed"
    )
    eq(remote_url.parse("git@github.com:owner/git.git").repo, "git", "a repo named git")
end

T["parse_remote_url_subgroups"] = function()
    local expected = { host = "gitlab.com", owner = "group/sub", repo = "repo" }
    local https = vim.tbl_extend("force", expected, { scheme = "https" })
    eq(remote_url.parse("https://gitlab.com/group/sub/repo"), https, "https remote in a subgroup")
    eq(remote_url.parse("https://gitlab.com/group/sub/repo.git"), https, "https remote in a subgroup with .git")
    eq(remote_url.parse("git@gitlab.com:group/sub/repo.git"), expected, "scp-like remote in a subgroup")
    eq(remote_url.parse("ssh://git@gitlab.com/group/sub/repo.git"), expected, "ssh url remote in a subgroup")
end

T["parse_remote_url_ports"] = function()
    eq(
        remote_url.parse("ssh://git@host:2222/group/sub/repo"),
        { host = "host", owner = "group/sub", repo = "repo" },
        "the ssh port is not part of the host"
    )
    eq(
        remote_url.parse("https://gitlab.example.com:8443/group/repo.git"),
        { host = "gitlab.example.com:8443", owner = "group", repo = "repo", scheme = "https" },
        "the https port is part of the host, because the API is on the same origin"
    )
    eq(remote_url.parse("git://example.com:9418/owner/repo.git").host, "example.com", "the git daemon port")
end

T["parse_remote_url_credentials"] = function()
    eq(
        remote_url.parse("https://user:token@github.com/o/r"),
        { host = "github.com", owner = "o", repo = "r", scheme = "https" },
        "credentials are not part of the host"
    )
    eq(remote_url.parse("https://token@github.com:8443/o/r").host, "github.com:8443", "a token and a port")
    eq(remote_url.parse("org-123@github.com:owner/repo.git").host, "github.com", "an scp-like user other than git")
    eq(remote_url.parse("git+ssh://git@github.com/owner/repo.git").host, "github.com", "a git+ssh remote")
end

T["parse_remote_url_trailing_slash"] = function()
    local expected = { host = "github.com", owner = "owner", repo = "repo" }
    local https = vim.tbl_extend("force", expected, { scheme = "https" })
    eq(remote_url.parse("https://github.com/owner/repo/"), https, "a trailing slash")
    eq(remote_url.parse("https://github.com/owner/repo.git/"), https, "a trailing slash after .git")
    eq(remote_url.parse("git@github.com:owner/repo.git\n"), expected, "a trailing newline")
end

T["parse_remote_url_scheme"] = function()
    eq(remote_url.parse("https://example.com/owner/repo.git").scheme, "https", "an https remote")
    eq(
        remote_url.parse("HTTP://127.0.0.1:3000/owner/repo.git"),
        { host = "127.0.0.1:3000", owner = "owner", repo = "repo", scheme = "http" },
        "an http remote keeps its port and its scheme in lowercase"
    )
    eq(remote_url.parse("git@example.com:owner/repo.git").scheme, nil, "an scp-like remote has no scheme")
    eq(remote_url.parse("ssh://git@example.com/owner/repo.git").scheme, nil, "an ssh remote has no scheme")
    eq(remote_url.parse("git://example.com/owner/repo.git").scheme, nil, "a git remote has no scheme")
end

T["parse_remote_url_unsupported"] = function()
    eq(remote_url.parse(nil), {}, "no URL")
    eq(remote_url.parse(""), {}, "an empty URL")
    eq(remote_url.parse("/srv/git/project.git"), {}, "a local path")
    eq(remote_url.parse("./project"), {}, "a relative path")
    eq(remote_url.parse("file:///srv/git/owner/project.git"), {}, "a file URL")
    eq(remote_url.parse("https://github.com/repo"), {}, "a URL without an owner")
end

return T
