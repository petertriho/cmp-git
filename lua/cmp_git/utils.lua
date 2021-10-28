local M = {}

local char_to_hex = function(c)
    return string.format("%%%02X", string.byte(c))
end

M.url_encode = function(value)
    return string.gsub(value, "([^%w _%%%-%.~])", char_to_hex)
end

M.get_git_info = function()
    local remote_origin_url = vim.fn.system("git config --get remote.origin.url")
    local clean_remote_origin_url = remote_origin_url:gsub("%.git", ""):gsub("%s", "")

    local host, owner, repo = string.match(clean_remote_origin_url, "^git@(.+):(.+)/(.+)$")

    if host == nil then
        host, owner, repo = string.match(clean_remote_origin_url, "^https?://(.+)/(.+)/(.+)$")
    end

    return { host = host, owner = owner, repo = repo }
end

M.handle_response = function(response, handle_item)
    local items = {}

    local process_data = function(ok, parsed)
        if not ok then
            vim.notify("Failed to parse gitlab api result")
            return
        end

        for _, item in ipairs(parsed) do
            table.insert(items, handle_item(item))
        end
    end

    if vim.json and vim.json.decode then
        local ok, parsed = pcall(vim.json.decode, response)
        process_data(ok, parsed)
    else
        vim.schedule(function()
            local ok, parsed = pcall(vim.fn.json_decode, response)
            process_data(ok, parsed)
        end)
    end

    return items
end

return M
