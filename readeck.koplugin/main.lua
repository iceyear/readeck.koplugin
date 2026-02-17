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
local DocumentRegistry = require("document/documentregistry")
local Event = require("ui/event")
local FFIUtil = require("ffi/util")
local FileManager = require("apps/filemanager/filemanager")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local ButtonDialog= require("ui/widget/buttondialog")
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

-- 实现分层日志记录功能
local Log = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4,
    level = 4, -- 默认为 ERROR 级别
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

-- 设置日志级别
Log.level = Log.DEBUG -- 可以通过设置 Log.level 的值来调整日志级别

-- constants
local article_id_suffix = " [rd-id_"
local article_id_postfix = "]"
local failed, skipped, downloaded = 1, 2, 3
local OAUTH_DEVICE_GRANT = "urn:ietf:params:oauth:grant-type:device_code"
local DEFAULT_OAUTH_SCOPES = "bookmarks:read bookmarks:write"

local Readeck = WidgetContainer:extend{
    name = "readeck",
}

function Readeck:onDispatcherRegisterActions()
    Dispatcher:registerAction("readeck_download", { category="none", event="SynchronizeReadeck", title=_("Readeck retrieval"), general=true,})
end

function Readeck:init()
    Log:info("Initializing Readeck plugin")
    self.token_expiry = 0
    -- Initialize cached authentication info
    self.cached_auth_token = ""
    self.cached_username = ""
    self.cached_password = ""
    self.cached_server_url = ""
    self.cached_auth_method = ""
    self.oauth_client_id = ""
    self.oauth_refresh_token = ""
    self.oauth_rng_seeded = false
    self.oauth_poll_state = nil
    self.oauth_prompt_dialog = nil
    self.sync_in_progress = false
    -- default values so that user doesn't have to explicitly set them
    self.is_delete_finished = true
    self.is_delete_read = false
    self.is_auto_delete = false
    self.is_sync_remote_delete = false
    self.is_archiving_deleted = true
    self.send_review_as_tags = false
    self.filter_tag = ""
    self.sort_param = "-created"  -- default to most recent first
    self.ignore_tags = ""
    self.auto_tags = ""
    self.articles_per_sync = 30  -- max number of articles to get metadata for
    self.sort_options = {
        {"created",    _("Added, oldest first")},
        {"-created",   _("Added, most recent first")},
        {"published",  _("Published, oldest first")},
        {"-published", _("Published, most recent first")},
        {"duration",   _("Duration, shortest first")},
        {"-duration",  _("Duration, longest first")},
        {"site",       _("Site name, A to Z")},
        {"-site",      _("Site name, Z to A")},
        {"title",      _("Title, A to Z")},
        {"-title",     _("Title, Z to A")},
    }
    
    -- 默认超时设置（秒）
    self.block_timeout = 30
    self.total_timeout = 120
    self.file_block_timeout = 10
    self.file_total_timeout = 30
    
    -- 用于存储会话cookie
    self.cookies = {}

    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    self.rd_settings = self:readSettings()
    self.server_url = self.rd_settings.data.readeck.server_url
    self.auth_token = self.rd_settings.data.readeck.auth_token or ""
    self.username = self.rd_settings.data.readeck.username
    self.password = self.rd_settings.data.readeck.password
    self.directory = self.rd_settings.data.readeck.directory
    
    -- 加载缓存的访问令牌和过期时间
    self.access_token = self.rd_settings.data.readeck.access_token or ""
    self.token_expiry = self.rd_settings.data.readeck.token_expiry or 0
    -- 加载用于生成当前 access_token 的认证信息
    self.cached_auth_token = self.rd_settings.data.readeck.cached_auth_token or ""
    self.cached_username = self.rd_settings.data.readeck.cached_username or ""
    self.cached_password = self.rd_settings.data.readeck.cached_password or ""
    self.cached_server_url = self.rd_settings.data.readeck.cached_server_url or ""
    self.cached_auth_method = self.rd_settings.data.readeck.cached_auth_method or ""
    self.oauth_client_id = self.rd_settings.data.readeck.oauth_client_id or ""
    self.oauth_refresh_token = self.rd_settings.data.readeck.oauth_refresh_token or ""
    
    if self.rd_settings.data.readeck.is_delete_finished ~= nil then
        self.is_delete_finished = self.rd_settings.data.readeck.is_delete_finished
    end
    if self.rd_settings.data.readeck.send_review_as_tags ~= nil then
        self.send_review_as_tags = self.rd_settings.data.readeck.send_review_as_tags
    end
    if self.rd_settings.data.readeck.is_delete_read ~= nil then
        self.is_delete_read = self.rd_settings.data.readeck.is_delete_read
    end
    if self.rd_settings.data.readeck.is_auto_delete ~= nil then
        self.is_auto_delete = self.rd_settings.data.readeck.is_auto_delete
    end
    if self.rd_settings.data.readeck.is_sync_remote_delete ~= nil then
        self.is_sync_remote_delete = self.rd_settings.data.readeck.is_sync_remote_delete
    end
    if self.rd_settings.data.readeck.is_archiving_deleted ~= nil then
        self.is_archiving_deleted = self.rd_settings.data.readeck.is_archiving_deleted
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
    -- 加载超时设置
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
    self.remote_star_threshold= self.rd_settings.data.readeck.remote_star_threshold or 5
    self.sync_star_rating_as_label = self.rd_settings.data.readeck.sync_star_rating_as_label or false

    -- workaround for dateparser only available if newsdownloader is active
    self.is_dateparser_available = false
    self.is_dateparser_checked = false

    -- workaround for dateparser, only once
    -- the parser is in newsdownloader.koplugin, check if it is available
    if not self.is_dateparser_checked then
        local res
        res, self.dateparser = pcall(require, "lib.dateparser")
        if res then self.is_dateparser_available = true end
        self.is_dateparser_checked = true
    end

    if self.ui and self.ui.link then
        self.ui.link:addToExternalLinkDialog("25_readeck", function(this, link_url)
            return {
                text = _("Add to Readeck"),
                callback = function()
                    UIManager:close(this.external_link_dialog)
                    this.ui:handleEvent(Event:new("AddReadeckArticle", link_url))
                end,
            }
        end)
    end
    Log:info("Readeck plugin initialization complete")
end

