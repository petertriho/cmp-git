-- Helpers for the tests that run the real CLIs. The cases must not use the network: gh and glab talk to a fake HTTP
-- server in this process, and tea, the fj token, and curl talk to Gitea and Forgejo servers on 127.0.0.1.
local MiniTest = require("mini.test")
local helpers = require("tests.helpers")

local uv = vim.uv

local M = {}

---With CMP_GIT_INTEGRATION_REQUIRE=1, as in CI, a missing binary fails the case. Otherwise, it skips the case.
---@param names string[]
function M.require_binaries(names)
    local missing = vim.tbl_filter(function(name)
        return vim.fn.executable(name) ~= 1
    end, names)
    if #missing == 0 then
        return
    end

    local reason = "Missing " .. table.concat(missing, ", ") .. ". Run the tests in `nix develop .#integration`."
    if vim.env.CMP_GIT_INTEGRATION_REQUIRE == "1" then
        error(reason, 2)
    end
    helpers.skip(reason)
end

---A request that the fake server got. The path is not decoded, so that `%2F` in a GitLab project ID stays.
---@class tests.integration.Request
---@field method string
---@field target string The path and the query.
---@field path string
---@field query table<string, string> The decoded query parameters.
---@field headers table<string, string> By lowercase name.
---@field body string

---@class tests.integration.Response
---@field status? integer 200 when it is nil.
---@field body? string|table A table is sent as JSON.
---@field headers? table<string, string>

---@alias tests.integration.Route tests.integration.Response | fun(request: tests.integration.Request): tests.integration.Response

local STATUS_TEXT = {
    [200] = "OK",
    [201] = "Created",
    [204] = "No Content",
    [401] = "Unauthorized",
    [403] = "Forbidden",
    [404] = "Not Found",
    [502] = "Bad Gateway",
}

