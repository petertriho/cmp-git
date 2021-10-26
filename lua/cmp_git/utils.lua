local M = {
    has_nvim_0_5_1 = vim.fn.has("nvim-0.5.1"),
}

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

    if M.has_nvim_0_5_1 then
        vim.schedule(function()
            local ok, parsed = pcall(vim.fn.json_decode, response)
            process_data(ok, parsed)
        end)
    else
        local ok, parsed = pcall(vim.json_decode, response)
        process_data(ok, parsed)
    end

    return items
end

return M