function Readeck:addToMainMenu(menu_items)
    menu_items.readeck = {
        text = _("Readeck"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Synchronize articles with server"),
                callback = function()
                    self.ui:handleEvent(Event:new("SynchronizeReadeck"))
                end,
            },
            {
                text = _("Export highlights to server"),
                callback = function()
                    NetworkMgr:runWhenOnline(function() self:exportHighlights() end)
                end,
                enabled_func = function()
                    return self.ui.document ~= nil
                end,
            },
            {
                text = _("Delete finished articles remotely"),
                callback = function()
                    local connect_callback = function()
                        local num_deleted = self:processLocalFiles("manual")
                        UIManager:show(InfoMessage:new{
                            text = T(_("Articles processed.\nDeleted: %1"), num_deleted)
                        })
                        self:refreshCurrentDirIfNeeded()
                    end
                    NetworkMgr:runWhenOnline(connect_callback)
                end,
                enabled_func = function()
                    return self.is_delete_finished or self.is_delete_read
                end,
            },
            {
                text = _("Go to download folder"),
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
                text = _("Settings"),
                callback_func = function()
                    return nil
                end,
                separator = true,
                sub_item_table = {
                    {
                        text = _("Configure Readeck server"),
                        keep_menu_open = true,
                        callback = function()
                            self:editServerSettings()
                        end,
                    },
                    {
                        text = _("Configure Readeck client"),
                        keep_menu_open = true,
                        callback = function()
                            self:editClientSettings()
                        end,
                    },
                    {
                        text_func = function()
                            local path
                            if not self.directory or self.directory == "" then
                                path = _("Not set")
                            else
                                path = filemanagerutil.abbreviate(self.directory)
                            end
                            return T(_("Download folder: %1"), BD.dirpath(path))
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
                                filter = _("All articles")
                            else
                                filter = self.filter_tag
                            end
                            return T(_("Only download articles with tag: %1"), filter)
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
                            return T(_("Sort articles by: %1"), sort_desc)
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            self:setSortParam(touchmenu_instance)
                        end,
                    },
                    {
                        text_func = function()
                            if not self.ignore_tags or self.ignore_tags == "" then
                                return _("Tags to ignore")
                            end
                            return T(_("Tags to ignore (%1)"), self.ignore_tags)
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            self:setTagsDialog(touchmenu_instance,
                                _("Tags to ignore"),
                                _("Enter a comma-separated list of tags to ignore"),
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
                                return _("Tags to add to new articles")
                            end
                            return T(_("Tags to add to new articles (%1)"), self.auto_tags)
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            self:setTagsDialog(touchmenu_instance,
                                _("Tags to add to new articles"),
                                _("Enter a comma-separated list of tags to automatically add to new articles"),
                                self.auto_tags,
                                function(tags)
                                    self.auto_tags = tags
                                end
                            )
                        end,
                        separator = true,
                    },
                    {
                        text = _("Article deletion"),
                        separator = true,
                        sub_item_table = {
                            {
                                text = _("Remotely delete finished articles"),
                                checked_func = function() return self.is_delete_finished end,
                                callback = function()
                                    self.is_delete_finished = not self.is_delete_finished
                                    self:saveSettings()
                                end,
                            },
                            {
                                text = _("Remotely delete 100% read articles"),
                                checked_func = function() return self.is_delete_read end,
                                callback = function()
                                    self.is_delete_read = not self.is_delete_read
                                    self:saveSettings()
                                end,
                                separator = true,
                            },
                            {
                                text = _("Mark as archived instead of deleting"),
                                checked_func = function() return self.is_archiving_deleted end,
                                callback = function()
                                    self.is_archiving_deleted = not self.is_archiving_deleted
                                    self:saveSettings()
                                end,
                                separator = true,
                            },
                            {
                                text = _("Process deletions when downloading"),
                                checked_func = function() return self.is_auto_delete end,
                                callback = function()
                                    self.is_auto_delete = not self.is_auto_delete
                                    self:saveSettings()
                                end,
                            },
                            {
                                text = _("Synchronize remotely deleted files"),
                                checked_func = function() return self.is_sync_remote_delete end,
                                callback = function()
                                    self.is_sync_remote_delete = not self.is_sync_remote_delete
                                    self:saveSettings()
                                end,
                            },
                        },
                    },
                    {
                        text_func = function()
                            local stars = {}
                            stars[0] = ": disabled"
                            for i = 1, 5 do
                                stars[i] = "if ⩾ "..string.rep("★", i)..""
                            end
                            return T(_("“Like” entries in Readeck %1"), stars[self.remote_star_threshold])
                        end,
                        help_text = _("Mark entries as starred/favourited/liked on the server upon sync, if they're rated above your chosen star threshold in the book status page."),
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            self.buttondlg = ButtonDialog:new{
                                title = "Threshold",
                                title_align = "center",
                                -- shrink_unneeded_width = true,
                                width_factor = 0.33,
                                buttons = {
                                       { {
                                            text = _("★★★★★"),
                                            align = "left",
                                            callback = function()
                                                self.sync_star_status = true
                                                self.remote_star_threshold = 5
                                                self:saveSettings()
                                                touchmenu_instance:updateItems()
                                                UIManager:close(self.buttondlg)
                                            end,
                                        }},
                                       { {
                                            text = _("★★★★"),
                                            align = "left",
                                            callback = function()
                                                self.sync_star_status = true
                                                self.remote_star_threshold = 4
                                                self:saveSettings()
                                                touchmenu_instance:updateItems()
                                                UIManager:close(self.buttondlg)
                                            end,
                                        }},
                                       { {
                                            text = _("★★★"),
                                            align = "left",
                                            callback = function()
                                                self.sync_star_status = true
                                                self.remote_star_threshold = 3
                                                self:saveSettings()
                                                touchmenu_instance:updateItems()
                                                UIManager:close(self.buttondlg)
                                            end,
                                        }},
                                       { {
                                            text = _("★★"),
                                            align = "left",
                                            callback = function()
                                                self.sync_star_status = true
                                                self.remote_star_threshold = 2
                                                self:saveSettings()
                                                touchmenu_instance:updateItems()
                                                UIManager:close(self.buttondlg)
                                            end,

                                        }},
                                        {{
                                            text = _("★"),
                                            align = "left",
                                            callback = function()
                                                self.sync_star_status = true
                                                self.remote_star_threshold = 1
                                                self:saveSettings()
                                                touchmenu_instance:updateItems()
                                                UIManager:close(self.buttondlg)
                                            end,

                                        }},
                                        {{
                                            text_func = function()
                                                return T(_("Disable"), self.remote_star_threshold)
                                            end,
                                            align = "left",
                                            callback = function()
                                                self.sync_star_status = false
                                                self.remote_star_threshold = 0
                                                self:saveSettings()
                                                touchmenu_instance:updateItems()
                                                UIManager:close(self.buttondlg)
                                            end,
                                        }}
                                    }
                               } 
                                UIManager:show(self.buttondlg)
                            end,
                    },
                    {
                        text = _("Label entries in Readeck with their star rating"),
                        help_text = _("Sync star ratings to Readeck as labels, regardless of threshold for marking entries as liked."),
                        keep_menu_open = true,
                        checked_func = function() return self.sync_star_rating_as_label end,
                        callback = function()
                            self.sync_star_rating_as_label = not self.sync_star_rating_as_label
                            self:saveSettings()
                        end,
                    },
                    {
                        text = _("Send review as tags"),
                        help_text = _("This allow you to write tags in the review field, separated by commas, which can then be sent to Readeck."),
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
                        text = _("Remove finished articles from history"),
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
                        text = _("Remove 100% read articles from history"),
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
                        text = _("Set timeout"),
                        keep_menu_open = true,
                        callback = function()
                            self:editTimeoutSettings()
                        end,
                    },
                    {
                        text = _("Authentication"),
                        keep_menu_open = true,
                        sub_item_table = {
                            {
                                text = _("Authorize with OAuth"),
                                keep_menu_open = true,
                                callback = function()
                                    NetworkMgr:runWhenOnline(function()
                                        self:authorizeWithOAuthDeviceFlowAsync()
                                    end)
                                end,
                            },
                            {
                                text = _("Reset access token"),
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
                                text = _("Clear all cached tokens"),
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
                                text = _("Alternative credentials"),
                                keep_menu_open = true,
                                callback = function()
                                    self:editAuthSettings()
                                end,
                            },
                        },
                    },
                    {
                        text = _("Help"),
                        keep_menu_open = true,
                        callback = function()
                            UIManager:show(InfoMessage:new{
                                text = _([[Download directory: use a directory that is exclusively used by the Readeck plugin. Existing files in this directory risk being deleted.

Articles marked as finished or 100% read can be deleted from the server. Those articles can also be deleted automatically when downloading new articles if the 'Process deletions during download' option is enabled.

The 'Synchronize remotely deleted files' option will remove local files that no longer exist on the server.]])
                            })
                        end,
                    }
                }
            },
            {
                text = _("Info"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = T(_([[Readeck is an open source read-it-later service. This plugin synchronizes with a Readeck server.

More details: https://www.readeck.net

Downloads to folder: %1]]), BD.dirpath(filemanagerutil.abbreviate(self.directory)))
                    })
                end,
            },
        },
    }
