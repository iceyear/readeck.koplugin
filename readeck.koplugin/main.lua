--[[--
@module koplugin.readeck
]]

-- Readeck for KOReader - Readeck API client plugin
-- Based on wallabag2.koplugin by clach04

local BD = require("ui/bidi")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local Event = require("ui/event")
local FFIUtil = require("ffi/util")
local FileManager = require("apps/filemanager/filemanager")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local JSON = require("json")
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
                        text = _("Reset access token"),
                        keep_menu_open = true,
                        callback = function()
                            self:resetAccessToken()
                        end,
                        enabled_func = function()
                            return not self:isempty(self.access_token)
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
    
    -- Try to get a new token immediately
    if self:getBearerToken() then
        UIManager:show(InfoMessage:new{
            text = _("Access token reset successfully"),
        })
    else
        UIManager:show(InfoMessage:new{
            text = _("Failed to obtain new access token"),
        })
    end
end

function Readeck:clearAllTokens()
    Log:info("Clearing all cached tokens and credentials")
    
    -- Clear all cached authentication data
    self.access_token = ""
    self.token_expiry = 0
    self.cached_auth_token = ""
    self.cached_username = ""
    self.cached_password = ""
    self.cached_server_url = ""
    
    -- Save the cleared state
    self:saveSettings()
    
    UIManager:show(InfoMessage:new{
        text = _("All cached tokens and credentials cleared"),
    })
end

