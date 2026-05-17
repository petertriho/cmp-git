local remote_url = require("cmp_git.repository.remote_url")

local M = {}

---@param cmd string
---@param opts { on_complete: fun(success: boolean, output: string[]): nil; cwd?: string }
---@return nil
local function run_cmd_async(cmd, opts)
    vim.system({ "sh", "-c", cmd }, {
        text = true,
        cwd = opts.cwd,
    }, function(result)
        vim.schedule(function()
            local output = vim.split(result.stdout or "", "\n", { trimempty = true })
            opts.on_complete(result.code == 0, output)
        end)
    end)
end

---@return string
function M.get_cwd()
    if vim.fn.getreg("%") ~= "" and vim.bo.filetype ~= "octo" then
        return vim.fn.expand("%:p:h")
    end
    return vim.fn.getcwd()
end

---@alias cmp_git.GitInfo cmp_git.RepositoryMetadata

---@param on_result fun(is_git_repo: boolean): nil
---@return nil
function M.is_git_repo(on_result)
    local cwd = M.get_cwd() ---@type string?
    local function check_in_git_repo()
        local cmd = "git rev-parse --is-inside-work-tree --is-inside-git-dir"
        run_cmd_async(cmd, {
            on_complete = function(success, output)
                local is_git_repo = success and #output > 0 and output[1]:find("true") ~= nil
                if not is_git_repo and cwd ~= nil then
                    cwd = nil
                    check_in_git_repo()
                    return
                end
                on_result(is_git_repo)
            end,
            cwd = cwd,
        })
    end
    check_in_git_repo()
end

---@param metadata cmp_git.RepositoryMetadata
---@param ssh_aliases table<string, string>?
---@return cmp_git.RepositoryMetadata
local function apply_ssh_aliases(metadata, ssh_aliases)
    if metadata.host == nil or ssh_aliases == nil then
        return metadata
    end

    for alias, host in pairs(ssh_aliases) do
        metadata.host = metadata.host:gsub("^" .. alias:gsub("%-", "%%-"):gsub("%.", "%%.") .. "$", host, 1)
    end

    return metadata
end

---@return cmp_git.RepositoryMetadata?
local function discover_octo()
    if vim.bo.filetype ~= "octo" then
        return nil
    end

    local host = require("octo.config").values.github_hostname or ""
    if host == "" then
        host = "github.com"
    end

    local filename = vim.fn.expand("%:p:h")
    local owner, repo = string.match(filename, "^octo://([^/]+)/([^/]+)")
    return { host = host, owner = owner, repo = repo }
end

---@param remotes string|string[]
---@param opts {enableRemoteUrlRewrites: boolean, ssh_aliases: {[string]: string}, on_complete: fun(metadata: cmp_git.RepositoryMetadata): nil}
---@return nil
function M.discover(remotes, opts)
    opts = opts or {}
    local cwd = M.get_cwd() ---@type string?

    local discover ---@type fun(): nil

    ---@param metadata cmp_git.RepositoryMetadata
    local function handle_metadata(metadata)
        if metadata.host == nil and cwd ~= nil then
            cwd = nil
            discover()
            return
        end

        opts.on_complete(apply_ssh_aliases(metadata, opts.ssh_aliases))
    end

    discover = function()
        if type(remotes) == "string" then
            remotes = { remotes }
        end

        local octo_metadata = discover_octo()
        if octo_metadata ~= nil then
            handle_metadata(octo_metadata)
            return
        end

        local remote_index = 1
        local function check_remote()
            if remote_index > #remotes then
                handle_metadata({})
                return
            end

            local remote = remotes[remote_index]
            local cmd ---@type string
            if opts.enableRemoteUrlRewrites then
                cmd = "git remote get-url " .. remote
            else
                cmd = "git config --get remote." .. remote .. ".url"
            end

            run_cmd_async(cmd, {
                on_complete = function(success, output)
                    remote_index = remote_index + 1
                    if not success then
                        check_remote()
                        return
                    end

                    local metadata = remote_url.parse(output[1])
                    if metadata.host ~= nil and metadata.owner ~= nil and metadata.repo ~= nil then
                        handle_metadata(metadata)
                        return
                    end

                    check_remote()
                end,
                cwd = cwd,
            })
        end
        check_remote()
    end

    discover()
end

return M