end

function Readeck:isempty(s)
    return s == nil or s == ""
end

function Readeck:resetAccessToken()
    Log:info("Manually resetting access token")
    
    -- Clear current access token but keep cached credentials for comparison
    self.access_token = ""
    self.token_expiry = 0
    
    -- Try to get a new token immediately; OAuth may continue asynchronously.
    if self:getBearerToken({
        on_oauth_success = function()
            UIManager:show(InfoMessage:new{
                text = _("Access token reset successfully"),
            })
        end,
    }) then
        UIManager:show(InfoMessage:new{
            text = _("Access token reset successfully"),
        })
    elseif self:isOAuthPollingActive() then
        UIManager:show(InfoMessage:new{
            text = _("OAuth authorization started. Finish login to refresh access token."),
        })
    else
        UIManager:show(InfoMessage:new{
            text = _("Failed to obtain new access token"),
        })
    end
end

function Readeck:clearAllTokens()
    Log:info("Clearing all cached tokens and credentials")
    self:cancelOAuthPolling()
    
    -- Clear all cached authentication data
    self.access_token = ""
    self.token_expiry = 0
    self.cached_auth_token = ""
    self.cached_username = ""
    self.cached_password = ""
    self.cached_server_url = ""
    self.cached_auth_method = ""
    self.oauth_client_id = ""
    self.oauth_refresh_token = ""
    
    -- Save the cleared state
    self:saveSettings()
    
    UIManager:show(InfoMessage:new{
        text = _("All cached tokens and credentials cleared"),
    })
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
    return (template:gsub("[xy]", function(c)
        local v
        if c == "x" then
            v = math.random(0, 15)
        else
            v = math.random(8, 11)
        end
        return string.format("%x", v)
    end))
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
        self.cached_username = ""
        self.cached_password = ""
    elseif method == "legacy" then
        self.cached_auth_token = ""
        self.cached_username = self.username or ""
        self.cached_password = self.password or ""
    else
        self.cached_auth_token = ""
        self.cached_username = ""
        self.cached_password = ""
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

function Readeck:authenticateWithLegacy(show_failure_message)
    if self:isempty(self.username) or self:isempty(self.password) then
        return false
    end

    Log:info("Attempting legacy username/password login")
    local bodyJSON = JSON.encode({
        username = self.username,
        password = self.password,
        application = "KOReader",
    })
    local headers = {
        ["Content-type"] = "application/json",
        ["Accept"] = "application/json, */*",
        ["Content-Length"] = tostring(#bodyJSON),
    }

    local result = self:callAPI("POST", "/api/auth", headers, bodyJSON, "", true)
    if result and result.token then
        Log:info("Legacy authentication successful")
        self:storeAccessToken("legacy", result.token, 365 * 24 * 60 * 60)
        return true
    end

    Log:warn("Legacy authentication failed")
    if show_failure_message then
        UIManager:show(InfoMessage:new{
            text = _("Could not login with username/password."),
        })
    end
    return false
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
        UIManager:show(MultiConfirmBox:new{
            text = _("Please configure the Readeck server URL first."),
            choice1_text = _("Server settings"),
            choice1_callback = function() self:editServerSettings() end,
            choice2_text = _("Cancel"),
            choice2_callback = function() end,
        })
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
        UIManager:show(InfoMessage:new{
            text = _("OAuth setup failed: could not register client."),
        })
        return nil
    end

    local client_id = client_info.client_id
    local device_info, device_err, device_code = self:callOAuthFormAPI("/api/oauth/device", {
        client_id = client_id,
        scope = DEFAULT_OAUTH_SCOPES,
    })
    if not device_info or not device_info.device_code then
        Log:error("OAuth device code request failed", device_err or "", device_code or "")
        UIManager:show(InfoMessage:new{
            text = _("OAuth setup failed: could not request device code."),
        })
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
    self.oauth_prompt_dialog = ConfirmBox:new{
        text = text,
        cancel_text = _("Cancel"),
        cancel_callback = function()
            self:cancelOAuthPolling(_("OAuth authorization canceled."))
        end,
        no_ok_button = true,
        keep_dialog_open = true,
        other_buttons = {{
            {
                text = _("Show QR"),
                callback = function()
                    self:showOAuthPollingQR()
                end,
            },
        }},
        other_buttons_first = true,
    }
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
        return "fail", _("OAuth authorization was denied.")
    end
    if oauth_error == "expired_token" then
        return "fail", _("OAuth authorization request expired.")
    end
    if poll_code and poll_code >= 500 then
        Log:warn("OAuth token polling server error", poll_code)
        return "retry", wait_interval + 5
    end

    Log:error("OAuth token polling failed", poll_err or "", oauth_error or "", poll_code or "")
    return "fail", _("OAuth token request failed.")
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
        UIManager:show(InfoMessage:new{
            text = message,
        })
    end
end

function Readeck:showOAuthPollingQR()
    local state = self.oauth_poll_state
    if not state or state.done then
        UIManager:show(InfoMessage:new{
            text = _("No OAuth authorization is in progress."),
        })
        return false
    end
    if not state.verification_uri_complete or state.verification_uri_complete == "" then
        UIManager:show(InfoMessage:new{
            text = _("No QR URL is available for this authorization flow."),
        })
        return false
    end
    if state.qr_dialog then
        return true
    end

    state.qr_dialog = QRMessage:new{
        text = state.verification_uri_complete,
        width = Device.screen:getWidth(),
        height = Device.screen:getHeight(),
        dismiss_callback = function()
            if state and not state.done then
                state.qr_dialog = nil
            end
        end,
    }
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
            UIManager:show(InfoMessage:new{
                text = message,
            })
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
                finish(false, _("OAuth login timed out."))
                return
            end

            local token_result, poll_err, poll_code = self:callOAuthFormAPI("/api/oauth/token", {
                grant_type = OAUTH_DEVICE_GRANT,
                client_id = ctx.client_id,
                device_code = ctx.device_code,
            })
            local outcome, value = self:evaluateOAuthDeviceTokenPoll(
                ctx,
                token_result,
                poll_err,
                poll_code,
                state.interval
            )
            if outcome == "success" then
                finish(true, _("OAuth authorization successful."))
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
        local text = _("OAuth authorization is already in progress.")
        if current_state.fallback_uri and current_state.user_code then
            text = text .. T(_("\n\nOpen this URL in your browser:\n%1\nCode: %2"),
                current_state.fallback_uri,
                current_state.user_code)
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
        T(_("OAuth login started.\nOpen this URL in your browser:\n%1\nCode: %2"),
            ctx.fallback_uri,
            ctx.user_code)
    )
    return true
