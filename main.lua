--[[--
A plugin for managing reading lists on your KOReader

@module koplugin.readinglist
]]

local Dispatcher = require("dispatcher") -- luacheck:ignore
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

--- Base plugin widget
local ReadingList = WidgetContainer:extend({
	name = "reading_list",
	is_doc_only = false,
})

--- Register plugin widget actions
function ReadingList:onDispatcherRegisterActions()
	Dispatcher:registerAction(
		"newreadinglist_action",
		{ category = "none", event = "NewReadingList", title = _("New Reading List"), general = true }
	)
end

--- Initialize plugin widget
function ReadingList:init()
	self:onDispatcherRegisterActions()
	self.ui.menu:registerToMainMenu(self)
end

--- Add plugin widget to main menu
function ReadingList:addToMainMenu(menu_items)
	menu_items.reading_list = {
		text = _("Reading List"),
		sorting_hint = "tools",
		sub_item_table_func = function()
			return self:getSubMenuItems()
		end,
	}
end

--- Get widget sub menu items
function ReadingList:getSubMenuItems()
	local sub_item_table = {
		{
			text = _("New reading list"),
			keep_menu_open = true,
			callback = function()
				self:onNewReadingList()
			end,
		},
	}

	return sub_item_table
end

--- New reading list event handler
function ReadingList:onNewReadingList()
	local popup = InfoMessage:new({
		text = _("Hello World"),
	})
	UIManager:show(popup)
end

return ReadingList
