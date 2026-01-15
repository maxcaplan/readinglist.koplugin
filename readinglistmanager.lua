--[[
Reading list plugin data manager

@module koplugin.readinglist.readinglistmanager
--]]

local xml2lua = require("lib.xml2lua.xml2lua")
local handler = require("lib.xml2lua.xmlhandler.tree")
local pluginUtil = require("lib.util")

local DataStorage = require("datastorage")

local logger = require("logger")
local util = require("util")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")

local T = ffiUtil.template

local XML_DECLARATION_STRING = '<?xml version="1.0" encoding="UTF-8"?>'

local ReadingListManager = {
    schema_version = { major = 1, minor = 0 }, -- XML data schema version
    reading_lists_file = "reading_lists.xml", -- Reading lists data file name
    reading_lists_path = nil, -- Reading lists data file path
    parser = nil, -- Data file parser
    handler = nil, -- Data parser handler
    data = nil, -- Reading lists data table
    updated = false, -- Whether there are unflushed reading list settings
    max_order = 0, -- Read only maximum order value for data
    root = { -- Data associated with the root XML element
        schema_uri = "https://raw.githubusercontent.com/maxcaplan/readinglist.koplugin/refs/heads/master/reading_lists_schema.xsd", -- XML data schema file location
    },
}

--- Create a new reading list manager instance
-- @param schema_version Version for XML data schema
function ReadingListManager:new(o, schema_version)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    if schema_version then
        o.schema_version = schema_version
    end

    o:init()

    return o
end

--- Initialize reading list manager instance
function ReadingListManager:init()
    -- Ensure valid schma version is set
    assert(self.schema_version ~= nil, "`ReadingListManager.schema_version` cannot be nil")
    assert(self.schema_version.major ~= nil, "`ReadingListManager.schema_version.major` cannot be nil")

    -- Ensure reading lists file name is set
    assert(type(self.reading_lists_file) == "string", "`ReadingListManager.reading_lists_file` is not a string")

    -- Ensure reading lists file path is set
    if not self.reading_lists_path then
        self.reading_lists_path = DataStorage:getDataDir() .. "/" .. self.reading_lists_file
    end

    -- Instantiate XML parser
    self.handler = handler:new()
    self.parser = xml2lua.parser(self.handler)
end

--- Load reading lists data
function ReadingListManager:load()
    if self.data then
        return
    end

    -- Ensure reading list manager has a schema version set
    assert(self.schema_version ~= nil, "`ReadingListManager.schema_version` cannot be nil")
    assert(self.schema_version.major ~= nil, "`ReadingListManager.schema_version.major` cannot be nil")

    -- Read data from file
    local file_exists = lfs.attributes(self.reading_lists_path, "mode") == "file"
    local xml, read_err = util.readFromFile(self.reading_lists_path, "r")
    local loaded_data

    if xml == nil then
        assert(not file_exists, T("Failed to load %1: %2", self.reading_lists_path, read_err))
    else
        -- Parse file data
        local parse_ok, parse_err = pcall(function()
            return self.parser:parse(xml)
        end)

        if not parse_ok then
            if parse_err then
                error(T("Failed to parse file '%1': %2", self.reading_lists_path, parse_err))
            else
                error(T("Failed to parse file '%1'", self.reading_lists_path))
            end
        else
            -- Ensure XML has correct root element
            assert(self.handler.root["reading-lists"], T("Invalid reading lists xml: %1", self.reading_lists_path))

            -- Ensure XML data has valid schema version
            assert(
                self.handler.root["reading-lists"]._attr and self.handler.root["reading-lists"]._attr.version,
                "XML data does not have a schema version"
            )

            local loaded_version = pluginUtil.parseVersion(self.handler.root["reading-lists"]._attr.version)

            -- Ensure XML data schema version is formatted properly
            assert(
                loaded_version ~= nil and loaded_version.major ~= nil and loaded_version.minor ~= nil,
                "XML data version number is invalid"
            )

            -- Ensure XML data schema version is compatible with manager schema version
            local is_valid_version, version_err = pluginUtil.validateVersion(loaded_version, self.schema_version)
            if not is_valid_version then
                if version_err then
                    error(T("XML data schema version is invalid: %1", version_err))
                else
                    error("XML data schema version is invalid")
                end
            end

            -- Ensure data is same shape for multiple lists or single list or no lists
            if not self.handler.root["reading-lists"]["reading-list"] then
                loaded_data = {}
            elseif #self.handler.root["reading-lists"]["reading-list"] > 1 then
                loaded_data = self.handler.root["reading-lists"]["reading-list"]
            else
                loaded_data = { self.handler.root["reading-lists"]["reading-list"] }
            end
        end
    end

    self.data = {}

    -- Transform loaded data
    if loaded_data then
        for data_idx, data_value in ipairs(loaded_data) do
            if data_value.name and data_value.name ~= "" then
                self.data[data_value.name] = data_value

                -- Ensure reading list has list items table
                if not data_value["list-items"] then
                    self.data[data_value.name]["list-items"] = {}
                end

                -- Set data order value
                self.data[data_value.name].order = data_idx
                self.max_order = data_idx
            else
                logger.warn("Reading list does not have name. Skipping")
            end
        end
    end

    print()
