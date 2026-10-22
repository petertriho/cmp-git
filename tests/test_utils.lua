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
    eq(
        utils.parse_github_date("2024-01-02T03:04:05Z"),
        os.time({ year = 2024, month = 1, day = 2, hour = 3, min = 4, sec = 5 }),
        "UTC date"
    )
end

T["parse_gitlab_date"] = function()
    local with_offset = os.time({ year = 2024, month = 1, day = 2, hour = 8, min = 34, sec = 5 })

    eq(utils.parse_gitlab_date("2024-01-02T03:04:05.678+05:30"), with_offset, "date with a + offset")
    -- The offset sign is not applied, so both signs give the same time
    eq(utils.parse_gitlab_date("2024-01-02T03:04:05.678-05:30"), with_offset, "date with a - offset")
    eq(
        utils.parse_gitlab_date("2024-01-02T03:04:05.678Z"),
        os.time({ year = 2024, month = 1, day = 2, hour = 3, min = 4, sec = 5 }),
        "UTC date without offset captures"
    )
end

return T