end

function Readeck:getCurrentAuthMethod()
    if not self:isempty(self.auth_token) then
        return "api_token"
    end

    local has_legacy_creds = not self:isempty(self.username) and not self:isempty(self.password)
    local has_oauth_context = (self.cached_auth_method == "oauth")
        or (not self:isempty(self.oauth_refresh_token))

    if has_oauth_context then
        return "oauth"
    end
    if has_legacy_creds then
        return "legacy"
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
    if auth_method == "legacy" then
        return (self.username or "") ~= (self.cached_username or "")
            or (self.password or "") ~= (self.cached_password or "")
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
        Log:warn("Configuration incomplete - Server:", server_empty and "missing" or "ok",
                 ", Directory:", directory_empty and "missing" or "ok")
        UIManager:show(MultiConfirmBox:new{
            text = _("Please configure the server settings and set a download folder."),
            choice1_text_func = function()
                if server_empty then
                    return _("Server (★)")
                else
                    return _("Server")
                end
            end,
            choice1_callback = function() self:editServerSettings() end,
            choice2_text_func = function()
                if directory_empty then
                    return _("Folder (★)")
                else
                    return _("Folder")
                end
            end,
            choice2_callback = function() self:setDownloadDirectory() end,
        })
        return false
    end

    local dir_mode = lfs.attributes(self.directory, "mode")
    if dir_mode ~= "directory" then
        Log:warn("Invalid download directory:", self.directory)
        UIManager:show(InfoMessage:new{
            text = _("The download directory is not valid.\nPlease configure it in the settings.")
        })
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
        if self:authenticateWithLegacy(false) then
            return true
        end
        return false
    end

    if self:authenticateWithLegacy(true) then
        return true
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
    local filtering = ""
    if self.filter_tag ~= "" then
        filtering = "&labels=" .. self.filter_tag
    end

    local sorting = ""
    if self.sort_param ~= "" then
        sorting = "&sort=" .. self.sort_param
    end

    local article_list = {}
    local offset = 0
    local limit = math.min(self.articles_per_sync, 30)  -- 服务器默认每页数量是30

    -- 从服务器获取文章列表，直到达到目标数量
    while #article_list < self.articles_per_sync do
        -- 获取包含文章列表的JSON
        local articles_url = "/api/bookmarks?limit=" .. limit  -- 修改文章列表路径，添加 /api 前缀
                          .. "&offset=" .. offset
                          .. "&is_archived=0"  -- 只获取未归档的文章
                          .. "&type=article" -- No sense downloading videos, but maybe photos
                          .. filtering
                          .. sorting

        Log:debug("Fetching article list with URL:", articles_url)
        local articles_json, err, code = self:callAPI("GET", articles_url, nil, "", "", true)

        if err == "http_error" and code == 404 then
            -- 可能已经到了最后一页，没有更多文章了
            Log:debug("Couldn't get offset", offset)
            break -- 退出循环
        elseif err == "auth_pending" then
            Log:info("OAuth authorization started while requesting article list")
            return nil, err
        elseif err or articles_json == nil then
            -- 发生了其他错误，不继续下载或删除文章
            Log:warn("Download at offset", offset, "failed with", err, code)
            UIManager:show(InfoMessage:new{
                text = _("Requesting article list failed."), })
            return
        end

        -- 只关注JSON中的实际文章
        -- 构建一个数组，以便稍后更容易地操作
        local new_article_list = {}
        for _, article in ipairs(articles_json) do
            table.insert(new_article_list, article)
        end

        local pending_articles = #new_article_list >= limit

        -- 应用过滤器
        new_article_list = self:filterIgnoredTags(new_article_list)

        -- 将过滤后的列表追加到最终的文章列表中
        for _, article in ipairs(new_article_list) do
            if #article_list == self.articles_per_sync then
                Log:debug("Hit the article target", self.articles_per_sync)
                break
            end
            table.insert(article_list, article)
        end

        if not pending_articles then
            -- 服务器返回的文章数量小于请求的数量，说明没有更多文章了
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
                Log:debug("Ignoring tag", tag, "in article",
                           article.id, ":", article.title)
                break -- no need to look for other tags
            end
        end
        if not skip_article then
            table.insert(filtered_list, article)
        end
    end

    return filtered_list
end