function Readeck:getBearerToken()
    Log:debug("Getting bearer token")
    
    -- Check if the configuration is complete
    local server_empty = self:isempty(self.server_url) 
    local auth_empty = self:isempty(self.auth_token) and (self:isempty(self.username) or self:isempty(self.password))
    local directory_empty = self:isempty(self.directory)
    
    if server_empty or auth_empty or directory_empty then
        Log:warn("Configuration incomplete - Server:", server_empty and "missing" or "ok", 
                 ", Auth:", auth_empty and "missing" or "ok", 
                 ", Directory:", directory_empty and "missing" or "ok")
        UIManager:show(MultiConfirmBox:new{
            text = _("Please configure the server settings and set a download folder."),
            choice1_text_func = function()
                if server_empty or auth_empty then
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

    -- Check if the download directory is valid
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

    -- 检查是否已有访问令牌并且令牌仍有效，同时验证是否使用相同的认证信息
    local now = os.time()
    local auth_changed = false
    
    -- 检查认证信息是否有变化
    if not self:isempty(self.auth_token) then
        -- 使用 API token 的情况
        auth_changed = (self.auth_token ~= self.cached_auth_token) or 
                      (self.server_url ~= self.cached_server_url)
    else
        -- 使用用户名密码的情况
        auth_changed = (self.username ~= self.cached_username) or 
                      (self.password ~= self.cached_password) or
                      (self.server_url ~= self.cached_server_url)
    end
    
    if not self:isempty(self.access_token) and self.token_expiry > now + 300 and not auth_changed then
        -- 令牌仍有效且认证信息未变化，无需更新
        Log:debug("Using cached token, still valid for", self.token_expiry - now, "seconds")
        return true
    end
    
    if auth_changed then
        Log:debug("Authentication credentials changed, invalidating cached token")
    end

    -- 如果已经有 API token 则直接使用
    if not self:isempty(self.auth_token) then
        Log:info("Using provided API token")
        self.access_token = self.auth_token
        -- 设置一个很长的过期时间，因为API token通常不会过期
        self.token_expiry = now + 365 * 24 * 60 * 60 -- 一年
        -- 保存用于生成此 access_token 的认证信息
        self.cached_auth_token = self.auth_token
        self.cached_username = ""
        self.cached_password = ""
        self.cached_server_url = self.server_url
        self:saveSettings() -- 保存新的令牌和过期时间
        return true
    end

    -- 如果没有token，则使用用户名密码获取
    Log:info("No token provided, attempting to login with username/password")
    local login_url = "/api/auth"  -- 修改认证路径，添加 /api 前缀

    local body = {
        username = self.username,
        password = self.password,
        application = "KOReader"
    }

    Log:debug("Auth request - Username:", self.username, "App: KOReader")
    local bodyJSON = JSON.encode(body)
    Log:debug("Auth request body:", bodyJSON)

    local headers = {
        ["Content-type"] = "application/json",
        ["Accept"] = "application/json, */*",
        ["Content-Length"] = tostring(#bodyJSON),
    }
    
    Log:debug("Sending auth request to", self.server_url .. login_url)
    local result = self:callAPI("POST", login_url, headers, bodyJSON, "")
    
    if result and result.token then
        Log:info("Authentication successful, token received")
        self.access_token = result.token
        self.token_expiry = now + 365 * 24 * 60 * 60  -- 假设token一年有效
        -- 保存用于生成此 access_token 的认证信息
        self.cached_auth_token = ""
        self.cached_username = self.username
        self.cached_password = self.password
        self.cached_server_url = self.server_url
        -- 保存访问令牌和过期时间
        self:saveSettings()
        return true
    else
        Log:error("Authentication failed")
        UIManager:show(InfoMessage:new{
            text = _("Could not login to Readeck server."), 
        })
        return false
    end
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

        if #new_article_list < limit then
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
    
    -- Handle authentication errors - retry with fresh token if possible
    if (code == 401 or code == 403) and not retry_auth and apiurl:sub(1, 1) == "/" then
        Log:info("Authentication failed (", code, "), attempting to refresh token")
        
        -- Clear current token and try to get a fresh one
        self.access_token = ""
        self.token_expiry = 0
        
        if self:getBearerToken() then
            Log:info("Token refreshed, retrying API call")
            -- Retry the API call with the new token, but mark retry_auth to prevent infinite recursion
            return self:callAPI(method, apiurl, nil, body, filepath, quiet, true)
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
    local info = InfoMessage:new{ text = _("Connecting…") }
    UIManager:show(info)
    UIManager:forceRePaint()
    UIManager:close(info)

    if self:getBearerToken() == false then
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
        local articles = self:getArticleList()
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

    if self:getBearerToken() == false then
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
                            self:removeArticle(entry_path)
                            num_deleted = num_deleted + 1
                        end
                    elseif percent_finished == 1 then -- 100% read
                        if self.is_delete_read then
                            self:removeArticle(entry_path)
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

    if not article_url or self:getBearerToken() == false then
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

function Readeck:removeArticle(path)
    Log:debug("Removing article", path)
    local id = self:getArticleID(path)
    if id then
        if self.is_archiving_deleted then
            local body = {
                is_archived = true
            }
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
Enter the details of your Readeck server and account.

You can use either an API token (preferred) or username/password for authentication.

If you use both, the API token will be used first. If token authentication fails, username/password will be used as fallback.

Note: For the Server URL, provide the base URL without the /api path (e.g., http://example.com).

Restart KOReader after editing the config file.]]), BD.dirpath(DataStorage:getSettingsDir()))

    self.settings_dialog = MultiInputDialog:new {
        title = _("Readeck settings"),
        fields = {
            {
                text = self.server_url,
                hint = _("Server URL (without /api)")
            },
            {
                text = self.auth_token,
                hint = _("API Token (recommended)")
            },
            {
                text = self.username,
                hint = _("Username (alternative)")
            },
            {
                text = self.password,
                text_type = "password",
                hint = _("Password (alternative)")
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
                        self.auth_token = myfields[2]
                        self.username   = myfields[3]
                        self.password   = myfields[4]
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

    local readeck_result = self:addArticle(article_url)
    if readeck_result then
        UIManager:show(InfoMessage:new{
            text = T(_("Article added to Readeck:\n%1"), BD.url(article_url)),
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
