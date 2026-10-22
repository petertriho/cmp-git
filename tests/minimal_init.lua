local script_path = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(script_path, ":p:h:h")

vim.opt.runtimepath:prepend(root .. "/deps/mini.nvim")
vim.opt.runtimepath:prepend(root)
-- Lets test files `require("tests.helpers")` after a case changes the cwd
package.path = root .. "/?.lua;" .. package.path

require("mini.test").setup({
    execute = {
        reporter = require("mini.test").gen_reporter.stdout(),
    },
})