--- Download Readeck article.
-- @string article
-- @treturn int 1 failed, 2 skipped, 3 downloaded
function Readeck:download(article)
    local skip_article = false
    local title = util.getSafeFilename(article.title, self.directory, 230, 0)
    local file_ext = ".epub"
    local item_url = "/api/bookmarks/" .. article.id .. "/article.epub"  -- 修改下载路径，添加 /api 前缀

    local local_path = self.directory .. title .. article_id_suffix .. article.id .. article_id_postfix .. file_ext
    Log:debug("DOWNLOAD: id:", article.id)
    Log:debug("DOWNLOAD: title:", article.title)
    Log:debug("DOWNLOAD: filename:", local_path)

    local attr = lfs.attributes(local_path)
    if attr then
        -- 文件已存在，跳过。最好只在本地文件日期比服务器的新时才跳过。
        -- newsdownloader.koplugin 有一个日期解析器，但只有在插件被激活时才可用。
        if self.is_dateparser_available and article.created then
            local server_date = self.dateparser.parse(article.created)
            if server_date < attr.modification then
                skip_article = true
                Log:debug("Skipping file (date checked):", local_path)
            end
        else
            skip_article = true
            Log:debug("Skipping file:", local_path)
        end
    end

    if skip_article == false then
        if self:callAPI("GET", item_url, nil, "", local_path) then
            return downloaded
        else
            return failed
        end
    end
    return skipped
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
        request.sink = ltn12.sink.file(io.open(filepath, "w"))
        socketutil:set_timeout(self.file_block_timeout, self.file_total_timeout)
    else
        request.sink = ltn12.sink.table(sink)
        socketutil:set_timeout(self.block_timeout, self.total_timeout)
    end
    request.headers = headers
    if body ~= "" then
        request.source = ltn12.source.string(body)
    end
    Log:debug("API request - URL:", request.url, "Method:", method)
    
    -- 打印请求头（隐藏认证信息）
    for k, v in pairs(headers or {}) do
        if k == "Authorization" then
            Log:debug("Header:", k, "= Bearer ***")
        else
            Log:debug("Header:", k, "=", v)
        end
    end

    local code, resp_headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()
    
    -- 处理响应头
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
    local is_auth_endpoint = (apiurl == "/api/auth") or (apiurl:sub(1, 11) == "/api/oauth/")
    if (code == 401 or code == 403) and not retry_auth and apiurl:sub(1, 1) == "/" and not is_auth_endpoint then
        Log:info("Authentication failed (", code, "), attempting to refresh token")
        
        -- Clear current token and try to get a fresh one
        self.access_token = ""
        self.token_expiry = 0
        
        local oauth_success_callback = nil
        if self.sync_in_progress then
            oauth_success_callback = function() self:scheduleSyncAfterOAuth() end
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
                UIManager:show(InfoMessage:new{
                    text = _("Authentication failed. Please check your credentials."),
                })
            end
            return nil, "auth_error", code
        end
    end
    
    -- 处理正常响应
    if code == 200 or code == 201 or code == 202 or code == 204 then  -- 添加 204 No Content 作为成功状态码
        if filepath ~= "" then
            Log:info("File downloaded successfully to", filepath)
            return true
        else
            local content = table.concat(sink)
            Log:debug("Response content length:", #content, "bytes")
            
            if #content > 0 and #content < 500 then
                Log:debug("Response content:", content)
            end
            
            -- 对于 204 No Content 响应，不需要解析 JSON，直接返回成功
            if code == 204 then
                Log:debug("Successfully received 204 No Content response")
                return true
            elseif content ~= "" and (string.sub(content, 1,1) == "{" or string.sub(content, 1,1) == "[") then
                local ok, result = pcall(JSON.decode, content)
                if ok and result then
                    Log:debug("Successfully parsed JSON response")
                    return result
                else
                    Log:error("Failed to parse JSON:", result or "unknown error")
                    if not quiet then
                        UIManager:show(InfoMessage:new{
                            text = _("Server response is not valid."), 
                        })
                    end
                end
            elseif content == "" then
                -- 空响应但状态码是成功的情况
                Log:debug("Empty response with successful status code")
                return true
            else
                Log:error("Response is not valid JSON")
                if not quiet then
                    UIManager:show(InfoMessage:new{
                        text = _("Server response is not valid."), 
                    })
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
            UIManager:show(InfoMessage:new{
                text = _("Communication with server failed."), 
            })
        end
        Log:error("Request failed:", status or code, "URL:", request.url)
        return nil, "http_error", code
    end
end

function Readeck:synchronize()
    self.sync_in_progress = true
    local info = InfoMessage:new{ text = _("Connecting…") }
    UIManager:show(info)
    UIManager:forceRePaint()
    UIManager:close(info)

    if self:getBearerToken({
        on_oauth_success = function() self:scheduleSyncAfterOAuth() end,
    }) == false then
        self.sync_in_progress = false
        return false
    end
    if self.download_queue and next(self.download_queue) ~= nil then
        info = InfoMessage:new{ text = _("Adding articles from queue…") }
        UIManager:show(info)
        UIManager:forceRePaint()
        for _, articleUrl in ipairs(self.download_queue) do
            self:addArticle(articleUrl)
        end
        self.download_queue = {}
        self:saveSettings()
        UIManager:close(info)
    end

    local deleted_count = self:processLocalFiles()

    info = InfoMessage:new{ text = _("Getting article list…") }
    UIManager:show(info)
    UIManager:forceRePaint()
    UIManager:close(info)

    local remote_article_ids = {}
    local downloaded_count = 0
    local failed_count = 0
    if self.access_token ~= "" then
        local articles, list_err = self:getArticleList()
        if list_err == "auth_pending" then
            self.sync_in_progress = false
            return false
        end
        if articles then
            Log:debug("Number of articles:", #articles)

            info = InfoMessage:new{ text = _("Downloading articles…") }
            UIManager:show(info)
            UIManager:forceRePaint()
            UIManager:close(info)
            for _, article in ipairs(articles) do
                Log:debug("Processing article ID:", article.id)
                remote_article_ids[ tostring(article.id) ] = true
                local res = self:download(article)
                if res == downloaded then
                    downloaded_count = downloaded_count + 1
                elseif res == failed then
                    failed_count = failed_count + 1
                end
            end
            -- synchronize remote deletions
            deleted_count = deleted_count + self:processRemoteDeletes(remote_article_ids)

            local msg
            if failed_count ~= 0 then
                msg = _("Processing finished.\n\nArticles downloaded: %1\nDeleted: %2\nFailed: %3")
                info = InfoMessage:new{ text = T(msg, downloaded_count, deleted_count, failed_count) }
            else
                msg = _("Processing finished.\n\nArticles downloaded: %1\nDeleted: %2")
                info = InfoMessage:new{ text = T(msg, downloaded_count, deleted_count) }
            end
            UIManager:show(info)
        end -- articles
    end -- access_token
    self.sync_in_progress = false
end

function Readeck:processRemoteDeletes(remote_article_ids)
    if not self.is_sync_remote_delete then
        Log:debug("Processing of remote file deletions disabled.")
        return 0
    end
    Log:debug("Articles IDs from server:", remote_article_ids)

    local info = InfoMessage:new{ text = _("Synchronizing remote deletions…") }
    UIManager:show(info)
    UIManager:forceRePaint()
    UIManager:close(info)
    local deleted_count = 0
    for entry in lfs.dir(self.directory) do
        if entry ~= "." and entry ~= ".." then
            local entry_path = self.directory .. "/" .. entry
            local id = self:getArticleID(entry_path)
            if not remote_article_ids[ id ] then
                Log:debug("Deleting local file (deleted on server):", entry_path)
                self:deleteLocalArticle(entry_path)
                deleted_count = deleted_count + 1
            end
        end
    end -- for entry
    return deleted_count
end

function Readeck:processLocalFiles(mode)
    if mode then
        if self.is_auto_delete == false and mode ~= "manual" then
            Log:debug("Automatic processing of local files disabled.")
            return 0, 0
        end
    end

    if self:getBearerToken({
        on_oauth_success = function()
            NetworkMgr:runWhenOnline(function()
                self:processLocalFiles(mode)
                self:refreshCurrentDirIfNeeded()
            end)
        end,
    }) == false then
        return 0, 0
    end

    local num_deleted = 0
    if self.is_delete_finished or self.is_delete_read then
        local info = InfoMessage:new{ text = _("Processing local files…") }
        UIManager:show(info)
        UIManager:forceRePaint()
        UIManager:close(info)
        for entry in lfs.dir(self.directory) do
            if entry ~= "." and entry ~= ".." then
                local entry_path = self.directory .. "/" .. entry
                if DocSettings:hasSidecarFile(entry_path) then
                    if self.send_review_as_tags then
                        self:addTags(entry_path)
                    end
                    local doc_settings = DocSettings:open(entry_path)
                    local summary = doc_settings:readSetting("summary")
                    local status = summary and summary.status
                    local percent_finished = doc_settings:readSetting("percent_finished")
                    if status == "complete" or status == "abandoned" then
                        if self.is_delete_finished then
                            -- If we're archiving, optionally also mark as fully read on the server.
                            -- "complete" typically implies finished reading; "abandoned" does not.
                            local mark_read_complete = (status == "complete") or (percent_finished == 1)
                            self:removeArticle(entry_path, mark_read_complete)
                            num_deleted = num_deleted + 1
                        end
                    elseif percent_finished == 1 then -- 100% read
                        if self.is_delete_read then
                            self:removeArticle(entry_path, true)
                            num_deleted = num_deleted + 1
                        end
                    end
                end -- has sidecar
            end -- not . and ..
        end -- for entry
    end -- flag checks
    return num_deleted
end

function Readeck:addArticle(article_url)
    Log:debug("Adding article", article_url)

    if not article_url then
        return false
    end
    if self:getBearerToken({
        on_oauth_success = function()
            NetworkMgr:runWhenOnline(function()
                self:addArticle(article_url)
                self:refreshCurrentDirIfNeeded()
            end)
        end,
    }) == false then
        if self:isOAuthPollingActive() then
            return nil, "auth_pending"
        end
        return false
    end

    local body = {
        url = article_url,
    }

    -- 如果设置了自动标签，添加到新文章中
    if self.auto_tags and self.auto_tags ~= "" then
        local tags = {}
        for tag in util.gsplit(self.auto_tags, "[,]+", false) do
            table.insert(tags, tag:gsub("^%s*(.-)%s*$", "%1")) -- 去除前后空格
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

    return self:callAPI("POST", "/api/bookmarks", headers, body_JSON, "")  -- 修改添加文章路径，添加 /api 前缀
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
                table.insert(tags, tag:gsub("^%s*(.-)%s*$", "%1")) -- 去除前后空格
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

            self:callAPI("PATCH", "/api/bookmarks/" .. id, headers, bodyJSON, "")  -- 修改添加标签路径，添加 /api 前缀
        else
            Log:debug("No tags to send for", path)
        end
    end
end

-- Remove (or archive) an article remotely and delete it locally.
-- If mark_read_complete is true and we're archiving, also set read_progress=100 on the server.
function Readeck:removeArticle(path, mark_read_complete)
    Log:debug("Removing article", path)
    local id = self:getArticleID(path)
    if id then
        if self.is_archiving_deleted then
            local body = {
                is_archived = true
            }
            if mark_read_complete then
                body.read_progress = 100
            end
            if self.sync_star_status then
                local doc_settings = DocSettings:open(path)
                local summary = doc_settings:readSetting("summary")
                if summary and summary.rating then
                    if summary.rating > 0 and self.sync_star_rating_as_label == true then
                        local label = {summary.rating.."-star"}
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

            self:callAPI("PATCH", "/api/bookmarks/" .. id, headers, bodyJSON, "")  -- 修改归档文章路径，添加 /api 前缀
        else
            self:callAPI("DELETE", "/api/bookmarks/" .. id, nil, "", "")  -- 修改删除文章路径，添加 /api 前缀
        end
        self:deleteLocalArticle(path)
    end
end

function Readeck:deleteLocalArticle(path)
    if lfs.attributes(path, "mode") == "file" then
        FileManager:deleteFile(path, true)
   end
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
   self.tag_dialog = InputDialog:new {
        title =  _("Enter a single tag to filter articles on"),
        input = self.filter_tag,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.tag_dialog)
                    end,
                },
                {
                    text = _("OK"),
                    is_enter_default = true,
                    callback = function()
                        self.filter_tag = self.tag_dialog:getInputText()
                        self:saveSettings()
                        touchmenu_instance:updateItems()
                        UIManager:close(self.tag_dialog)
                    end,
                }
            }
        },
    }
    UIManager:show(self.tag_dialog)
    self.tag_dialog:onShowKeyboard()
