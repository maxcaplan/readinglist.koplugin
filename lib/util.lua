--[[
Reading list plugin helper functions

@module koplugin.readinglist.util
--]]

local ffiUtil = require("ffi/util")

local T = ffiUtil.template

local util = {}

--- Load meta data string from text file
-- @param file File to load relative to plugin dir
function util.loadMeta(file)
    local function script_path()
        local path = debug.getinfo(2, "S").source:sub(2)
        path = path:match("(.*/)") or "./"

        -- Remove `lib/` from end of path
        local suffix = "lib/"
        if path:sub(-#suffix) == suffix then
            path = path:sub(1, -#suffix - 1)
        end

        return path
    end

    local function startsWithAny(s, patterns)
        for _, pattern in ipairs(patterns) do
            if string.find(s, pattern) == 1 then
                return true
            end
        end

        return false
    end

    local meta_fields = {
        name = { "NAME", "name", "Name" },
        fullname = { "FULLNAME", "fullname", "FullName", "FULL_NAME", "full_name", "Full_Name" },
        description = { "DESCRIPTION", "description", "Description" },
        version = { "VERSION", "version", "Version" },
    }

    local meta = {}

    for line in io.lines(script_path() .. file) do
        if type(line) == "string" then
            for meta_field, meta_key_names in pairs(meta_fields) do
                if startsWithAny(line, meta_key_names) then
                    local idx = 0
                    for sub_str in string.gmatch(line, "([^=]+)") do
                        if idx > 1 then
                            break
                        end

                        if idx == 1 then
                            meta[meta_field] = sub_str
                            break
                        end

                        idx = idx + 1
                    end
                end
            end
        end
    end

    assert(meta.name, "ReadingList: Name not found in plugin meta file")
    assert(meta.version, "ReadingList: Version number not found in plugin meta file")
    return meta
end

--- Return table of major and minor numbers of a string or number.
--- Example: "1.10" -> { major = 1, minor = 10 }
--- Example: "20" -> { major = 20, minor = 0 }
--- Example: "ab.cd" -> nil
--- Example: 12.9 -> { major = 12, minor = 9 }
function util.parseVersion(value)
    -- Ensure value param is a valid type
    if type(value) ~= "string" and type(value) ~= "number" then
        return nil
    end

    local major, minor

    -- Iterate through values seperated by "."
    local idx = 0
    for sub_str in string.gmatch(value, "[^%.]+") do
        local sub_num = tonumber(sub_str)

        if sub_num then
            -- Set major to first value and minor to second
            if idx == 0 then
                major = sub_num
            elseif idx == 1 then
                minor = sub_num
            end
        end

        -- Don't iterate past 2 values
        if idx > 0 then
            break
        end

        idx = idx + 1
    end

    -- Return nil if failed to parse
    if major == nil then
        return nil
    end

    -- Return parsed value
    return { major = major, minor = minor or 0 }
end

--- Convert major and minor number to a version formatted string
--- Example: 1, 10 -> "1.10"
--- Example: "12" -> "12"
--- Example: { major = 1, minor = 10 } -> "1.10"
--- Example: nil, 10 -> nil
function util.toVersionString(major, minor)
    local function validVersionType(value)
        return type(value) == "number" or type(value) == "string"
    end

    -- Ensure major param is valid type
    if not validVersionType(major) and type(major) ~= "table" then
        return nil
    end

    -- Process just first param if it is a table
    if type(major) == "table" then
        if not validVersionType(major.major) then
            return nil
        end

        -- Return version with major and minor if minor is set
        if validVersionType(major.minor) then
            return tostring(major.major) .. "." .. tostring(major.minor)
        end

        -- Return major version if minor is not set
        return tostring(major.major)
    end

    -- Return version with major and minor if minor is set
    if validVersionType(minor) then
        return tostring(major) .. "." .. tostring(minor)
    end

    -- Return major version if minor is not set
    return tostring(major)
end

--- Determin whether a version is valid based on a reference version.
--- Example: "1.1", "1.1" -> true
--- Example: "1.1", "1.10" -> true
--- Example: "1.20", "1.10" -> false
--- Example: "1.1", "2.10" -> false
--- Example: "2.1", "1.10" -> false
-- @param version Version to validate
-- @param ref_version Version to validate against
function util.validateVersion(version, ref_version)
    if version == nil or ref_version == nil then
        return false, "Invalid values for versions"
    end

    local parsed_version = version
    local parsed_ref_version = ref_version

    -- Ensure version values have been parsed
    if type(parsed_version) ~= "table" then
        parsed_version = util.parseVersion(parsed_version)
    end
    if type(parsed_ref_version) ~= "table" then
        parsed_ref_version = util.parseVersion(parsed_ref_version)
    end

    -- Ensure version values were properly parsed
    if parsed_version.major == nil or parsed_version.minor == nil then
        return false, "Invalid value for version"
    end
    if parsed_ref_version.major == nil or parsed_ref_version.minor == nil then
        return false, "Invalid value for ref version"
    end

    -- Ensure versions have same major value
    if parsed_version.major ~= parsed_ref_version.major then
        return false, T("Major version '%1' does not match '%2'", parsed_version.major, parsed_ref_version.major)
    end

    -- Ensure version has smaller or equal minor value to ref version
    if parsed_version.minor > parsed_ref_version.minor then
        return false,
            T("Minor version '%1' must be less than or equal to '%2'", parsed_version.minor, parsed_ref_version.minor)
    end

    return true, nil
end

--- Create hash map of table order values
local function _createOrderMap(table)
    local order_map = { max = 0, min = 0, map = {} }

    for key, value in pairs(table) do
        assert(
            type(value.order) == "number" and value.order >= 0,
            "All table elements must have a non negative 'order' field"
        )
        assert(order_map.map[value.order] == nil, "All table elements must have an 'order' field with a unique value")

        order_map.map[value.order] = key

        if value.order > order_map.max then
            order_map.max = value.order
        end

        if value.order < order_map.min then
            order_map.min = value.order
        end
    end

    return order_map
end

--- Functions like `pairs(table, key)` but gets the next table key and value
--- based on an `order` field of table elemenets
function util.orderedNext(table, key)
    if table == nil then
        return nil
    end

    local index = 0

    -- Generate order index if not set
    if table.__order_map == nil then
        table.__order_map = _createOrderMap(table)
        index = table.__order_map.min
    end

    if key ~= nil then
        index = table[key].order + 1
    end

    -- Get next value and index
    while index <= table.__order_map.max do
        for order_key, order_value in pairs(table.__order_map.map) do
            if order_key == index then
                return table.__order_map.map[index], table[order_value]
            end
        end

        index = index + 1
    end

    -- No more items
    table.__order_map = nil
    return nil
end

--- Functions like `pairs(data)` but returns pairs
--- based on an `order` field value value
function util.orderedPairs(table)
    return util.orderedNext, table, nil
end

return util
