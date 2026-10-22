local helpers = require("tests.helpers")
local utils = require("cmp_git.utils")

local eq = helpers.eq

local T = helpers.new_set()

T["trim"] = function()
    eq(utils.trim("  subject line \n"), "subject line", "trims both ends")
    eq(utils.trim("   "), "", "whitespace only")
end

T["split_nul"] = function()
    eq(utils.split_nul("one\0\0two three\0"), { "one", "", "two three" }, "keeps empty records")
    eq(utils.split_nul("one\0dangling"), { "one" }, "drops a trailing record without a NUL")
    eq(utils.split_nul(""), {}, "empty input")
end

T["url_encode"] = function()
    eq((utils.url_encode("group/subgroup/project")), "group%2Fsubgroup%2Fproject", "encodes slashes")
    eq((utils.url_encode("my-group/my.project_2~x")), "my-group%2Fmy.project_2~x", "keeps unreserved characters")
    eq((utils.url_encode("a+b&c=d?e#f")), "a%2Bb%26c%3Dd%3Fe%23f", "encodes reserved characters")
end

T["parse_github_date"] = function()
    eq(utils.parse_github_date("2024-01-02T03:04:05Z"), 1704164645, "UTC date")
    eq(utils.parse_github_date("2000-02-29T12:00:00Z"), 951825600, "leap day")
    eq(utils.parse_github_date("1999-12-31T23:59:59Z"), 946684799, "end of a year")
    eq(utils.parse_github_date("2100-03-01T00:00:00Z"), 4107542400, "after a century year without a leap day")
end

T["parse_gitlab_date"] = function()
    eq(utils.parse_gitlab_date("2024-01-02T03:04:05.678Z"), 1704164645, "UTC date with milliseconds")
    eq(utils.parse_gitlab_date("2024-01-02T03:04:05Z"), 1704164645, "UTC date without milliseconds")
    eq(utils.parse_gitlab_date("2024-01-02T03:04:05.678+05:30"), 1704144845, "a + offset is ahead of UTC")
    eq(utils.parse_gitlab_date("2024-01-02T03:04:05.678-05:30"), 1704184445, "a - offset is behind UTC")
end

T["parse_dates_ignore_the_local_time_zone"] = function()
    -- A POSIX time zone 5 hours behind UTC, which needs no time zone database
    helpers.stub(vim.env, "TZ", "XYZ+05")

    eq(utils.parse_github_date("2024-01-02T03:04:05Z"), 1704164645, "GitHub date")
    eq(utils.parse_gitlab_date("2024-01-02T03:04:05.678Z"), 1704164645, "GitLab date")
end

T["parse_dates_without_a_valid_value"] = function()
    for _, parse in ipairs({ utils.parse_github_date, utils.parse_gitlab_date }) do
        eq(parse(nil), 0, "a missing date is the oldest")
        eq(parse(vim.NIL), 0, "a JSON null date is the oldest")
        eq(parse("yesterday"), 0, "an unknown format is the oldest")
        eq(parse("2024-01-02T03:04:05"), 0, "a date without a time zone is the oldest")
    end
end

return T