---@param text string
---@return string
local function decode_component(text)
    text = string.gsub(text, "+", " ")
    return (string.gsub(text, "%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

---@param query string
---@return table<string, string>
local function parse_query(query)
    local result = {}
    for pair in vim.gsplit(query, "&", { plain = true, trimempty = true }) do
        local key, value = string.match(pair, "^([^=]*)=?(.*)$")
        result[decode_component(key)] = decode_component(value)
    end
    return result
end

---@param buffer string The bytes so far.
---@return tests.integration.Request? request nil until the buffer has the head and the body.
local function parse_request(buffer)
    local head_end = string.find(buffer, "\r\n\r\n", 1, true)
    if head_end == nil then
        return nil
    end

    local lines = vim.split(string.sub(buffer, 1, head_end - 1), "\r\n", { plain = true })
    local method, target = string.match(lines[1], "^(%S+) (%S+) HTTP/1%.%d$")
    local headers = {}
    for i = 2, #lines do
        local name, value = string.match(lines[i], "^([^:]+):%s*(.-)%s*$")
        if name ~= nil then
            headers[name:lower()] = value
        end
    end

    -- The CLIs send a body with Content-Length. A chunked body would wait here until the client gives up.
    local length = tonumber(headers["content-length"] or "0") or 0
    local body_start = head_end + 4
    if #buffer < body_start + length - 1 then
        return nil
    end

    local path, query = string.match(target or "", "^([^?]*)%??(.*)$")
    return {
        method = method or "",
        target = target or "",
        path = path or "",
        query = parse_query(query or ""),
        headers = headers,
        body = string.sub(buffer, body_start, body_start + length - 1),
    }
end

---Write the response and close the connection, so that each request needs a new connection.
---@param client uv.uv_stream_t
---@param response tests.integration.Response
local function send(client, response)
    local body = response.body or ""
    if type(body) == "table" then
        body = vim.json.encode(body)
    end
    local status = response.status or 200
    local headers = vim.tbl_extend("force", { ["Content-Type"] = "application/json" }, response.headers or {})
    headers["Content-Length"] = tostring(#body)
    headers["Connection"] = "close"

    local lines = { string.format("HTTP/1.1 %d %s", status, STATUS_TEXT[status] or "Status") }
    for name, value in pairs(headers) do
        table.insert(lines, name .. ": " .. value)
    end
    client:write(table.concat(lines, "\r\n") .. "\r\n\r\n" .. body, function()
        client:shutdown(function()
            client:close()
        end)
    end)
end

---Send the request to the upstream server without the path prefix, and copy its response to the client.
---@param client uv.uv_stream_t
---@param request tests.integration.Request
---@param upstream { port: integer, prefix: string }
local function forward(client, request, upstream)
    local target = string.sub(request.target, #upstream.prefix + 1)
    if string.sub(target, 1, 1) ~= "/" then
        target = "/" .. target
    end
    local lines = { string.format("%s %s HTTP/1.1", request.method, target) }
    for name, value in pairs(request.headers) do
        if name ~= "connection" then
            table.insert(lines, name .. ": " .. value)
        end
    end
    -- The upstream server then closes the connection after the response, and the proxy closes the client
    table.insert(lines, "connection: close")

    local connection = assert(uv.new_tcp())
    connection:connect("127.0.0.1", upstream.port, function(err)
        if err then
            connection:close()
            send(client, { status = 502, body = { message = err } })
            return
        end
        connection:write(table.concat(lines, "\r\n") .. "\r\n\r\n" .. request.body)
        connection:read_start(function(read_err, chunk)
            if chunk ~= nil then
                client:write(chunk)
                return
            end
            if read_err then
                send(client, { status = 502, body = { message = read_err } })
            end
            connection:close()
            client:shutdown(function()
                client:close()
            end)
        end)
    end)
end

---A fake HTTP/1.1 server in this Neovim. It answers while a case waits with `vim.wait`.
---@class tests.integration.HttpServer
---@field url? string `http://127.0.0.1:<port>` for a TCP server.
---@field port? integer
---@field socket? string The path of a Unix socket server.
---@field routes table<string, tests.integration.Route> By `<method> <path>`, such as `GET /api/v4/version`.
---@field requests tests.integration.Request[] The requests so far, in order.
---@field upstream? { port: integer, prefix: string } Set to make the server a proxy that removes the prefix.
---@field handle uv.uv_stream_t
local HttpServer = {}
HttpServer.__index = HttpServer

---@param request tests.integration.Request
---@return tests.integration.Response
function HttpServer:respond(request)
    local route = self.routes[request.method .. " " .. request.path]
    if type(route) == "function" then
        return route(request)
    end
    if route ~= nil then
        return route
    end
    return { status = 404, body = { message = "No route for " .. request.method .. " " .. request.path } }
end

---@param client uv.uv_stream_t
function HttpServer:serve(client)
    local buffer = ""
    client:read_start(function(err, chunk)
        if err or chunk == nil then
            client:close()
            return
        end

        buffer = buffer .. chunk
        -- For example the TLS handshake of an https URL. The client then fails at once and does not wait.
        if not string.find(buffer, "^%u") then
            client:close()
            return
        end
        local request = parse_request(buffer)
        if request == nil then
            return
        end
        client:read_stop()
        table.insert(self.requests, request)

        local upstream = self.upstream
        if upstream == nil then
            -- An error in a route must not kill the loop callback, or the client waits until its timeout
            local ok, response = pcall(self.respond, self, request)
            send(client, ok and response or { status = 500, body = { message = tostring(response) } })
        elseif string.sub(request.path .. "/", 1, #upstream.prefix + 1) == upstream.prefix .. "/" then
            forward(client, request, upstream)
        else
            send(client, { status = 404, body = { message = "Not under " .. upstream.prefix } })
        end
    end)
end

---The requests so far as `<method> <target>`.
---@return string[]
function HttpServer:request_lines()
    return vim.tbl_map(function(request)
        return request.method .. " " .. request.target
    end, self.requests)
end

function HttpServer:close()
    if not self.handle:is_closing() then
        self.handle:close()
    end
end

---Start a fake server on a free TCP port of 127.0.0.1, or on a Unix socket.
---@param opts? { routes?: table<string, tests.integration.Route>, socket?: string, upstream?: { port: integer, prefix: string } }
---@return tests.integration.HttpServer
function M.http_server(opts)
    opts = opts or {}
    local self = setmetatable({ routes = opts.routes or {}, requests = {}, upstream = opts.upstream }, HttpServer)

    if opts.socket then
        local pipe = assert(uv.new_pipe(false))
        assert(pipe:bind(opts.socket))
        self.handle = pipe
        self.socket = opts.socket
    else
        local tcp = assert(uv.new_tcp())
        assert(tcp:bind("127.0.0.1", 0))
        self.handle = tcp
        self.port = tcp:getsockname().port
        self.url = "http://127.0.0.1:" .. self.port
    end

    assert(self.handle:listen(64, function(err)
        assert(not err, err)
        local client = assert(opts.socket and uv.new_pipe(false) or uv.new_tcp(), "cannot make the client handle")
        self.handle:accept(client)
        self:serve(client)
    end))
    return self
end

---@return integer port A port of 127.0.0.1 that no server uses now.
local function free_port()
    local tcp = assert(uv.new_tcp())
    assert(tcp:bind("127.0.0.1", 0))
    local port = tcp:getsockname().port
    tcp:close()
    return port
end

local PASSWORD = "Password1!"

---The settings of a server that starts fast, in its own directory, and does not use the network.
---@param dir string
---@param port integer
---@param root_url string
---@return string[]
local function app_ini(dir, port, root_url)
    return {
        "APP_NAME = cmp-git test",
        "RUN_MODE = prod",
        "WORK_PATH = " .. dir,
        "[database]",
        "DB_TYPE = sqlite3",
        "PATH = " .. dir .. "/data/forge.db",
        "[repository]",
        "ROOT = " .. dir .. "/repos",
        "[server]",
        "HTTP_ADDR = 127.0.0.1",
        "HTTP_PORT = " .. port,
        "ROOT_URL = " .. root_url,
        "DISABLE_SSH = true",
        "OFFLINE_MODE = true",
        "APP_DATA_PATH = " .. dir .. "/data",
        "LFS_START_SERVER = false",
        "[security]",
        "INSTALL_LOCK = true",
        "SECRET_KEY = cmp-git-test-secret",
        "INTERNAL_TOKEN = cmp-git-test-internal-token",
        "[oauth2]",
        "ENABLED = false",
        "[service]",
        "DISABLE_REGISTRATION = true",
        "[actions]",
        "ENABLED = false",
        "[packages]",
        "ENABLED = false",
        "[log]",
        "MODE = console",
        "LEVEL = Info",
        "[cron]",
        "ENABLED = false",
        "[indexer]",
        "ISSUE_INDEXER_TYPE = db",
        "REPO_INDEXER_ENABLED = false",
        "[mailer]",
        "ENABLED = false",
    }
end

---A real Gitea or Forgejo server for the cases of one file, on 127.0.0.1 in its own temporary directory. The first
---case that calls `start` starts it, and `stop` in `post_once` ends it.
---@class tests.integration.Forge
---@field bin "gitea" | "forgejo"
---@field prefix? string
---@field url? string The URL for cmp-git and the CLIs, with the path prefix, such as `http://127.0.0.1:3000`.
---@field host? string The host for cmp-git, with the port and the path prefix, such as `127.0.0.1:3000`.
---@field token? string An access token of the admin user `root`.
---@field port? integer The port of the server.
---@field dir? string
---@field proxy? tests.integration.HttpServer The proxy that removes the path prefix.
---@field process? vim.SystemObj
---@field exit_code? integer
---@field output string[] The output of the server so far.
---@field failure? string The error of a start that failed. The next cases fail with it at once.
---@field exe? string
---@field curl? string
---@field env? table<string, string>
local Forge = {}
Forge.__index = Forge

---@param bin "gitea" | "forgejo"
---@param opts? { prefix?: string } A path prefix in ROOT_URL. A proxy in front of the server removes it, because
---the server does not serve its routes under the prefix.
---@return tests.integration.Forge
function M.forge(bin, opts)
    opts = opts or {}
    return setmetatable({ bin = bin, prefix = opts.prefix, output = {} }, Forge)
end

---Run a command of the server binary, and fail with its output when it fails.
---@param args string[]
---@return string stdout
function Forge:run(args)
    local dir = assert(self.dir, "the server has no directory")
    local command = vim.list_extend({ self.exe }, args)
    vim.list_extend(command, { "--config", dir .. "/app.ini", "--work-path", dir })
    local result = vim.system(command, { env = self.env, clear_env = true, text = true }):wait(120000)
    if result.code ~= 0 then
        error(string.format("`%s %s` failed:\n%s%s", self.bin, args[1], result.stdout, result.stderr), 0)
    end
    return result.stdout
end

---Send a request to the API of the server as `root`.
---@param method string
---@param path string The path after `/api/v1`.
---@param body? table Sent as JSON.
---@return any response The decoded JSON, or nil for an empty response.
function Forge:api(method, path, body)
    local command = { self.curl, "-sS", "--fail-with-body", "-X", method }
    vim.list_extend(command, { "-H", "Authorization: token " .. self.token, "-H", "Content-Type: application/json" })
    if body then
        vim.list_extend(command, { "--data-binary", vim.json.encode(body) })
    end
    table.insert(command, string.format("http://127.0.0.1:%d/api/v1%s", self.port, path))

    local result = vim.system(command, { text = true }):wait(30000)
    if result.code ~= 0 then
        error(string.format("%s %s failed: %s%s", method, path, result.stdout, result.stderr), 2)
    end
    return result.stdout ~= "" and vim.json.decode(result.stdout) or nil
end

---Wait until the API answers, or fail with the output of the server.
function Forge:wait_until_ready()
    local version = string.format("http://127.0.0.1:%d/api/v1/version", self.port)
    local deadline = uv.hrtime() + 120e9
    while vim.system({ self.curl, "-sf", version }):wait(5000).code ~= 0 do
        if self.exit_code ~= nil then
            error(string.format("%s exited with %d:\n%s", self.bin, self.exit_code, self:log()), 0)
        end
        if uv.hrtime() > deadline then
            error(string.format("%s did not answer within 120 s:\n%s", self.bin, self:log()), 0)
        end
        vim.wait(100)
    end
end

---The repositories of `root`: `root/public` and the private `root/private`. Each has the issue #1, the pull request
---#2 from the branch `feature`, and the collaborator `ada`, so that the assignees are `ada` and `root`.
function Forge:seed()
    self:api("POST", "/admin/users", {
        username = "ada",
        full_name = "Ada Lovelace",
        email = "ada@example.com",
        password = PASSWORD,
        must_change_password = false,
    })
    for _, name in ipairs({ "public", "private" }) do
        local repo = "/repos/root/" .. name
        self:api("POST", "/user/repos", { name = name, private = name == "private", auto_init = true })
        self:api("POST", repo .. "/issues", { title = "A " .. name .. " issue", body = "The body of the issue" })
        self:api("POST", repo .. "/contents/feature.txt", {
            content = vim.base64.encode("feature\n"),
            message = "Add a feature",
            new_branch = "feature",
        })
        self:api("POST", repo .. "/pulls", {
            head = "feature",
            base = "main",
            title = "A " .. name .. " pull request",
            body = "Fixes #1",
        })
        self:api("PUT", repo .. "/collaborators/ada", { permission = "write" })
    end
end

function Forge:launch()
    local started = uv.hrtime()
    self.exe = vim.fn.exepath(self.bin)
    self.curl = vim.fn.exepath("curl")
    -- Outside the temporary directory of the case, which the case hooks delete
    self.dir = vim.fn.tempname()
    vim.fn.mkdir(self.dir, "p")
    self.port = free_port()

    local root_url = string.format("http://127.0.0.1:%d/", self.port)
    if self.prefix then
        self.proxy = M.http_server({ upstream = { port = self.port, prefix = "/" .. self.prefix } })
        root_url = string.format("%s/%s/", self.proxy.url, self.prefix)
    end
    self.url = string.gsub(root_url, "/$", "")
    self.host = string.gsub(self.url, "^http://", "")
    assert(
        vim.fn.writefile(app_ini(self.dir, self.port, root_url), self.dir .. "/app.ini") == 0,
        "cannot write app.ini"
    )

    -- Only these variables, so that the GITEA__* and FORGEJO__* variables of the developer do not change the settings.
    -- The server runs git from PATH.
    self.env = { HOME = self.dir, PATH = vim.env.PATH, USER = vim.env.USER or "cmp-git" }
    self:run({ "migrate" })
    local created = self:run({
        "admin",
        "user",
        "create",
        "--admin",
        "--username",
        "root",
        "--password",
        PASSWORD,
        "--email",
        "root@example.com",
        "--access-token",
        "--must-change-password=false",
    })
    self.token = string.match(created, "Access token was successfully created%.%.%. (%x+)")
    assert(self.token, "no access token in the output: " .. created)

    local function collect(_, data)
        if data then
            table.insert(self.output, data)
        end
    end
    local web = vim.list_extend({ self.exe, "web" }, { "--config", self.dir .. "/app.ini", "--work-path", self.dir })
    self.process = vim.system(web, {
        env = self.env,
        clear_env = true,
        text = true,
        stdout = collect,
        stderr = collect,
    }, function(result)
        self.exit_code = result.code
    end)
    self:wait_until_ready()
    self:seed()

    MiniTest.add_note(string.format("%s started and seeded in %.1f s", self.bin, (uv.hrtime() - started) / 1e9))
end

---Start the server once for the file, and give it to the case. Call it before the case changes PATH. Forgejo always
---skips on aarch64-darwin, where nixpkgs marks it as broken. When the case fails, the server log goes to its notes.
---@return tests.integration.Forge
function Forge:start()
    local uname = uv.os_uname()
    if self.bin == "forgejo" and uname.sysname == "Darwin" and uname.machine == "arm64" then
        helpers.skip("nixpkgs has no forgejo for aarch64-darwin")
    end
    M.require_binaries({ self.bin, "curl", "git" })
    if self.failure then
        error(self.failure, 0)
    end
    if not self.process then
        local ok, err = pcall(self.launch, self)
        if not ok then
            self.failure = tostring(err)
            error(self.failure, 0)
        end
    end

    helpers.defer(function()
        local case = MiniTest.current.case
        if case and #case.exec.fails > 0 then
            MiniTest.add_note(string.format("The log of %s:\n%s", self.bin, self:log()))
        end
    end)
    return self
end

---@return string lines The last lines of the server output.
function Forge:log()
    local lines = vim.split(table.concat(self.output), "\n", { trimempty = true })
    return table.concat(vim.list_slice(lines, math.max(1, #lines - 40)), "\n")
end

function Forge:stop()
    if self.process and self.exit_code == nil then
        self.process:kill(15)
        if not vim.wait(10000, function()
            return self.exit_code ~= nil
        end, 50) then
            self.process:kill(9)
            vim.wait(5000, function()
                return self.exit_code ~= nil
            end, 50)
        end
    end
    if self.proxy then
        self.proxy:close()
    end
    if self.dir then
        vim.fn.delete(self.dir, "rf")
    end
end

---Run a CLI with the arguments, and fail with its output when it fails.
---@param command string[]
local function run_cli(command)
    local result = vim.system(command, { text = true, stdin = "" }):wait(30000)
    if result.code ~= 0 then
        error(string.format("`%s` failed:\n%s%s", table.concat(command, " ", 1, 3), result.stdout, result.stderr), 2)
    end
end

---Give tea one login for the server, in a new config directory, until the end of the case.
---@param server tests.integration.Forge
---@param name string
function M.use_tea(server, name)
    helpers.stub(vim.env, "XDG_CONFIG_HOME", helpers.tempdir())
    run_cli({
        "tea",
        "login",
        "add",
        "--name",
        name,
        "--url",
        assert(server.url, "start the server first"),
        "--token",
        server.token,
    })
end

---Give tea a new config directory without logins until the end of the case.
function M.without_tea_logins()
    helpers.stub(vim.env, "XDG_CONFIG_HOME", helpers.tempdir())
end

---Give fj the token of the server with `fj auth add-token`, in a new data directory, until the end of the case.
---@param server tests.integration.Forge
function M.use_fj(server)
    helpers.stub(vim.env, "XDG_DATA_HOME", helpers.tempdir())
    run_cli({ "fj", "--host", assert(server.url, "start the server first"), "auth", "add-token", server.token })
end

---@param path string
---@param lines string[]
local function write_file(path, lines)
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    assert(vim.fn.writefile(lines, path) == 0, "cannot write " .. path)
    -- glab reads no config file that other users can read
    assert(uv.fs_chmod(path, tonumber("600", 8)))
end

---Put commands that exit with a code first on PATH until the end of the case. The other commands stay.
---@param codes table<string, integer> The exit code of each command, by name.
function M.failing_commands(codes)
    local bin = helpers.tempdir()
    for name, code in pairs(codes) do
        local path = bin .. "/" .. name
        assert(vim.fn.writefile({ "#!/bin/sh", "exit " .. code }, path) == 0, "cannot write " .. path)
        assert(uv.fs_chmod(path, tonumber("755", 8)))
    end
    helpers.stub(vim.env, "PATH", bin .. ":" .. vim.env.PATH)
end

---The curl fallback of GitHub and GitLab uses the real hosts. A curl that fails at once, as without a connection,
---keeps the cases off the network when a CLI fails.
function M.offline_curl()
    -- 7 is the exit code of curl for a failed connection
    M.failing_commands({ curl = 7 })
end

---Open a buffer in a new directory outside a repository. The commands of its requests run there, so that the git
---config of the cmp-git checkout, such as the default repository of gh, does not reach them.
---@return integer bufnr
function M.edit_outside_repository()
    vim.cmd.edit(vim.fn.fnameescape(helpers.tempdir() .. "/COMMIT_EDITMSG"))
    return vim.api.nvim_get_current_buf()
end

---Make gh send all its requests to the server until the end of the case. gh then uses plain HTTP over the socket for
---each host.
---@param server tests.integration.HttpServer A Unix socket server.
function M.use_gh(server)
    local dir = helpers.tempdir()
    write_file(dir .. "/config.yml", { "http_unix_socket: " .. assert(server.socket, "gh needs a Unix socket") })
    helpers.stub(vim.env, "GH_CONFIG_DIR", dir)
    helpers.stub(vim.env, "GH_TOKEN", "gh-token")
    helpers.stub(vim.env, "GH_PROMPT_DISABLED", "1")
    helpers.stub(vim.env, "GH_NO_UPDATE_NOTIFIER", "1")
end

---Make glab send its requests for the host to the server until the end of the case.
---@param server tests.integration.HttpServer A TCP server.
---@return string host The host of the server, `127.0.0.1:<port>`.
function M.use_glab(server)
    local host = "127.0.0.1:" .. assert(server.port, "glab needs a TCP server")
    local dir = helpers.tempdir()
    write_file(dir .. "/config.yml", {
        "check_update: false",
        "hosts:",
        "  " .. host .. ":",
        "    api_protocol: http",
        "    api_host: " .. host,
        "    token: glab-token",
    })
    helpers.stub(vim.env, "GLAB_CONFIG_DIR", dir)
    helpers.stub(vim.env, "GITLAB_HOST", host)
    helpers.stub(vim.env, "GITLAB_TOKEN", "glab-token")
    helpers.stub(vim.env, "GLAB_SEND_TELEMETRY", "false")
    helpers.stub(vim.env, "GLAB_SHOW_WHATS_NEW", "false")
    helpers.stub(vim.env, "GLAB_CHECK_UPDATE", "false")
    return host
end

return M
