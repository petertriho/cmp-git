local helpers = require("tests.helpers")
local log = require("cmp_git.log")

local eq = helpers.eq

local T = helpers.new_set()

T["logger"] = function()
    log.debug("debug message")
    log.fmt_debug("debug %s", "message")
    log.warn("warn message")
    helpers.flush()

    eq(helpers.notifications, {
        { message = "warn message", level = vim.log.levels.WARN, opts = { title = "cmp-git" } },
    }, "debug messages are off by default")

    helpers.stub(vim.g, "cmp_git_debug", true)
    log.fmt_debug("debug %s", "message")
    helpers.flush()

    eq(helpers.notifications[2], {
        message = "debug message",
        level = vim.log.levels.DEBUG,
        opts = { title = "cmp-git" },
    }, "debug messages show with cmp_git_debug")
end

return T
