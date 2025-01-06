local Source = require("cmp_git.source")

local M = {}

---@param overrides cmp_git.Config Can be a partial config
function M.setup(overrides)
    require("cmp").register_source("git", Source.new(overrides))
end

return M
