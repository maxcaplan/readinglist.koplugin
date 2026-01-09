--[[
Reading list plugin reading list manager

@module koplugin.readinglist.readinglistmanager
--]]

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local util = require("util")

local ReadingListManager = {
    reading_lists_file = DataStorage:getSettingsDir() .. "reading_lists.lua", -- Path to reading lists data file
    reading_lists = nil, -- Reading lists settings
    data = nil, -- Reading lists data table
    updated = false, -- Whether there are unflushed reading list settings
}

--- Create a new reading list manager instance
function ReadingListManager:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    return o
end

--- Load reading lists data
function ReadingListManager:loadReadingLists()
    if self.reading_lists then
        return
    end

    self.reading_lists = LuaSettings:open(self.reading_lists_file)
    self.data = self.reading_lists.data

    for data_key, data_value in pairs(self.data) do
        -- Ensure reading list has settings table
        if not data_value.settings then
            data_value.settings = {}
        end

        -- Ensure reading list has a name
        if not data_value.settings.name then
            data_value.settings.name = data_key
            self.updated = true
        end
    end

    self:flush()
end

--- Write reading list data to file
function ReadingListManager:flush()
    if not (self.reading_lists == nil) and self.updated then
        self.reading_lists:flush()
        self.updated = false
    end
end

-- Get all reading lists
function ReadingListManager:getAllLists()
    self:loadReadingLists()
    return self.data
end

--- Get a reading list by name
-- @param name Name of the reading list
function ReadingListManager:getList(name)
    if name == nil then
        return
    end

    self:loadReadingLists()

    return self.data[name]
end

--- Create new reading list
-- @param name Name of new reading list
-- @return New reading list
function ReadingListManager:createList(name)
    if name == nil then
        return
    end

    self:loadReadingLists()

    if self.data[name] then
        return
    end

    self.data[name] = {
        settings = {
            name = name,
            order = self:maxOrder() + 1,
        },
        items = {},
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

    self:loadReadingLists()

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

    self:loadReadingLists()

    if self.data[old_name] == nil then
        return
    end

    -- Create copy of reading list with new name
    self.data[new_name] = util.tableDeepCopy(self.data[old_name])
    self.data[new_name].settings.name = new_name

    -- Delete reading list with old name
    self.data[old_name] = nil

    self.updated = true

    return self.data[new_name]
end

--- Get highest order value from reading lists
function ReadingListManager:maxOrder()
    local max_order = 0

    if self.data then
        for _, data_value in pairs(self.data) do
            if data_value.settings.order > max_order then
                max_order = data_value.settings.order
            end
        end
    end

    return max_order
end

return ReadingListManager
