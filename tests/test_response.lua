local helpers = require("tests.helpers")
local response = require("cmp_git.response")

local eq = helpers.eq

local T = helpers.new_set()

T["handle_response"] = function()
    local items = response.handle_response('[{"name":"one"}]', function(item)
        return { label = item.name }
    end)
    eq(#items, 1, "valid JSON item count")
    eq(items[1].label, "one", "valid JSON item mapping")

    local mapped = response.handle_response('{"items":[{"name":"two"}]}', function(item)
        return { label = item.name }
    end, function(parsed)
        return parsed.items
    end)
    eq(#mapped, 1, "mapped JSON item count")
    eq(mapped[1].label, "two", "mapped JSON item mapping")

    local empty = response.handle_response("[]", function(item)
        return item
    end)
    eq(#empty, 0, "empty JSON item count")

    local invalid = response.handle_response("not json", function(item)
        return item
    end)
    eq(#invalid, 0, "invalid JSON item count")
    helpers.flush()
    eq(helpers.notifications[1].message, "Failed to parse api result", "invalid JSON logs a warning")
end

return T
