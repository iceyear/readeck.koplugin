--[[--
@module koplugin.readeck
]]

-- Readeck for KOReader - Readeck API client plugin
-- Based on wallabag2.koplugin by clach04

local BD = require("ui/bidi")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local DocSettings = require("docsettings")
local Event = require("ui/event")
local FFIUtil = require("ffi/util")
local FileManager = require("apps/filemanager/filemanager")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local JSON = require("json")
local QRMessage = require("ui/widget/qrmessage")
local RadioButtonWidget = require("ui/widget/radiobuttonwidget")
local LuaSettings = require("frontend/luasettings")
local Math = require("optmath")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local ReadHistory = require("readhistory")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local http = require("socket.http")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local util = require("util")
local _ = require("gettext")
local T = FFIUtil.template
local Api = require("readeck.api")
local Dates = require("readeck.dates")
local Features = require("readeck.features")
local Highlights = require("readeck.highlights")
local I18n = require("readeck.i18n")
local Metadata = require("readeck.metadata")
local Scheduler = require("readeck.scheduler")
local Status = require("readeck.status")
local L = I18n.with_gettext(_, function()
    return G_reader_settings
end)

-- Layered logging helper.
local Log = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4,
    level = 4,
}

function Log:debug(...)
    if self.level <= self.DEBUG then
        logger.info("READECK[DEBUG]:", ...)
    end
end

function Log:info(...)
    if self.level <= self.INFO then
        logger.info("READECK[INFO]:", ...)
    end
end

function Log:warn(...)
    if self.level <= self.WARN then
        logger.warn("READECK[WARN]:", ...)
    end
end

function Log:error(...)
    if self.level <= self.ERROR then
        logger.err("READECK[ERROR]:", ...)
    end
end

Log.level = Log.DEBUG

-- constants
local article_id_suffix = " [rd-id_"
local article_id_postfix = "]"
local failed, skipped, downloaded = 1, 2, 3
local OAUTH_DEVICE_GRANT = "urn:ietf:params:oauth:grant-type:device_code"
local DEFAULT_OAUTH_SCOPES = "bookmarks:read bookmarks:write"
local COMPLETION_ACTION_SYNC_POLICY_VERSION = 1

local Readeck = WidgetContainer:extend({
    name = "readeck",
})

function Readeck:onDispatcherRegisterActions()
    Dispatcher:registerAction(
        "readeck_download",
        { category = "none", event = "SynchronizeReadeck", title = L("Readeck sync"), general = true }
    )
end

function Readeck:init()
    Log:info("Initializing Readeck plugin")
    self.token_expiry = 0
    -- Initialize cached authentication info
    self.cached_auth_token = ""
    self.cached_server_url = ""
    self.cached_auth_method = ""
    self.oauth_client_id = ""
    self.oauth_refresh_token = ""
    self.oauth_rng_seeded = false
    self.oauth_poll_state = nil
    self.oauth_prompt_dialog = nil
    self.sync_in_progress = false
    -- default values so that user doesn't have to explicitly set them
    self.completion_action_finished_enabled = true
    self.completion_action_read_enabled = false
    self.process_completion_on_sync = true
    self.completion_action_sync_policy_version = COMPLETION_ACTION_SYNC_POLICY_VERSION
    self.remove_local_missing_remote = false
    self.archive_instead_of_delete = true
    self.send_review_as_tags = false
    self.filter_tag = ""
    self.sort_param = "-created" -- default to most recent first
    self.ignore_tags = ""
    self.auto_tags = ""
    self.articles_per_sync = 30 -- max number of articles to get metadata for
    self.download_concurrency = 2
    self.auto_export_highlights = true
    self.export_highlights_before_sync = true
    self.periodic_sync_enabled = false
    self.periodic_sync_interval_minutes = 60
    self.periodic_sync_callback = nil
    self.server_info = nil
    self.async_http_client_checked = false
    self.async_http_client = nil
    self.experimental_async_downloads = false
    self.download_scheduler = nil
    self.sort_options = {
        { "created", L("Added, oldest first") },
        { "-created", L("Added, most recent first") },
        { "published", L("Published, oldest first") },
        { "-published", L("Published, most recent first") },
        { "duration", L("Duration, shortest first") },
        { "-duration", L("Duration, longest first") },
        { "site", L("Site name, A to Z") },
        { "-site", L("Site name, Z to A") },
        { "title", L("Title, A to Z") },
        { "-title", L("Title, Z to A") },
    }

    -- Default timeout settings in seconds.
    self.block_timeout = 30
    self.total_timeout = 120
    self.file_block_timeout = 10
    self.file_total_timeout = 30

    -- Session cookies.
    self.cookies = {}

    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    self.rd_settings = self:readSettings()
    self.server_url = self.rd_settings.data.readeck.server_url
    self.auth_token = self.rd_settings.data.readeck.auth_token or ""
    self.directory = self.rd_settings.data.readeck.directory

    -- Cached access token and expiry.
    self.access_token = self.rd_settings.data.readeck.access_token or ""
    self.token_expiry = self.rd_settings.data.readeck.token_expiry or 0
    -- Authentication context used to create the current access token.
    self.cached_auth_token = self.rd_settings.data.readeck.cached_auth_token or ""
    self.cached_server_url = self.rd_settings.data.readeck.cached_server_url or ""
    self.cached_auth_method = self.rd_settings.data.readeck.cached_auth_method or ""
    self.oauth_client_id = self.rd_settings.data.readeck.oauth_client_id or ""
    self.oauth_refresh_token = self.rd_settings.data.readeck.oauth_refresh_token or ""
    self.server_info = self.rd_settings.data.readeck.server_info

    local settings = self.rd_settings.data.readeck
    local settings_changed = false
    self.completion_action_sync_policy_version = settings.completion_action_sync_policy_version or 0
    if settings.completion_action_finished_enabled ~= nil then
        self.completion_action_finished_enabled = settings.completion_action_finished_enabled
    elseif settings.is_delete_finished ~= nil then
        self.completion_action_finished_enabled = settings.is_delete_finished
    end
    if settings.send_review_as_tags ~= nil then
        self.send_review_as_tags = settings.send_review_as_tags
    end
    if settings.completion_action_read_enabled ~= nil then
        self.completion_action_read_enabled = settings.completion_action_read_enabled
    elseif settings.is_delete_read ~= nil then
        self.completion_action_read_enabled = settings.is_delete_read
    end
    if settings.process_completion_on_sync ~= nil then
        self.process_completion_on_sync = settings.process_completion_on_sync
    elseif settings.is_auto_delete ~= nil then
        self.process_completion_on_sync = settings.is_auto_delete
    end
    if settings.remove_local_missing_remote ~= nil then
        self.remove_local_missing_remote = settings.remove_local_missing_remote
    elseif settings.is_sync_remote_delete ~= nil then
        self.remove_local_missing_remote = settings.is_sync_remote_delete
    end
    if settings.archive_instead_of_delete ~= nil then
        self.archive_instead_of_delete = settings.archive_instead_of_delete
    elseif settings.is_archiving_deleted ~= nil then
        self.archive_instead_of_delete = settings.is_archiving_deleted
    end
    if self.completion_action_sync_policy_version < COMPLETION_ACTION_SYNC_POLICY_VERSION then
        if
            self.process_completion_on_sync == false
            and self.archive_instead_of_delete ~= false
            and self.completion_action_finished_enabled
        then
            self.process_completion_on_sync = true
            Log:info("Enabled completion actions during sync for archived completion workflow")
        end
        self.completion_action_sync_policy_version = COMPLETION_ACTION_SYNC_POLICY_VERSION
        settings_changed = true
    end
    if self.rd_settings.data.readeck.filter_tag then
        self.filter_tag = self.rd_settings.data.readeck.filter_tag
    end
    if self.rd_settings.data.readeck.sort_param then
        self.sort_param = self.rd_settings.data.readeck.sort_param
    end
    if self.rd_settings.data.readeck.ignore_tags then
        self.ignore_tags = self.rd_settings.data.readeck.ignore_tags
    end
    if self.rd_settings.data.readeck.auto_tags then
        self.auto_tags = self.rd_settings.data.readeck.auto_tags
    end
    if self.rd_settings.data.readeck.articles_per_sync ~= nil then
        self.articles_per_sync = self.rd_settings.data.readeck.articles_per_sync
    end
    if self.rd_settings.data.readeck.download_concurrency ~= nil then
        self.download_concurrency = self:clampDownloadConcurrency(self.rd_settings.data.readeck.download_concurrency)
    end
    if self.rd_settings.data.readeck.experimental_async_downloads ~= nil then
        self.experimental_async_downloads = self.rd_settings.data.readeck.experimental_async_downloads
    end
    if self.rd_settings.data.readeck.auto_export_highlights ~= nil then
        self.auto_export_highlights = self.rd_settings.data.readeck.auto_export_highlights
    end
    if self.rd_settings.data.readeck.export_highlights_before_sync ~= nil then
        self.export_highlights_before_sync = self.rd_settings.data.readeck.export_highlights_before_sync
    end
    if self.rd_settings.data.readeck.periodic_sync_enabled ~= nil then
        self.periodic_sync_enabled = self.rd_settings.data.readeck.periodic_sync_enabled
    end
    if self.rd_settings.data.readeck.periodic_sync_interval_minutes ~= nil then
        self.periodic_sync_interval_minutes = self.rd_settings.data.readeck.periodic_sync_interval_minutes
    end
    -- Timeout settings.
    if self.rd_settings.data.readeck.block_timeout ~= nil then
        self.block_timeout = self.rd_settings.data.readeck.block_timeout
    end
    if self.rd_settings.data.readeck.total_timeout ~= nil then
        self.total_timeout = self.rd_settings.data.readeck.total_timeout
    end
    if self.rd_settings.data.readeck.file_block_timeout ~= nil then
        self.file_block_timeout = self.rd_settings.data.readeck.file_block_timeout
    end
    if self.rd_settings.data.readeck.file_total_timeout ~= nil then
        self.file_total_timeout = self.rd_settings.data.readeck.file_total_timeout
    end
    self.remove_finished_from_history = self.rd_settings.data.readeck.remove_finished_from_history or false
    self.download_queue = self.rd_settings.data.readeck.download_queue or {}
    self.sync_star_status = self.rd_settings.data.readeck.sync_star_status or false
    self.remote_star_threshold = self.rd_settings.data.readeck.remote_star_threshold or 5
    self.sync_star_rating_as_label = self.rd_settings.data.readeck.sync_star_rating_as_label or false

    -- workaround for dateparser only available if newsdownloader is active
    self.is_dateparser_available = false
    self.is_dateparser_checked = false

    -- workaround for dateparser, only once
    -- the parser is in newsdownloader.koplugin, check if it is available
    if not self.is_dateparser_checked then
        local res
        res, self.dateparser = pcall(require, "lib.dateparser")
        if res then
            self.is_dateparser_available = true
        end
        self.is_dateparser_checked = true
    end

    if self.ui and self.ui.link then
        self.ui.link:addToExternalLinkDialog("25_readeck", function(this, link_url)
            return {
                text = L("Add to Readeck"),
                callback = function()
                    UIManager:close(this.external_link_dialog)
                    this.ui:handleEvent(Event:new("AddReadeckArticle", link_url))
                end,
            }
        end)
    end
    if settings_changed then
        self:saveSettings()
    end
    Log:info("Readeck plugin initialization complete")
    self:reschedulePeriodicSync()
