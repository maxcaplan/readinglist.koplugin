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

--- Reading list data

--- Reading list data wrapper
local ReadingListData = {
    name = nil,
    ["list-items"] = {}, -- Reading list items
    order = 0, -- Reading lists sorting value
    manager = nil, -- Reading list manager instance
    max_item_order = 0, -- Read only max order value of list items
}

--- Create a new reading list data instance
-- @param o Table to create reading list with
-- @param order Order value for new reading list
-- @param manager Object that manages this reading list
function ReadingListData:new(o, order, manager)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    if order then
        o.order = order
    end

    if manager then
        o.manager = manager
    end

    o:init()

    return o
end

--- Initialize reading list data instance
function ReadingListData:init()
    -- Ensure reading list has list items table
    if not self["list-items"] then
        self["list-items"] = {}
    end

    local transformed_items = {}

    -- Ensure data is same shape for multiple items or single item or no items
    if not self["list-items"]["list-item"] then
        transformed_items = {}
    elseif #self["list-items"]["list-item"] > 1 then
        transformed_items = self["list-items"]["list-item"]
    else
        transformed_items = { self["list-items"]["list-item"] }
    end

    self["list-items"] = {}

    -- Transform list items data
    for item_idx, item_value in ipairs(transformed_items) do
        if item_value.name then
            self["list-items"][item_value.name] = item_value
            self["list-items"][item_value.name].order = item_idx
            self.max_item_order = item_idx
        else
            logger.warn("List item does not have name. Skipping")
        end
    end
end

--- Return reading lists data formatted for writing
function ReadingListData:data()
    -- Temporarily unset reading list manager to not copy it
    local temp_manager = self.manager
    self.manager = nil

    -- Copy reading list
    local data = util.tableDeepCopy(self) or {}

    -- Remove application data from copied reading list
    data.order = nil
    data.max_item_order = nil

    -- Transform list items data for writing
    if data["list-items"] ~= nil then
        local list_item_data = {}

        for _, item_value in pluginUtil.orderedPairs(data["list-items"]) do
            local list_item = util.tableDeepCopy(item_value)

            -- Remove list item order value
            list_item.order = nil

            table.insert(list_item_data, list_item)
        end

        if #list_item_data > 0 then
            data["list-items"] = { ["list-item"] = list_item_data }
        else
            data["list-items"] = nil
        end
    end

    -- Restore manager to reading list
    self.manager = temp_manager

    return data
end

--- Return table of all list items for this reading list
function ReadingListData:getAllListItems()
    return ReadingListData["list-items"]
end

--- Return table of a list item by name for this reading list
function ReadingListData:getListItem(name)
    return ReadingListData["list-items"][name]
end

--- Create a list item in this reading list
function ReadingListData:createListItem(item_name)
    if not item_name then
        return
    end

    -- Ensure item with name does not exist
    if self["list-items"][item_name] then
        return
    end

    -- Increment max item order value
    self.max_item_order = self.max_item_order + 1

    self["list-items"][item_name] = {
        name = item_name,
        order = self.max_item_order,
    }

    if self.manager then
        self.manager.updated = true
    end

    return self["list-items"][item_name]
end

--- Remove a list item with a specified name from this reading list
function ReadingListData:deleteListItem(item_name)
    if not item_name then
        return false
    end

    -- If item doesn't exist, do nothing
    if not self["list-items"][item_name] then
        return true
    end

    -- Update max order value if deleted item was the highest order
    if self["list-items"][item_name].order >= self.max_item_order then
        self["list-items"][item_name] = nil
        self:updateMaxItemOrder()
    else
        self["list-items"][item_name] = nil
    end

    if self.manager then
        self.manager.updated = true
    end

    return true
end

--- Update the name of a list item of a specified name in this reading list
function ReadingListData:updateListItemName(old_name, new_name)
    if old_name == nil or new_name == nil then
        return
    end

    -- Ensure item exists
    if not self["list-items"][old_name] then
        return
    end

    -- Create copy of list item with new name
    self["list-items"][new_name] = util.tableDeepCopy(self["list-items"][old_name])
    self["list-items"][new_name].name = new_name

    -- Delete list item with old name
    self["list-items"][old_name] = nil

    if self.manager then
        self.manager.updated = true
    end

    return self["list-items"][new_name]
end

--- Update max order value for current list items
function ReadingListData:updateMaxItemOrder()
    self.max_item_order = 0

    if self["list-items"] then
        for _, item_value in pairs(self["list-items"]) do
            if item_value.order > self.max_item_order then
                self.max_item_order = item_value.order
            end
        end
    end

    return self.max_item_order
