--[[--
A plugin for managing reading lists on your KOReader

@module koplugin.readinglist
]]

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Dispatcher = require("dispatcher")

local UIManager = require("ui/uimanager")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local util = require("util")
local ffiUtil = require("ffi/util")
local _ = require("gettext")

local T = ffiUtil.template

--- Base plugin widget
--- @class ReadingList
--- @field reading_lists_file string Path to reading lists data file
--- @field reading_lists table? Reading lists table
--- @field data table? Rading lists data table
--- @field updated boolean Whether there have been updates to reading lists that have not been flushed
local ReadingList = WidgetContainer:extend({
	name = "reading_list",
	is_doc_only = false,
	reading_lists_file = DataStorage:getSettingsDir() .. "reading_lists.lua",
	reading_lists = nil,
	data = nil,
	updated = false,
})

--- Initialize plugin widget
function ReadingList:init()
	self:onDispatcherRegisterActions()
	self.ui.menu:registerToMainMenu(self)
end

--- Load reading lists from file
function ReadingList:loadReadingLists()
	-- Skip if reading lists already loaded
	if self.reading_lists then
		return
	end

	self.reading_lists = LuaSettings:open(self.reading_lists_file)
	self.data = self.reading_lists.data

	-- Ensure reading lists have properly set names
	for data_key, data_value in pairs(self.data) do
		if not data_value.settings then
			data_value.settings = {}
		end

		if not data_value.settings.name then
			data_value.settings.name = data_key
			self.updated = true
		end
	end

	self:onFlushSettings()
end

--- Flush widget settings event handler.
function ReadingList:onFlushSettings()
	-- If reading lists updated, write to file
	if self.reading_lists and self.updated then
		self.reading_lists:flush()
		self.updated = false
	end
end

--- Register plugin widget actions
function ReadingList:onDispatcherRegisterActions()
	Dispatcher:registerAction(
		"newreadinglist_action",
		{ category = "none", event = "NewReadingList", title = _("New Reading List"), general = true }
	)
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
	self:loadReadingLists()

	-- Set static sub menu items
	local sub_item_table = {
		{
			text = _("New reading list"),
			keep_menu_open = true,
			callback = function(touchmenu_instance)
				--- @type fun(new_name: string)
				local function editCallback(new_name)
					-- Create data for new reading list
					self.data[new_name] = { settings = { name = new_name } }
					self.updated = true

					self:refreshSubMenu(touchmenu_instance)
				end

				self:editReadingListName(editCallback)
			end,
		},
	}

	-- Set dynamic sub menu items
	for data_key, data_value in pairs(self.data) do
		local sub_menu_item = {
			text = data_key,
			sub_item_table = {
				ignored_by_menu_search = true, -- Do not include sub menu items in menu search
				{
					text = T(_("Rename: %1"), data_key),
					keep_menu_open = true,
					callback = function(touchmenu_instance)
						--- @type fun(new_name: string)
						local function editCallback(new_name)
							-- Create copy of reading list with new name
							self.data[new_name] = util.tableDeepCopy(data_value)
							self.data[new_name].settings.name = new_name

							-- Delete reading list with old name
							self.data[data_key] = nil

							self.updated = true

							self:backToUpperMenu(touchmenu_instance)
						end

						self:editReadingListName(editCallback, data_key)
					end,
				},
				{
					text = _("Delete"),
					keep_menu_open = true,
					callback = function(touchmenu_instance)
						-- Prompt user for delete confirmitaion
						UIManager:show(ConfirmBox:new({
							text = _("Do you want to delete this reading list?"),
							ok_text = _("Delete"),
							ok_callback = function()
								self.data[data_key] = nil
								self.updated = true
								self:backToUpperMenu(touchmenu_instance)
							end,
						}))
					end,
				},
			},
		}

		table.insert(sub_item_table, sub_menu_item)
	end

	return sub_item_table
end

--- Refresh widget sub menu
--- @param touchmenu_instance any Touch menu widget instance for sub menu
function ReadingList:refreshSubMenu(touchmenu_instance)
	touchmenu_instance.item_table = self:getSubMenuItems()
	touchmenu_instance.page = 1
	touchmenu_instance:updateItems()
end

--- Exit nested widget menu
--- @param touchmenu_instance any Touch menu widget instance for sub menu
function ReadingList:backToUpperMenu(touchmenu_instance)
	touchmenu_instance.item_table = self:getSubMenuItems()
	touchmenu_instance:updateItems()
	table.remove(touchmenu_instance.item_table_stack)
end

--- Prompt user for reading list name to update an existing list or create a new one
--- @param editCallback fun(new_name: string)
--- @param old_name string?
function ReadingList:editReadingListName(editCallback, old_name)
	local name_input
	name_input = InputDialog:new({
		title = _("Enter reading list name"),
		buttons = {
			{
				{
					text = _("Cancel"),
					id = "close",
					input = old_name,
					callback = function()
						UIManager:close(name_input)
					end,
				},
				{
					text = _("Save"),
					callback = function()
						local new_name = name_input:getInputText()

						-- Keep input open if name is empty or unchanged
						if new_name == "" or new_name == old_name then
							return
						end

						UIManager:close(name_input)

						-- Check that reading list with name doesn't exist
						if self.data[new_name] then
							UIManager:show(InfoMessage:new({
								text = T(_("Reading list already exists: %1"), new_name),
							}))
							return
						end

						editCallback(new_name)
					end,
				},
			},
		},
	})

	UIManager:show(name_input)
	name_input:onShowKeyboard()
end

return ReadingList