end

function Readeck:addToMainMenu(menu_items)
    menu_items.readeck = {
        text = L("Readeck"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = L("Synchronize articles with server"),
                callback = function()
                    self.ui:handleEvent(Event:new("SynchronizeReadeck"))
                end,
            },
            {
                text = L("Export highlights to server"),
                callback = function()
                    NetworkMgr:runWhenOnline(function()
                        self:exportHighlights()
                    end)
                end,
                enabled_func = function()
                    return self.ui.document ~= nil
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
                text = L("Go to download folder"),
                callback = function()
                    if self.ui.document then
                        self.ui:onClose()
                    end
                    if FileManager.instance then
                        FileManager.instance:reinit(self.directory)
                    else
                        FileManager:showFiles(self.directory)
                    end
                end,
            },
            {
                text = L("Settings"),
                callback_func = function()
                    return nil
                end,
                separator = true,
                sub_item_table = {
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
                                    self.completion_action_finished_enabled =
                                        not self.completion_action_finished_enabled
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
                                text = L("Export highlights before sync"),
                                checked_func = function()
                                    return self.export_highlights_before_sync
                                end,
                                callback = function()
                                    self.export_highlights_before_sync = not self.export_highlights_before_sync
                                    self:saveSettings()
                                end,
                            },
                            {
                                text = L("Export highlights when closing a document"),
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
                        text = L("Periodic sync"),
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
                                title = "Threshold",
                                title_align = "center",
                                -- shrink_unneeded_width = true,
                                width_factor = 0.33,
                                buttons = {
                                    {
                                        {
                                            text = L("★★★★★"),
                                            align = "left",
                                            callback = function()
                                                self.sync_star_status = true
                                                self.remote_star_threshold = 5
                                                self:saveSettings()
                                                touchmenu_instance:updateItems()
                                                UIManager:close(self.buttondlg)
                                            end,
                                        },
                                    },
                                    {
                                        {
                                            text = L("★★★★"),
                                            align = "left",
                                            callback = function()
                                                self.sync_star_status = true
                                                self.remote_star_threshold = 4
                                                self:saveSettings()
                                                touchmenu_instance:updateItems()
                                                UIManager:close(self.buttondlg)
                                            end,
                                        },
                                    },
                                    {
                                        {
                                            text = L("★★★"),
                                            align = "left",
                                            callback = function()
                                                self.sync_star_status = true
                                                self.remote_star_threshold = 3
                                                self:saveSettings()
                                                touchmenu_instance:updateItems()
                                                UIManager:close(self.buttondlg)
                                            end,
                                        },
                                    },
                                    {
                                        {
                                            text = L("★★"),
                                            align = "left",
                                            callback = function()
                                                self.sync_star_status = true
                                                self.remote_star_threshold = 2
                                                self:saveSettings()
                                                touchmenu_instance:updateItems()
                                                UIManager:close(self.buttondlg)
                                            end,
                                        },
                                    },
                                    {
                                        {
                                            text = L("★"),
                                            align = "left",
                                            callback = function()
                                                self.sync_star_status = true
                                                self.remote_star_threshold = 1
                                                self:saveSettings()
                                                touchmenu_instance:updateItems()
                                                UIManager:close(self.buttondlg)
                                            end,
                                        },
                                    },
                                    {
                                        {
                                            text_func = function()
                                                return T(L("Disable"), self.remote_star_threshold)
                                            end,
                                            align = "left",
                                            callback = function()
                                                self.sync_star_status = false
                                                self.remote_star_threshold = 0
                                                self:saveSettings()
                                                touchmenu_instance:updateItems()
                                                UIManager:close(self.buttondlg)
                                            end,
                                        },
                                    },
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

The 'Remove local files missing from Readeck' option will remove local files that no longer exist on the server.]]
                                ),
                            }))
                        end,
                    },
                },
            },
            {
                text = L("Info"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new({
                        text = T(
                            L(
                                [[Readeck is an open source read-it-later service. This plugin synchronizes with a Readeck server.

More details: https://www.readeck.net

Downloads to folder: %1]]
                            ),
                            BD.dirpath(filemanagerutil.abbreviate(self.directory))
                        ),
                    }))
                end,
            },
        },
    }
end

function Readeck:isempty(s)
    return s == nil or s == ""
end

function Readeck:clampDownloadConcurrency(value)
    return math.max(1, math.min(3, math.floor(tonumber(value) or 1)))
end

function Readeck:isReadeckDocumentPath(path)
    if not (path and self.directory and self.directory ~= "") then
        return false
    end
    local directory = self.directory
    if string.sub(directory, -1) ~= "/" then
        directory = directory .. "/"
    end
    return self:getArticleID(path) ~= nil and directory == string.sub(path, 1, string.len(directory))
end

function Readeck:formatLocalProcessingMessage(counts)
    counts = counts or Status.new_counts()
    local parts = { L("Articles processed.") }
    if (counts.remote_archived or 0) > 0 then
        table.insert(parts, T(L("Archived in Readeck: %1"), counts.remote_archived))
    end
    if (counts.remote_deleted or 0) > 0 then
        table.insert(parts, T(L("Deleted from Readeck: %1"), counts.remote_deleted))
    end
    if (counts.local_removed or 0) > 0 then
        table.insert(parts, T(L("Removed from KOReader: %1"), counts.local_removed))
    end
    if (counts.failed or 0) > 0 then
        table.insert(parts, T(L("Failed: %1"), counts.failed))
    end
    if #parts == 1 then
        table.insert(parts, L("No local articles needed processing."))
    end
    return table.concat(parts, "\n")
end

function Readeck:appendCompletionResultParts(parts, counts)
    if (counts.remote_archived or 0) > 0 then
        table.insert(parts, T(L("Archived in Readeck: %1"), counts.remote_archived))
    end
    if (counts.remote_deleted or 0) > 0 then
        table.insert(parts, T(L("Deleted from Readeck: %1"), counts.remote_deleted))
    end
    if (counts.local_removed or 0) > 0 then
        table.insert(parts, T(L("Removed from KOReader: %1"), counts.local_removed))
    end
    if (counts.completion_actions_disabled or 0) > 0 then
        table.insert(parts, L("Completion actions skipped during sync."))
    end
end

function Readeck:formatSyncMessage(downloaded_count, skipped_count, failed_count, counts)
    counts = counts or Status.new_counts()
    local parts = { L("Processing finished.") }
    table.insert(parts, T(L("Downloaded: %1"), downloaded_count or 0))
    table.insert(parts, T(L("Skipped: %1"), skipped_count or 0))
    if (failed_count or 0) > 0 then
        table.insert(parts, T(L("Failed: %1"), failed_count))
    end
    self:appendCompletionResultParts(parts, counts)
    if (counts.failed or 0) > 0 then
        table.insert(parts, T(L("Completion action failed: %1"), counts.failed))
    end
    return table.concat(parts, "\n")
end

function Readeck:formatDownloadProgressMessage(counts, total, action_counts)
    counts = counts or {}
    action_counts = action_counts or {}
    local parts = {
        T(L("Syncing articles… %1/%2 checked"), counts.completed or 0, total or 0),
        table.concat({
            T(L("Downloaded: %1"), counts.downloaded or 0),
            T(L("Skipped: %1"), counts.skipped or 0),
            T(L("Failed: %1"), counts.failed or 0),
        }, "  "),
    }
    self:appendCompletionResultParts(parts, action_counts)
    return table.concat(parts, "\n")
end

function Readeck:formatCompletionPlanMessage(plan)
    plan = plan or {}
    local parts = { L("Processing local completion actions…") }
    if (plan.remote_archive_candidates or 0) > 0 then
        table.insert(parts, T(L("Will archive in Readeck: %1"), plan.remote_archive_candidates))
    end
    if (plan.remote_delete_candidates or 0) > 0 then
        table.insert(parts, T(L("Will delete from Readeck: %1"), plan.remote_delete_candidates))
    end
    if (plan.local_remove_candidates or 0) > 0 then
        table.insert(parts, T(L("Will remove from KOReader: %1"), plan.local_remove_candidates))
    end
    if #parts == 1 then
        table.insert(parts, L("No local articles needed processing."))
    end
    return table.concat(parts, "\n")
end

function Readeck:applyDownloadedArticleMetadata(local_path, article)
    local timestamp = Dates.article_timestamp(article, self.is_dateparser_available and self.dateparser or nil)
    if timestamp then
        local ok, err = pcall(lfs.touch, local_path, timestamp, timestamp)
        if not ok then
            Log:warn("Could not set downloaded article timestamp:", local_path, err)
        end
    end

    local ok, err = pcall(Metadata.save_article_keywords, DocSettings, local_path, article, {
        reading_time = L("Reading time"),
        minute = L("min"),
    })
    if not ok then
        Log:warn("Could not save Readeck article metadata:", local_path, err)
    end
