local BD = require("ui/bidi")
local Event = require("ui/event")
local FileManager = require("apps/filemanager/filemanager")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local filemanagerutil = require("apps/filemanager/filemanagerutil")

local SettingsMenu = require("readeck.ui.menu.settings")

local Menu = {}

function Menu.install(Readeck, deps)
    local L = deps.L
    local T = deps.T
    SettingsMenu.install(Readeck, deps)

    local function normalize_directory(path)
        if type(path) ~= "string" or path == "" then
            return nil
        end
        return path:sub(-1) == "/" and path or (path .. "/")
    end

    local function is_current_document_readeck_article(plugin)
        if not (plugin.ui and plugin.ui.document and plugin.ui.document.file) then
            return false
        end

        local directory = normalize_directory(plugin.directory)
        if not directory then
            return false
        end

        local path = tostring(plugin.ui.document.file)
        return path:sub(1, #directory) == directory and plugin:getArticleID(path) ~= nil
    end

    function Readeck:isCurrentDocumentReadeckArticle()
        return is_current_document_readeck_article(self)
    end

    function Readeck:addToMainMenu(menu_items)
        menu_items.readeck = {
            text = L("Readeck"),
            sorting_hint = "tools",
            sub_item_table_func = function()
                local items = {
                    {
                        text = L("Synchronize articles with server"),
                        callback = function()
                            self.ui:handleEvent(Event:new("SynchronizeReadeck"))
                        end,
                    },
                    {
                        text = L("Sync current article highlights"),
                        callback = function()
                            NetworkMgr:runWhenOnline(function()
                                self:syncHighlights()
                            end)
                        end,
                    },
                    {
                        text = L("Process finished/read articles"),
                        callback = function()
                            local connect_callback = function()
                                local counts = self:processLocalFiles("manual")
                                UIManager:show(InfoMessage:new({
                                    text = self:formatLocalProcessingMessage(counts),
                                }))
                                self:refreshCurrentDirIfNeeded()
                            end
                            NetworkMgr:runWhenOnline(connect_callback)
                        end,
                        enabled_func = function()
                            return self.completion_action_finished_enabled or self.completion_action_read_enabled
                        end,
                    },
                    {
                        text_func = function()
                            if self.directory and self.directory ~= "" then
                                return T(
                                    L("Go to download folder: %1"),
                                    BD.dirpath(filemanagerutil.abbreviate(self.directory))
                                )
                            end
                            return L("Go to download folder")
                        end,
                        callback = function()
                            if self:isempty(self.directory) then
                                UIManager:show(InfoMessage:new({
                                    text = L("Please configure a download folder first."),
                                }))
                                return
                            end
                            if self.ui.document then
                                self.ui:onClose()
                            end
                            if FileManager.instance then
                                FileManager.instance:reinit(self.directory)
                            else
                                FileManager:showFiles(self.directory)
                            end
                        end,
                        enabled_func = function()
                            return not self:isempty(self.directory)
                        end,
                    },
                    {
                        text = L("Settings"),
                        callback_func = function()
                            return nil
                        end,
                        separator = true,
                        sub_item_table_func = function()
                            return Readeck.buildSettingsMenuItems(self)
                        end,
                    },
                    {
                        text = L("Info"),
                        keep_menu_open = true,
                        callback = function()
                            UIManager:show(InfoMessage:new({
                                text = T(
                                    L(
                                        [[Readeck is an open source read-it-later service. This plugin synchronizes with a Readeck server.

More details: https://readeck.org

Downloads to folder: %1]]
                                    ),
                                    BD.dirpath(filemanagerutil.abbreviate(self.directory))
                                ),
                            }))
                        end,
                    },
                }
                if not is_current_document_readeck_article(self) then
                    table.remove(items, 2)
                end
                return items
            end,
        }
    end
end

return Menu
