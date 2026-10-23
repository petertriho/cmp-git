-- The fj token and curl against a real Forgejo server, which starts once for the file. The server has the
-- repositories `root/public` and `root/private`, each with the issue #1, the pull request #2, and the assignees `ada`
-- and `root`.
local helpers = require("tests.helpers")
local integration = require("tests.integration.helpers")
local config = require("cmp_git.config")
local Forgejo = require("cmp_git.sources.forgejo")

local eq = helpers.eq

local forgejo = integration.forge("forgejo")

local T = helpers.new_set({
    post_once = function()
        forgejo:stop()
    end,
})

---@param repo string
---@return cmp_git.GitInfo
local function remote(repo)
    return { host = assert(forgejo.host, "start the server first"), owner = "root", repo = repo, scheme = "http" }
end

---@return cmp_git.Source.GiteaApi
local function source()
    return Forgejo.new(config.normalize({ forgejo = { hosts = { forgejo.host } } }).forgejo)
end

---Run a request of the source and return the labels of its list.
---@param forgejo_source cmp_git.Source.GiteaApi
---@param method string
---@param git_info cmp_git.GitInfo
---@param trigger_char string
---@return string[]
local function complete(forgejo_source, method, git_info, trigger_char)
    local bufnr = vim.api.nvim_get_current_buf()
    local callback, lists = helpers.recorder()
    eq(forgejo_source[method](forgejo_source, callback, git_info, trigger_char, bufnr), true, method .. " handles it")
    helpers.wait_for(function()
        return #lists > 0
    end, method .. " answers")
    return vim.tbl_map(function(item)
        return item.label
    end, lists[#lists].items)
end

T["the_fj_token_gives_the_private_items"] = function()
    forgejo:start()
    integration.use_fj(forgejo)
    integration.edit_outside_repository()
    local private = remote("private")

    eq(
        complete(source(), "complete_issues_and_change_requests", private, "#"),
        { "#1: A private issue", "#2: A private pull request" },
        "#"
    )
    eq(complete(source(), "complete_change_requests", private, "!"), { "!2: A private pull request" }, "!")
    eq(complete(source(), "complete_mentions", private, "@"), { "@ada", "@root" }, "@")
end

T["the_forgejo_token_gives_the_private_items"] = function()
    forgejo:start()
    integration.edit_outside_repository()
    vim.env.FORGEJO_TOKEN = forgejo.token
    local private = remote("private")

    eq(complete(source(), "complete_issues", private, "#"), { "#1: A private issue" }, "#")
    eq(complete(source(), "complete_mentions", private, "@"), { "@ada", "@root" }, "@")
end

T["without_credentials_curl_gives_the_public_items"] = function()
    forgejo:start()
    integration.edit_outside_repository()
    local public = remote("public")

    eq(
        complete(source(), "complete_issues_and_change_requests", public, "#"),
        { "#1: A public issue", "#2: A public pull request" },
        "#"
    )
    eq(complete(source(), "complete_issues", remote("private"), "#"), {}, "no private items")
    eq(complete(source(), "complete_mentions", public, "@"), {}, "the assignees API needs a token")
end

return T
