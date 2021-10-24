local Source = require("cmp_git.source")

local M = {}

M.setup = function(overrides)
    require("cmp").register_source("cmp_git", Source.new(overrides))
end

return M
