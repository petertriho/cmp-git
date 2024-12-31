local Source = require("cmp_git.source")

local M = {}

function M.setup(overrides)
    require("cmp").register_source("git", Source.new(overrides))
end

return M
