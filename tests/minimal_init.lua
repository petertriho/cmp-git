local script_path = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(script_path, ":p:h:h")

vim.opt.runtimepath:prepend(root .. "/deps/mini.nvim")
vim.opt.runtimepath:prepend(root)
-- Lets test files `require("tests.helpers")` after a case changes the cwd
package.path = root .. "/?.lua;" .. package.path

-- `make test` runs the unit tests. `make test-integration` sets TEST_SUITE=integration and runs the tests in
-- `tests/integration/`, which need the CLIs and the servers of the `integration` shell.
local integration = vim.env.TEST_SUITE == "integration"

require("mini.test").setup({
    collect = {
        find_files = function()
            return vim.tbl_filter(function(file)
                return (file:find("^tests/integration/") ~= nil) == integration
            end, vim.fn.globpath("tests", "**/test_*.lua", true, true))
        end,
    },
    execute = {
        reporter = require("mini.test").gen_reporter.stdout(),
    },
})
