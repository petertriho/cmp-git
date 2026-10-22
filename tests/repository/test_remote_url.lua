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

return T