end

--- Reading list manager

local XML_DECLARATION_STRING = '<?xml version="1.0" encoding="UTF-8"?>'

local ReadingListManager = {
    schema_version = { major = 1, minor = 0 }, -- XML data schema version
    reading_lists_file = "reading_lists.xml", -- Reading lists data file name
    reading_lists_path = nil, -- Reading lists data file path
    parser = nil, -- Data file parser
    handler = nil, -- Data parser handler
    data = nil, -- Reading lists data table
    updated = false, -- Whether there are unflushed reading list settings
    max_list_order = 0, -- Read only maximum order value for reading lists
    root = { -- Data associated with the root XML element
        schema_uri = "https://raw.githubusercontent.com/maxcaplan/readinglist.koplugin/refs/heads/master/reading_lists_schema.xsd", -- XML data schema file location
    },
}

--- Create a new reading list manager instance
-- @param o Table to create reading list manager with
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

    -- Create reading list data objects from loaded data
    if loaded_data then
        for data_idx, data_value in ipairs(loaded_data) do
            if data_value.name and data_value.name ~= "" then
                self.data[data_value.name] = ReadingListData:new(data_value, data_idx, self)

                -- Set data order value
                self.max_list_order = data_idx
            else
                logger.warn("Reading list does not have name. Skipping")
            end
        end
    end
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
    for _, data_value in pluginUtil.orderedPairs(self.data) do
        if not write_data["reading-lists"]["reading-list"] then
            write_data["reading-lists"]["reading-list"] = {}
        end

        -- Add reading list data to write data
        table.insert(write_data["reading-lists"]["reading-list"], data_value:data())
    end

    -- Convert data to xml
    local xml = xml2lua.toXml(write_data)

    -- Prepend xml declaration to xml string
    xml = XML_DECLARATION_STRING .. "\n\n" .. xml

    -- Write xml data to file
    local file, open_err = io.open(self.reading_lists_path, "w")

    if file and not open_err then
        file:write(xml)
        self.updated = false
    else
        logger.err(T("Failed to write reading lists to file: %1", open_err))
    end
end

--- Reading lists

--- Get all reading lists
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
    self.max_list_order = self.max_list_order + 1

    self.data[name] = ReadingListData:new({
        name = name,
        order = self.max_list_order,
        manager = self,
    })

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

    -- If list doesn't exist, do nothing
    if not self.data[name] then
        return true
    end

    -- Update max order value if deleted list was the highest order
    if self.data[name].order >= self.max_list_order then
        self.data[name] = nil
        self:updateMaxListOrder()
    else
        self.data[name] = nil
    end

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

    -- Unset reading list manager so it is not copied
    self.data[old_name].manager = nil

    -- Create copy of reading list with new name
    self.data[new_name] = util.tableDeepCopy(self.data[old_name])
    self.data[new_name].name = new_name
    self.data[new_name].manager = self

    -- Delete reading list with old name
    self.data[old_name] = nil

    self.updated = true

    return self.data[new_name]
end

--- Update max order value for current reading lists
function ReadingListManager:updateMaxListOrder()
    self.max_list_order = 0

    if self.data then
        for _, data_value in pairs(self.data) do
            if data_value.order > self.max_list_order then
                self.max_list_order = data_value.order
            end
        end
    end

    return self.max_list_order
end

--- List items

function ReadingListManager:createListItem(list_name, item_name)
    if not list_name or not item_name then
        return
    end

    self:load()

    -- Ensure list exists
    if not self.data[list_name] then
        return
    end

    -- Create new list item
    local new_item = self.data[list_name]:createListItem(item_name)

    if new_item then
        self.updated = true
    end

    return new_item
end

function ReadingListManager:deleteListItem(list_name, item_name)
    if not list_name or not item_name then
        return false
    end

    self:load()

    -- Ensure list exists
    if not self.data[list_name] then
        return false
    end

    -- Delete list item
    local deleted = self.data[list_name]:deleteListItem(item_name)

    if deleted then
        self.updated = true
    end

    return deleted
end

function ReadingListManager:updateListItemName(list_name, old_name, new_name)
    if list_name == nil or old_name == nil or new_name == nil then
        return
    end

    self:load()

    -- Ensure list exists
    if not self.data[list_name] then
        return
    end

    -- Update list item
    local updated_item = self.data[list_name]:updateListItemName(old_name, new_name)

    if updated_item then
        self.updated = true
    end

    return updated_item
end

return ReadingListManager
