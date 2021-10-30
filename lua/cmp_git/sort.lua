local M = {}

M.get_sort_text = function(config_val, item)
    if type(config_val) == "function" then
        return config_val(item)
    elseif type(config_val) == "string" then
        return item[config_val]
    end

    return nil
end

return M
