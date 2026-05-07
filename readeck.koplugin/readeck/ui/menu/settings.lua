local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local RadioButtonWidget = require("ui/widget/radiobuttonwidget")
local UIManager = require("ui/uimanager")
local filemanagerutil = require("apps/filemanager/filemanagerutil")

local I18n = require("readeck.i18n")

local SettingsMenu = {}

local function build_star_button(plugin, L, touchmenu_instance, value)
    return {
        {
            text = value > 0 and L(string.rep("★", value)) or nil,
            text_func = value == 0 and function()
                return L("disabled")
            end or nil,
            align = "left",
            callback = function()
                plugin.sync_star_status = value > 0
                plugin.remote_star_threshold = value
                plugin:saveSettings()
                touchmenu_instance:updateItems()
                UIManager:close(plugin.buttondlg)
            end,
        },
    }
end

function SettingsMenu.install(Readeck, deps)
    local L = deps.L
    local T = deps.T

    function Readeck:getLanguageOverrideLabel()
        local language = self.language_override or ""
        if language == "" then
            return L("Follow KOReader language")
        end
        if language == "en" then
            return L("English")
        end
        if language == "zh-cn" then
            return L("Simplified Chinese")
        end
        return language
    end

    function Readeck:setLanguageOverride(touchmenu_instance)
        local options = {
            { "", L("Follow KOReader language") },
            { "en", L("English") },
            { "zh-cn", L("Simplified Chinese") },
        }
        local radio_buttons = {}
        for _, option in ipairs(options) do
            table.insert(radio_buttons, {
                { text = option[2], provider = option[1], checked = (self.language_override or "") == option[1] },
            })
        end

        UIManager:show(RadioButtonWidget:new({
            title_text = L("Language"),
            cancel_text = L("Cancel"),
            ok_text = L("Apply"),
            radio_buttons = radio_buttons,
            callback = function(radio)
                if radio then
                    self.language_override = radio.provider
                    I18n.set_language_override(self.language_override)
                    self.sort_options = self:buildSortOptions()
                    self:saveSettings()
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end
            end,
        }))
    end

    function Readeck:setSortParam(touchmenu_instance)
        local radio_buttons = {}

        for _, opt in ipairs(self.sort_options) do
            local key, value = opt[1], opt[2]
            table.insert(radio_buttons, {
                { text = value, provider = key, checked = (self.sort_param == key) },
            })
        end

        UIManager:show(RadioButtonWidget:new({
            title_text = L("Sort articles by"),
            cancel_text = L("Cancel"),
            ok_text = L("Apply"),
            radio_buttons = radio_buttons,
            callback = function(radio)
                if radio then
                    self.sort_param = radio.provider
                    self:saveSettings()
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end
            end,
        }))
    end

    function Readeck:buildSettingsMenuItems()
        return {
            {
                text = L("Configure Readeck server"),
                keep_menu_open = true,
                callback = function()
                    self:editServerSettings()
                end,
            },
            {
                text = L("Configure Readeck client"),
                keep_menu_open = true,
                callback = function()
                    self:editClientSettings()
                end,
            },
            {
                text_func = function()
                    return T(L("Language: %1"), self:getLanguageOverrideLabel())
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:setLanguageOverride(touchmenu_instance)
                end,
            },
            {
                text_func = function()
                    local path
                    if not self.directory or self.directory == "" then
                        path = L("Not set")
                    else
                        path = filemanagerutil.abbreviate(self.directory)
                    end
                    return T(L("Download folder: %1"), BD.dirpath(path))
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:setDownloadDirectory(touchmenu_instance)
                end,
                separator = true,
            },
            {
                text_func = function()
                    local filter
                    if not self.filter_tag or self.filter_tag == "" then
                        filter = L("All articles")
                    else
                        filter = self.filter_tag
                    end
                    return T(L("Only download articles with tag: %1"), filter)
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:setFilterTag(touchmenu_instance)
                end,
            },
            {
                text_func = function()
                    local sort_desc = self.sort_param
                    for _, opt in ipairs(self.sort_options) do
                        if opt[1] == self.sort_param then
                            sort_desc = opt[2]
                            break
                        end
                    end
                    return T(L("Sort articles by: %1"), sort_desc)
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:setSortParam(touchmenu_instance)
                end,
            },
            {
                text_func = function()
                    if not self.ignore_tags or self.ignore_tags == "" then
                        return L("Tags to ignore")
                    end
                    return T(L("Tags to ignore (%1)"), self.ignore_tags)
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:setTagsDialog(
                        touchmenu_instance,
                        L("Tags to ignore"),
                        L("Enter a comma-separated list of tags to ignore"),
                        self.ignore_tags,
                        function(tags)
                            self.ignore_tags = tags
                        end
                    )
                end,
            },
            {
                text_func = function()
                    if not self.auto_tags or self.auto_tags == "" then
                        return L("Tags to add to new articles")
                    end
                    return T(L("Tags to add to new articles (%1)"), self.auto_tags)
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:setTagsDialog(
                        touchmenu_instance,
                        L("Tags to add to new articles"),
                        L("Enter a comma-separated list of tags to automatically add to new articles"),
                        self.auto_tags,
                        function(tags)
                            self.auto_tags = tags
                        end
                    )
                end,
                separator = true,
            },
            {
                text = L("Article completion actions"),
                separator = true,
                sub_item_table = {
                    {
                        text = L("Process finished articles in Readeck"),
                        checked_func = function()
                            return self.completion_action_finished_enabled
                        end,
                        callback = function()
                            self.completion_action_finished_enabled = not self.completion_action_finished_enabled
                            self:saveSettings()
                        end,
                    },
                    {
                        text = L("Process 100% read articles in Readeck"),
                        checked_func = function()
                            return self.completion_action_read_enabled
                        end,
                        callback = function()
                            self.completion_action_read_enabled = not self.completion_action_read_enabled
                            self:saveSettings()
                        end,
                        separator = true,
                    },
                    {
                        text = L("Archive completion actions instead of deleting"),
                        checked_func = function()
                            return self.archive_instead_of_delete
                        end,
                        callback = function()
                            self.archive_instead_of_delete = not self.archive_instead_of_delete
                            self:saveSettings()
                        end,
                        separator = true,
                    },
                    {
                        text = L("Process completion actions when syncing"),
                        checked_func = function()
                            return self.process_completion_on_sync
                        end,
                        callback = function()
                            self.process_completion_on_sync = not self.process_completion_on_sync
                            self:saveSettings()
                        end,
                    },
                    {
                        text = L("Sync reading progress to Readeck (beta)"),
                        help_text = L(
                            "Beta: syncs percent-based reading progress both ways. It may move the current position when Readeck has newer progress."
                        ),
                        checked_func = function()
                            return self.sync_reading_progress
                        end,
                        callback = function()
                            self.sync_reading_progress = not self.sync_reading_progress
                            self:saveSettings()
                        end,
                    },
                    {
                        text = L("Remove local files missing from Readeck"),
                        checked_func = function()
                            return self.remove_local_missing_remote
                        end,
                        callback = function()
                            self.remove_local_missing_remote = not self.remove_local_missing_remote
                            self:saveSettings()
                        end,
                    },
                },
            },
            {
                text = L("Highlights"),
                sub_item_table = {
                    {
                        text = L("Sync highlights before article sync"),
                        checked_func = function()
                            return self.export_highlights_before_sync
                        end,
                        callback = function()
                            self.export_highlights_before_sync = not self.export_highlights_before_sync
                            self:saveSettings()
                        end,
                    },
                    {
                        text = L("Sync highlights when closing a document"),
                        checked_func = function()
                            return self.auto_export_highlights
                        end,
                        callback = function()
                            self.auto_export_highlights = not self.auto_export_highlights
                            self:saveSettings()
                        end,
                    },
                },
            },
            {
                text = L("Periodic sync (beta)"),
                help_text = L("Beta: periodically runs sync while KOReader is open."),
                sub_item_table = {
                    {
                        text_func = function()
                            if self.periodic_sync_enabled then
                                return T(L("Enabled: every %1 minutes"), self.periodic_sync_interval_minutes)
                            end
                            return L("Disabled")
                        end,
                        checked_func = function()
                            return self.periodic_sync_enabled
                        end,
                        callback = function(touchmenu_instance)
                            self.periodic_sync_enabled = not self.periodic_sync_enabled
                            self:saveSettings()
                            self:reschedulePeriodicSync()
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                        end,
                    },
                    {
                        text_func = function()
                            return T(L("Interval: %1 minutes"), self.periodic_sync_interval_minutes)
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            self:setPeriodicSyncInterval(touchmenu_instance)
                        end,
                    },
                },
            },
            {
                text_func = function()
                    local stars = {}
                    stars[0] = L("disabled")
                    for i = 1, 5 do
                        stars[i] = T(L("if >= %1"), string.rep("★", i))
                    end
                    return T(L("Like entries in Readeck: %1"), stars[self.remote_star_threshold])
                end,
                help_text = L(
                    "Mark entries as starred/favourited/liked on the server upon sync, if they're rated above your chosen star threshold in the book status page."
                ),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self.buttondlg = ButtonDialog:new({
                        title = L("Star rating threshold"),
                        title_align = "center",
                        width_factor = 0.33,
                        buttons = {
                            build_star_button(self, L, touchmenu_instance, 5),
                            build_star_button(self, L, touchmenu_instance, 4),
                            build_star_button(self, L, touchmenu_instance, 3),
                            build_star_button(self, L, touchmenu_instance, 2),
                            build_star_button(self, L, touchmenu_instance, 1),
                            build_star_button(self, L, touchmenu_instance, 0),
                        },
                    })
                    UIManager:show(self.buttondlg)
                end,
            },
            {
                text = L("Label entries in Readeck with their star rating"),
                help_text = L(
                    "Sync star ratings to Readeck as labels, regardless of threshold for marking entries as liked."
                ),
                keep_menu_open = true,
                checked_func = function()
                    return self.sync_star_rating_as_label
                end,
                callback = function()
                    self.sync_star_rating_as_label = not self.sync_star_rating_as_label
                    self:saveSettings()
                end,
            },
            {
                text = L("Send review as tags"),
                help_text = L(
                    "This allow you to write tags in the review field, separated by commas, which can then be sent to Readeck."
                ),
                keep_menu_open = true,
                checked_func = function()
                    return self.send_review_as_tags or false
                end,
                callback = function()
                    self.send_review_as_tags = not self.send_review_as_tags
                    self:saveSettings()
                end,
            },
            {
                text = L("Remove finished articles from history"),
                keep_menu_open = true,
                checked_func = function()
                    return self.remove_finished_from_history or false
                end,
                callback = function()
                    self.remove_finished_from_history = not self.remove_finished_from_history
                    self:saveSettings()
                end,
            },
            {
                text = L("Remove 100% read articles from history"),
                keep_menu_open = true,
                checked_func = function()
                    return self.remove_read_from_history or false
                end,
                callback = function()
                    self.remove_read_from_history = not self.remove_read_from_history
                    self:saveSettings()
                end,
                separator = true,
            },
            {
                text = L("Set timeout"),
                keep_menu_open = true,
                callback = function()
                    self:editTimeoutSettings()
                end,
            },
            {
                text = L("Authentication"),
                keep_menu_open = true,
                sub_item_table = {
                    {
                        text = L("Authorize with OAuth"),
                        keep_menu_open = true,
                        callback = function()
                            NetworkMgr:runWhenOnline(function()
                                self:authorizeWithOAuthDeviceFlowAsync()
                            end)
                        end,
                    },
                    {
                        text = L("Reset access token"),
                        keep_menu_open = true,
                        callback = function()
                            self:resetAccessToken()
                        end,
                        enabled_func = function()
                            return not self:isempty(self.access_token)
                                or not self:isempty(self.oauth_refresh_token)
                                or not self:isempty(self.auth_token)
                        end,
                    },
                    {
                        text = L("Clear all cached tokens"),
                        keep_menu_open = true,
                        callback = function()
                            self:clearAllTokens()
                        end,
                        enabled_func = function()
                            return not self:isempty(self.access_token)
                                or not self:isempty(self.oauth_refresh_token)
                                or not self:isempty(self.auth_token)
                        end,
                    },
                    {
                        text = L("API token"),
                        keep_menu_open = true,
                        callback = function()
                            self:editAuthSettings()
                        end,
                    },
                },
            },
            {
                text = L("Help"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new({
                        text = L(
                            [[Download directory: use a directory that is exclusively used by the Readeck plugin. Existing files in this directory risk being deleted.

Articles marked as finished or 100% read can be archived or deleted in Readeck. Those actions can also run automatically when syncing if the 'Process completion actions when syncing' option is enabled.

Beta: reading progress below 100% can sync both ways between KOReader and Readeck without archiving the article.

Beta: periodic sync can run while KOReader is open.

Highlight sync merges Readeck annotations into KOReader highlights and exports new KOReader highlights back to Readeck.

The 'Remove local files missing from Readeck' option will remove local files that no longer exist on the server.]]
                        ),
                    }))
                end,
            },
        }
    end
end

return SettingsMenu