end

function Readeck:setTagsDialog(touchmenu_instance, title, description, value, callback)
   self.tags_dialog = InputDialog:new {
        title =  title,
        description = description,
        input = value,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.tags_dialog)
                    end,
                },
                {
                    text = _("Set tags"),
                    is_enter_default = true,
                    callback = function()
                        callback(self.tags_dialog:getInputText())
                        self:saveSettings()
                        touchmenu_instance:updateItems()
                        UIManager:close(self.tags_dialog)
                    end,
                }
            }
        },
    }
    UIManager:show(self.tags_dialog)
    self.tags_dialog:onShowKeyboard()
end

function Readeck:editServerSettings()
    local text_info = T(_([[
Configure your Readeck server URL.

Authentication options are available in:
Settings > Authentication

Note: For the Server URL, provide the base URL without the /api path (e.g., http://example.com).

Restart KOReader after editing the config file.]]), BD.dirpath(DataStorage:getSettingsDir()))

    self.settings_dialog = MultiInputDialog:new {
        title = _("Readeck settings"),
        fields = {
            {
                text = self.server_url,
                hint = _("Server URL (without /api)")
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.settings_dialog)
                    end
                },
                {
                    text = _("Info"),
                    callback = function()
                        UIManager:show(InfoMessage:new{ text = text_info })
                    end
                },
                {
                    text = _("Apply"),
                    callback = function()
                        local myfields = self.settings_dialog:getFields()
                        self.server_url = myfields[1]:gsub("/*$", "")  -- remove all trailing "/" slashes
                        self:saveSettings()
                        UIManager:close(self.settings_dialog)
                    end
                },
            },
        },
    }
    UIManager:show(self.settings_dialog)
    self.settings_dialog:onShowKeyboard()
end

function Readeck:editAuthSettings()
    local text_info = T(_([[
Configure credentials for Readeck access.

API token is preferred when provided.
If not set, OAuth is used by default.
Username/password is kept as fallback for older servers.]]), BD.dirpath(DataStorage:getSettingsDir()))

    self.auth_settings_dialog = MultiInputDialog:new {
        title = _("Authentication settings"),
        fields = {
            {
                text = self.auth_token,
                hint = _("API Token (optional)")
            },
            {
                text = self.username,
                hint = _("Username (legacy fallback)")
            },
            {
                text = self.password,
                text_type = "password",
                hint = _("Password (legacy fallback)")
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.auth_settings_dialog)
                    end
                },
                {
                    text = _("Info"),
                    callback = function()
                        UIManager:show(InfoMessage:new{ text = text_info })
                    end
                },
                {
                    text = _("Apply"),
                    callback = function()
                        local myfields = self.auth_settings_dialog:getFields()
                        self.auth_token = myfields[1]
                        self.username   = myfields[2]
                        self.password   = myfields[3]
                        self:saveSettings()
                        UIManager:close(self.auth_settings_dialog)
                    end
                },
            },
        },
    }
    UIManager:show(self.auth_settings_dialog)
    self.auth_settings_dialog:onShowKeyboard()
end

