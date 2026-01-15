--[[--
A plugin for managing reading lists on your KOReader

@module koplugin.readinglist
]]

-- Data schema version used by the plugin
local DATA_SCHEMA_VERSION = { major = 1, minor = 0 }

local WidgetContainer = require("ui/widget/container/widgetcontainer")

local _ = require("gettext")

local ReadingListManager = require("readinglistmanager")
local ReadingListMenu = require("readinglistmenu")

--- Reading list plugin widget
local ReadingList = WidgetContainer:extend({
    name = "reading_list",
    title = _("Reading Lists"),
    is_doc_only = false,
    data_schema_version = DATA_SCHEMA_VERSION, -- Data schema version of the plugin
    reading_list_manager = nil, -- Reading lists manager
    reading_list_menu = nil, -- Reading list menu manager
})

--- Initialize plugin widget
function ReadingList:init()
    -- Initialize reading list manager
    self.reading_list_manager = ReadingListManager:new({}, self.data_schema_version)

    -- Initialize reading list menu
    self.reading_list_menu = ReadingListMenu:new({
        getAllReadingListsCallback = function()
            return self.reading_list_manager:getAllLists()
        end,

        getReadingListCallback = function(name)
            return self.reading_list_manager:getList(name)
        end,

        newReadingListCallback = function(name)
            return self.reading_list_manager:createList(name)
        end,

        removeReadingListCallback = function(name)
            return self.reading_list_manager:deleteList(name)
        end,

        renameReadingListCallback = function(old_name, new_name)
            return self.reading_list_manager:updateListName(old_name, new_name)
        end,
    })

    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

--- Flush widget settings event handler.
function ReadingList:onFlushSettings()
    self.reading_list_manager:flush()
end

--- Register plugin widget actions
function ReadingList:onDispatcherRegisterActions()
    --
end

--- Add plugin widget to main menu
function ReadingList:addToMainMenu(menu_items)
    menu_items.reading_list = {
        text = _("Reading Lists"),
        sorting_hint = "tools",
        callback = function()
            self:onShowAllReadingListsMenu()
        end,
    }
end

--- Show all reading lists menu event handler
function ReadingList:onShowAllReadingListsMenu()
    self.reading_list_menu:showAllListsMenu()
end

return ReadingList