end

function Readeck:refreshServerInfo(quiet)
    if self:isempty(self.server_url) then
        return nil
    end
    local info, err = self:callAPI("GET", Api.paths.info, {}, "", "", true)
    if type(info) == "table" then
        self.server_info = info
        self:saveSettings()
        return info
    end
    if not quiet then
        UIManager:show(InfoMessage:new({
            text = L("Could not fetch Readeck server information."),
        }))
    end
    Log:warn("Could not fetch server info", err or "")
    return self.server_info
end

function Readeck:serverSupportsOAuth()
    local support = Features.supports_oauth(self.server_info)
    if support == nil then
        support = Features.supports_oauth(self:refreshServerInfo(true))
    end
    return support
end

function Readeck:resetAccessToken()
    Log:info("Manually resetting access token")

    -- Clear current access token but keep cached authentication context for comparison
    self.access_token = ""
    self.token_expiry = 0

    -- Try to get a new token immediately; OAuth may continue asynchronously.
    if
        self:getBearerToken({
            on_oauth_success = function()
                UIManager:show(InfoMessage:new({
                    text = L("Access token reset successfully"),
                }))
            end,
        })
    then
        UIManager:show(InfoMessage:new({
            text = L("Access token reset successfully"),
        }))
    elseif self:isOAuthPollingActive() then
        UIManager:show(InfoMessage:new({
            text = L("OAuth authorization started. Finish login to refresh access token."),
        }))
    else
        UIManager:show(InfoMessage:new({
            text = L("Failed to obtain new access token"),
        }))
    end
end

function Readeck:clearAllTokens()
    Log:info("Clearing all cached tokens")
    self:cancelOAuthPolling()

    -- Clear all cached authentication data
    self.access_token = ""
    self.token_expiry = 0
    self.cached_auth_token = ""
    self.cached_server_url = ""
    self.cached_auth_method = ""
    self.oauth_client_id = ""
    self.oauth_refresh_token = ""

    -- Save the cleared state
    self:saveSettings()

    UIManager:show(InfoMessage:new({
        text = L("All cached tokens cleared"),
    }))
end