end

--- Write reading list data to file
function ReadingListManager:flush()
    if self.data == nil or not self.updated then
        return
    end

    local write_data = {
        ["reading-lists"] = {
            _attr = {
                version = pluginUtil.toVersionString(self.schema_version),
                ["xmlns:xsi"] = "http://www.w3.org/2001/XMLSchema-instance",
                ["xsi:noNamespaceSchemaLocation"] = "https://raw.githubusercontent.com/maxcaplan/readinglist.koplugin/refs/heads/master/reading_lists_schema.xsd",
            },
        },
    }

    -- Format data for writing to xml
    for _, data_value in self:dataPairs() do
        if not write_data["reading-lists"]["reading-list"] then
            write_data["reading-lists"]["reading-list"] = {}
        end

        local reading_list = util.tableDeepCopy(data_value)

        -- Remove order value from reading list
        reading_list.order = nil

        -- Add reading list data to write data
        table.insert(write_data["reading-lists"]["reading-list"], reading_list)
    end

    -- Convert data to xml
    local xml = xml2lua.toXml(write_data)

    -- Prepend xml declaration to xml string
    xml = XML_DECLARATION_STRING .. "\n\n" .. xml

    logger.info("XML TO SAVE")
    logger.info(xml)

    -- Write xml data to file
    local file, open_err = io.open(self.reading_lists_path, "w")

    if file and not open_err then
        file:write(xml)
        self.updated = false
    else
        logger.err(T("Failed to write reading lists to file: %1", open_err))
    end
end

-- Get all reading lists
function ReadingListManager:getAllLists()
    self:load()
    return self.data
end

--- Get a reading list by name
-- @param name Name of the reading list
function ReadingListManager:getList(name)
    if name == nil then
        return
    end

    self:load()

    return self.data[name]
end

--- Create new reading list
-- @param name Name of new reading list
-- @return New reading list
function ReadingListManager:createList(name)
    if name == nil then
        return
    end

    self:load()

    if self.data[name] then
        return
    end

    -- Increment max order value
    self.max_order = self.max_order + 1

    self.data[name] = {
        name = name,
        order = self.max_order,
        ["list-items"] = {},
    }

    self.updated = true

    return self.data[name]
end

--- Delete reading list data
-- @param name Name of reading list to delete
-- @return If delete was successful
function ReadingListManager:deleteList(name)
    if name == nil then
        return false
    end

    self:load()

    -- Update max order value if deleted list was the highest order
    if self.data[name].order >= self.max_order then
        self:updateMaxOrder()
    end

    self.data[name] = nil
    self.updated = true

    return true
end

--- Change the name of an existing reading list
-- @param old_name Name of existing reading list
-- @param new_name Name to update reading list to
-- @return Updated reading list
function ReadingListManager:updateListName(old_name, new_name)
    if old_name == nil or new_name == nil then
        return
    end

    self:load()

    if self.data[old_name] == nil then
        return
    end

    -- Create copy of reading list with new name
    self.data[new_name] = util.tableDeepCopy(self.data[old_name])
    self.data[new_name].name = new_name

    -- Delete reading list with old name
    self.data[old_name] = nil

    self.updated = true

    return self.data[new_name]
end

--- Update max order value for current data
function ReadingListManager:updateMaxOrder()
    self.max_order = 0

    if self.data then
        for _, data_value in pairs(self.data) do
            if data_value.order > self.max_order then
                self.max_order = data_value.order
            end
        end
    end

    return self.max_order
end

--- Functions like ```pairs(data)``` but returns data pairs
--- based on their order value
function ReadingListManager:dataPairs()
    local dataNext = function(data, key)
        return self:_dataNext(data, key)
    end
    return dataNext, self.data, nil
end

--- Internal method to get next data pair in order
function ReadingListManager:_dataNext(data, key)
    if data == nil then
        return nil
    end

    -- Ensure max order is set
    if not self.max_order then
        self:updateMaxOrder()
    end

    -- Return initial index and value
    if key == nil then
        -- Return table item with smallest order
        local value = nil
        local order

        for data_key, data_value in pairs(data) do
            if order == nil or data_value.order < order then
                order = data_value.order
                value = data_value
                key = data_key
            end
        end

        return key, value
    end

    local order = data[key].order

    -- Return next value in order
    while order <= self.max_order do
        order = order + 1

        for data_key, data_value in pairs(data) do
            if data_value.order == order then
                return data_key, data_value
            end
        end
    end

    -- No more items
    return nil
end

return ReadingListManager
