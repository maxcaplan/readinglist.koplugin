--[[
Reading list plugin menu widget manager

@module koplugin.readinglist.readinglistmenu
--]]

local UIManager = require("ui/uimanager")

local Menu = require("ui/widget/menu")
local ButtonDialog = require("ui/widget/buttondialog")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")

local logger = require("logger")
local ffiUtil = require("ffi/util")
local _ = require("gettext")

local T = ffiUtil.template

local ReadingListMenu = {
    list_menu = nil, -- Menu widget for reading list
    all_lists_menu = nil, -- Menu widget for list of reading lists
    getReadingListCallback = nil,
    getAllReadingListsCallback = nil,
    newReadingListCallback = nil,
    removeReadingListCallback = nil,
    renameReadingListCallback = nil,
}

--- Create a new reading list menu instance
function ReadingListMenu:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    return o
end

--- Reading list menu

--- Show menu for a reading list
-- @param reading_list Reading list to show menu for
function ReadingListMenu:showListMenu(reading_list)
    if reading_list == nil then
        logger.err("Reading list is nil")
        return
    end

    -- Create reading list menu widget
    self.list_menu = Menu:new({
        path = reading_list.name,
        subtitle = "",
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        title_bar_left_icon = "appbar.menu",
        onLeftButtonTap = function()
            self:onShowListMenuDialog()
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
        UIManager:close(self.list_menu)
        self.list_menu = nil
    end

    -- Set menu items
    self:updateListMenuItemTable(reading_list)

    -- Show menu
    UIManager:show(self.list_menu)
    return true
end

--- Set item table for reading list menu
-- @param reading_list Reading list to update menu for
-- @param item_table Existing table to update
function ReadingListMenu:updateListMenuItemTable(reading_list, item_table)
    -- Create item table from data
    if item_table == nil then
        item_table = {}

        if not (reading_list.items == nil) then
            for _, item_value in pairs(reading_list.items) do
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
    local title = T("%1 (%2)", reading_list.name, #item_table)

    -- Update menu
    self.list_menu:switchItemTable(title, item_table, -1, nil)
end

--- Show reading list menu dialog
function ReadingListMenu:onShowListMenuDialog()
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
        },
    })

    UIManager:show(button_dialog)
end

--- All reading lists menu

--- Event handler for showing reading lists menu
-- @param reading_lists List of all reading lists
function ReadingListMenu:showAllListsMenu()
    if not self.getAllReadingListsCallback then
        logger.warn("Get all reading lists callback not set")
        return
    end

    local reading_lists = self.getAllReadingListsCallback()

    if reading_lists == nil then
        logger.err("Failed to get reading lists")
        return
    end

    -- Create all reading lists menu widget
    self.all_lists_menu = Menu:new({
        path = true, -- grab focus
        subtitle = "",
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        title_bar_left_icon = "appbar.menu",
        onLeftButtonTap = function()
            self:onShowAllListsMenuDialog()
        end,
        onMenuChoice = self.onAllListsMenuChoice,
        onMenuHold = self.onAllListsMenuHold,
        _manager = self,
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

--- Set item table for all reading lists menu
-- @param reading_lists List of reading lists to update menu with
-- @param item_number List item to focus
function ReadingListMenu:updateAllListsMenuItemTable(reading_lists, item_number)
    local item_table

    if reading_lists then
        item_table = {}

        -- set item table items for reading lists data
        for _, reading_list_value in pairs(reading_lists) do
            table.insert(item_table, {
                text = reading_list_value.name,
                name = reading_list_value.name,
                order = reading_list_value.order,
            })
        end

        -- Sort item table by item order
        if #item_table > 1 then
            table.sort(item_table, function(v1, v2)
                return v1.order < v2.order
            end)
        end
    else
        item_table = self.all_lists_menu.item_table
    end

    -- Add item count to menu title
    local title = T(_("Reading Lists (%1)"), #item_table)

    -- Update menu
    self.all_lists_menu:switchItemTable(title, item_table, item_number or -1, nil)
end

--- Event handler for showing dialog for all reading lists menu
function ReadingListMenu:onShowAllListsMenuDialog()
    local button_dialog
    button_dialog = ButtonDialog:new({
        buttons = {
            {
                {
                    text = _("New reading list"),
                    callback = function()
                        local function editCallback(name)
                            -- Call new reading list callback
                            if not self.newReadingListCallback then
                                logger.warn("New reading list callback not set")
                                return
                            end

                            local new_reading_list = self.newReadingListCallback(name)

                            -- Add new list to menu if created
                            if new_reading_list then
                                table.insert(self.all_lists_menu.item_table, {
                                    text = new_reading_list.name,
                                    name = new_reading_list.name,
                                    order = new_reading_list.order,
                                })

                                self:updateAllListsMenuItemTable(nil, #self.all_lists_menu.item_table) -- Show new reading list
                            end
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
function ReadingListMenu:onAllListsMenuChoice(item)
    if not self._manager.getReadingListCallback then
        logger.warn("onAllListsMenuChoice: Get reading list callback not set")
    end

    local reading_list = self._manager.getReadingListCallback(item.name)

    if reading_list then
        self._manager:showListMenu(reading_list)
    end
end

--- All Reading lists menu hold event handler
function ReadingListMenu:onAllListsMenuHold(item)
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
                        self._manager:onRemoveReadingList(item)
                    end,
                },
                {
                    text = _("Rename reading list"),
                    callback = function()
                        UIManager:close(button_dialog)
                        self._manager:onRenameReadingList(item)
                    end,
                },
            },
        },
    })

    UIManager:show(button_dialog)
end

--- Remove reading list event handler
function ReadingListMenu:onRemoveReadingList(item)
    local confirm_box
    confirm_box = ConfirmBox:new({
        text = _("Remove reading list?") .. "\n\n" .. item.name,
        ok_text = _("Remove"),
        ok_callback = function()
            if not self.removeReadingListCallback then
                logger.warn("Remove reading list callback not set")
                return
            end

            if self.removeReadingListCallback(item.name) then
                -- Remove reading list menu item
                table.remove(self.all_lists_menu.item_table, item.idx)
                self:updateAllListsMenuItemTable()
            else
                logger.err(T("Failed to remove reading list: %1", item.name))
            end
        end,
    })

    UIManager:show(confirm_box)
end

--- Rename reading list event handler
function ReadingListMenu:onRenameReadingList(item)
    local function editCallback(new_name)
        if not self.renameReadingListCallback then
            logger.warn("Rename reading list callback not set")
            return
        end

        local new_reading_list = self.renameReadingListCallback(item.name, new_name)

        -- Update all reading lists menu
        if new_reading_list then
            self.all_lists_menu.item_table[item.idx].name = new_name
            self.all_lists_menu.item_table[item.idx].text = new_name
            self:updateAllListsMenuItemTable()
        end
    end

    self:editReadingListName(editCallback, item.name)
end

--- Prompt user for reading list name input
function ReadingListMenu:editReadingListName(editCallback, old_name)
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

                        if not self.getReadingListCallback then
                            logger.warn("editReadingListName: Get reading list callback not set")
                            return
                        end

                        -- Check that reading list with name doesn't exist
                        if self.getReadingListCallback(new_name) then
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

return ReadingListMenu