function Readeck:editClientSettings()
    self.client_settings_dialog = MultiInputDialog:new {
        title = _("Readeck client settings"),
        fields = {
            {
                text = self.articles_per_sync,
                description = _("Number of articles"),
                input_type = "number",
                hint = _("Number of articles to download per sync")
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.client_settings_dialog)
                    end
                },
                {
                    text = _("Apply"),
                    callback = function()
                        local myfields = self.client_settings_dialog:getFields()
                        self.articles_per_sync = math.max(1, tonumber(myfields[1]) or self.articles_per_sync)
                        self:saveSettings(myfields)
                        UIManager:close(self.client_settings_dialog)
                    end
                },
            },
        },
    }
    UIManager:show(self.client_settings_dialog)
    self.client_settings_dialog:onShowKeyboard()
end

function Readeck:setDownloadDirectory(touchmenu_instance)
    require("ui/downloadmgr"):new{
        onConfirm = function(path)
            Log:debug("Set download directory to:", path)
            self.directory = path
            self:saveSettings()
            if touchmenu_instance then
                touchmenu_instance:updateItems()
            end
        end,
    }:chooseDir()
end

function Readeck:saveSettings()
    local tempsettings = {
        server_url            = self.server_url,
        auth_token            = self.auth_token,
        username              = self.username,
        password              = self.password,
        oauth_client_id       = self.oauth_client_id,
        oauth_refresh_token   = self.oauth_refresh_token,
        directory             = self.directory,
        filter_tag            = self.filter_tag,
        sort_param            = self.sort_param,
        ignore_tags           = self.ignore_tags,
        auto_tags             = self.auto_tags,
        is_delete_finished    = self.is_delete_finished,
        is_delete_read        = self.is_delete_read,
        is_archiving_deleted  = self.is_archiving_deleted,
        is_auto_delete        = self.is_auto_delete,
        is_sync_remote_delete = self.is_sync_remote_delete,
        articles_per_sync     = self.articles_per_sync,
        send_review_as_tags   = self.send_review_as_tags,
        remove_finished_from_history = self.remove_finished_from_history,
        remove_read_from_history = self.remove_read_from_history,
        download_queue        = self.download_queue,
        block_timeout         = self.block_timeout,
        total_timeout         = self.total_timeout,
        file_block_timeout    = self.file_block_timeout,
        file_total_timeout    = self.file_total_timeout,
        access_token          = self.access_token,
        token_expiry          = self.token_expiry,
        cached_auth_token     = self.cached_auth_token,
        cached_username       = self.cached_username,
        cached_password       = self.cached_password,
        cached_server_url     = self.cached_server_url,
        cached_auth_method    = self.cached_auth_method,
        sync_star_status = self.sync_star_status,
        remote_star_threshold = self.remote_star_threshold,
        sync_star_rating_as_label = self.sync_star_rating_as_label,
    }
    self.rd_settings:saveSetting("readeck", tempsettings)
    self.rd_settings:flush()
end

function Readeck:readSettings()
    local rd_settings = LuaSettings:open(DataStorage:getSettingsDir().."/readeck.lua")
    rd_settings:readSetting("readeck", {})
    return rd_settings
end

function Readeck:saveRDSettings(setting)
    if not self.rd_settings then self.rd_settings = self:readSettings() end
    self.rd_settings:saveSetting("readeck", setting)
    self.rd_settings:flush()
end

function Readeck:onAddReadeckArticle(article_url)
    if not NetworkMgr:isOnline() then
        self:addToDownloadQueue(article_url)
        UIManager:show(InfoMessage:new{
            text = T(_("Article added to download queue:\n%1"), BD.url(article_url)),
            timeout = 1,
         })
        return
    end

    local readeck_result, add_err = self:addArticle(article_url)
    if readeck_result then
        UIManager:show(InfoMessage:new{
            text = T(_("Article added to Readeck:\n%1"), BD.url(article_url)),
        })
    elseif add_err == "auth_pending" then
        UIManager:show(InfoMessage:new{
            text = _("OAuth authorization started. Finish login and the article will be retried."),
        })
    else
        UIManager:show(InfoMessage:new{
            text = T(_("Error adding link to Readeck:\n%1"), BD.url(article_url)),
        })
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
    if self.remove_finished_from_history or self.remove_read_from_history then
        local document_full_path = self.ui.document.file
        local summary = self.ui.doc_settings:readSetting("summary")
        local status = summary and summary.status
        local is_finished = status == "complete" or status == "abandoned"
        local is_read = self:getLastPercent() == 1

        if document_full_path
           and self.directory
           and ( (self.remove_finished_from_history and is_finished) or (self.remove_read_from_history and is_read) )
           and self.directory == string.sub(document_full_path, 1, string.len(self.directory)) then
            ReadHistory:removeItemByPath(document_full_path)
            self.ui:setLastDirForFileBrowser(self.directory)
        end
    end
end

-- Helper functions for highlight export
local function _clean_highlight_selector(selector)
    if not selector then return "" end
    -- Removes KOReader-specific prefixes from the XPath
    return selector:gsub("/body/DocFragment/body/main/", ""):gsub("/text%(%)$", "")
end

local function _normalize_highlight_selector(selector)
    if not selector then return "" end

    -- Canonicalize XPath by adding [1] to segments without predicates.
    -- e.g., "section/p[2]" becomes "section[1]/p[2]".
    -- This makes server selectors ("section/p[2]") comparable to
    -- client selectors ("section[1]/p[2]").
    local parts = {}
    for part in util.gsplit(selector, "/") do
        if part ~= "" then
            -- Add [1] if it's a tag without a predicate
            if not part:find("%[") then
                part = part .. "[1]"
            end
            table.insert(parts, part)
        end
    end
    local canonical_selector = table.concat(parts, "/")

    -- Pad numbers in XPath indices with zeros for correct lexicographical sorting
    return canonical_selector:gsub("%[(%d+)%]", function(d)
        return string.format("[%05d]", tonumber(d))
    end)
end

local function _compare_highlight_points(s1, o1, s2, o2)
    local norm_s1 = _normalize_highlight_selector(s1)
    local norm_s2 = _normalize_highlight_selector(s2)

    if norm_s1 < norm_s2 then return -1 end
    if norm_s1 > norm_s2 then return 1 end

    -- selectors are effectively equal, compare offsets
    if o1 < o2 then return -1 end
    if o1 > o2 then return 1 end
    return 0
end

local function _highlights_overlap(h1, h2)
    -- h1 is the local highlight (start/end points are pre-ordered).
    -- h2 is the remote highlight.

    -- Defensive check for malformed highlight objects from the server
    if not (h2 and h2.start_selector and h2.end_selector and h2.start_offset and h2.end_offset) then
        Log:warn("Cannot compare with an incomplete remote highlight object. Assuming no overlap.")
        return false
    end

    -- Clean and order points for the remote highlight (h2)
    local h2_start_s, h2_start_o, h2_end_s, h2_end_o
    local clean_s1, clean_s2 = _clean_highlight_selector(h2.start_selector), _clean_highlight_selector(h2.end_selector)
    if _compare_highlight_points(clean_s1, h2.start_offset, clean_s2, h2.end_offset) <= 0 then
        h2_start_s, h2_start_o, h2_end_s, h2_end_o = clean_s1, h2.start_offset, clean_s2, h2.end_offset
    else
        h2_start_s, h2_start_o, h2_end_s, h2_end_o = clean_s2, h2.end_offset, clean_s1, h2.start_offset
    end

    -- Overlap check: start1 < end2 AND start2 < end1
    local start1_before_end2 = _compare_highlight_points(h1.start_selector, h1.start_offset, h2_end_s, h2_end_o) < 0
    local start2_before_end1 = _compare_highlight_points(h2_start_s, h2_start_o, h1.end_selector, h1.end_offset) < 0

    return start1_before_end2 and start2_before_end1
