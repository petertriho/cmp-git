local M = {}

local function notify(level, message)
    vim.schedule(function()
        vim.notify(message, level, { title = "cmp-git" })
    end)
end

function M.debug(message)
    if vim.g.cmp_git_debug then
        notify(vim.log.levels.DEBUG, message)
    end
end

function M.fmt_debug(message, ...)
    if vim.g.cmp_git_debug then
        M.debug(string.format(message, ...))
    end
end

function M.warn(message)
    notify(vim.log.levels.WARN, message)
end

return M
