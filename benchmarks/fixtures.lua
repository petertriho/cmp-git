---Deterministic data for the benchmarks: commits, the output of the git commands that cmp-git runs, API responses,
---and a git repository with a fake `gh`. Nothing here uses the network.
local M = {}

local US = "\031"
local NUL = "\0"

---@class bench.Person
---@field name string
---@field email string

---@param prefix string
---@param count integer
---@return bench.Person[]
local function people(prefix, count)
    local result = {}
    for i = 1, count do
        table.insert(result, {
            name = string.format("%s %d", prefix, i),
            email = string.format("%s.%d@example.com", prefix:lower(), i),
        })
    end
    return result
end

local AUTHORS = people("Author", 40)
local COAUTHORS = people("Contributor", 300)

local WORDS = {
    "parser",
    "cache",
    "request",
    "trailer",
    "remote",
    "buffer",
    "provider",
    "format",
    "history",
    "option",
    "window",
    "message",
}

---@class bench.Commit
---@field sha string
---@field subject string
---@field body string The body that `%b` prints, with the trailer block.
---@field author bench.Person
---@field timestamp integer
---@field trailers { key: string, value: string }[]

---@param count integer
---@return bench.Commit[] commits Newest first, like `git log`.
function M.commits(count)
    local commits = {}
    for i = 1, count do
        local word = WORDS[i % #WORDS + 1]
        local author = AUTHORS[i % #AUTHORS + 1]
        local trailers = {}
        if i % 3 == 0 then
            local coauthor = COAUTHORS[(i * 7) % #COAUTHORS + 1]
            table.insert(trailers, { key = "Co-authored-by", value = coauthor.name .. " <" .. coauthor.email .. ">" })
        end
        if i % 5 == 0 then
            table.insert(trailers, { key = "Fixes", value = "#" .. (1000 + i) })
        end
        if i % 7 == 0 then
            table.insert(trailers, { key = "Refs", value = "ABC-" .. (i % 50) })
        end
        if i % 11 == 0 then
            local reviewer = COAUTHORS[(i * 13) % #COAUTHORS + 1]
            table.insert(trailers, { key = "Reviewed-by", value = reviewer.name .. " <" .. reviewer.email .. ">" })
        end
        if i % 13 == 0 then
            table.insert(trailers, { key = "Assisted-by", value = "Tool " .. (i % 3) })
        end
        table.insert(trailers, { key = "Signed-off-by", value = author.name .. " <" .. author.email .. ">" })

        local trailer_lines = {}
        for _, trailer in ipairs(trailers) do
            table.insert(trailer_lines, trailer.key .. ": " .. trailer.value)
        end

        local body = table.concat({
            string.format("Change how the %s handles the case that commit %d found. The old code read the", word, i),
            string.format("whole %s each time, so it was slow when the history was long.", word),
            "",
            table.concat(trailer_lines, "\n"),
        }, "\n") .. "\n"

        table.insert(commits, {
            sha = string.rep(string.format("%08x", i * 2654435761 % 4294967296), 5),
            subject = string.format("fix(%s): handle the case from commit %d", word, i),
            body = body,
            author = author,
            timestamp = 1700000000 - i * 3600,
            trailers = trailers,
        })
    end
    return commits
end

---The output of the `git log` command in `provider/capabilities/commits.lua`. `--pretty=format:` puts a newline
---between entries.
---@param commits bench.Commit[]
---@return string
function M.commits_log(commits)
    local entries = {}
    for _, commit in ipairs(commits) do
        table.insert(
            entries,
            table.concat({
                commit.sha,
                commit.subject,
                commit.body,
                commit.author.name,
                commit.author.email,
                tostring(commit.timestamp),
                "",
            }, NUL)
        )
    end
    return table.concat(entries, "\n")
end

---The output of `trailers.keys.request`. `--format=` ends each entry with a newline.
---@param commits bench.Commit[]
---@return string
function M.trailer_keys_log(commits)
    local entries = {}
    for _, commit in ipairs(commits) do
        local keys = {}
        for _, trailer in ipairs(commit.trailers) do
            table.insert(keys, trailer.key)
        end
        table.insert(entries, table.concat(keys, US) .. NUL .. "\n")
    end
    return table.concat(entries)
end

---The output of `trailers.identities.request` for the default identity keys.
---@param commits bench.Commit[]
---@return string
function M.trailer_identities_log(commits)
    local identity_keys = { ["Co-authored-by"] = true, ["Reviewed-by"] = true, ["Signed-off-by"] = true }
    local entries = {}
    for _, commit in ipairs(commits) do
        local fields = { tostring(commit.timestamp), commit.author.name, commit.author.email }
        local trailers = {}
        for _, trailer in ipairs(commit.trailers) do
            if identity_keys[trailer.key] then
                table.insert(trailers, trailer.key .. ": " .. trailer.value)
            end
        end
        table.insert(fields, table.concat(trailers, US))
        table.insert(entries, table.concat(fields, US) .. NUL .. "\n")
    end
    return table.concat(entries)
end

---The output of `trailers.values.request`.
---@param commits bench.Commit[]
---@return string
function M.trailer_values_log(commits)
    local entries = {}
    for _, commit in ipairs(commits) do
        local fields = { tostring(commit.timestamp) }
        for _, trailer in ipairs(commit.trailers) do
            table.insert(fields, trailer.key .. ": " .. trailer.value)
        end
        table.insert(entries, table.concat(fields, US) .. NUL .. "\n")
    end
    return table.concat(entries)
end

---@param i integer
---@return string
local function issue_body(i)
    local lines = {}
    for line = 1, 8 do
        table.insert(
            lines,
            string.format("Line %d of issue %d. The %s fails when the input is long.", line, i, WORDS[line])
        )
    end
    return table.concat(lines, "\r\n")
end

---@param i integer
---@return string
local function iso_date(i)
    return string.format("2024-%02d-%02dT%02d:04:05Z", i % 12 + 1, i % 28 + 1, i % 24)
end

---`gh issue list --json` or `gh pr list --json` output with the default fields.
---@param count integer
---@return string
function M.github_issues_json(count)
    local issues = {}
    for i = 1, count do
        table.insert(issues, {
            number = 2000 + i,
            title = string.format("The %s fails when the input is long (%d)", WORDS[i % #WORDS + 1], i),
            body = issue_body(i),
            updatedAt = iso_date(i),
            state = "OPEN",
        })
    end
    return vim.json.encode(issues)
end

---@param count integer
---@return string
function M.github_mentions_json(count)
    local users = {}
    for i = 1, count do
        table.insert(users, { login = string.format("user-%d", i), id = i, type = "User" })
    end
    return vim.json.encode(users)
end

---GitLab merge requests API output.
---@param count integer
---@return string
function M.gitlab_merge_requests_json(count)
    local merge_requests = {}
    for i = 1, count do
        table.insert(merge_requests, {
            iid = 300 + i,
            title = string.format("Change the %s (%d)", WORDS[i % #WORDS + 1], i),
            description = issue_body(i),
            updated_at = iso_date(i),
            state = "opened",
        })
    end
    return vim.json.encode(merge_requests)
end

---@param length integer
---@return string
function M.prose(length)
    local words = {}
    local size = 0
    local i = 0
    while size < length do
        i = i + 1
        local word = WORDS[i % #WORDS + 1]
        table.insert(words, word)
        size = size + #word + 1
    end
    return table.concat(words, " "):sub(1, length)
end

local temp_root = nil ---@type string?

---The temporary directory of this run. `cleanup` deletes it.
---@return string
function M.temp_root()
    if not temp_root then
        temp_root = vim.fn.tempname()
        vim.fn.mkdir(temp_root, "p")
        temp_root = assert(vim.uv.fs_realpath(temp_root))
    end
    return temp_root
end

function M.cleanup()
    if temp_root then
        vim.fn.delete(temp_root, "rf")
        temp_root = nil
    end
end

---Run git and stop the benchmark run when it fails.
---@param args string[]
---@param opts? { stdin?: string }
---@return string stdout
local function git(args, opts)
    local result = vim.system(vim.list_extend({ "git" }, args), { text = true, stdin = opts and opts.stdin }):wait()
    if result.code ~= 0 then
        error(string.format("git %s failed: %s", table.concat(args, " "), result.stderr), 0)
    end
    return result.stdout
end

---Set the environment that the fixture repository and the fake `gh` need. Git does not read the user's config, and
---the `gh` in the fixture directory comes first in `PATH`.
function M.isolate_environment()
    local root = M.temp_root()
    local home = root .. "/home"
    local bin = root .. "/bin"
    local data = root .. "/data"
    vim.fn.mkdir(home, "p")
    vim.fn.mkdir(bin, "p")
    vim.fn.mkdir(data, "p")

    vim.env.HOME = home
    vim.env.XDG_CONFIG_HOME = home .. "/.config"
    vim.env.XDG_CACHE_HOME = home .. "/.cache"
    vim.env.GIT_CONFIG_GLOBAL = "/dev/null"
    vim.env.GIT_CONFIG_NOSYSTEM = "1"
    vim.env.GIT_CEILING_DIRECTORIES = root
    vim.env.GITHUB_API_TOKEN = nil
    vim.env.GITLAB_TOKEN = nil
    vim.env.CMP_GIT_BENCH_DATA = data
    vim.env.PATH = bin .. ":" .. vim.env.PATH
    vim.g.cmp_git_debug = nil

    local function write(path, content)
        local file = assert(io.open(path, "wb"))
        file:write(content)
        file:close()
    end

    write(data .. "/github_issues.json", M.github_issues_json(100))
    write(data .. "/github_pull_requests.json", M.github_issues_json(40))
    write(data .. "/github_mentions.json", M.github_mentions_json(30))
    -- `gh repo set-default --view` fails, as when no default repository is set
    write(
        bin .. "/gh",
        table.concat({
            "#!/bin/sh",
            'case "$1 $2" in',
            '"issue list") cat "$CMP_GIT_BENCH_DATA/github_issues.json" ;;',
            '"pr list") cat "$CMP_GIT_BENCH_DATA/github_pull_requests.json" ;;',
            '"api "*)',
            '    case "$2" in',
            "    */permission) printf '%s' '{\"permission\":\"write\"}' ;;",
            '    *"&page=1") cat "$CMP_GIT_BENCH_DATA/github_mentions.json" ;;',
            "    *) printf '%s' '[]' ;;",
            "    esac",
            "    ;;",
            "*) exit 1 ;;",
            "esac",
            "",
        }, "\n")
    )
    vim.uv.fs_chmod(bin .. "/gh", tonumber("755", 8))
end

local repo_dir = nil ---@type string?

---A git repository with `count` commits from `M.commits` and a GitHub `origin`. It is made once for each run.
---@param count integer
---@return string dir
function M.repo(count)
    if repo_dir then
        return repo_dir
    end

    local dir = M.temp_root() .. "/repo"
    vim.fn.mkdir(dir, "p")
    git({ "-C", dir, "-c", "init.defaultBranch=main", "init", "-q" })
    git({ "-C", dir, "remote", "add", "origin", "https://github.com/owner/repo.git" })

    -- fast-import makes the history in one process. The commits have empty trees.
    local commits = M.commits(count)
    local stream = {}
    for i = #commits, 1, -1 do
        local commit = commits[i]
        local message = commit.subject .. "\n\n" .. commit.body
        local ident = string.format("%s <%s> %d +0000", commit.author.name, commit.author.email, commit.timestamp)
        table.insert(stream, "commit refs/heads/main")
        table.insert(stream, "mark :" .. i)
        table.insert(stream, "author " .. ident)
        table.insert(stream, "committer " .. ident)
        table.insert(stream, "data " .. #message)
        table.insert(stream, message)
        if i < #commits then
            table.insert(stream, "from :" .. (i + 1))
        end
        table.insert(stream, "")
    end
    git({ "-C", dir, "fast-import", "--quiet" }, { stdin = table.concat(stream, "\n") })
    git({ "-C", dir, "config", "user.name", "Bench User" })
    git({ "-C", dir, "config", "user.email", "bench@example.com" })

    repo_dir = dir
    return dir
end

---A commit message buffer in `.git` of the repository, as git opens it. It becomes the current buffer, because
---cmp-git reads the cwd and the filetype from the current buffer.
---@param dir string The repository.
---@param lines string[]
---@return integer bufnr
function M.commit_buffer(dir, lines)
    local bufnr = vim.fn.bufadd(dir .. "/.git/COMMIT_EDITMSG")
    vim.fn.bufload(bufnr)
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].filetype = "gitcommit"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(bufnr)
    return bufnr
end

---A scratch commit message buffer for cases that start no process. It becomes the current buffer.
---@param lines string[]
---@return integer bufnr
function M.scratch_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(true, true)
    vim.bo[bufnr].filetype = "gitcommit"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(bufnr)
    return bufnr
end

return M