function Readeck:urlEncodeFormValue(value)
    local s = tostring(value or "")
    s = s:gsub("\n", "\r\n")
    s = s:gsub(" ", "+")
    s = s:gsub("([^%w%+%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return s
end

function Readeck:encodeFormData(fields)
    local parts = {}
    for key, value in pairs(fields or {}) do
        if type(value) == "table" then
            for _, item in ipairs(value) do
                table.insert(parts, self:urlEncodeFormValue(key) .. "=" .. self:urlEncodeFormValue(item))
            end
        else
            table.insert(parts, self:urlEncodeFormValue(key) .. "=" .. self:urlEncodeFormValue(value))
        end
    end
    table.sort(parts)
    return table.concat(parts, "&")
end

function Readeck:callOAuthFormAPI(apiurl, form_data)
    if self:isempty(self.server_url) then
        Log:warn("OAuth request attempted without configured server URL")
        return nil, "config_error"
    end

    local sink = {}
    local body = self:encodeFormData(form_data)
    local request = {
        method = "POST",
        url = self.server_url .. apiurl,
        sink = ltn12.sink.table(sink),
        source = ltn12.source.string(body),
        headers = {
            ["Content-type"] = "application/x-www-form-urlencoded",
            ["Accept"] = "application/json, */*",
            ["Content-Length"] = tostring(#body),
        },
    }

    socketutil:set_timeout(self.block_timeout, self.total_timeout)
    local code, resp_headers = socket.skip(1, http.request(request))
    socketutil:reset_timeout()
    if not resp_headers then
        return nil, "network_error"
    end
    local code_num = tonumber(code)

    local content = table.concat(sink)
    local result
    if content ~= "" then
        local ok, parsed = pcall(JSON.decode, content)
        if ok then
            result = parsed
        end
    end
    if code_num and code_num >= 200 and code_num < 300 then
        return result or {}, nil, code_num
    end
    return result, "http_error", code_num or code
end

function Readeck:makeOAuthSoftwareID()
    if not self.oauth_rng_seeded then
        local seed = os.time()
        if socket and socket.gettime then
            seed = seed + math.floor(socket.gettime() * 1000)
        end
        math.randomseed(seed)
        self.oauth_rng_seeded = true
    end
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (
        template:gsub("[xy]", function(c)
            local v
            if c == "x" then
                v = math.random(0, 15)
            else
                v = math.random(8, 11)
            end
            return string.format("%x", v)
        end)
    )
end

function Readeck:storeAccessToken(method, token, expires_in, auth_meta)
    local now = os.time()
    local ttl = tonumber(expires_in)
    if ttl and ttl > 0 then
        self.token_expiry = now + ttl
    else
        self.token_expiry = now + 365 * 24 * 60 * 60
    end
    self.access_token = token
    self.cached_auth_method = method
    self.cached_server_url = self.server_url

    if method == "api_token" then
        self.cached_auth_token = self.auth_token
    else
        self.cached_auth_token = ""
    end

    if auth_meta then
        if auth_meta.oauth_refresh_token ~= nil then
            self.oauth_refresh_token = auth_meta.oauth_refresh_token
        end
        if auth_meta.oauth_client_id ~= nil then
            self.oauth_client_id = auth_meta.oauth_client_id
        end
    end
    self:saveSettings()
end

function Readeck:authenticateWithApiToken()
    Log:info("Using provided API token")
    self:storeAccessToken("api_token", self.auth_token, 365 * 24 * 60 * 60)
    return true
end

function Readeck:formatOAuthUserCode(user_code)
    if not user_code or user_code == "" then
        return ""
    end
    if #user_code == 8 then
        return user_code:sub(1, 4) .. "-" .. user_code:sub(5)
    end
    return user_code
end

function Readeck:refreshOAuthToken()
    if self:isempty(self.oauth_refresh_token) or self:isempty(self.oauth_client_id) then
        return false
    end

    Log:info("Attempting OAuth refresh token flow")
    local result = self:callOAuthFormAPI("/api/oauth/token", {
        grant_type = "refresh_token",
        client_id = self.oauth_client_id,
        refresh_token = self.oauth_refresh_token,
    })
    if result and result.access_token then
        Log:info("OAuth token refreshed")
        self:storeAccessToken("oauth", result.access_token, result.expires_in, {
            oauth_refresh_token = result.refresh_token or self.oauth_refresh_token,
            oauth_client_id = self.oauth_client_id,
        })
        return true
    end

    return false
end

function Readeck:getOAuthDeviceAuthorizationContext()
    if self:isempty(self.server_url) then
        UIManager:show(MultiConfirmBox:new({
            text = L("Please configure the Readeck server URL first."),
            choice1_text = L("Server settings"),
            choice1_callback = function()
                self:editServerSettings()
            end,
            choice2_text = L("Cancel"),
            choice2_callback = function() end,
        }))
        return nil
    end

    local oauth_support = self:serverSupportsOAuth()
    if oauth_support == false then
        local version = Features.version(self.server_info) or L("unknown")
        UIManager:show(InfoMessage:new({
            text = T(
                L(
                    "This Readeck server does not advertise OAuth support.\nServer version: %1\nUse an API token instead."
                ),
                version
            ),
        }))
        return nil
    end

    local client_name = "Readeck for KOReader"
    local software_id = self:makeOAuthSoftwareID()

    local client_info, client_err, client_code = self:callOAuthFormAPI("/api/oauth/client", {
        client_name = client_name,
        client_uri = "https://github.com/iceyear/readeck.koplugin",
        software_id = software_id,
        software_version = "1.0",
        grant_types = { OAUTH_DEVICE_GRANT },
    })

    if not client_info or not client_info.client_id then
        Log:error("OAuth client registration failed", client_err or "", client_code or "")
        UIManager:show(InfoMessage:new({
            text = L("OAuth setup failed: could not register client."),
        }))
        return nil
    end

    local client_id = client_info.client_id
    local device_info, device_err, device_code = self:callOAuthFormAPI("/api/oauth/device", {
        client_id = client_id,
        scope = DEFAULT_OAUTH_SCOPES,
    })
    if not device_info or not device_info.device_code then
        Log:error("OAuth device code request failed", device_err or "", device_code or "")
        UIManager:show(InfoMessage:new({
            text = L("OAuth setup failed: could not request device code."),
        }))
        return nil
    end

    local verification_uri = device_info.verification_uri or ""
    local verification_uri_complete = device_info.verification_uri_complete or verification_uri
    local user_code = self:formatOAuthUserCode(device_info.user_code)
    local fallback_uri = verification_uri ~= "" and verification_uri or (self.server_url .. "/device")
    local interval = tonumber(device_info.interval) or 5
    if interval < 5 then
        interval = 5
    end
    local expires_in = tonumber(device_info.expires_in) or 300
    local deadline = os.time() + math.max(30, expires_in)

    return {
        client_id = client_id,
        device_code = device_info.device_code,
        interval = interval,
        deadline = deadline,
        verification_uri_complete = verification_uri_complete,
        fallback_uri = fallback_uri,
        user_code = user_code,
    }
end

function Readeck:closeOAuthPromptDialog()
    if not self.oauth_prompt_dialog then
        return
    end
    local prompt = self.oauth_prompt_dialog
    self.oauth_prompt_dialog = nil
    UIManager:close(prompt)
end

function Readeck:isOAuthPollingActive()
    return self.oauth_poll_state and not self.oauth_poll_state.done
end

function Readeck:showOAuthPollingPrompt(text)
    self:closeOAuthPromptDialog()
    self.oauth_prompt_dialog = ConfirmBox:new({
        text = text,
        cancel_text = L("Cancel"),
        cancel_callback = function()
            self:cancelOAuthPolling(L("OAuth authorization canceled."))
        end,
        no_ok_button = true,
        keep_dialog_open = true,
        other_buttons = {
            {
                {
                    text = L("Show QR"),
                    callback = function()
                        self:showOAuthPollingQR()
                    end,
                },
            },
        },
        other_buttons_first = true,
    })
    UIManager:show(self.oauth_prompt_dialog)
end

function Readeck:addOAuthSuccessCallback(state, callback)
    if type(callback) ~= "function" or not state then
        return
    end
    state.on_success_callbacks = state.on_success_callbacks or {}
    for _, existing in ipairs(state.on_success_callbacks) do
        if existing == callback then
            return
        end
    end
    table.insert(state.on_success_callbacks, callback)
end

function Readeck:evaluateOAuthDeviceTokenPoll(ctx, token_result, poll_err, poll_code, wait_interval)
    if token_result and token_result.access_token then
        self:storeAccessToken("oauth", token_result.access_token, token_result.expires_in, {
            oauth_refresh_token = token_result.refresh_token or "",
            oauth_client_id = ctx.client_id,
        })
        return "success"
    end

    local oauth_error = token_result and token_result.error or ""
    if oauth_error == "authorization_pending" then
        return "retry", wait_interval
    end
    if oauth_error == "slow_down" then
        return "retry", wait_interval + 5
    end
    if oauth_error == "access_denied" then
        return "fail", L("OAuth authorization was denied.")
    end
    if oauth_error == "expired_token" then
        return "fail", L("OAuth authorization request expired.")
    end
    if poll_code and poll_code >= 500 then
        Log:warn("OAuth token polling server error", poll_code)
        return "retry", wait_interval + 5
    end

    Log:error("OAuth token polling failed", poll_err or "", oauth_error or "", poll_code or "")
    return "fail", L("OAuth token request failed.")
end

function Readeck:cancelOAuthPolling(message)
    local state = self.oauth_poll_state
    if not state or state.done then
        return
    end

    state.done = true
    if state.poll_callback then
        UIManager:unschedule(state.poll_callback)
        state.poll_callback = nil
    end
    if state.qr_dialog then
        local dialog = state.qr_dialog
        state.qr_dialog = nil
        UIManager:close(dialog)
    end
    self:closeOAuthPromptDialog()
    self.oauth_poll_state = nil
    if message then
        UIManager:show(InfoMessage:new({
            text = message,
        }))
    end
end

function Readeck:showOAuthPollingQR()
    local state = self.oauth_poll_state
    if not state or state.done then
        UIManager:show(InfoMessage:new({
            text = L("No OAuth authorization is in progress."),
        }))
        return false
    end
    if not state.verification_uri_complete or state.verification_uri_complete == "" then
        UIManager:show(InfoMessage:new({
            text = L("No QR URL is available for this authorization flow."),
        }))
        return false
    end
    if state.qr_dialog then
        return true
    end

    state.qr_dialog = QRMessage:new({
        text = state.verification_uri_complete,
        width = Device.screen:getWidth(),
        height = Device.screen:getHeight(),
        dismiss_callback = function()
            if state and not state.done then
                state.qr_dialog = nil
            end
        end,
    })
    UIManager:show(state.qr_dialog)
    return true
end

function Readeck:startOAuthPollingAsync(ctx, on_success)
    if not ctx then
        return false
    end
    if self.oauth_poll_state and not self.oauth_poll_state.done then
        self:cancelOAuthPolling()
    end

    local state = {
        done = false,
        poll_callback = nil,
        qr_dialog = nil,
        interval = ctx.interval,
        verification_uri_complete = ctx.verification_uri_complete,
        fallback_uri = ctx.fallback_uri,
        user_code = ctx.user_code,
        on_success_callbacks = {},
    }
    self:addOAuthSuccessCallback(state, on_success)
    self.oauth_poll_state = state

    local function finish(success, message)
        if state.done then
            return
        end
        state.done = true
        if state.poll_callback then
            UIManager:unschedule(state.poll_callback)
            state.poll_callback = nil
        end
        if state.qr_dialog then
            local dialog = state.qr_dialog
            state.qr_dialog = nil
            UIManager:close(dialog)
        end
        if self.oauth_poll_state == state then
            self.oauth_poll_state = nil
        end
        self:closeOAuthPromptDialog()
        if message then
            UIManager:show(InfoMessage:new({
                text = message,
            }))
        end
        if success and state.on_success_callbacks then
            for _, cb in ipairs(state.on_success_callbacks) do
                local callback = cb
                UIManager:scheduleIn(0, function()
                    local ok, err = pcall(callback)
                    if not ok then
                        Log:error("OAuth success callback failed:", err)
                    end
                end)
            end
        end
        return success
    end

    local function schedule_next_poll(delay)
        if state.done then
            return
        end
        state.poll_callback = function()
            state.poll_callback = nil
            if state.done then
                return
            end
            if os.time() >= ctx.deadline then
                finish(false, L("OAuth login timed out."))
                return
            end

            local token_result, poll_err, poll_code = self:callOAuthFormAPI("/api/oauth/token", {
                grant_type = OAUTH_DEVICE_GRANT,
                client_id = ctx.client_id,
                device_code = ctx.device_code,
            })
            local outcome, value =
                self:evaluateOAuthDeviceTokenPoll(ctx, token_result, poll_err, poll_code, state.interval)
            if outcome == "success" then
                finish(true, L("OAuth authorization successful."))
                return
            end
            if outcome == "retry" then
                state.interval = value
                schedule_next_poll(state.interval)
                return
            end
            finish(false, value)
        end
        UIManager:scheduleIn(delay, state.poll_callback)
    end

    schedule_next_poll(state.interval)
    return true
end

function Readeck:authorizeWithOAuthDeviceFlowAsync(options)
    Log:info("Starting OAuth device flow (async)")
    options = options or {}
    if self.oauth_poll_state and not self.oauth_poll_state.done then
        local current_state = self.oauth_poll_state
        self:addOAuthSuccessCallback(current_state, options.on_success)
        if options.auto_trigger then
            return false
        end
        local text = L("OAuth authorization is already in progress.")
        if current_state.fallback_uri and current_state.user_code then
            text = text
                .. T(
                    L("\n\nOpen this URL in your browser:\n%1\nCode: %2"),
                    current_state.fallback_uri,
                    current_state.user_code
                )
        end
        self:showOAuthPollingPrompt(text)
        return false
    end

    local ctx = self:getOAuthDeviceAuthorizationContext()
    if not ctx then
        return false
    end

    self:startOAuthPollingAsync(ctx, options.on_success)
    if not self.oauth_poll_state or self.oauth_poll_state.done then
        return false
    end

    self:showOAuthPollingPrompt(
        T(L("OAuth login started.\nOpen this URL in your browser:\n%1\nCode: %2"), ctx.fallback_uri, ctx.user_code)
    )
    return true
end

function Readeck:getCurrentAuthMethod()
    if not self:isempty(self.auth_token) then
        return "api_token"
    end

    local has_oauth_context = (self.cached_auth_method == "oauth") or (not self:isempty(self.oauth_refresh_token))

    if has_oauth_context then
        return "oauth"
    end
    return "oauth"
end

function Readeck:isAuthContextChanged(auth_method)
    if self.server_url ~= self.cached_server_url then
        return true
    end
    if auth_method ~= self.cached_auth_method then
        return true
    end

    if auth_method == "api_token" then
        return self.auth_token ~= self.cached_auth_token
    end
    return false
end

function Readeck:getBearerToken(options)
    Log:debug("Getting bearer token")
    options = options or {}
    local function authorize_with_oauth()
        self:authorizeWithOAuthDeviceFlowAsync({
            auto_trigger = true,
            on_success = options.on_oauth_success,
        })
        return self:isOAuthPollingActive()
    end

    local server_empty = self:isempty(self.server_url)
    local directory_empty = self:isempty(self.directory)
    if server_empty or directory_empty then
        Log:warn(
            "Configuration incomplete - Server:",
            server_empty and "missing" or "ok",
            ", Directory:",
            directory_empty and "missing" or "ok"
        )
        UIManager:show(MultiConfirmBox:new({
            text = L("Please configure the server settings and set a download folder."),
            choice1_text_func = function()
                if server_empty then
                    return L("Server (★)")
                else
                    return L("Server")
                end
            end,
            choice1_callback = function()
                self:editServerSettings()
            end,
            choice2_text_func = function()
                if directory_empty then
                    return L("Folder (★)")
                else
                    return L("Folder")
                end
            end,
            choice2_callback = function()
                self:setDownloadDirectory()
            end,
        }))
        return false
    end

    local dir_mode = lfs.attributes(self.directory, "mode")
    if dir_mode ~= "directory" then
        Log:warn("Invalid download directory:", self.directory)
        UIManager:show(InfoMessage:new({
            text = L("The download directory is not valid.\nPlease configure it in the settings."),
        }))
        return false
    end
    if string.sub(self.directory, -1) ~= "/" then
        self.directory = self.directory .. "/"
    end

    local now = os.time()
    local auth_method = self:getCurrentAuthMethod()
    local auth_changed = self:isAuthContextChanged(auth_method)
    if not self:isempty(self.access_token) and self.token_expiry > now + 300 and not auth_changed then
        Log:debug("Using cached token, still valid for", self.token_expiry - now, "seconds")
        return true
    end

    if auth_method == "api_token" then
        return self:authenticateWithApiToken()
    end

    if auth_method == "oauth" then
        if self:refreshOAuthToken() then
            return true
        end
        if authorize_with_oauth() then
            return false
        end
        return false
    end

    authorize_with_oauth()
    return false
end

function Readeck:scheduleSyncAfterOAuth()
    NetworkMgr:runWhenOnline(function()
        self:synchronize()
        self:refreshCurrentDirIfNeeded()
    end)
end

--- Get a JSON formatted list of articles from the server.
-- The list should have self.article_per_sync item, or less if an error occured.
-- If filter_tag is set, only articles containing this tag are queried.
-- If ignore_tags is defined, articles containing either of the tags are skipped.
function Readeck:getArticleList()
    local article_list = {}
    local offset = 0
    local limit = math.min(self.articles_per_sync, 30) -- Readeck defaults to 30 items per page.

    -- Fetch pages until the configured target count is reached.
    while #article_list < self.articles_per_sync do
        -- Fetch one page of bookmark summaries.
        local articles_url = Api.bookmarks_query({
            limit = limit,
            offset = offset,
            is_archived = 0,
            type = "article",
            labels = self.filter_tag,
            sort = self.sort_param,
        })

        Log:debug("Fetching article list with URL:", articles_url)
        local articles_json, err, code = self:callAPI("GET", articles_url, nil, "", "", true)

        if err == "http_error" and code == 404 then
            Log:debug("Couldn't get offset", offset)
            break
        elseif err == "auth_pending" then
            Log:info("OAuth authorization started while requesting article list")
            return nil, err
        elseif err or articles_json == nil then
            Log:warn("Download at offset", offset, "failed with", err, code)
            UIManager:show(InfoMessage:new({
                text = L("Requesting article list failed."),
            }))
            return
        end

        -- Keep the response as a regular array for easier filtering.
        local new_article_list = {}
        for _, article in ipairs(articles_json) do
            table.insert(new_article_list, article)
        end

        local pending_articles = #new_article_list >= limit

        new_article_list = self:filterIgnoredTags(new_article_list)

        for _, article in ipairs(new_article_list) do
            if #article_list == self.articles_per_sync then
                Log:debug("Hit the article target", self.articles_per_sync)
                break
            end
            table.insert(article_list, article)
        end

        if not pending_articles then
            Log:debug("No more articles to query")
            break
        end

        offset = offset + limit
    end

    return article_list
end

--- Remove all the articles from the list containing one of the ignored tags.
-- article_list: array containing a json formatted list of articles
-- returns: same array, but without any articles that contain an ignored tag.
function Readeck:filterIgnoredTags(article_list)
    -- decode all tags to ignore
    local ignoring = {}
    if self.ignore_tags ~= "" then
        for tag in util.gsplit(self.ignore_tags, "[,]+", false) do
            ignoring[tag] = true
        end
    end

    -- rebuild a list without the ignored articles
    local filtered_list = {}
    for _, article in ipairs(article_list) do
        local skip_article = false
        for _, tag in ipairs(article.labels or {}) do
            if ignoring[tag] then
                skip_article = true
                Log:debug("Ignoring tag", tag, "in article", article.id, ":", article.title)
                break -- no need to look for other tags
            end
        end
        if not skip_article then
            table.insert(filtered_list, article)
        end
    end

    return filtered_list
end

function Readeck:getDownloadDirectory()
    local directory = self.directory or ""
    if directory ~= "" and directory:sub(-1) ~= "/" then
        directory = directory .. "/"
    end
    return directory
end

function Readeck:findLocalArticlePathByID(article_id)
    if self:isempty(self.directory) or not article_id then
        return nil
    end
    if lfs.attributes(self.directory, "mode") ~= "directory" then
        return nil
    end

    local expected_id = tostring(article_id)
    for entry in lfs.dir(self.directory) do
        if entry ~= "." and entry ~= ".." then
            local entry_path = FFIUtil.joinPath(self.directory, entry)
            if self:getArticleID(entry_path) == expected_id and lfs.attributes(entry_path, "mode") == "file" then
                return entry_path
            end
        end
    end
    return nil
end

function Readeck:getDownloadTarget(article)
    local existing_path = self:findLocalArticlePathByID(article.id)
    if existing_path then
        return existing_path, Api.paths.bookmark_article(article.id)
    end

    local title = util.getSafeFilename(article.title, self.directory, 230, 0)
    local file_ext = ".epub"
    local local_path = self:getDownloadDirectory()
        .. title
        .. article_id_suffix
        .. article.id
        .. article_id_postfix
        .. file_ext
    return local_path, Api.paths.bookmark_article(article.id)
end

function Readeck:shouldSkipDownload(local_path, article)
    Log:debug("DOWNLOAD: id:", article.id)
    Log:debug("DOWNLOAD: title:", article.title)
    Log:debug("DOWNLOAD: filename:", local_path)

    local attr = lfs.attributes(local_path)
    if attr then
        Log:debug("Skipping existing local article:", local_path)
        return true
    end

    local existing_path = self:findLocalArticlePathByID(article.id)
    if existing_path then
        Log:debug("Skipping existing local article by Readeck ID:", existing_path)
        return true
    end

    return false
end

function Readeck:getAsyncHTTPClient()
    if not self.experimental_async_downloads or self:clampDownloadConcurrency(self.download_concurrency) <= 1 then
        return nil
    end
    if self.async_http_client_checked then
        return self.async_http_client
    end
    self.async_http_client_checked = true
    local ok, client = pcall(require, "httpclient")
    if ok and type(client) == "table" and type(client.new) == "function" then
        self.async_http_client = client
    end
    return self.async_http_client
end

function Readeck:disableAsyncHTTPClient(reason)
    if self.async_http_client then
        Log:warn("Disabling async article downloader:", reason or "download failed")
    end
    self.async_http_client = nil
    self.async_http_client_checked = true
end

function Readeck:writeDownloadedArticle(local_path, body)
    local file, err = io.open(local_path, "wb")
    if not file then
        Log:error("Could not open downloaded article file:", local_path, err or "")
        return false
    end
    file:write(body or "")
    file:close()
    return true
end

function Readeck:getAsyncResponseCode(response)
    local code = response and (response.code or response.status)
    if type(code) == "string" then
        return tonumber(code) or tonumber(code:match("(%d%d%d)"))
    end
    return tonumber(code)
end

function Readeck:formatAsyncDownloadFailure(response)
    if not response then
        return "no response"
    end
    if response.error then
        local err = response.error
        if type(err) == "table" then
            return tostring(err.message or err.code or "network error")
        end
        return tostring(err)
    end
    return tostring(self:getAsyncResponseCode(response) or "network error")
end

function Readeck:isAsyncClientFailure(response)
    return not response or response.error ~= nil or self:getAsyncResponseCode(response) == nil
end

function Readeck:handleAsyncDownloadResponse(article, local_path, response)
    local code = self:getAsyncResponseCode(response)
    if code and code >= 200 and code < 300 and response.body then
        if self:writeDownloadedArticle(local_path, response.body) then
            self:applyDownloadedArticleMetadata(local_path, article)
            return downloaded
        end
    end

    if lfs.attributes(local_path, "mode") == "file" then
        os.remove(local_path)
    end
    Log:warn("Async article download failed:", article.id, self:formatAsyncDownloadFailure(response))
    return failed
end

function Readeck:downloadAsync(article, done)
    local client = self:getAsyncHTTPClient()
    if not client then
        UIManager:scheduleIn(0, function()
            done(self:download(article))
        end)
        return Scheduler.ASYNC
    end

    local local_path, item_url = self:getDownloadTarget(article)
    if self:shouldSkipDownload(local_path, article) then
        self:applyDownloadedArticleMetadata(local_path, article)
        done(skipped)
        return Scheduler.ASYNC
    end

    client:new():request({
        url = self.server_url .. item_url,
        method = "GET",
        on_headers = function(headers)
            headers:add("Authorization", "Bearer " .. self.access_token)
            headers:add("Accept", "application/epub+zip, */*")
        end,
    }, function(response)
        local result = self:handleAsyncDownloadResponse(article, local_path, response)
        if result == failed then
            if self:isAsyncClientFailure(response) then
                self:disableAsyncHTTPClient(self:formatAsyncDownloadFailure(response))
            end
            Log:warn("Retrying article download with blocking client:", article.id)
            result = self:download(article)
        end
        done(result)
    end)

    return Scheduler.ASYNC
end

--- Download Readeck article.
-- @string article
-- @treturn int 1 failed, 2 skipped, 3 downloaded
function Readeck:download(article)
    local local_path, item_url = self:getDownloadTarget(article)
    if not self:shouldSkipDownload(local_path, article) then
        local ok, err, code = self:callAPI("GET", item_url, nil, "", local_path)
        if ok then
            self:applyDownloadedArticleMetadata(local_path, article)
            return downloaded
        end
        Log:warn("Article download failed:", article.id, err or "unknown", code or "")
        return failed
    end
    self:applyDownloadedArticleMetadata(local_path, article)
    return skipped
end

function Readeck:wrapSinkWithUIRefresh(sink)
    local last_refresh = socket.gettime()
    return function(chunk, err)
        local ok, sink_err = sink(chunk, err)
        if chunk then
            local now = socket.gettime()
            if now - last_refresh >= 1 then
                last_refresh = now
                UIManager:forceRePaint()
            end
        end
        return ok, sink_err
    end
end

-- method: (mandatory) GET, POST, DELETE, PATCH, etc...
-- apiurl: (mandatory) API call excluding the server path, or full URL to a file
-- headers: defaults to auth if given nil value, provide all headers necessary if in use
-- body: empty string if not needed
-- filepath: downloads the file if provided, returns JSON otherwise
-- @treturn result or (nil, "network_error") or (nil, "json_error")
-- or (nil, "http_error", code)
function Readeck:callAPI(method, apiurl, headers, body, filepath, quiet, retry_auth)
    local sink = {}
    local request = {}

    -- Is it an API call, or a regular file direct download?
    if apiurl:sub(1, 1) == "/" then
        -- API call to our server, has the form "/random/api/call"
        request.url = self.server_url .. apiurl
        if headers == nil then
            headers = {
                ["Authorization"] = "Bearer " .. self.access_token,
            }
        end
    else
        -- regular url link to a foreign server
        local file_url = apiurl
        request.url = file_url
        if headers == nil then
            -- no need for a token here
            headers = {}
        end
    end

    request.method = method

    if filepath ~= "" then
        local file, open_err = io.open(filepath, "wb")
        if not file then
            Log:error("Could not open response file:", filepath, open_err or "")
            return nil, "file_error"
        end
        socketutil:set_timeout(self.file_block_timeout, self.file_total_timeout)
        request.sink = self:wrapSinkWithUIRefresh(socketutil.file_sink(file))
    else
        socketutil:set_timeout(self.block_timeout, self.total_timeout)
        request.sink = socketutil.table_sink(sink)
    end
    request.headers = headers
    if body ~= "" then
        request.source = ltn12.source.string(body)
    end
    Log:debug("API request - URL:", request.url, "Method:", method)

    -- Log request headers while redacting authorization.
    for k, v in pairs(headers or {}) do
        if k == "Authorization" then
            Log:debug("Header:", k, "= Bearer ***")
        else
            Log:debug("Header:", k, "=", v)
        end
    end

    local code, resp_headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()

    -- Log response headers.
    if resp_headers then
        Log:debug("Response code:", code, "Status:", status or "nil")
        for k, v in pairs(resp_headers) do
            Log:debug("Response header:", k, "=", v)
        end
    else
        Log:error("No response headers received")
        return nil, "network_error"
    end

    -- Handle authentication errors - retry with fresh token if possible.
    -- Do not recurse on auth endpoints themselves.
    local is_auth_endpoint = apiurl == Api.paths.info or apiurl:sub(1, 11) == "/api/oauth/"
    if (code == 401 or code == 403) and not retry_auth and apiurl:sub(1, 1) == "/" and not is_auth_endpoint then
        Log:info("Authentication failed (", code, "), attempting to refresh token")

        -- Clear current token and try to get a fresh one
        self.access_token = ""
        self.token_expiry = 0

        local oauth_success_callback = nil
        if self.sync_in_progress then
            oauth_success_callback = function()
                self:scheduleSyncAfterOAuth()
            end
        end

        if self:getBearerToken({
            on_oauth_success = oauth_success_callback,
        }) then
            Log:info("Token refreshed, retrying API call")
            -- Retry the API call with the new token, but mark retry_auth to prevent infinite recursion
            return self:callAPI(method, apiurl, nil, body, filepath, quiet, true)
        elseif self:isOAuthPollingActive() then
            Log:info("OAuth authorization flow started after auth failure")
            return nil, "auth_pending", code
        else
            Log:error("Failed to refresh token")
            if not quiet then
                UIManager:show(InfoMessage:new({
                    text = L("Authentication failed. Please check your OAuth or API token settings."),
                }))
            end
            return nil, "auth_error", code
        end
    end

    -- Handle successful responses.
    if code == 200 or code == 201 or code == 202 or code == 204 then
        if filepath ~= "" then
            Log:info("File downloaded successfully to", filepath)
            return true
        else
            local content = table.concat(sink)
            Log:debug("Response content length:", #content, "bytes")

            if #content > 0 and #content < 500 then
                Log:debug("Response content:", content)
            end

            if code == 204 then
                Log:debug("Successfully received 204 No Content response")
                return true
            elseif content ~= "" and (string.sub(content, 1, 1) == "{" or string.sub(content, 1, 1) == "[") then
                local ok, result = pcall(JSON.decode, content)
                if ok and result then
                    Log:debug("Successfully parsed JSON response")
                    return result
                else
                    Log:error("Failed to parse JSON:", result or "unknown error")
                    if not quiet then
                        UIManager:show(InfoMessage:new({
                            text = L("Server response is not valid."),
                        }))
                    end
                end
            elseif content == "" then
                Log:debug("Empty response with successful status code")
                return true
            else
                Log:error("Response is not valid JSON")
                if not quiet then
                    UIManager:show(InfoMessage:new({
                        text = L("Server response is not valid."),
                    }))
                end
            end
            return nil, "json_error"
        end
    else
        if filepath ~= "" then
            local entry_mode = lfs.attributes(filepath, "mode")
            if entry_mode == "file" then
                os.remove(filepath)
                Log:warn("Removed failed download:", filepath)
            end
        elseif not quiet then
            Log:error("Communication with server failed:", code)
            UIManager:show(InfoMessage:new({
                text = L("Communication with server failed."),
            }))
        end
        Log:error("Request failed:", status or code, "URL:", request.url)
        return nil, "http_error", code
    end
end

function Readeck:showDownloadProgress(counts, total, action_counts)
    local message = self:formatDownloadProgressMessage(counts, total, action_counts)
    UIManager:show(InfoMessage:new({
        text = message,
        timeout = 1,
    }))
    UIManager:forceRePaint()
end

function Readeck:downloadArticlesAsync(articles, options)
    options = options or {}
    local counts = {
        downloaded = 0,
        skipped = 0,
        failed = 0,
        completed = 0,
    }
    local remote_article_ids = {}
    local total = #articles

    if total == 0 then
        if options.on_finish then
            options.on_finish(counts, remote_article_ids)
        end
        return nil
    end

    self:showDownloadProgress(counts, total, options.action_counts)
    local max_concurrent = self:getAsyncHTTPClient() and self:clampDownloadConcurrency(self.download_concurrency) or 1
    if max_concurrent <= 1 then
        Log:info("Using blocking article downloader")
    else
        Log:info("Using experimental async article downloader with concurrency:", max_concurrent)
    end
    self.download_scheduler = Scheduler.run(articles, {
        max_concurrent = max_concurrent,
        schedule = function(callback, delay)
            UIManager:scheduleIn(delay or 0, callback)
        end,
        worker = function(article, done)
            Log:debug("Processing article ID:", article.id)
            remote_article_ids[tostring(article.id)] = true
            return self:downloadAsync(article, done)
        end,
        on_result = function(_, result)
            if result == downloaded then
                counts.downloaded = counts.downloaded + 1
            elseif result == skipped then
                counts.skipped = counts.skipped + 1
            else
                counts.failed = counts.failed + 1
            end
            counts.completed = counts.completed + 1
            self:showDownloadProgress(counts, total, options.action_counts)
        end,
        on_finish = function()
            self.download_scheduler = nil
            if options.on_finish then
                options.on_finish(counts, remote_article_ids)
            end
        end,
    })
    return self.download_scheduler
end

function Readeck:filterArticlesProcessedEarlierInSync(articles, processed_article_ids)
    if type(processed_article_ids) ~= "table" then
        return articles
    end

    local filtered = {}
    for _, article in ipairs(articles or {}) do
        if processed_article_ids[tostring(article.id)] then
            Log:debug("Skipping article already processed during this sync:", article.id)
        else
            table.insert(filtered, article)
        end
    end
    return filtered
end

function Readeck:synchronize()
    if self.sync_in_progress then
        Log:info("Sync requested while another sync is already running")
        return false
    end
    self.sync_in_progress = true
    local info = InfoMessage:new({ text = L("Connecting…") })
    UIManager:show(info)
    UIManager:forceRePaint()
    UIManager:close(info)

    if
        self:getBearerToken({
            on_oauth_success = function()
                self:scheduleSyncAfterOAuth()
            end,
        }) == false
    then
        self.sync_in_progress = false
        return false
    end
    if self.download_queue and next(self.download_queue) ~= nil then
        info = InfoMessage:new({ text = L("Adding articles from queue…") })
        UIManager:show(info)
        UIManager:forceRePaint()
        for _, articleUrl in ipairs(self.download_queue) do
            self:addArticle(articleUrl)
        end
        self.download_queue = {}
        self:saveSettings()
        UIManager:close(info)
    end

    if self.export_highlights_before_sync then
        self:exportHighlightsForLocalFiles({ quiet = true })
    end

    local action_counts = self:processLocalFiles("sync")

    info = InfoMessage:new({ text = L("Getting article list…") })
    UIManager:show(info)
    UIManager:forceRePaint()
    UIManager:close(info)

    if self.access_token ~= "" then
        local articles, list_err = self:getArticleList()
        if list_err == "auth_pending" then
            self.sync_in_progress = false
            return false
        end
        if articles then
            articles = self:filterArticlesProcessedEarlierInSync(articles, action_counts.processed_article_ids)
            Log:debug("Number of articles:", #articles)

            info = InfoMessage:new({ text = L("Checking articles…") })
            UIManager:show(info)
            UIManager:forceRePaint()
            UIManager:close(info)

            self:downloadArticlesAsync(articles, {
                action_counts = action_counts,
                on_finish = function(download_counts, remote_article_ids)
                    Status.add(action_counts, self:processRemoteDeletes(remote_article_ids))

                    UIManager:show(InfoMessage:new({
                        text = self:formatSyncMessage(
                            download_counts.downloaded,
                            download_counts.skipped,
                            download_counts.failed,
                            action_counts
                        ),
                    }))
                    self.sync_in_progress = false
                    self:refreshCurrentDirIfNeeded()
                end,
            })
            return true
        end -- articles
    end -- access_token
    self.sync_in_progress = false
end

function Readeck:processRemoteDeletes(remote_article_ids)
    local counts = Status.new_counts()
    if not self.remove_local_missing_remote then
        Log:debug("Processing of remote file removals disabled.")
        return counts
    end
    Log:debug("Articles IDs from server:", remote_article_ids)

    local candidates = self:collectRemoteDeleteCandidates(remote_article_ids)
    if #candidates == 0 then
        return counts
    end

    local info = InfoMessage:new({
        text = table.concat({
            L("Removing local files missing from Readeck…"),
            T(L("Will remove from KOReader: %1"), #candidates),
        }, "\n"),
    })
    UIManager:show(info)
    UIManager:forceRePaint()
    UIManager:close(info)
    for _, entry_path in ipairs(candidates) do
        Log:debug("Deleting local file (deleted on server):", entry_path)
        counts.local_removed = counts.local_removed + self:deleteLocalArticle(entry_path)
    end
    return counts
end

function Readeck:collectRemoteDeleteCandidates(remote_article_ids)
    local candidates = {}
    for entry in lfs.dir(self.directory) do
        if entry ~= "." and entry ~= ".." then
            local entry_path = FFIUtil.joinPath(self.directory, entry)
            local id = self:getArticleID(entry_path)
            if id and not remote_article_ids[id] and lfs.attributes(entry_path, "mode") == "file" then
                table.insert(candidates, entry_path)
            end
        end
    end -- for entry
    return candidates
end

function Readeck:isCompletionProcessingEnabledForMode(mode)
    return not mode or mode == "manual" or self.process_completion_on_sync ~= false
end

function Readeck:getLocalCompletionAction(path)
    local doc_settings = DocSettings:open(path)
    local summary = doc_settings:readSetting("summary")
    local status = summary and summary.status
    local percent_finished = doc_settings:readSetting("percent_finished")
    if status == "complete" or status == "abandoned" then
        if self.completion_action_finished_enabled then
            return {
                mark_read_complete = (status == "complete") or (percent_finished == 1),
            }
        end
    elseif percent_finished == 1 then
        if self.completion_action_read_enabled then
            return {
                mark_read_complete = true,
            }
        end
    end
end

function Readeck:collectLocalFileActions(options)
    options = options or {}
    local completion_enabled = options.completion_enabled ~= false
    local completion_actions_enabled = completion_enabled
        and (self.completion_action_finished_enabled or self.completion_action_read_enabled)
    local should_scan = completion_actions_enabled or self.send_review_as_tags
    local files = {}
    local plan = {
        remote_archive_candidates = 0,
        remote_delete_candidates = 0,
        local_remove_candidates = 0,
    }
    if not should_scan then
        return files, plan
    end

    for entry in lfs.dir(self.directory) do
        if entry ~= "." and entry ~= ".." then
            local entry_path = FFIUtil.joinPath(self.directory, entry)
            if lfs.attributes(entry_path, "mode") == "file" and DocSettings:hasSidecarFile(entry_path) then
                local file_action = {
                    path = entry_path,
                }
                if completion_actions_enabled then
                    local completion_action = self:getLocalCompletionAction(entry_path)
                    if completion_action and self:getArticleID(entry_path) then
                        file_action.completion_action = completion_action
                        if self.archive_instead_of_delete then
                            plan.remote_archive_candidates = plan.remote_archive_candidates + 1
                        else
                            plan.remote_delete_candidates = plan.remote_delete_candidates + 1
                        end
                        plan.local_remove_candidates = plan.local_remove_candidates + 1
                    end
                end
                table.insert(files, file_action)
            end
        end
    end
    return files, plan
end

function Readeck:processLocalFiles(mode)
    local counts = Status.new_counts()
    local completion_enabled = self:isCompletionProcessingEnabledForMode(mode)
    if not completion_enabled then
        counts.completion_actions_disabled = 1
        if not self.send_review_as_tags then
            Log:debug("Automatic processing of local completion actions disabled.")
            return counts
        end
    end

    if
        self:getBearerToken({
            on_oauth_success = function()
                NetworkMgr:runWhenOnline(function()
                    self:processLocalFiles(mode)
                    self:refreshCurrentDirIfNeeded()
                end)
            end,
        }) == false
    then
        return counts
    end

    local local_files, plan = self:collectLocalFileActions({
        completion_enabled = completion_enabled,
    })
    if #local_files > 0 then
        local message = L("Processing local files…")
        if completion_enabled and (self.completion_action_finished_enabled or self.completion_action_read_enabled) then
            message = self:formatCompletionPlanMessage(plan)
        end
        local info = InfoMessage:new({ text = message })
        UIManager:show(info)
        UIManager:forceRePaint()
        UIManager:close(info)
    end
    for _, local_file in ipairs(local_files) do
        if self.send_review_as_tags then
            self:addTags(local_file.path)
        end
        if local_file.completion_action then
            Status.add(counts, self:removeArticle(local_file.path, local_file.completion_action.mark_read_complete))
        end
    end
    return counts
end

function Readeck:addArticle(article_url)
    Log:debug("Adding article", article_url)

    if not article_url then
        return false
    end
    if
        self:getBearerToken({
            on_oauth_success = function()
                NetworkMgr:runWhenOnline(function()
                    self:addArticle(article_url)
                    self:refreshCurrentDirIfNeeded()
                end)
            end,
        }) == false
    then
        if self:isOAuthPollingActive() then
            return nil, "auth_pending"
        end
        return false
    end

    local body = {
        url = article_url,
    }

    -- Apply configured labels to newly submitted bookmarks.
    if self.auto_tags and self.auto_tags ~= "" then
        local tags = {}
        for tag in util.gsplit(self.auto_tags, "[,]+", false) do
            table.insert(tags, tag:gsub("^%s*(.-)%s*$", "%1"))
        end
        body.labels = tags
    end

    local body_JSON = JSON.encode(body)

    local headers = {
        ["Content-type"] = "application/json",
        ["Accept"] = "application/json, */*",
        ["Content-Length"] = tostring(#body_JSON),
        ["Authorization"] = "Bearer " .. self.access_token,
    }

    return self:callAPI("POST", Api.paths.bookmarks, headers, body_JSON, "")
end

function Readeck:addTags(path)
    Log:debug("Managing tags for article", path)
    local id = self:getArticleID(path)
    if id then
        local doc_settings = DocSettings:open(path)
        local summary = doc_settings:readSetting("summary")
        local tags_text = summary and summary.note
        if tags_text and tags_text ~= "" then
            Log:debug("Sending tags", tags_text, "for", path)

            local tags = {}
            for tag in util.gsplit(tags_text, "[,]+", false) do
                table.insert(tags, tag:gsub("^%s*(.-)%s*$", "%1"))
            end

            local body = {
                add_labels = tags,
            }

            local bodyJSON = JSON.encode(body)

            local headers = {
                ["Content-type"] = "application/json",
                ["Accept"] = "application/json, */*",
                ["Content-Length"] = tostring(#bodyJSON),
                ["Authorization"] = "Bearer " .. self.access_token,
            }

            self:callAPI("PATCH", Api.paths.bookmark(id), headers, bodyJSON, "")
        else
            Log:debug("No tags to send for", path)
        end
    end
end

-- Remove (or archive) an article remotely and delete it locally.
-- If mark_read_complete is true and we're archiving, also set read_progress=100 on the server.
function Readeck:removeArticle(path, mark_read_complete)
    Log:debug("Removing article", path)
    local counts = Status.new_counts()
    local id = self:getArticleID(path)
    if id then
        local highlights_ok = self:exportHighlightsForPath(path, { quiet = true })
        if highlights_ok == false then
            Log:warn("Skipping completion action because highlight export failed:", path)
            counts.failed = counts.failed + 1
            return counts
        end

        local remote_ok
        if self.archive_instead_of_delete then
            local body = {
                is_archived = true,
            }
            if mark_read_complete then
                body.read_progress = 100
            end
            if self.sync_star_status then
                local doc_settings = DocSettings:open(path)
                local summary = doc_settings:readSetting("summary")
                if summary and summary.rating then
                    if summary.rating > 0 and self.sync_star_rating_as_label == true then
                        local label = { summary.rating .. "-star" }
                        body.add_labels = label
                    end
                    if summary.rating >= self.remote_star_threshold then
                        body.is_marked = true
                    end
                end
            end
            local bodyJSON = JSON.encode(body)

            local headers = {
                ["Content-type"] = "application/json",
                ["Accept"] = "application/json, */*",
                ["Content-Length"] = tostring(#bodyJSON),
                ["Authorization"] = "Bearer " .. self.access_token,
            }

            remote_ok = self:callAPI("PATCH", Api.paths.bookmark(id), headers, bodyJSON, "")
            if remote_ok then
                counts.remote_archived = counts.remote_archived + 1
            end
        else
            remote_ok = self:callAPI("DELETE", Api.paths.bookmark(id), nil, "", "")
            if remote_ok then
                counts.remote_deleted = counts.remote_deleted + 1
            end
        end
        if remote_ok then
            counts.processed_article_ids = {
                [tostring(id)] = true,
            }
            counts.local_removed = counts.local_removed + self:deleteLocalArticle(path)
        else
            counts.failed = counts.failed + 1
        end
    end
    return counts
end

function Readeck:deleteLocalArticle(path)
    if lfs.attributes(path, "mode") == "file" then
        FileManager:deleteFile(path, true)
        return 1
    end
    return 0
end

function Readeck:getArticleID(path)
    -- 1. Find the starting position of the prefix
    local start_pos = path:find(article_id_suffix, 1, true) -- `true` disables pattern matching
    if not start_pos then
        return -- Suffix not found
    end

    -- 2. Find the ending position of the postfix, starting after the prefix
    local end_pos = path:find(article_id_postfix, start_pos)
    if not end_pos then
        return -- Postfix not found
    end

    -- 3. Extract the ID from between the markers
    local id_start = start_pos + article_id_suffix:len()
    local id_end = end_pos - 1
    return path:sub(id_start, id_end)
end

function Readeck:refreshCurrentDirIfNeeded()
    if FileManager.instance then
        FileManager.instance:onRefresh()
    end
end

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
                        self.server_url = myfields[1]:gsub("/*$", "") -- remove all trailing "/" slashes
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

function Readeck:cancelPeriodicSync()
    if self.periodic_sync_callback then
        UIManager:unschedule(self.periodic_sync_callback)
        self.periodic_sync_callback = nil
    end
end

function Readeck:runPeriodicSync()
    if self.sync_in_progress then
        Log:info("Periodic sync skipped: sync already running")
        return
    end
    if not NetworkMgr:isOnline() then
        Log:info("Periodic sync skipped: offline")
        return
    end
    NetworkMgr:runWhenOnline(function()
        self:synchronize()
        self:refreshCurrentDirIfNeeded()
    end)
end

function Readeck:reschedulePeriodicSync()
    self:cancelPeriodicSync()
    if not self.periodic_sync_enabled then
        return
    end
    local delay = math.max(5, tonumber(self.periodic_sync_interval_minutes) or 60) * 60
    self.periodic_sync_callback = function()
        self.periodic_sync_callback = nil
        self:runPeriodicSync()
        self:reschedulePeriodicSync()
    end
    UIManager:scheduleIn(delay, self.periodic_sync_callback)
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

function Readeck:saveSettings()
    local tempsettings = {
        server_url = self.server_url,
        auth_token = self.auth_token,
        oauth_client_id = self.oauth_client_id,
        oauth_refresh_token = self.oauth_refresh_token,
        directory = self.directory,
        filter_tag = self.filter_tag,
        sort_param = self.sort_param,
        ignore_tags = self.ignore_tags,
        auto_tags = self.auto_tags,
        completion_action_finished_enabled = self.completion_action_finished_enabled,
        completion_action_read_enabled = self.completion_action_read_enabled,
        archive_instead_of_delete = self.archive_instead_of_delete,
        process_completion_on_sync = self.process_completion_on_sync,
        completion_action_sync_policy_version = self.completion_action_sync_policy_version,
        remove_local_missing_remote = self.remove_local_missing_remote,
        is_delete_finished = self.completion_action_finished_enabled,
        is_delete_read = self.completion_action_read_enabled,
        is_archiving_deleted = self.archive_instead_of_delete,
        is_auto_delete = self.process_completion_on_sync,
        is_sync_remote_delete = self.remove_local_missing_remote,
        articles_per_sync = self.articles_per_sync,
        download_concurrency = self.download_concurrency,
        experimental_async_downloads = self.experimental_async_downloads,
        auto_export_highlights = self.auto_export_highlights,
        export_highlights_before_sync = self.export_highlights_before_sync,
        periodic_sync_enabled = self.periodic_sync_enabled,
        periodic_sync_interval_minutes = self.periodic_sync_interval_minutes,
        send_review_as_tags = self.send_review_as_tags,
        remove_finished_from_history = self.remove_finished_from_history,
        remove_read_from_history = self.remove_read_from_history,
        download_queue = self.download_queue,
        block_timeout = self.block_timeout,
        total_timeout = self.total_timeout,
        file_block_timeout = self.file_block_timeout,
        file_total_timeout = self.file_total_timeout,
        access_token = self.access_token,
        token_expiry = self.token_expiry,
        cached_auth_token = self.cached_auth_token,
        cached_server_url = self.cached_server_url,
        cached_auth_method = self.cached_auth_method,
        server_info = self.server_info,
        sync_star_status = self.sync_star_status,
        remote_star_threshold = self.remote_star_threshold,
        sync_star_rating_as_label = self.sync_star_rating_as_label,
    }
    self.rd_settings:saveSetting("readeck", tempsettings)
    self.rd_settings:flush()
end

function Readeck:readSettings()
    local rd_settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/readeck.lua")
    rd_settings:readSetting("readeck", {})
    return rd_settings
end

function Readeck:saveRDSettings(setting)
    if not self.rd_settings then
        self.rd_settings = self:readSettings()
    end
    self.rd_settings:saveSetting("readeck", setting)
    self.rd_settings:flush()
end

function Readeck:onAddReadeckArticle(article_url)
    if not NetworkMgr:isOnline() then
        self:addToDownloadQueue(article_url)
        UIManager:show(InfoMessage:new({
            text = T(L("Article added to download queue:\n%1"), BD.url(article_url)),
            timeout = 1,
        }))
        return
    end

    local readeck_result, add_err = self:addArticle(article_url)
    if readeck_result then
        UIManager:show(InfoMessage:new({
            text = T(L("Article added to Readeck:\n%1"), BD.url(article_url)),
        }))
    elseif add_err == "auth_pending" then
        UIManager:show(InfoMessage:new({
            text = L("OAuth authorization started. Finish login and the article will be retried."),
        }))
    else
        UIManager:show(InfoMessage:new({
            text = T(L("Error adding link to Readeck:\n%1"), BD.url(article_url)),
        }))
    end

    -- stop propagation
    return true
end

function Readeck:onSynchronizeReadeck()
    local connect_callback = function()
        self:synchronize()
        self:refreshCurrentDirIfNeeded()
    end
    NetworkMgr:runWhenOnline(connect_callback)

    -- stop propagation
    return true
end

function Readeck:getLastPercent()
    local percent = self.ui.paging and self.ui.paging:getLastPercent() or self.ui.rolling:getLastPercent()
    return Math.roundPercent(percent)
end

function Readeck:addToDownloadQueue(article_url)
    table.insert(self.download_queue, article_url)
    self:saveSettings()
end

function Readeck:onCloseDocument()
    local document_full_path = self.ui and self.ui.document and self.ui.document.file
    if self.auto_export_highlights and self:isReadeckDocumentPath(document_full_path) and NetworkMgr:isOnline() then
        local annotations = self:getCurrentAnnotations()
        NetworkMgr:runWhenOnline(function()
            self:exportHighlightsForPath(document_full_path, { quiet = true, annotations = annotations })
        end)
    end

    if document_full_path and (self.remove_finished_from_history or self.remove_read_from_history) then
        local summary = self.ui.doc_settings:readSetting("summary")
        local status = summary and summary.status
        local is_finished = status == "complete" or status == "abandoned"
        local is_read = self:getLastPercent() == 1

        if
            document_full_path
            and self.directory
            and ((self.remove_finished_from_history and is_finished) or (self.remove_read_from_history and is_read))
            and self:isReadeckDocumentPath(document_full_path)
        then
            ReadHistory:removeItemByPath(document_full_path)
            self.ui:setLastDirForFileBrowser(self.directory)
        end
    end
end

function Readeck:getCurrentAnnotations()
    if self.ui and self.ui.annotation and self.ui.annotation.annotations then
        return self.ui.annotation.annotations
    end
    if self.ui and self.ui.view and self.ui.view.ui and self.ui.view.ui.annotation then
        return self.ui.view.ui.annotation.annotations
    end
end

function Readeck:getAnnotationsForPath(path, options)
    options = options or {}
    if options.annotations then
        return options.annotations
    end
    if self.ui and self.ui.document and self.ui.document.file == path then
        return self:getCurrentAnnotations()
    end
    if DocSettings:hasSidecarFile(path) then
        return DocSettings:open(path):readSetting("annotations")
    end
end

function Readeck:formatHighlightExportMessage(counts)
    counts = counts or {}
    local message_parts = {}
    if (counts.success or 0) > 0 then
        table.insert(message_parts, T(L("Success: %1"), counts.success))
    end
    if (counts.error or 0) > 0 then
        table.insert(message_parts, T(L("Failed: %1"), counts.error))
    end
    if (counts.skipped or 0) > 0 then
        table.insert(message_parts, T(L("Skipped (overlap): %1"), counts.skipped))
    end

    if #message_parts > 0 then
        return T(L("Finished exporting highlights.\n%1"), table.concat(message_parts, "\n"))
    end
    return L("Finished exporting highlights. No new highlights to export.")
end

function Readeck:exportHighlightsForArticle(article_id, annotations, options)
    options = options or {}
    if not annotations or not next(annotations) then
        if not options.quiet then
            UIManager:show(InfoMessage:new({ text = L("No highlights found in this document.") }))
        end
        return true, { success = 0, error = 0, skipped = 0 }
    end

    if
        self:getBearerToken({
            on_oauth_success = function()
                NetworkMgr:runWhenOnline(function()
                    self:exportHighlightsForArticle(article_id, annotations, options)
                end)
            end,
        }) == false
    then
        return false, { success = 0, error = 1, skipped = 0 }
    end

    local existing_highlights_raw, err = self:callAPI("GET", Api.paths.annotations(article_id), nil, "", "", true)
    local existing_highlights = {}
    if err then
        if err == "auth_pending" then
            return false, { success = 0, error = 1, skipped = 0 }
        end
        if not options.quiet then
            UIManager:show(
                InfoMessage:new({ text = L("Could not fetch existing highlights from Readeck. Aborting export.") })
            )
        end
        return false, { success = 0, error = 1, skipped = 0 }
    end
    if existing_highlights_raw and type(existing_highlights_raw) == "table" then
        existing_highlights = existing_highlights_raw
    end

    local counts = { success = 0, error = 0, skipped = 0 }
    for _, h in pairs(annotations) do
        local local_highlight = Highlights.build_payload(h)

        if local_highlight then
            local is_overlapping = false
            for _, remote_h in ipairs(existing_highlights) do
                if Highlights.overlap(local_highlight, remote_h) then
                    is_overlapping = true
                    break
                end
            end

            if is_overlapping then
                counts.skipped = counts.skipped + 1
                Log:info("Skipping overlapping highlight:", local_highlight.text)
            else
                local bodyJSON = JSON.encode(local_highlight)
                Log:debug(
                    "Start selector:",
                    local_highlight.start_selector,
                    "End selector:",
                    local_highlight.end_selector
                )
                local headers = {
                    ["Content-type"] = "application/json",
                    ["Accept"] = "application/json, */*",
                    ["Content-Length"] = tostring(#bodyJSON),
                    ["Authorization"] = "Bearer " .. self.access_token,
                }

                local result = self:callAPI("POST", Api.paths.annotations(article_id), headers, bodyJSON, "")
                if result then
                    counts.success = counts.success + 1
                    table.insert(existing_highlights, local_highlight)
                else
                    counts.error = counts.error + 1
                end
            end
        end
    end

    if not options.quiet then
        UIManager:show(InfoMessage:new({ text = self:formatHighlightExportMessage(counts) }))
    end
    return counts.error == 0, counts
end

function Readeck:exportHighlightsForPath(path, options)
    options = options or {}
    local article_id = self:getArticleID(path)
    if not article_id then
        if not options.quiet then
            UIManager:show(InfoMessage:new({ text = L("Could not find Readeck article ID for this document.") }))
        end
        return false
    end
    return self:exportHighlightsForArticle(article_id, self:getAnnotationsForPath(path, options), options)
end

function Readeck:exportHighlightsForLocalFiles(options)
    options = options or {}
    if self:isempty(self.directory) or lfs.attributes(self.directory, "mode") ~= "directory" then
        return true
    end

    local ok = true
    for entry in lfs.dir(self.directory) do
        if entry ~= "." and entry ~= ".." then
            local path = FFIUtil.joinPath(self.directory, entry)
            if
                self:getArticleID(path)
                and (DocSettings:hasSidecarFile(path) or (self.ui.document and self.ui.document.file == path))
            then
                local export_ok = self:exportHighlightsForPath(path, options)
                if export_ok == false then
                    ok = false
                end
            end
        end
    end
    return ok
end

function Readeck:exportCurrentDocumentHighlights(options)
    local document = self.ui.document
    if not document then
        if not (options and options.quiet) then
            UIManager:show(InfoMessage:new({ text = L("No document opened.") }))
        end
        return true
    end
    return self:exportHighlightsForPath(document.file, options)
end

function Readeck:exportHighlights()
    return self:exportCurrentDocumentHighlights({ quiet = false })
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

return Readeck
