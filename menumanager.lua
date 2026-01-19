--[[
Reading list plugin menu widget manager

@module koplugin/readinglist/menumanager
--]]

local Device = require("device")
local logger = require("logger")
local ffiUtil = require("ffi/util")
local _ = require("gettext")

local Screen = Device.screen
local T = ffiUtil.template

local UIManager = require("ui/uimanager")

local CheckButton = require("ui/widget/checkbutton")
local Menu = require("ui/widget/menu")
local ButtonDialog = require("ui/widget/buttondialog")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")

local MenuManager = {
    list_menu = nil, -- Menu widget for reading list
    all_lists_menu = nil, -- Menu widget for list of reading lists
    data_manager = nil, -- Reading list data manager instance
    check_button = nil, -- List menu item checkbox button
}

--- Create a new reading list menu instance
function MenuManager:new(o, data_manager)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    if data_manager then
        self.data_manager = data_manager
    end

    return o
end

--- Reading list menu

--- Show menu for a reading list
-- @param reading_list Reading list to show menu for
function MenuManager:showListMenu(reading_list)
    if reading_list == nil then
        logger.err("Reading list can not be nil")
        return
    end

    local items_per_page = 14
    local button_width = math.floor(Screen:getHeight() / items_per_page * 2 / 5) * 2

    -- Create reading list menu widget
    self.list_menu = Menu:new({
        path = reading_list.name,
        subtitle = "",
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        title_bar_left_icon = "appbar.menu",
        items_per_page = items_per_page,
        state_w = button_width,
        onLeftButtonTap = function()
            self:showListMenuDialog(reading_list)
        end,
        onMenuHold = function(_, item)
            self:onListMenuHold(reading_list, item)
        end,
        onReturn = function()
            self.list_menu.close_callback()
            self:showAllListsMenu()
        end,
        _manager = self,
        _recreate_func = function()
            self:showListMenu(reading_list)
        end,
    })

    -- Enable onReturn button for menu widget
    table.insert(self.list_menu.paths, true)

    -- Set menu close callback
    self.list_menu.close_callback = function()
        logger.info("CLOSE CALLBACK")
        UIManager:close(self.list_menu)
        self.list_menu = nil
    end

    -- Disable menu item selection
    self.list_menu.onMenuSelect = function() end

    -- Set menu items
    self:updateListMenuItemTable(reading_list.list_items)

    -- Show menu
    UIManager:show(self.list_menu)
    return true
end

--- Create list menu table item for a reading list item
-- @param item Item to create table item for
-- @param reading_list Reading list item is associated with
function MenuManager:createListMenuTableItem(item, reading_list)
    if not reading_list then
        reading_list = self.data_manager:getList(self.list_menu.path)
    end
    assert(reading_list, "Reading list can not be nil")

    local check_button

    if self.list_menu.state_w and self.list_menu.state_w > 0 then
        check_button = CheckButton:new({
            checked = reading_list:isListItemChecked(item.name),
            parent = self.list_menu,
            width = self.list_menu.state_w,
            callback = function()
                reading_list:updateListItemChecked(item.name, check_button.checked)
                check_button.checked = reading_list:isListItemChecked(item.name)
            end,
        })
    end

    return {
        name = item.name,
        text = item.name,
        order = item.order,
        state = check_button,
    }
end

