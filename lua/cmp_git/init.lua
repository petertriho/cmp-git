local Source = require("cmp_git.source")

local M = {}

M.setup = function(overrides)
    require("cmp").register_source("git", Source.new(overrides))
end

return M
