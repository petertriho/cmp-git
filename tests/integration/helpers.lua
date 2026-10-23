-- Helpers for the tests that run the real CLIs. The cases must not use the network: gh and glab talk to a fake HTTP
-- server in this process, and tea, the fj token, and curl talk to Gitea and Forgejo servers on 127.0.0.1.
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
