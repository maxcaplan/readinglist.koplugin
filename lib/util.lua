--[[
Reading list plugin helper functions

@module koplugin.readinglist.util
--]]

local ffiUtil = require("ffi/util")

local T = ffiUtil.template

local util = {}

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

return util
