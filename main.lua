--[[--
A plugin for managing reading lists on your KOReader

@module koplugin.readinglist
]]

local logger = require("logger")
local pluginUtil = require("lib/util")

-- Get plugin meta version number
local PLUGIN_VERSION = pluginUtil.parseVersion(require("_meta").version)
assert(PLUGIN_VERSION, "ReadingList: Plugin version number is invalid")
logger.dbg("ReadingList: version " .. pluginUtil.toVersionString(PLUGIN_VERSION))

local _ = require("gettext")

local WidgetContainer = require("ui/widget/container/widgetcontainer")

local DataManager = require("datamanager")
local MenuManager = require("menumanager")

--- Reading list plugin widget
local ReadingList = WidgetContainer:extend({
    name = "reading_list",
    title = _("Reading Lists"),
    is_doc_only = false,
    data_schema_version = PLUGIN_VERSION, -- Data schema version of the plugin
    data_manager = nil, -- Reading list data manager
    menu_manager = nil, -- Reading list menu manager
})

--- Initialize plugin widget
function ReadingList:init()
    -- Initialize data manager
    self.data_manager = DataManager:new({}, self.data_schema_version)

    -- Initialize menu manager
    self.menu_manager = MenuManager:new(nil, self.data_manager)

    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

--- Flush widget settings event handler.
function ReadingList:onFlushSettings()
    self.data_manager:flush()
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
    self.menu_manager:showAllListsMenu()
end

return ReadingList
