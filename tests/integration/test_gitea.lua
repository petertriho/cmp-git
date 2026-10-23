-- The real tea and curl against a real Gitea server, which starts once for the file. The server has the
-- repositories `root/public` and `root/private`, each with the issue #1, the pull request #2, and the assignees `ada`
-- and `root`.
local helpers = require("tests.helpers")
local integration = require("tests.integration.helpers")
local config = require("cmp_git.config")
local Core = require("cmp_git.core")
local Gitea = require("cmp_git.sources.gitea")

local eq = helpers.eq

local gitea = integration.forge("gitea")
-- A second server with `/gitea/` in ROOT_URL, behind a proxy that removes the prefix
local prefixed = integration.forge("gitea", { prefix = "gitea" })

local T = helpers.new_set({
    post_once = function()
        gitea:stop()
        prefixed:stop()
    end,
})

---@param server tests.integration.Forge
---@param repo string
---@return cmp_git.GitInfo
local function remote(server, repo)
    return { host = assert(server.host, "start the server first"), owner = "root", repo = repo, scheme = "http" }
end

---@param server tests.integration.Forge
---@return cmp_git.Source.GiteaApi
local function source(server)
    return Gitea.new(config.normalize({ gitea = { hosts = { server.host } } }).gitea)
end

---Run a request of the source and return the labels of its list.
---@param gitea_source cmp_git.Source.GiteaApi
---@param method string
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@return string[]
local function complete(gitea_source, method, git_info, trigger_char)
    local bufnr = vim.api.nvim_get_current_buf()
    local callback, lists = helpers.recorder()
    eq(gitea_source[method](gitea_source, callback, git_info, trigger_char, bufnr), true, method .. " handles the host")
    helpers.wait_for(function()
        return #lists > 0
    end, method .. " answers")
    return vim.tbl_map(function(item)
        return item.label
    end, lists[#lists].items)
end

local PRIVATE = { "#1: A private issue", "#2: A private pull request" }

T["tea_api_with_a_login_gives_the_private_items"] = function()
    gitea:start()
    integration.use_tea(gitea, "local")
    integration.edit_outside_repository()
    -- A failed tea would fall back to curl, which then fails too
    integration.failing_commands({ curl = 7 })
    local private = remote(gitea, "private")

    eq(complete(source(gitea), "complete_issues_and_change_requests", private, "#"), PRIVATE, "#")
    eq(complete(source(gitea), "complete_change_requests", private, "!"), { "!2: A private pull request" }, "!")
    eq(complete(source(gitea), "complete_mentions", private, "@"), { "@ada", "@root" }, "@")
end

T["without_a_tea_login_curl_sends_the_gitea_token"] = function()
    gitea:start()
    integration.without_tea_logins()
    integration.edit_outside_repository()
    vim.env.GITEA_TOKEN = gitea.token
    local private = remote(gitea, "private")

    eq(complete(source(gitea), "complete_issues", private, "#"), { "#1: A private issue" }, "#")
    eq(complete(source(gitea), "complete_mentions", private, "@"), { "@ada", "@root" }, "@")
end

T["an_invalid_gitea_token_falls_back_to_curl_without_a_token"] = function()
    gitea:start()
    integration.without_tea_logins()
    integration.edit_outside_repository()
    vim.env.GITEA_TOKEN = "0000000000000000000000000000000000000000"

    eq(
        complete(source(gitea), "complete_issues_and_change_requests", remote(gitea, "public"), "#"),
        { "#1: A public issue", "#2: A public pull request" },
        "the public items without a token"
    )
    eq(complete(source(gitea), "complete_issues", remote(gitea, "private"), "#"), {}, "no private items")
end

T["without_credentials_the_mentions_are_empty"] = function()
    gitea:start()
    integration.without_tea_logins()
    integration.edit_outside_repository()
    local public = remote(gitea, "public")

    eq(complete(source(gitea), "complete_change_requests", public, "!"), { "!2: A public pull request" }, "!")
    eq(complete(source(gitea), "complete_mentions", public, "@"), {}, "the assignees API needs a token")
end

T["a_path_prefix_reaches_the_server"] = function()
    prefixed:start()
    local proxy = assert(prefixed.proxy, "a server with a prefix has a proxy")
    eq(prefixed.host, "127.0.0.1:" .. proxy.port .. "/gitea", "the host has the path prefix")
    integration.edit_outside_repository()
    local private = remote(prefixed, "private")

    integration.use_tea(prefixed, "prefixed")
    eq(complete(source(prefixed), "complete_issues_and_change_requests", private, "#"), PRIVATE, "tea")

    integration.without_tea_logins()
    Gitea.clear_logins()
    vim.env.GITEA_TOKEN = prefixed.token
    eq(complete(source(prefixed), "complete_mentions", private, "@"), { "@ada", "@root" }, "curl")

    local paths = vim.tbl_map(function(request)
        return request.path
    end, proxy.requests)
    eq(vim.tbl_contains(paths, "/gitea/api/v1/repos/root/private/assignees"), true, "curl sends the prefix")
    eq(vim.tbl_contains(paths, "/gitea/api/v1/repos/root/private/issues"), true, "tea sends the prefix")
end

T["an_http_remote_reaches_the_server_through_discovery"] = function()
    gitea:start()
    integration.without_tea_logins()
    local repo = helpers.git_repo({ remotes = { { "origin", gitea.url .. "/root/public.git" } } })
    vim.cmd.edit(vim.fn.fnameescape(repo.dir .. "/COMMIT_EDITMSG"))
    local line = "see #"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
    local core = Core.new({ gitea = { hosts = { gitea.host } } })

    local callback, lists = helpers.recorder()
    core:complete({
        trigger_character = "#",
        cursor = { row = 1, character = #line },
        line = line,
        bufnr = vim.api.nvim_get_current_buf(),
    }, callback)
    helpers.wait_for(function()
        return #lists > 0
    end, "the completion answers")

    eq(
        vim.tbl_map(function(item)
            return item.label
        end, lists[#lists].items),
        { "#1: A public issue", "#2: A public pull request" },
        "discovery keeps the http scheme, and curl asks the server with plain HTTP"
    )
end

return T