--- Set item table for reading list menu
-- @param reading_list Reading list to update menu for
-- @param item_table Existing table to update
-- @param item_number List item to focus
function MenuManager:updateListMenuItemTable(list_items, item_number)
    local item_table
    -- Create item table from data
    if list_items then
        local reading_list = self.data_manager:getList(self.list_menu.path)
        assert(reading_list, "Reading list can not be nil")

        item_table = {}

        -- Create menu items from list items
        for _, item_value in pairs(list_items) do
            table.insert(item_table, self:createListMenuTableItem(item_value, reading_list))
        end

        -- Sort item table
        if #item_table > 1 then
            table.sort(item_table, function(v1, v2)
                return v1.order < v2.order
            end)
        end
    else
        item_table = self.list_menu.item_table or {}
    end

    -- Create menu title from menu path and menu item count
    local title = T("%1 (%2)", self.list_menu.path, #item_table)

    -- Update menu
    self.list_menu:switchItemTable(title, item_table, item_number or -1, nil)
end

--- Show reading list menu dialog
function MenuManager:showListMenuDialog(reading_list)
    local button_dialog
    button_dialog = ButtonDialog:new({
        buttons = {
            {
                {
                    text = _("Reading Lists"),
                    callback = function()
                        UIManager:close(button_dialog)
                        self.list_menu.close_callback()
                        self:showAllListsMenu()
                    end,
                },
            },
            {}, -- Seperator
            {
                {
                    text = _("New list item"),
                    callback = function()
                        local function promptCallback(new_name)
                            assert(reading_list, "Reading list can not be nil")

                            -- Check that list item with name doesn't exist
                            if reading_list:getListItem(new_name) then
                                UIManager:show(InfoMessage:new({
                                    text = T(_("List item already exists: %1"), new_name),
                                }))
                            end

                            -- Create new list item
                            local new_list_item = reading_list:createListItem(new_name)

                            -- Add new list item to menu if created
                            if new_list_item then
                                table.insert(
                                    self.list_menu.item_table,
                                    self:createListMenuTableItem({
                                        name = new_list_item.name,
                                        text = new_list_item.name,
                                        order = new_list_item.order,
                                    }, reading_list)
                                )

                                -- Show new list item
                                self:updateListMenuItemTable(nil, #self.list_menu.item_table)
                            else
                                logger.err("Failed to create new list item")
                            end
                        end

                        UIManager:close(button_dialog)
                        self:namePrompt(_("Enter list item name"), promptCallback)
                    end,
                },
            },
        },
    })

    UIManager:show(button_dialog)
end

--- List menu menu item hold event handler
-- @param reading_list Reading list data object associated with this menu
-- @param item Menu item associated with this event
function MenuManager:onListMenuHold(reading_list, item)
    local button_dialog
    button_dialog = ButtonDialog:new({
        title = item.name,
        title_align = "center",
        buttons = {
            {
                {
                    text = _("Remove list item"),
                    callback = function()
                        UIManager:close(button_dialog)
                        self:onRemoveListItem(reading_list, item)
                    end,
                },
                {
                    text = _("Rename list item"),
                    callback = function()
                        UIManager:close(button_dialog)
                        self:onRenameListItem(reading_list, item)
                    end,
                },
            },
        },
    })

    UIManager:show(button_dialog)
end

--- Remove list item event handler
-- @param reading_list Reading list data object that contains list item to remove
-- @param item Menu item associated with this list item to remove
function MenuManager:onRemoveListItem(reading_list, item)
    local confirm_box
    confirm_box = ConfirmBox:new({
        text = _("Remove list item?") .. "\n\n" .. item.name,
        ok_text = _("Remove"),
        ok_callback = function()
            assert(reading_list, "Reading list can not be nil")

            if reading_list:deleteListItem(item.name) then
                -- Remove list menu item
                table.remove(self.list_menu.item_table, item.idx)
                self:updateListMenuItemTable()
            else
                logger.err(T("Failed to remove list item: %1", item.name))
            end
        end,
    })

    UIManager:show(confirm_box)
end

--- Rename list item event handler
-- @param reading_list Reading list data object that contains list item to rename
-- @param item Menu item associated with this list item to rename
function MenuManager:onRenameListItem(reading_list, item)
    local function promptCallback(new_name)
        assert(reading_list, "Reading list can not be nil")

        -- Check that list item with name doesn't exist
        if reading_list:getListItem(new_name) then
            UIManager:show(InfoMessage:new({
                text = T(_("List item already exists: %1"), new_name),
            }))
        end

        -- Update list item name
        local new_list_item = reading_list:updateListItemName(item.name, new_name)

        if new_list_item then
            -- Update list menu
            self.list_menu.item_table[item.idx].name = new_name
            self.list_menu.item_table[item.idx].text = new_name
            self:updateListMenuItemTable()
        else
            logger.err("Failed to rename list item")
        end
    end

    self:namePrompt(_("Enter list item name"), promptCallback, item.name)
end

--- All reading lists menu

--- Event handler for showing reading lists menu
-- @param reading_lists List of all reading lists
function MenuManager:showAllListsMenu()
    assert(self.data_manager, "Reading list manager can not be nil")

    -- Get reading lists
    local reading_lists = self.data_manager:getAllLists()
    assert(reading_lists ~= nil, "Failed to get reading lists")

    -- Create menu widget
    self.all_lists_menu = Menu:new({
        path = true, -- grab focus
        subtitle = "",
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        title_bar_left_icon = "appbar.menu",
        onLeftButtonTap = function()
            self:showAllListsMenuDialog()
        end,
        onMenuChoice = function(_, item)
            self:onAllListsMenuChoice(item)
        end,
        onMenuHold = function(_, item)
            self:onAllListsMenuHold(item)
        end,
        _recreate_func = function()
            self:showAllListsMenu()
        end,
    })

    -- Set menu close callback
    self.all_lists_menu.close_callback = function()
        UIManager:close(self.all_lists_menu)
        self.all_lists_menu = nil
    end

    -- init menu items
    self:updateAllListsMenuItemTable(reading_lists)

    -- Show menu
    UIManager:show(self.all_lists_menu)
    return true
end

function MenuManager:createAllListsMenuTableItem(reading_list)
    return {
        text = reading_list.name,
        name = reading_list.name,
        order = reading_list.order,
    }
end

--- Set item table for all reading lists menu
-- @param reading_lists List of reading lists to update menu with
-- @param item_number List item to focus
function MenuManager:updateAllListsMenuItemTable(reading_lists, item_number)
    local item_table

    if reading_lists then
        item_table = {}

        -- set item table items for reading lists data
        for _, reading_list_value in pairs(reading_lists) do
            table.insert(item_table, self:createAllListsMenuTableItem(reading_list_value))
        end

        -- Sort item table by item order
        if #item_table > 1 then
            table.sort(item_table, function(v1, v2)
                return v1.order < v2.order
            end)
        end
    else
        item_table = self.all_lists_menu.item_table or {}
    end

    -- Add item count to menu title
    local title = T(_("Reading Lists (%1)"), #item_table)

    -- Update menu
    self.all_lists_menu:switchItemTable(title, item_table, item_number or -1, nil)
end

--- Show dialog for all reading lists menu event handler
function MenuManager:showAllListsMenuDialog()
    local button_dialog
    button_dialog = ButtonDialog:new({
        buttons = {
            {
                {
                    text = _("New reading list"),
                    callback = function()
                        local function promptCallback(new_name)
                            assert(self.data_manager, "Reading list manager can not be nil")

                            -- Check that reading list with name doesn't exist
                            if self.data_manager:getList(new_name) then
                                UIManager:show(InfoMessage:new({
                                    text = T(_("Reading list already exists: %1"), new_name),
                                }))
                                return
                            end

                            local new_reading_list = self.data_manager:createList(new_name)

                            -- Update all reading lists menu
                            if new_reading_list then
                                table.insert(
                                    self.all_lists_menu.item_table,
                                    self:createAllListsMenuTableItem({
                                        text = new_reading_list.name,
                                        name = new_reading_list.name,
                                        order = new_reading_list.order,
                                    })
                                )

                                -- Show new reading list
                                self:updateAllListsMenuItemTable(nil, #self.all_lists_menu.item_table)
                            else
                                logger.err("Failed to create new reading list")
                            end
                        end

                        UIManager:close(button_dialog)
                        self:namePrompt(_("Enter reading list name"), promptCallback)
                    end,
                },
            },
        },
    })

    UIManager:show(button_dialog)
end

--- All Reading lists menu choice event handler
function MenuManager:onAllListsMenuChoice(item)
    assert(item ~= nil, "All lists menu item can not be nil")
    assert(type(item.name) == "string", "All lists menu item name must be string")

    local reading_list = self.data_manager:getList(item.name)

    if reading_list == nil then
        logger.err("Failed to get reading list with name")
        return
    end

    self:showListMenu(reading_list)
end

--- All Reading lists menu hold event handler
function MenuManager:onAllListsMenuHold(item)
    assert(item ~= nil, "All lists menu item can not be nil")
    assert(type(item.name) == "string", "All lists menu item name must be string")

    local button_dialog
    button_dialog = ButtonDialog:new({
        title = item.name,
        title_align = "center",
        buttons = {
            {
                {
                    text = _("Remove reading list"),
                    callback = function()
                        UIManager:close(button_dialog)
                        self:onRemoveReadingList(item)
                    end,
                },
                {
                    text = _("Rename reading list"),
                    callback = function()
                        UIManager:close(button_dialog)
                        self:onRenameReadingList(item)
                    end,
                },
            },
        },
    })

    UIManager:show(button_dialog)
end

--- Remove reading list event handler
function MenuManager:onRemoveReadingList(item)
    local confirm_box
    confirm_box = ConfirmBox:new({
        text = _("Remove reading list?") .. "\n\n" .. item.name,
        ok_text = _("Remove"),
        ok_callback = function()
            assert(self.data_manager, "Reading list manager can not be nil")

            if self.data_manager:deleteList(item.name) then
                -- Remove reading list menu item from menu
                table.remove(self.all_lists_menu.item_table, item.idx)
                self:updateAllListsMenuItemTable()
            else
                logger.err("Failed to remove reading list")
            end
        end,
    })

    UIManager:show(confirm_box)
end

--- Rename reading list event handler
function MenuManager:onRenameReadingList(item)
    assert(item ~= nil, "All lists menu item can not be nil")
    assert(type(item.name) == "string", "All lists menu item name must be string")

    local function promptCallback(new_name)
        assert(self.data_manager, "Reading list manager can not be nil")

        -- Check that reading list with name doesn't exist
        if self.data_manager:getList(new_name) then
            UIManager:show(InfoMessage:new({
                text = T(_("Reading list already exists: %1"), new_name),
            }))
            return
        end

        local new_reading_list = self.data_manager:updateListName(item.name, new_name)

        -- Update all reading lists menu
        if new_reading_list then
            self.all_lists_menu.item_table[item.idx].name = new_name
            self.all_lists_menu.item_table[item.idx].text = new_name
            self:updateAllListsMenuItemTable()
        else
            logger.err("Failed to rename reading list")
        end
    end

    self:namePrompt(_("Enter reading list name"), promptCallback, item.name)
end

--- Other menus

--- Prompt user for name input
-- @param prompt_title Title for the prompt
-- @param promptCallback Function called when a name is successfuly inputed
function MenuManager:namePrompt(prompt_title, promptCallback, old_name)
    local name_input
    name_input = InputDialog:new({
        title = prompt_title,
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

                        promptCallback(new_name)
                    end,
                },
            },
        },
    })

    UIManager:show(name_input)
    name_input:onShowKeyboard()
end

return MenuManager
