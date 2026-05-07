local BD = require("ui/bidi")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local UIManager = require("ui/uimanager")

local SettingsUI = {}

function SettingsUI.install(Readeck, deps)
    local L = deps.L
    local T = deps.T
    local Log = deps.Log

    function Readeck:setFilterTag(touchmenu_instance)
        self.tag_dialog = InputDialog:new({
            title = L("Enter a single tag to filter articles on"),
            input = self.filter_tag,
            buttons = {
                {
                    {
                        text = L("Cancel"),
                        id = "close",
                        callback = function()
                            UIManager:close(self.tag_dialog)
                        end,
                    },
                    {
                        text = L("OK"),
                        is_enter_default = true,
                        callback = function()
                            self.filter_tag = self.tag_dialog:getInputText()
                            self:saveSettings()
                            touchmenu_instance:updateItems()
                            UIManager:close(self.tag_dialog)
                        end,
                    },
                },
            },
        })
        UIManager:show(self.tag_dialog)
        self.tag_dialog:onShowKeyboard()
    end

    function Readeck:setTagsDialog(touchmenu_instance, title, description, value, callback)
        self.tags_dialog = InputDialog:new({
            title = title,
            description = description,
            input = value,
            buttons = {
                {
                    {
                        text = L("Cancel"),
                        id = "close",
                        callback = function()
                            UIManager:close(self.tags_dialog)
                        end,
                    },
                    {
                        text = L("Set tags"),
                        is_enter_default = true,
                        callback = function()
                            callback(self.tags_dialog:getInputText())
                            self:saveSettings()
                            touchmenu_instance:updateItems()
                            UIManager:close(self.tags_dialog)
                        end,
                    },
                },
            },
        })
        UIManager:show(self.tags_dialog)
        self.tags_dialog:onShowKeyboard()
    end

    function Readeck:editServerSettings()
        local text_info = T(
            L([[
Configure your Readeck server URL.

Authentication options are available in:
Settings > Authentication

Note: For the Server URL, provide the base URL without the /api path (e.g., http://example.com).

Restart KOReader after editing the config file.]]),
            BD.dirpath(DataStorage:getSettingsDir())
        )

        self.settings_dialog = MultiInputDialog:new({
            title = L("Readeck settings"),
            fields = {
                {
                    text = self.server_url,
                    hint = L("Server URL (without /api)"),
                },
            },
            buttons = {
                {
                    {
                        text = L("Cancel"),
                        id = "close",
                        callback = function()
                            UIManager:close(self.settings_dialog)
                        end,
                    },
                    {
                        text = L("Info"),
                        callback = function()
                            UIManager:show(InfoMessage:new({ text = text_info }))
                        end,
                    },
                    {
                        text = L("Apply"),
                        callback = function()
                            local myfields = self.settings_dialog:getFields()
                            self.server_url = myfields[1]:gsub("/*$", "")
                            self.server_info = nil
                            self:saveSettings()
                            UIManager:close(self.settings_dialog)
                        end,
                    },
                },
            },
        })
        UIManager:show(self.settings_dialog)
        self.settings_dialog:onShowKeyboard()
    end

    function Readeck:editAuthSettings()
        local text_info = T(
            L([[
Configure Readeck access.

API token is preferred when provided.
If not set, OAuth device authorization is used by default.
Username/password login is no longer supported by current Readeck versions.]]),
            BD.dirpath(DataStorage:getSettingsDir())
        )

        self.auth_settings_dialog = MultiInputDialog:new({
            title = L("Authentication settings"),
            fields = {
                {
                    text = self.auth_token,
                    hint = L("API Token (optional)"),
                },
            },
            buttons = {
                {
                    {
                        text = L("Cancel"),
                        id = "close",
                        callback = function()
                            UIManager:close(self.auth_settings_dialog)
                        end,
                    },
                    {
                        text = L("Info"),
                        callback = function()
                            UIManager:show(InfoMessage:new({ text = text_info }))
                        end,
                    },
                    {
                        text = L("Apply"),
                        callback = function()
                            local myfields = self.auth_settings_dialog:getFields()
                            self.auth_token = myfields[1]
                            self:saveSettings()
                            UIManager:close(self.auth_settings_dialog)
                        end,
                    },
                },
            },
        })
        UIManager:show(self.auth_settings_dialog)
        self.auth_settings_dialog:onShowKeyboard()
    end

    function Readeck:editClientSettings()
        self.client_settings_dialog = MultiInputDialog:new({
            title = L("Readeck client settings"),
            fields = {
                {
                    text = self.articles_per_sync,
                    description = L("Number of articles"),
                    input_type = "number",
                    hint = L("Number of articles to download per sync"),
                },
                {
                    text = self.download_concurrency,
                    description = L("Concurrent downloads"),
                    input_type = "number",
                    hint = L("Number of article downloads to run at the same time (1-3)"),
                },
            },
            buttons = {
                {
                    {
                        text = L("Cancel"),
                        id = "close",
                        callback = function()
                            UIManager:close(self.client_settings_dialog)
                        end,
                    },
                    {
                        text = L("Apply"),
                        callback = function()
                            local myfields = self.client_settings_dialog:getFields()
                            self.articles_per_sync = math.max(1, tonumber(myfields[1]) or self.articles_per_sync)
                            self.download_concurrency = self:clampDownloadConcurrency(myfields[2])
                            self:saveSettings(myfields)
                            UIManager:close(self.client_settings_dialog)
                        end,
                    },
                },
            },
        })
        UIManager:show(self.client_settings_dialog)
        self.client_settings_dialog:onShowKeyboard()
    end

    function Readeck:setPeriodicSyncInterval(touchmenu_instance)
        self.periodic_interval_dialog = InputDialog:new({
            title = L("Periodic sync interval"),
            input = tostring(self.periodic_sync_interval_minutes),
            input_type = "number",
            buttons = {
                {
                    {
                        text = L("Cancel"),
                        id = "close",
                        callback = function()
                            UIManager:close(self.periodic_interval_dialog)
                        end,
                    },
                    {
                        text = L("Apply"),
                        is_enter_default = true,
                        callback = function()
                            local interval = tonumber(self.periodic_interval_dialog:getInputText())
                                or self.periodic_sync_interval_minutes
                            self.periodic_sync_interval_minutes = math.max(5, math.floor(interval))
                            self:saveSettings()
                            self:reschedulePeriodicSync()
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                            UIManager:close(self.periodic_interval_dialog)
                        end,
                    },
                },
            },
        })
        UIManager:show(self.periodic_interval_dialog)
        self.periodic_interval_dialog:onShowKeyboard()
    end

    function Readeck:setDownloadDirectory(touchmenu_instance)
        require("ui/downloadmgr")
            :new({
                onConfirm = function(path)
                    Log:debug("Set download directory to:", path)
                    self.directory = path
                    self:saveSettings()
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end,
            })
            :chooseDir()
    end

    function Readeck:editTimeoutSettings()
        self.timeout_settings_dialog = MultiInputDialog:new({
            title = L("Set timeout"),
            fields = {
                {
                    text = self.block_timeout,
                    description = L("Block timeout (seconds)"),
                    input_type = "number",
                    hint = L("Block timeout"),
                },
                {
                    text = self.total_timeout,
                    description = L("Total timeout (seconds)"),
                    input_type = "number",
                    hint = L("Total timeout"),
                },
                {
                    text = self.file_block_timeout,
                    description = L("File block timeout (seconds)"),
                    input_type = "number",
                    hint = L("File block timeout"),
                },
                {
                    text = self.file_total_timeout,
                    description = L("File total timeout (seconds)"),
                    input_type = "number",
                    hint = L("File total timeout"),
                },
            },
            buttons = {
                {
                    {
                        text = L("Cancel"),
                        id = "close",
                        callback = function()
                            UIManager:close(self.timeout_settings_dialog)
                        end,
                    },
                    {
                        text = L("Apply"),
                        callback = function()
                            local myfields = self.timeout_settings_dialog:getFields()
                            self.block_timeout = math.max(1, tonumber(myfields[1]) or self.block_timeout)
                            self.total_timeout = math.max(1, tonumber(myfields[2]) or self.total_timeout)
                            self.file_block_timeout = math.max(1, tonumber(myfields[3]) or self.file_block_timeout)
                            self.file_total_timeout = math.max(1, tonumber(myfields[4]) or self.file_total_timeout)
                            self:saveSettings(myfields)
                            UIManager:close(self.timeout_settings_dialog)
                        end,
                    },
                },
            },
        })
        UIManager:show(self.timeout_settings_dialog)
        self.timeout_settings_dialog:onShowKeyboard()
    end
end

return SettingsUI
