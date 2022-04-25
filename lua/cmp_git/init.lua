local Source = require("cmp_git.source")

local M = {}

M.setup = function(overrides)
    local cmp_git_source = Source.new(overrides)
    local notified = false
    cmp_git_source.complete = function(params, callback)
        if not notified then
            vim.api.nvim_echo({
                { "[cmp-git] ", "Normal" },
                { "source name ", "Normal" },
                { "'cmp_git' ", "WarningMsg" },
                { "is being deprecated. Change this to ", "Normal" },
                { "'git' ", "WarningMsg" },
                { "in your nvim-cmp setup.", "Normal" },
            }, true, {})
            notified = true
        end
    end

    require("cmp").register_source("cmp_git", cmp_git_source)
    require("cmp").register_source("git", Source.new(overrides))
end

return M