end

local ALLOWED_HIGHLIGHT_COLORS = { red = true, green = true, blue = true, yellow = true }
local function _build_highlight_payload(h)
    -- We are only interested in highlights, not other kinds of annotations.
    if not h.drawer then return nil end

    local start_selector, start_offset = h.pos0:match("(.*)%.(%d+)")
    local end_selector, end_offset = h.pos1:match("(.*)%.(%d+)")

    if not (start_selector and start_offset and end_selector and end_offset) then return nil end

    local s_offset = tonumber(start_offset)
    local e_offset = tonumber(end_offset)

    start_selector = _clean_highlight_selector(start_selector)
    end_selector = _clean_highlight_selector(end_selector)

    -- Ensure start point is before end point for comparison logic
    if _compare_highlight_points(start_selector, s_offset, end_selector, e_offset) > 0 then
        start_selector, end_selector = end_selector, start_selector
        s_offset, e_offset = e_offset, s_offset
    end

    local color = (h.color and ALLOWED_HIGHLIGHT_COLORS[h.color]) and h.color or "yellow"

    return { text = h.text, color = color, start_selector = start_selector, start_offset = s_offset, end_selector = end_selector, end_offset = e_offset }
end

function Readeck:exportHighlights()
    local document = self.ui.document
    if not document then
        UIManager:show(InfoMessage:new{ text = _("No document opened.") })
        return
    end

    local article_id = self:getArticleID(document.file)
    if not article_id then
        UIManager:show(InfoMessage:new{ text = _("Could not find Readeck article ID for this document.") })
        return
    end

    if self:getBearerToken({
        on_oauth_success = function()
            NetworkMgr:runWhenOnline(function()
                self:exportHighlights()
            end)
        end,
    }) == false then
        return false
    end

    -- Fetch existing highlights to check for overlaps
    local existing_highlights_raw, err = self:callAPI("GET", "/api/bookmarks/" .. article_id .. "/annotations", nil, "", "", true)
    local existing_highlights = {}
    if err then
        if err == "auth_pending" then
            return false
        end
        UIManager:show(InfoMessage:new{ text = _("Could not fetch existing highlights from Readeck. Aborting export.") })
        return
    end
    if existing_highlights_raw and type(existing_highlights_raw) == "table" then
        existing_highlights = existing_highlights_raw
    end

    -- The highlights are in the annotation module of the reader UI.
    local highlights = self.ui.view.ui.annotation.annotations

    if not highlights or not next(highlights) then
        UIManager:show(InfoMessage:new{ text = _("No highlights found in this document.") })
        return
    end

    local success_count = 0
    local error_count = 0
    local skipped_count = 0

    for _, h in pairs(highlights) do
        local local_highlight = _build_highlight_payload(h)

        if local_highlight then
            local is_overlapping = false
            for _, remote_h in ipairs(existing_highlights) do
                if _highlights_overlap(local_highlight, remote_h) then
                    is_overlapping = true
                    break
                end
            end

            if is_overlapping then
                skipped_count = skipped_count + 1
                Log:info("Skipping overlapping highlight:", local_highlight.text)
            else
                local bodyJSON = JSON.encode(local_highlight)
                Log:debug("Start selector:", local_highlight.start_selector, "End selector:", local_highlight.end_selector)
                local headers = {
                    ["Content-type"] = "application/json",
                    ["Accept"] = "application/json, */*",
                    ["Content-Length"] = tostring(#bodyJSON),
                    ["Authorization"] = "Bearer " .. self.access_token,
                }

                local result = self:callAPI("POST", "/api/bookmarks/" .. article_id .. "/annotations", headers, bodyJSON, "")
                if result then
                    success_count = success_count + 1
                    -- Add to existing highlights to prevent sending another local highlight that overlaps with this new one.
                    table.insert(existing_highlights, local_highlight)
                else
                    error_count = error_count + 1
                end
            end
        end
    end

    local message_parts = {}
    if success_count > 0 then
        table.insert(message_parts, T(_("Success: %1"), success_count))
    end
    if error_count > 0 then
        table.insert(message_parts, T(_("Failed: %1"), error_count))
    end
    if skipped_count > 0 then
        table.insert(message_parts, T(_("Skipped (overlap): %1"), skipped_count))
    end

    local message
    if #message_parts > 0 then
        message = T(_("Finished exporting highlights.\n%1"), table.concat(message_parts, "\n"))
    else
        message = _("Finished exporting highlights. No new highlights to export.")
    end
    UIManager:show(InfoMessage:new{ text = message })
end

function Readeck:editTimeoutSettings()
    self.timeout_settings_dialog = MultiInputDialog:new {
        title = _("Set timeout"),
        fields = {
            {
                text = self.block_timeout,
                description = _("Block timeout (seconds)"),
                input_type = "number",
                hint = _("Block timeout")
            },
            {
                text = self.total_timeout,
                description = _("Total timeout (seconds)"),
                input_type = "number",
                hint = _("Total timeout")
            },
            {
                text = self.file_block_timeout,
                description = _("File block timeout (seconds)"),
                input_type = "number",
                hint = _("File block timeout")
            },
            {
                text = self.file_total_timeout,
                description = _("File total timeout (seconds)"),
                input_type = "number",
                hint = _("File total timeout")
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.timeout_settings_dialog)
                    end
                },
                {
                    text = _("Apply"),
                    callback = function()
                        local myfields = self.timeout_settings_dialog:getFields()
                        self.block_timeout = math.max(1, tonumber(myfields[1]) or self.block_timeout)
                        self.total_timeout = math.max(1, tonumber(myfields[2]) or self.total_timeout)
                        self.file_block_timeout = math.max(1, tonumber(myfields[3]) or self.file_block_timeout)
                        self.file_total_timeout = math.max(1, tonumber(myfields[4]) or self.file_total_timeout)
                        self:saveSettings(myfields)
                        UIManager:close(self.timeout_settings_dialog)
                    end
                },
            },
        },
    }
    UIManager:show(self.timeout_settings_dialog)
    self.timeout_settings_dialog:onShowKeyboard()
end

function Readeck:setSortParam(touchmenu_instance)
    local radio_buttons = {}

    for _, opt in ipairs(self.sort_options) do
        local key, value = opt[1], opt[2]
        table.insert(radio_buttons, {
            {text = value, provider = key, checked = (self.sort_param == key)}
        })
    end

    UIManager:show(RadioButtonWidget:new{
        title_text = _("Sort articles by"),
        cancel_text = _("Cancel"),
        ok_text = _("Apply"),
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
    })
end

return Readeck
