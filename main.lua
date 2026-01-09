--[[--
A plugin for managing reading lists on your KOReader

@module koplugin.readinglist
]]

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")

local Menu = require("ui/widget/menu")
local ButtonDialog = require("ui/widget/buttondialog")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local logger = require("logger")
local util = require("util")
local ffiUtil = require("ffi/util")
local _ = require("gettext")

local T = ffiUtil.template

--- Base plugin widget
local ReadingList = WidgetContainer:extend({
    name = "reading_list",
    title = _("Reading Lists"),
    is_doc_only = false,
    reading_lists_file = DataStorage:getSettingsDir() .. "reading_lists.lua", -- Path to reading lists data file
    reading_lists = nil, -- Reading lists settings
    data = nil, -- Reading lists data table
    updated = false, -- Whether there are unflushed reading list settings
    reading_list_menu = nil, -- Reading list menu widget
    all_reading_lists_menu = nil, -- Reading lists menu widget
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

    -- Data with an order value
    local ordered_data = {}
    -- Data without an order value
    local unordered_data = {}
    -- Map of used order values
    local order_map = {}

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
    --
end

--- Add plugin widget to main menu
function ReadingList:addToMainMenu(menu_items)
    menu_items.reading_list = {
        text = _("Reading Lists"),
        sorting_hint = "tools",
        callback = function()
            ReadingList:onShowAllReadingListsMenu()
        end,
    }
end

--- Event handler for showing a reading list
-- @param reading_list_name Name of the reading list to show
function ReadingList:onShowReadingListMenu(reading_list_name)
    if reading_list_name == nil then
        return
    end

    -- Create reading list menu widget
    self.reading_list_menu = Menu:new({
        path = reading_list_name,
        subtitle = "",
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        title_bar_left_icon = "appbar.menu",
        onLeftButtonTap = function()
            self:onShowReadingListMenuDialog()
        end,
        onReturn = function()
            self.reading_list_menu.close_callback()
            self:onShowAllReadingListsMenu()
        end,
        -- onMenuSelect =
        -- onMenuHold =
        _manager = self,
        _recreate_func = function()
            self:onShowReadingListMenu(reading_list_name)
        end,
    })

    -- Enable onReturn button for menu widget
    table.insert(self.reading_list_menu.paths, true)

    -- Set menu close callback
    self.reading_list_menu.close_callback = function()
        UIManager:close(self.reading_list_menu)
        self.reading_list_menu = nil
    end

    -- Set menu items
    self:updateReadingListMenuItemTable()

    -- Show menu
    UIManager:show(self.reading_list_menu)
    return true
end

--- Set item table for reading list menu
-- @param item_table Existing table to update
function ReadingList:updateReadingListMenuItemTable(item_table)
    self:loadReadingLists()

    -- Create item table from data
    if item_table == nil then
        item_table = {}

        if not (self.data[self.reading_list_menu.path].items == nil) then
            for _, item_value in pairs(self.data[self.reading_list_menu.path].items) do
                local item = {
                    text = item_value.text,
                    order = item_value.order,
                }

                table.insert(item_table, item)
            end

            -- Sort item table
            if #item_table > 1 then
                table.sort(item_table, function(v1, v2)
                    return v1.order < v2.order
                end)
            end
        end
    end

    -- Add item count to menu title
    local title = T("%1 (%2)", self.reading_list_menu.path, #item_table)

    -- Update menu
    self.reading_list_menu:switchItemTable(title, item_table, -1, nil)
end

--- Event handler for showing reading list menu dialog
function ReadingList:onShowReadingListMenuDialog()
    local button_dialog
    button_dialog = ButtonDialog:new({
        buttons = {
            {
                {
                    text = _("Reading Lists"),
                    callback = function()
                        UIManager:close(button_dialog)
                        self.reading_list_menu.close_callback()
                        self:onShowAllReadingListsMenu()
                    end,
                },
            },
        },
    })

    UIManager:show(button_dialog)
end

--- Event handler for showing reading lists menu
function ReadingList:onShowAllReadingListsMenu()
    -- Create all reading lists menu widget
    self.all_reading_lists_menu = Menu:new({
        path = true, -- grab focus
        subtitle = "",
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        title_bar_left_icon = "appbar.menu",
        onLeftButtonTap = function()
            self:onShowAllReadingListsMenuDialog()
        end,
        onMenuChoice = self.onReadingListsMenuChoice,
        onMenuHold = self.onReadingListsMenuHold,
        _manager = self,
        _recreate_func = function()
            self:onShowAllReadingListsMenu()
        end,
    })

    -- Set menu close callback
    self.all_reading_lists_menu.close_callback = function()
        UIManager:close(self.all_reading_lists_menu)
        self.all_reading_lists_menu = nil
    end

    -- init menu items
    self:updateAllReadingListsMenuItemTable(true)

    -- Show menu
    UIManager:show(self.all_reading_lists_menu)
    return true
end

--- Set item table for all reading lists menu
-- @param init Determines if this is the first update for the menu
-- @param item_number
function ReadingList:updateAllReadingListsMenuItemTable(init, item_number)
    self:loadReadingLists()

    local item_table

    if init then
        item_table = {}

        -- set item table items for reading lists data
        for data_key, data_value in pairs(self.data) do
            table.insert(item_table, {
                text = data_value.settings.name,
                name = data_key,
                order = data_value.settings.order,
            })
        end

        -- Sort item table by item order
        if #item_table > 1 then
            table.sort(item_table, function(v1, v2)
                return v1.order < v2.order
            end)
        end
    else
        item_table = self.all_reading_lists_menu.item_table
    end

    -- Add item count to menu title
    local title = T(_("Reading Lists (%1)"), #item_table)

    -- Update menu
    self.all_reading_lists_menu:switchItemTable(title, item_table, item_number or -1, nil)
end

--- Event handler for showing dialog for all reading lists menu
function ReadingList:onShowAllReadingListsMenuDialog()
    local button_dialog
    button_dialog = ButtonDialog:new({
        buttons = {
            {
                {
                    text = _("New reading list"),
                    callback = function()
                        local function editCallback(new_name)
                            -- Get highest order value from reading lists
                            local max_order = 0
                            for _, data_value in pairs(self.data) do
                                if data_value.settings.order > max_order then
                                    max_order = data_value.settings.order
                                end
                            end

                            -- Create data for new reading list
                            self.data[new_name] = { settings = { name = new_name, order = max_order + 1 } }
                            self.updated = true

                            -- Add reading list to menu
                            table.insert(self.all_reading_lists_menu.item_table, {
                                text = new_name,
                                name = new_name,
                                order = self.data[new_name].settings.order,
                            })

                            -- Update reading lists menu
                            self:updateAllReadingListsMenuItemTable(false, #self.all_reading_lists_menu.item_table) -- show added item
                        end

                        UIManager:close(button_dialog)
                        self:editReadingListName(editCallback)
                    end,
                },
            },
        },
    })

    UIManager:show(button_dialog)
end

--- All Reading lists menu choice event handler
function ReadingList:onReadingListsMenuChoice(item)
    self._manager:onShowReadingListMenu(item.name)
end

--- All Reading lists menu hold event handler
function ReadingList:onReadingListsMenuHold(item)
    local button_dialog
    button_dialog = ButtonDialog:new({
        title = item.text,
        title_align = "center",
        buttons = {
            {
                {
                    text = _("Remove reading list"),
                    callback = function()
                        UIManager:close(button_dialog)
                        self._manager:removeReadingList(item)
                    end,
                },
                {
                    text = _("Rename reading list"),
                    callback = function()
                        UIManager:close(button_dialog)
                        self._manager:renameReadingList(item)
                    end,
                },
            },
        },
    })

    UIManager:show(button_dialog)
end

function ReadingList:removeReadingList(item)
    local confirm_box
    confirm_box = ConfirmBox:new({
        text = _("Remove reading list?") .. "\n\n" .. item.name,
        ok_text = _("Remove"),
        ok_callback = function()
            logger.info(self.data[item.name])
            -- Remove reading list data
            self.data[item.name] = nil
            self.updated = true

            -- Remove reading list menu item
            table.remove(self.all_reading_lists_menu.item_table, item.idx)
            self:updateAllReadingListsMenuItemTable()
        end,
    })

    UIManager:show(confirm_box)
end

function ReadingList:renameReadingList(item)
    local function editCallback(name)
        -- Create copy of reading list data with new name
        self.data[name] = util.tableDeepCopy(self.data[item.name])
        self.data[name].settings.name = name

        -- Remove old reading list data
        self.data[item.name] = nil

        self.updated = true

        -- Update reading list menu item name
        self.all_reading_lists_menu.item_table[item.idx].name = name
        self.all_reading_lists_menu.item_table[item.idx].text = name
        self:updateAllReadingListsMenuItemTable()
    end

    self:editReadingListName(editCallback, item.name)
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
-- @param touchmenu_instance Touch menu widget instance for sub menu
function ReadingList:refreshSubMenu(touchmenu_instance)
    touchmenu_instance.item_table = self:getSubMenuItems()
    touchmenu_instance.page = 1
    touchmenu_instance:updateItems()
end

--- Exit nested widget menu
-- @param touchmenu_instance Touch menu widget instance for sub menu
function ReadingList:backToUpperMenu(touchmenu_instance)
    touchmenu_instance.item_table = self:getSubMenuItems()
    touchmenu_instance:updateItems()
    table.remove(touchmenu_instance.item_table_stack)
end

--- Prompt user for reading list name to update an existing list or create a new one
-- @param editCallback
-- @param old_name
function ReadingList:editReadingListName(editCallback, old_name)
    local name_input
    name_input = InputDialog:new({
        title = _("Enter reading list name"),
        input = old_name,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
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
