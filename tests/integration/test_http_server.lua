local helpers = require("tests.helpers")
local integration = require("tests.integration.helpers")

local eq = helpers.eq

local T = helpers.new_set()

---A fake server that closes at the end of the case.
---@param opts? table
---@return tests.integration.HttpServer
local function server(opts)
    local fake = integration.http_server(opts)
    helpers.defer(function()
        fake:close()
    end)
    return fake
end

---Run curl and wait for it, while the server answers in the event loop.
---@param args string[]
---@return { code: integer, stdout: string }
local function curl(args)
    local result
    vim.system(vim.list_extend({ "curl", "-s", "-S" }, args), { text = true }, function(completed)
        result = completed
    end)
    helpers.wait_for(function()
        return result ~= nil
    end, "curl ends")
    return result
end

T["a_route_answers_and_the_server_records_the_request"] = function()
    integration.require_binaries({ "curl" })
    local fake = server({ routes = { ["GET /api/v1/items"] = { body = { { id = 1 } } } } })

    local result = curl({ "-H", "Authorization: token secret", fake.url .. "/api/v1/items?state=open&q=a%20b" })

    eq(result.code, 0, "curl succeeds")
    eq(vim.json.decode(result.stdout), { { id = 1 } }, "the JSON of the route")
    eq(fake:request_lines(), { "GET /api/v1/items?state=open&q=a%20b" }, "the request")
    eq(fake.requests[1].query, { state = "open", q = "a b" }, "the decoded query")
    eq(fake.requests[1].headers.authorization, "token secret", "the headers by lowercase name")
end

T["a_function_route_gets_the_body"] = function()
    integration.require_binaries({ "curl" })
    local fake = server({
        routes = {
            ["POST /graphql"] = function(request)
                return { status = 201, body = { echo = vim.json.decode(request.body).query } }
            end,
        },
    })

    local result = curl({ "-w", "\n%{http_code}", "-d", '{"query":"IssueList"}', fake.url .. "/graphql" })

    eq(vim.split(result.stdout, "\n"), { '{"echo":"IssueList"}', "201" }, "the body and the status of the route")
end

T["a_missing_route_or_a_failed_route_is_an_http_error"] = function()
    integration.require_binaries({ "curl" })
    local fake = server({
        routes = {
            ["GET /broken"] = function()
                error("broken route")
            end,
        },
    })

    eq(curl({ "--fail", fake.url .. "/missing" }).code, 22, "a missing route is a 404")
    eq(curl({ "-o", "/dev/null", "-w", "%{http_code}", fake.url .. "/broken" }).stdout, "500", "a route error")
end

T["a_server_on_a_unix_socket"] = function()
    integration.require_binaries({ "curl" })
    local socket = helpers.tempdir() .. "/server.sock"
    local fake = server({ socket = socket, routes = { ["GET /user"] = { body = '{"login":"octocat"}' } } })

    local result = curl({ "--unix-socket", socket, "http://api.github.com/user" })

    eq(result.stdout, '{"login":"octocat"}', "the body of the route")
    eq(fake.requests[1].headers.host, "api.github.com", "the host of the URL")
end

T["a_proxy_removes_the_path_prefix"] = function()
    integration.require_binaries({ "curl" })
    local upstream = server({ routes = { ["GET /api/v1/version"] = { body = { version = "1" } } } })
    local proxy = server({ upstream = { port = assert(upstream.port, "a TCP server has a port"), prefix = "/gitea" } })

    eq(curl({ proxy.url .. "/gitea/api/v1/version?x=1" }).stdout, '{"version":"1"}', "the upstream answers")
    eq(upstream:request_lines(), { "GET /api/v1/version?x=1" }, "the upstream gets the path without the prefix")
    eq(curl({ "--fail", proxy.url .. "/api/v1/version" }).code, 22, "a path outside the prefix is a 404")
    eq(curl({ "--fail", proxy.url .. "/giteax/api/v1/version" }).code, 22, "the prefix is a whole segment")
    eq(#upstream.requests, 1, "the upstream gets only the requests under the prefix")
end

T["a_tls_handshake_fails_at_once"] = function()
    integration.require_binaries({ "curl" })
    local fake = server()

    local start = vim.uv.now()
    local result = curl({ "--max-time", "5", "https://127.0.0.1:" .. fake.port .. "/" })

    helpers.neq(result.code, 0, "curl fails")
    helpers.ok(vim.uv.now() - start < 4000, "without a wait for the timeout")
end

return T
