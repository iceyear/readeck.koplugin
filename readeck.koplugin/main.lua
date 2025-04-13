--[[--
This plugin downloads a set number of the newest articles from your Readeck instance.
It downloads articles as epubs. It can archive or delete articles from Readeck when you finish them
in KOReader. And it will delete or archive them locally when you finish them elsewhere.

Based on the Wallabag plugin.

@module koplugin.readeck
]]

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
local LuaSettings = require("luasettings")
local Math = require("optmath")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
-- Use the MultiInputDialog from the provided text file
local MultiInputDialog = require("ui/widget/multiinputdialog") -- Assuming multiinputdialog.lua is saved here
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
local N_ = _.ngettext
local T = FFIUtil.template

-- Helper function for timestamp conversion (from dateparser.lua)
local unix_timestamp
do
    local time, date, difftime, pcall = os.time, os.date, os.difftime, pcall
    local now = time()
    local local_UTC_offset_sec = difftime(time(date("!*t", now)), time(date("*t", now)))
    unix_timestamp = function(t, offset_sec)
        local success, improper_time = pcall(time, t)
        if not success or not improper_time then return nil, "invalid date. os.time says: " .. (improper_time or "nothing") end
        -- Adjust for local timezone offset and the provided offset
        return improper_time - local_UTC_offset_sec - (offset_sec or 0)
    end
end

-- constants
local article_id_prefix = "[rd-id_"
local article_id_postfix = "] "
local failed, skipped, downloaded = 1, 2, 3

-- Logging levels (match logger.lua)
local LOG_LEVEL_ERROR = 0
local LOG_LEVEL_WARN = 1
local LOG_LEVEL_INFO = 2
local LOG_LEVEL_DEBUG = 3

local Readeck = WidgetContainer:extend{
    name = "readeck",
    log_level = LOG_LEVEL_INFO, -- Default log level
    log_level_map = { -- Map level number to readable string for menu
        [LOG_LEVEL_ERROR] = _("Error"),
        [LOG_LEVEL_WARN] = _("Warning"),
        [LOG_LEVEL_INFO] = _("Info"),
        [LOG_LEVEL_DEBUG] = _("Debug"),
    },
}

--- Parse W3CDTF (ISO 8601 subset) date strings.
-- Integrated from dateparser.lua
-- @param string rest The date string to parse.
-- @treturn number|nil Unix timestamp or nil on failure.
function Readeck:parseW3CDTF(rest)
    if not rest then return nil end -- Handle nil input

    local year, day_of_year, month, day, week
    local hour, minute, second, second_fraction, offset_hours

    local alt_rest

    -- Match YYYY or YYYY-
    year, rest = rest:match("^(%d%d%d%d)%-?(.*)$")
    if not year then return nil end -- Year is mandatory

    -- Try matching ordinal date YYYY-DDD (optional hyphen)
    day_of_year, alt_rest = rest:match("^(%d%d%d)(.*)$")
    if day_of_year then
        -- Ordinal date format not fully supported by os.time easily, skip for now
        -- Or implement conversion from year+day_of_year to month/day if needed
        self:logW("parseW3CDTF: Ordinal date format (YYYY-DDD) not fully supported, parsing may be inaccurate:", rest)
        -- Fallback or return nil? For now, let's try to continue if time part exists
        rest = alt_rest -- Use the rest after DDD
        month = nil -- Mark month/day as unknown
        day = nil
    else
        -- Match YYYY-MM or YYYY-MM-
        month, rest = rest:match("^(%d%d)%-?(.*)$")
        if not month then return nil end -- Month is mandatory if not ordinal

        -- Match YYYY-MM-DD
        day, rest = rest:match("^(%d%d)(.*)$")
        if not day then return nil end -- Day is mandatory if month is present
    end

    -- Check for time part separator 'T' or space ' ' (RFC3339 allows space)
    if rest:sub(1,1) == "T" or rest:sub(1,1) == " " then
        rest = rest:sub(2) -- Remove separator

        -- Match HH or HH:
        hour, rest = rest:match("^([0-2]%d):?(.*)$")
        if not hour then return nil end -- Hour mandatory if time separator present

        -- Match MM or MM:
        minute, rest = rest:match("^([0-5]%d):?(.*)$")
        if not minute then return nil end -- Minute mandatory

        -- Match SS (optional)
        second, rest = rest:match("^([0-5]%d)(.*)$")
        -- second can be nil here, default to 0 later

        -- Match fractional seconds (optional)
        second_fraction, alt_rest = rest:match("^%.(%d+)(.*)$")
        if second_fraction then
            rest = alt_rest
        end

        -- Match Timezone: Z, +HH:MM, -HH:MM, +HHMM, -HHMM, +HH, -HH
        local tz_part = rest
        rest = "" -- Assume rest is consumed by timezone unless proven otherwise
        if tz_part == "Z" or tz_part == "z" then -- UTC
            offset_hours = 0
        elseif tz_part ~= "" then
            local sign, offset_h, offset_m, remaining
            sign, offset_h, offset_m, remaining = tz_part:match("^([+-])(%d%d):?(%d%d)(.*)$")
            if sign and offset_h and offset_m then -- Matches +HH:MM or +HHMM
                offset_hours = tonumber(sign .. offset_h) + (tonumber(offset_m) / 60)
                rest = remaining -- Update rest with anything after timezone
            else -- Try matching +HH or -HH only
                sign, offset_h, remaining = tz_part:match("^([+-])(%d%d)(.*)$")
                if sign and offset_h then
                    offset_hours = tonumber(sign .. offset_h)
                    rest = remaining -- Update rest with anything after timezone
                else
                    -- Invalid or missing timezone, assume local? Or error?
                    -- Readeck API seems to always use 'Z', so this might indicate an issue.
                    self:logW("parseW3CDTF: Invalid or missing timezone offset:", tz_part, "- Assuming UTC.")
                    offset_hours = 0 -- Default to UTC if offset is unparseable
                    rest = tz_part -- Put back the unparsed part into rest
                end
            end
        else
             -- No timezone specified after time part. Assume UTC as per Readeck's usual format.
             self:logD("parseW3CDTF: No timezone offset found after time, assuming UTC.")
             offset_hours = 0
        end

        -- Check if any unparsed characters remain (shouldn't happen for valid ISO8601)
        if rest and rest ~= "" then
            self:logW("parseW3CDTF: Trailing characters found after parsing:", rest)
            -- return nil -- Strict parsing: uncomment to fail on trailing chars
        end
    else
        -- No time part found, treat as midnight UTC? Or fail?
        -- Let's assume midnight UTC if only date is given.
        hour = "00"
        minute = "00"
        second = "00"
        offset_hours = 0
        -- Check for trailing characters after date part
        if rest and rest ~= "" then
             self:logW("parseW3CDTF: Trailing characters found after date part:", rest)
             -- return nil -- Strict parsing
        end
    end

    -- Convert to numbers, providing defaults
    year = tonumber(year)
    month = tonumber(month) -- Might be nil if ordinal date was encountered
    day = tonumber(day)     -- Might be nil if ordinal date was encountered
    hour = tonumber(hour)
    minute = tonumber(minute)
    second = tonumber(second) or 0

    -- Basic validation (os.time will do more thorough checks)
    if not year or not hour or not minute then
        self:logW("parseW3CDTF: Missing essential components after parsing.")
        return nil
    end
    -- If month/day were missing (ordinal date), os.time might fail.
    -- We need month/day for os.time. If they are nil, we can't proceed reliably.
    if not month or not day then
         self:logW("parseW3CDTF: Cannot reliably convert ordinal date without month/day.")
         return nil -- Or attempt conversion from day_of_year if implemented
    end


    local d = {
        year = year,
        month = month,
        day = day,
        hour = hour,
        min = minute,
        sec = second,
        isdst = false -- Important: assume standard time when calculating offset
    }

    -- Calculate the timestamp using the helper function
    local t, err = unix_timestamp(d, offset_hours * 3600)
    if not t then
        self:logW("parseW3CDTF: unix_timestamp conversion failed:", err, "for date table:", d, "offset_hours:", offset_hours)
        return nil
    end

    -- Add fractional seconds if present
    if second_fraction then
        t = t + tonumber("0." .. second_fraction)
    end

    return t
end

-- Logger wrapper functions
function Readeck:logE(...) if self.log_level >= LOG_LEVEL_ERROR then logger.err("Readeck:", ...) end end
function Readeck:logW(...) if self.log_level >= LOG_LEVEL_WARN then logger.warn("Readeck:", ...) end end
function Readeck:logI(...) if self.log_level >= LOG_LEVEL_INFO then logger.info("Readeck:", ...) end end
function Readeck:logD(...) if self.log_level >= LOG_LEVEL_DEBUG then logger.info("Readeck(Debug):", ...) end end


function Readeck:onDispatcherRegisterActions()
    Dispatcher:registerAction("readeck_download", {
        category = "none",
        event = "SynchronizeReadeck",
        title = _("Readeck retrieval"),
        general = true,
    })
    Dispatcher:registerAction("readeck_queue_upload", {
        category = "none",
        event = "UploadReadeckQueue",
        title = _("Readeck queue upload"),
        general = true,
    })
    Dispatcher:registerAction("readeck_status_upload", {
        category = "none",
        event = "UploadReadeckStatuses",
        title = _("Readeck statuses upload"),
        general = true,
    })
end

function Readeck:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    self.rd_settings = self:readSettings()

    -- Settings specific to Readeck
    self.server_url = self.rd_settings.data.readeck.server_url
    self.api_token = self.rd_settings.data.readeck.api_token
    self.application_name = self.rd_settings.data.readeck.application_name or "KOReader Plugin" -- Default app name
    self.username = self.rd_settings.data.readeck.username
    self.password = self.rd_settings.data.readeck.password
    self.directory = self.rd_settings.data.readeck.directory

    -- Common settings (defaults adapted from Wallabag)
    self.log_level                   = self.rd_settings.data.readeck.log_level or LOG_LEVEL_INFO
    self.filter_label                = self.rd_settings.data.readeck.filter_label or ""
    self.ignore_labels               = self.rd_settings.data.readeck.ignore_labels or ""
    self.auto_labels                 = self.rd_settings.data.readeck.auto_labels or ""
    self.archive_finished            = self.rd_settings.data.readeck.archive_finished -- default true below
    self.archive_read                = self.rd_settings.data.readeck.archive_read or false
    self.archive_abandoned           = self.rd_settings.data.readeck.archive_abandoned or false
    self.delete_instead              = self.rd_settings.data.readeck.delete_instead or false
    self.auto_archive                = self.rd_settings.data.readeck.auto_archive or false
    self.sync_remote_archive         = self.rd_settings.data.readeck.sync_remote_archive or false
    self.articles_per_sync           = self.rd_settings.data.readeck.articles_per_sync or 30
    self.remove_finished_from_history = self.rd_settings.data.readeck.remove_finished_from_history or false
    self.remove_read_from_history    = self.rd_settings.data.readeck.remove_read_from_history or false
    self.remove_abandoned_from_history = self.rd_settings.data.readeck.remove_abandoned_from_history or false
    self.offline_queue               = self.rd_settings.data.readeck.offline_queue or {}
    self.use_local_archive           = self.rd_settings.data.readeck.use_local_archive or false

    -- Default archive_finished to true if it's nil (first run)
    if self.archive_finished == nil then self.archive_finished = true end

    -- archive_directory only has a default if directory is set
    self.archive_directory = self.rd_settings.data.readeck.archive_directory
    if not self.archive_directory or self.archive_directory == "" then
        if self.directory and self.directory ~= "" then
            self.archive_directory = self.directory.."archive/"
        end
    end

    -- Readeck doesn't support downloading original non-HTML docs via API
    -- self.download_original_document = false -- Removed setting

    -- Setup external link handler
    if self.ui and self.ui.link then
        self.ui.link:addToExternalLinkDialog("26_readeck", function(this, link_url) -- Changed prio slightly
            return {
                text = _("Add to Readeck"),
                callback = function()
                    UIManager:close(this.external_link_dialog)
                    this.ui:handleEvent(Event:new("AddReadeckArticle", link_url))
                end,
            }
        end)
    end

    self:logI("Readeck plugin initialized")
end

--- Add Readeck to the Tools menu in both the file manager and the reader.
function Readeck:addToMainMenu(menu_items)
    menu_items.readeck = {
        text = _("Readeck"),
        sub_item_table = {
            {
                text_func = function()
                    if self.auto_archive then
                        return _("Synchronize articles with server")
                    else
                        return _("Download new articles from server")
                    end
                end,
                callback = function()
                    self.ui:handleEvent(Event:new("SynchronizeReadeck"))
                end,
            },
            {
                text = _("Upload queue of locally added articles to server"),
                callback = function()
                    self.ui:handleEvent(Event:new("UploadReadeckQueue"))
                end,
                enabled_func = function()
                    return self.offline_queue and #self.offline_queue > 0
                end,
            },
            {
                text = _("Upload article statuses to server"),
                callback = function()
                    self.ui:handleEvent(Event:new("UploadReadeckStatuses"))
                end,
                enabled_func = function()
                    return self.archive_finished or self.archive_read or self.archive_abandoned
                end,
            },
            {
                text = _("Go to download folder"),
                callback = function()
                    self.ui:handleEvent(Event:new("GoToReadeckDirectory"))
                end,
            },
            {
                text = _("Settings"),
                callback_func = function()
                    return nil -- Keep menu open
                end,
                separator = true,
                sub_item_table = {
                    {
                        text = _("Configure Readeck server/token"),
                        keep_menu_open = true,
                        callback = function()
                            self:editServerSettings()
                        end,
                    },
                    {
                        text = _("Download settings"),
                        sub_item_table = {
                            {
                                text_func = function()
                                    local path
                                    if not self.directory or self.directory == "" then
                                        path = _("not set")
                                    else
                                        path = filemanagerutil.abbreviate(self.directory)
                                    end
                                    return T(_("Download folder: %1"), BD.dirpath(path))
                                end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    self:setDownloadDirectory(touchmenu_instance)
                                end,
                            },
                            {
                                text_func = function()
                                    return T(_("Number of articles to keep locally: %1"), self.articles_per_sync)
                                end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    self:setArticlesPerSync(touchmenu_instance)
                                end,
                            },
                            {
                                text_func = function()
                                    return T(_("Only download articles with label: %1"), self.filter_label or "")
                                end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    self:setLabelDialog(
                                        touchmenu_instance,
                                        _("Label to include"),
                                        _("Enter a single label to filter articles on"),
                                        self.filter_label,
                                        function(label)
                                            self.filter_label = label:gsub("^%s*(.-)%s*$", "%1") -- Trim whitespace
                                            self:saveSettings()
                                        end
                                    )
                                end,
                            },
                            {
                                text_func = function()
                                    return T(_("Do not download articles with labels: %1"), self.ignore_labels or "")
                                end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    self:setLabelDialog(
                                        touchmenu_instance,
                                        _("Labels to ignore"),
                                        _("Enter a comma-separated list of labels to ignore"),
                                        self.ignore_labels,
                                        function(labels)
                                            self.ignore_labels = labels
                                            self:saveSettings()
                                        end
                                    )
                                end,
                            },
                            -- Readeck does not support downloading original non-HTML document format via API
                            --[[
                            {
                                text = _("Prefer original non-HTML document"),
                                keep_menu_open = true,
                                checked_func = function()
                                    return false -- Not supported by Readeck API
                                end,
                                enabled_func = function() return false end, -- Disable option
                                -- callback = function() end,
                            },
                            --]]
                        },
                    },
                    {
                        text = _("Remote mark-as-read settings"),
                        sub_item_table = {
                            {
                                text = _("Mark finished articles as read (archive)"),
                                checked_func = function() return self.archive_finished end,
                                callback = function()
                                    self.archive_finished = not self.archive_finished
                                    self:saveSettings()
                                end,
                            },
                            {
                                text = _("Mark 100% read articles as read (archive)"),
                                checked_func = function() return self.archive_read end,
                                callback = function()
                                    self.archive_read = not self.archive_read
                                    self:saveSettings()
                                end,
                            },
                            {
                                text = _("Mark articles on hold as read (archive)"),
                                checked_func = function() return self.archive_abandoned end,
                                callback = function()
                                    self.archive_abandoned = not self.archive_abandoned
                                    self:saveSettings()
                                end,
                                separator = true,
                            },
                            {
                                text = _("Auto-upload article statuses when downloading"),
                                checked_func = function() return self.auto_archive end,
                                callback = function()
                                    self.auto_archive = not self.auto_archive
                                    self:saveSettings()
                                end,
                            },
                            {
                                text = _("Delete instead of marking as read (archive)"),
                                checked_func = function() return self.delete_instead end,
                                callback = function()
                                    self.delete_instead = not self.delete_instead
                                    self:saveSettings()
                                end,
                            },
                        },
                    },
                    {
                        text = _("Local file removal settings"),
                        sub_item_table = {
                            {
                                text = _("Delete remotely archived and deleted articles locally"),
                                checked_func = function() return self.sync_remote_archive end,
                                callback = function()
                                    self.sync_remote_archive = not self.sync_remote_archive
                                    self:saveSettings()
                                end,
                            },
                            {
                                text = _("Move to archive folder instead of deleting"),
                                checked_func = function() return self.use_local_archive end,
                                callback = function()
                                    self.use_local_archive = not self.use_local_archive
                                    -- Ensure archive directory is set if enabling this
                                    if self.use_local_archive and (not self.archive_directory or self.archive_directory == "") then
                                        UIManager:show(InfoMessage:new{text = _("Please set an archive folder first.")})
                                        self.use_local_archive = false -- Revert if no dir set
                                    else
                                        self:saveSettings()
                                    end
                                end,
                            },
                            {
                                text_func = function()
                                    local path
                                    if not self.archive_directory or self.archive_directory == "" then
                                        path = _("not set")
                                    else
                                        path = filemanagerutil.abbreviate(self.archive_directory)
                                    end
                                    return T(_("Archive folder: %1"), BD.dirpath(path))
                                end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    self:setArchiveDirectory(touchmenu_instance)
                                end,
                                enabled_func = function()
                                    return self.use_local_archive
                                end,
                            },
                        },
                    },
                    {
                        text = _("History settings"),
                        sub_item_table = {
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
                            },
                            {
                                text = _("Remove articles on hold from history"),
                                keep_menu_open = true,
                                checked_func = function()
                                    return self.remove_abandoned_from_history or false
                                end,
                                callback = function()
                                    self.remove_abandoned_from_history = not self.remove_abandoned_from_history
                                    self:saveSettings()
                                end,
                            },
                        },
                        separator = true,
                    },
                    {
                        text_func = function()
                            return T(_("Labels to add to new articles: %1"), self.auto_labels or "")
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            self:setLabelDialog(
                                touchmenu_instance,
                                _("Labels to add to new articles"),
                                _("Enter a comma-separated list of labels to add when submitting a new article to Readeck."),
                                self.auto_labels,
                                function(labels)
                                    self.auto_labels = labels
                                    self:saveSettings()
                                end
                            )
                        end,
                        separator = true,
                    },
                    --[[ Readeck uses Annotations, not reviews/notes in the same way as Wallabag tags
                    {
                        text = _("Send review as tags"), -- Not applicable to Readeck
                        enabled_func = function() return false end,
                    },
                    --]]
                    {
                         text = _("Log level"),
                         keep_menu_open = true,
                         callback_func = function() -- Keep menu open
                            return nil
                         end,
                         sub_item_table_func = function()
                             local log_levels = {}
                             for level_num, level_name in pairs(self.log_level_map) do
                                 table.insert(log_levels, {
                                     text = level_name,
                                     level = level_num, -- 直接存储级别编号以便排序
                                     checked_func = function() return self.log_level == level_num end,
                                     callback = function()
                                         -- Use logger.info directly to bypass self.log_level check for debugging this specific issue
                                         logger.info("Readeck CB Start: Current self.log_level =", self.log_level, "Target level_num =", level_num, "Target level_name =", level_name)

                                         local previous_level_num = self.log_level
                                         local previous_level_name = self.log_level_map[previous_level_num] or "Unknown"

                                         -- Log attempt using the potentially failing logD
                                         self:logD("Attempting to change log level from", previous_level_name, "(", previous_level_num, ") to", level_name, "(", level_num, ")")

                                         self.log_level = level_num

                                         -- Log immediately after assignment using direct logger.info
                                         logger.info("Readeck CB After Assign: self.log_level is now =", self.log_level)

                                         -- Log using the potentially failing logD again
                                         self:logD("Log level changing from", previous_level_name, "(", previous_level_num, ") to", level_name, "(", level_num, ")")

                                         -- self:saveSettings() -- Keep commented out

                                         -- Log using the working logI
                                         self:logI("Log level set to", level_name)

                                         -- Log using the potentially failing logD one last time
                                         self:logD("Log level is now", self.log_level_map[self.log_level], "(", self.log_level, ") after assignment (save commented out)")

                                         -- Log end of callback using direct logger.info
                                         logger.info("Readeck CB End: Final self.log_level =", self.log_level)
                                     end,
                                 })
                             end
                             -- Directly sort by the stored level number
                             table.sort(log_levels, function(a, b)
                                return a.level < b.level
                             end)
                             return log_levels
                         end
                    },
                    {
                        text = _("Help"),
                        keep_menu_open = true,
                        callback = function()
                            UIManager:show(InfoMessage:new{
                                text = _([[Download folder: use a folder that is exclusively used by the Readeck plugin. Existing files in this folder risk being deleted.

Articles marked as finished, on hold or 100% read can be marked as read (archived) or deleted on the server. This is done automatically when retrieving new articles with the 'Auto-upload article statuses when downloading' setting.

The 'Delete remotely archived and deleted articles locally' option will allow deletion (or local archival) of local files that are archived or deleted on the server.]])
                            })
                        end,
                    }
                }
            },
            {
                text = _("Info"),
                keep_menu_open = true,
                callback = function()
                    local folder_info = self.directory and BD.dirpath(filemanagerutil.abbreviate(self.directory)) or _("not set")
                    UIManager:show(InfoMessage:new{
                        text = T(_([[Readeck is an open source read-it-later service. This plugin synchronizes with a Readeck server.

More details: https://readeck.org

Downloads to folder: %1]]), folder_info)
                    })
                end,
            },
        },
    }
end

--- Validate settings and obtain an API token if needed, optionally forcing a fetch with credentials.
-- Readeck tokens obtained via username/password are typically permanent.
-- @param[opt=false] force_fetch bool If true, attempt to fetch a new token using credentials even if one exists (or after clearing an invalid one).
-- @treturn bool True if configuration is valid and token is available (or successfully fetched), false otherwise.
function Readeck:getAuthToken(force_fetch)
    force_fetch = force_fetch or false
    local function isEmpty(s)
        return s == nil or s == ""
    end

    local server_url_empty = isEmpty(self.server_url)
    local token_empty = isEmpty(self.api_token)
    local creds_empty = isEmpty(self.username) or isEmpty(self.password) or isEmpty(self.application_name)
    local directory_empty = isEmpty(self.directory)

    -- Ensure server URL ends without a slash
    if self.server_url and self.server_url ~= "" then
        self.server_url = self.server_url:gsub("/*$", "")
        server_url_empty = false -- Recalculate after potential modification
    end

    -- If not forcing a fetch, prioritize existing token
    if not force_fetch and not server_url_empty and not token_empty then
        self:logD("getAuthToken: Using existing API token.")
        -- Assume it's valid until a 401 occurs.
        return true
    end

    -- If forcing fetch or no token exists, check if we can request one with username/password
    if not server_url_empty and not creds_empty then
        self:logI("getAuthToken: Attempting to fetch token using username/password. Force fetch:", force_fetch)

        local login_url = "/auth"
        local body = {
            username = self.username,
            password = self.password,
            application = self.application_name,
        }
        local body_json = JSON.encode(body)
        local headers = {
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/json",
            ["Content-Length"] = tostring(#body_json),
        }

        -- Temporarily clear token for the auth call itself
        local previous_token = self.api_token -- Store for potential restoration on failure
        self.api_token = nil

        -- Use callAPI internally, but ensure it doesn't trigger recursive auth on *this specific* call
        -- Pass quiet=true and retry_count=1
        self:logD("getAuthToken: Calling API POST", login_url)
        local ok, result, code = self:callAPI("POST", login_url, headers, body_json, nil, true, 1) -- Pass retry_count=1

        if ok and result and result.token then
            self:logI("getAuthToken: Successfully obtained new API token.")
            self.api_token = result.token
            -- Clear password after successful token acquisition? Optional.
            -- self.password = nil
            self:saveSettings()
            return true
        else
            self:logE("getAuthToken: Failed to obtain new API token. Status:", code or "N/A", "Result:", result or "N/A")
            -- Restore previous token if auth failed? Or keep it nil?
            -- Keeping it nil might be better to force config prompt if re-auth fails.
            self.api_token = nil -- Keep token nil on failure
            self:saveSettings() -- Save the cleared token state

            -- Show error only if this wasn't triggered by a 401 retry (i.e., initial setup or manual fetch)
            if not force_fetch then
                 UIManager:show(InfoMessage:new{ text = _("Could not login to Readeck server. Check credentials and application name.") })
                 self:editServerSettings()
            end
            return false
        end
    end

    -- If we reach here, config is incomplete or credentials are not available for fetching
    self:logW("getAuthToken: Configuration incomplete or credentials missing. Server empty:", server_url_empty, "Token empty:", token_empty, "Creds empty:", creds_empty, "Directory empty:", directory_empty)

    -- Show configuration prompts only if not called during a 401 retry
    if not force_fetch then
        if directory_empty then
            UIManager:show(MultiConfirmBox:new{
                text = _("Please configure the Readeck server/token and set a download folder."),
                choice1_text = _("Server/Token"),
                choice1_callback = function() self:editServerSettings() end,
                choice2_text = _("Folder (★)"),
                choice2_callback = function() self:setDownloadDirectory() end,
            })
        else
            UIManager:show(MultiConfirmBox:new{
                text = _("Please configure the Readeck server address and provide an API token or username/password."),
                choice1_text = _("Server/Token (★)"),
                choice1_callback = function() self:editServerSettings() end,
            })
        end
    end
    return false
end

--- Get a JSON formatted list of articles from the server.
-- Gets non-archived articles, sorted by newest first.
-- If filter_label is set, only articles containing this label are queried.
-- If ignore_labels is defined, articles containing any of the labels are skipped locally.
-- @treturn table List of article tables (bookmarkSummary) or nil on error
function Readeck:getArticleList()
    local params = {
        is_archived = "false",
        sort = "-created", -- Newest first
        limit = self.articles_per_sync,
    }

    if self.filter_label and self.filter_label ~= "" then
        params.labels = self.filter_label
        self:logD("getArticleList: Filtering by label:", self.filter_label)
    end

    local article_list = {}
    local total_fetched = 0
    local offset = 0

    -- Readeck uses limit/offset pagination
    while total_fetched < self.articles_per_sync do
        params.offset = tostring(offset)
        local articles_url = "/bookmarks" .. self:buildQueryString(params)

        self:logD("getArticleList: Calling API GET", articles_url)
        local ok, result, code, headers = self:callAPI("GET", articles_url, nil, nil, nil, true)

        if not ok then
            -- 404 might just mean offset is beyond the last page if we already got some articles
            if result == "http_error" and code == 404 and #article_list > 0 then
                self:logD("getArticleList: Reached end of articles (404 on offset", offset, ").")
                break
            end
            -- Other errors
            self:logE("getArticleList: Requesting articles failed. Status:", code or "N/A", "Result:", result or "N/A")
            UIManager:show(InfoMessage:new{ text = _("Requesting article list failed.") })
            return nil
        end

        -- Check if result is an array (expected format for bookmark list)
        if type(result) ~= "table" or not result[1] then
            self:logW("getArticleList: Received empty or invalid article list for offset", offset)
            -- If we received nothing on the first attempt, show message
            if offset == 0 and #article_list == 0 then
                 UIManager:show(InfoMessage:new{ text = _("No unread articles found.") })
                 return nil -- Return nil to indicate nothing found or error
            end
            break -- Assume end of list if non-array or empty array received on subsequent pages
        end

        local page_article_list = result -- API returns the array directly

        -- Filter ignored labels locally
        page_article_list = self:filterIgnoredLabels(page_article_list)

        -- self.logD("getArticleList: Current offset:", offset, "Current page size:", #page_article_list)
        -- self:logD("getArticleList: params.limit:", params.limit)
        -- self:logD("getArticleList: params.offset:", params.offset)

        -- Append this page's filtered list to the final article_list
        for _, article in ipairs(page_article_list) do
            table.insert(article_list, article)
            total_fetched = total_fetched + 1
            if total_fetched >= self.articles_per_sync then
                self:logD("getArticleList: Reached target article count:", self.articles_per_sync)
                break -- Exit inner loop
            end
        end

        if total_fetched >= self.articles_per_sync then
            break -- Exit outer loop
        end

        -- Check if there are more items based on headers or if we received fewer than requested
        local total_count = headers and tonumber(headers["Total-Count"])

        if #page_article_list < params.limit or (total_count and (offset + #page_article_list) >= total_count) then
             self:logD("getArticleList: Reached end of articles based on count or headers.")
             break
        end

        -- Prepare for next page
        offset = offset + params.limit
    end -- while loop

    self:logI("getArticleList: Compiled list of", #article_list, "articles.")
    return article_list
end

--- Remove all the articles from the list containing one of the ignored labels.
-- @tparam table article_list Array containing bookmarkSummary objects
-- @treturn table Same array, but without any articles that contain an ignored label.
function Readeck:filterIgnoredLabels(article_list)
    if not self.ignore_labels or self.ignore_labels == "" then
        return article_list -- No filtering needed
    end

    -- Decode labels to ignore (comma-separated, trim whitespace)
    local ignoring = {}
    for label in util.gsplit(self.ignore_labels, "[,]+", false) do
        local trimmed_label = label:gsub("^%s*(.-)%s*$", "%1") -- Trim whitespace
        if trimmed_label ~= "" then
            ignoring[trimmed_label] = true
            self:logD("filterIgnoredLabels: Will ignore label:", trimmed_label)
        end
    end

    if not next(ignoring) then -- Check if ignoring table is empty after processing
        return article_list -- No valid ignore labels found
    end

    local filtered_list = {}
    for _, article in ipairs(article_list) do
        local skip_article = false
        if article.labels and #article.labels > 0 then
            for _, label in ipairs(article.labels) do
                if ignoring[label] then
                    skip_article = true
                    self:logD("filterIgnoredLabels: Skipping article", article.id, "(", article.title, ") because it is labeled '", label, "'")
                    break -- No need to check other labels for this article
                end
            end
        end

        if not skip_article then
            table.insert(filtered_list, article)
        end
    end

    self:logD("filterIgnoredLabels: Filtered list size:", #filtered_list, "Original size:", #article_list)
    return filtered_list
end

--- Download a single article from the Readeck server as EPUB.
-- @tparam table article A bookmarkSummary object
-- @treturn int status code: 1 failed, 2 skipped, 3 downloaded
function Readeck:downloadArticle(article)
    local skip_article = false
    -- Use article.title or fallback if title is missing/empty
    local safe_title = (article.title and article.title ~= "") and article.title or ("Article " .. article.id)
    local title = util.getSafeFilename(safe_title, self.directory, 230, 0)
    local file_ext = ".epub" -- Readeck API primarily supports EPUB export
    local item_url = "/bookmarks/" .. article.id .. "/article.epub"

    local local_path = self.directory .. article_id_prefix .. article.id .. article_id_postfix .. title .. file_ext
    self:logD("downloadArticle: Preparing to download article", article.id, "to", local_path)

    local attr = lfs.attributes(local_path)
    if attr then
        -- File already exists. Skip if local file is newer than server's 'updated' timestamp.
        -- Readeck uses ISO 8601 format (YYYY-MM-DDTHH:MM:SS.ssssssZ)
        local server_mtime = self:parseW3CDTF(article.updated) -- 修改此行
        if server_mtime and server_mtime < attr.modification then
            skip_article = true
            self:logD("downloadArticle: Skipping download because local copy at", local_path, "is newer.")
        elseif not server_mtime then
            skip_article = true -- Cannot compare dates, skip to be safe
            self:logW("downloadArticle: Skipping download because server update time could not be parsed:", article.updated)
        else
            self:logD("downloadArticle: Local copy exists but is older or same age, will overwrite.")
        end
    end

    if not skip_article then
        self:logD("downloadArticle: Calling API GET", item_url, "to save to", local_path)
        local ok, result, code = self:callAPI("GET", item_url, nil, nil, local_path)
        if ok then
            self:logI("downloadArticle: Successfully downloaded article", article.id, "to", local_path)
            return downloaded -- = 3
        else
            self:logE("downloadArticle: Failed to download article", article.id, ". Status:", code or "N/A", "Result:", result or "N/A")
            -- callAPI already handles removing the failed download file
            return failed -- = 1
        end
    end

    return skipped -- = 2
end

-- Call the Readeck API.
-- Handles base URL, authentication, request types, and response parsing.
-- Automatically attempts re-authentication on 401 Unauthorized if credentials are available.
-- @param method string HTTP method (GET, POST, PATCH, DELETE, etc.)
-- @param url string API endpoint path (e.g., "/bookmarks")
-- @param[opt] headers table Additional headers
-- @param[opt] body string Request body (e.g., JSON string)
-- @param[opt] filepath string If provided, download response to this file path
-- @param[opt=false] quiet bool Suppress generic UI error messages
-- @param[opt=0] retry_count number Internal counter to prevent infinite auth loops.
-- @treturn bool success Was the request successful (considering expected codes)?
-- @treturn any result Decoded JSON response table, or filepath if downloaded, or error string
-- @treturn number|nil code HTTP status code
-- @treturn table|nil headers Response headers table
function Readeck:callAPI(method, url, headers, body, filepath, quiet, retry_count)
    quiet = quiet or false
    retry_count = retry_count or 0
    method = method:upper()

    if not self.server_url or self.server_url == "" then
        self:logE("callAPI: Server URL not configured.")
        if not quiet then UIManager:show(InfoMessage:new{ text = _("Readeck server URL not configured.")}) end
        return false, "config_error"
    end

    -- Authentication: Add Bearer token for all API calls except /auth itself
    local full_url = self.server_url .. url
    local request_headers = headers or {}
    if url ~= "/auth" then
        -- Only add auth header if token exists. If it's nil, the request might fail with 401, triggering re-auth attempt.
        if self.api_token and self.api_token ~= "" then
            request_headers["Authorization"] = "Bearer " .. self.api_token
        elseif retry_count == 0 then -- Only log missing token warning on first attempt
             self:logW("callAPI: API token is missing for authenticated request to", url, ". Request will likely fail.")
             -- Don't return error here, let the request proceed and potentially trigger 401 handling.
        end
    end

    -- Set default Accept header if not provided, except for file downloads
    if not filepath and not request_headers["Accept"] then
        request_headers["Accept"] = "application/json"
    end

    -- Set Content-Type for relevant methods if body exists and type not already set
    if body and (method == "POST" or method == "PATCH" or method == "PUT") and not request_headers["Content-Type"] then
        request_headers["Content-Type"] = "application/json" -- Assume JSON unless specified otherwise
    end

    local sink
    local request = {
        method = method,
        url = full_url,
        headers = request_headers,
    }

    if filepath then
        local f, err = io.open(filepath, "w")
        if not f then
            self:logE("callAPI: Cannot open file for writing:", filepath, "-", err)
            return false, "file_error"
        end
        request.sink = ltn12.sink.file(f) -- Let socket.http close the file handle
        socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
        self:logD("callAPI: Requesting", method, full_url, "-> file:", filepath)
    else
        sink = {} -- Capture response in memory
        request.sink = ltn12.sink.table(sink)
        socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
        self:logD("callAPI: Requesting", method, full_url)
    end

    if body then
        request.source = ltn12.source.string(body)
        request.headers["Content-Length"] = tostring(#body) -- Set content length if body provided
        -- Avoid logging potentially sensitive data in production logs if possible
        -- self:logD("callAPI: Request body:", body)
    end

    -- Perform the HTTP request
    local code, resp_headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout() -- Reset timeouts after request

    -- Check for network errors (resp_headers is nil)
    if resp_headers == nil then
        if filepath then self:removeFailedDownload(filepath) end
        self:logE("callAPI: Network error for", method, full_url, "-", status or code or "unknown error")
        if not quiet then NetworkMgr:showNetworkError("Readeck") end
        return false, "network_error", code
    end

    -- Log response status
    self:logD("callAPI: Response status:", code, status)
    -- if resp_headers then self:logD("callAPI: Response headers:", resp_headers) end -- Can be verbose

    -- Handle 401 Unauthorized: Attempt re-authentication and retry *once*
    if code == 401 and retry_count == 0 and url ~= "/auth" then
        self:logW("callAPI: Received 401 Unauthorized for", method, full_url, ". Attempting re-authentication.")
        self.api_token = nil -- Clear the invalid token before attempting to get a new one

        -- Call getAuthToken with force_fetch=true to try using credentials
        if self:getAuthToken(true) then
            self:logI("callAPI: Re-authentication successful (new token obtained). Retrying original request...")
            -- Retry the original call, incrementing retry_count.
            -- The new token is now in self.api_token and will be used by the recursive call.
            return self:callAPI(method, url, headers, body, filepath, quiet, retry_count + 1)
        else
            self:logE("callAPI: Re-authentication failed (getAuthToken returned false).")
            -- getAuthToken already cleared the token and saved settings.
            if not quiet then
                UIManager:show(InfoMessage:new{ text = _("Authentication failed. Please check your Readeck API token or username/password in settings.") })
                -- Optionally directly open settings
                self:editServerSettings()
            end
            -- Return the original 401 error details
            return false, "http_error", code, resp_headers
        end
    end

    -- Determine success based on HTTP status code (after potential retry)
    local success = (code >= 200 and code <= 299)

    if success then
        if filepath then
            self:logD("callAPI: File successfully downloaded to", filepath)
            return true, filepath, code, resp_headers
        else
            local content = table.concat(sink)
            -- Handle 204 No Content specifically
            if code == 204 then
                self:logD("callAPI: Request successful (204 No Content).")
                return true, nil, code, resp_headers -- Return nil for content
            end
            -- Attempt to parse JSON if content exists and JSON was expected
            local expect_json = request_headers["Accept"] and request_headers["Accept"]:find("application/json")
            if content and content ~= "" and expect_json then
                local json_ok, result = pcall(JSON.decode, content)
                if json_ok and result then
                    self:logD("callAPI: JSON response decoded successfully.")
                    return true, result, code, resp_headers
                else
                    self:logE("callAPI: Failed to decode JSON response for", method, full_url, ". Code:", code, ". Content:", content)
                    if not quiet then UIManager:show(InfoMessage:new{ text = _("Received invalid JSON response from server.") }) end
                    return false, "json_error", code, resp_headers
                end
            elseif content and content ~= "" then
                 -- Success code but no JSON expected/received, return raw content
                 self:logD("callAPI: Request successful, non-JSON content received. Code:", code)
                 return true, content, code, resp_headers
            else
                -- Success code, empty content (and not 204)
                self:logD("callAPI: Request successful, empty content received. Code:", code)
                return true, nil, code, resp_headers
            end
        end
    else -- Request failed (code >= 300, and not a 401 handled by retry)
        if filepath then self:removeFailedDownload(filepath) end
        local error_content = table.concat(sink)
        self:logE("callAPI: HTTP error for", method, full_url, ". Code:", code, "Status:", status, "Response:", error_content)

        -- Try to parse error message from JSON response if possible
        local error_message = _("Communication with server failed.") -- Default message
        if error_content and error_content ~= "" then
             local json_ok, error_result = pcall(JSON.decode, error_content)
             if json_ok and error_result and error_result.message then
                 error_message = T(_("Server error: %1"), error_result.message)
                 self:logE("callAPI: Server error message:", error_result.message)
             elseif json_ok and error_result and error_result.errors then -- Handle validation errors (422)
                 -- Simple representation of validation errors
                 local validation_errors = {}
                 if type(error_result.errors) == 'table' then table.insert(validation_errors, table.concat(error_result.errors, ", ")) end
                 if type(error_result.fields) == 'table' then
                     for field, data in pairs(error_result.fields) do
                         if type(data) == 'table' and data.errors and #data.errors > 0 then
                             table.insert(validation_errors, field .. ": " .. table.concat(data.errors, ", "))
                         end
                     end
                 end
                 if #validation_errors > 0 then
                     error_message = T(_("Validation failed: %1"), table.concat(validation_errors, "; "))
                     self:logE("callAPI: Server validation errors:", error_message)
                 end
             end
        end

        -- Specific handling for 401 that occurs during retry or initial /auth call
        if code == 401 then
             error_message = _("Authentication failed. Please check token/credentials.")
             if not quiet then self:editServerSettings() end -- Prompt settings on final auth failure
        end

        if not quiet then UIManager:show(InfoMessage:new{ text = error_message .. " (" .. code .. ")" }) end
        return false, "http_error", code, resp_headers
    end
end

--- Remove partially downloaded file on failure.
function Readeck:removeFailedDownload(filepath)
    if filepath then
        local entry_mode = lfs.attributes(filepath, "mode")
        if entry_mode == "file" then
            local ok, err = os.remove(filepath)
            if ok then
                self:logD("removeFailedDownload: Removed partially downloaded file:", filepath)
            else
                self:logW("removeFailedDownload: Could not remove file:", filepath, "-", err)
            end
        end
    end
end

--- Add articles from local queue to Readeck, then download new articles.
-- If self.auto_archive is true, then local article statuses are uploaded before downloading.
-- @treturn bool Whether the synchronization process reached the end (with or without errors)
function Readeck:downloadArticles()
    local info = InfoMessage:new{ text = _("Connecting to Readeck server…") }
    UIManager:show(info)
    UIManager:forceRePaint() -- Ensure message is shown immediately

    local del_count_remote = 0
    local del_count_local = 0

    -- Ensure authentication is set up
    if not self:getAuthToken() then
        self:logE("downloadArticles: Authentication failed or not configured.")
        UIManager:close(info)
        -- Error shown by getAuthToken
        return false
    end

    -- Check download directory validity *after* auth succeeds but before proceeding
    if not self.directory or self.directory == "" then
        self:logE("downloadArticles: Download directory not configured.")
        UIManager:close(info)
        UIManager:show(InfoMessage:new{ text = _("Download directory not configured.") })
        self:setDownloadDirectory() -- Prompt user to set it
        return false
    end
    local dir_mode = lfs.attributes(self.directory, "mode")
    if dir_mode ~= "directory" then
        self:logE("downloadArticles:", self.directory, "is not a valid directory.")
        UIManager:close(info)
        UIManager:show(InfoMessage:new{ text = T(_("Download folder '%1' is invalid."), self.directory) })
        self:setDownloadDirectory() -- Prompt user to set it
        return false
    end
     -- Add trailing slash if missing
    if string.sub(self.directory, -1) ~= "/" then
        self.directory = self.directory .. "/"
        self:saveSettings() -- Save corrected path
    end

    UIManager:close(info) -- Close "Connecting..." message

    -- Add articles from queue to remote
    local queue_count = self:uploadQueue()

    -- Upload local article statuses to remote if auto_archive enabled
    if self.auto_archive == true then
        self:logD("downloadArticles: Auto-uploading statuses...")
        local remote_cnt, local_cnt = self:uploadStatuses()
        del_count_remote = remote_cnt or 0
        del_count_local = local_cnt or 0
    else
        self:logD("downloadArticles: Skipping automatic status upload.")
    end

    local remote_article_ids = {}
    local download_count = 0
    local fail_count = 0
    local skip_count = 0

    -- Get a list of articles to download
    info = InfoMessage:new{ text = _("Getting list of newest articles from Readeck…") }
    UIManager:show(info)
    UIManager:forceRePaint()
    local articles = self:getArticleList() -- This returns bookmarkSummary objects
    UIManager:close(info)

    if articles and #articles > 0 then
        self:logI("downloadArticles: Received list of", #articles, "articles to process.")
        info = InfoMessage:new{
            text = T(N_("Received a list of 1 article.", "Received a list of %1 articles.", #articles), #articles),
            timeout = 2 -- Show briefly
        }
        UIManager:show(info)
        UIManager:forceRePaint()

        for i, article in ipairs(articles) do
            self:logD("downloadArticles: Processing article", i, "of", #articles, "ID:", article.id)
            -- Store the ID of every *unread* article fetched from the server
            -- This list is used later by processRemoteDeletes
            remote_article_ids[ tostring(article.id) ] = true

            local res = self:downloadArticle(article)

            if res == downloaded then
                self:logD("downloadArticles: Download succeeded for article", article.id)
                download_count = download_count + 1
                info = InfoMessage:new{
                    text = T(
                        _("Downloaded article %1 of %2…"),
                        download_count, -- Use actual downloads, not loop index 'i'
                        #articles
                    ),
                    timeout = 1 -- Quick update
                }
                UIManager:show(info)
                UIManager:forceRePaint()
            elseif res == failed then
                self:logW("downloadArticles: Download failed for article", article.id)
                fail_count = fail_count + 1
            else -- res == skipped
                self:logD("downloadArticles: Download skipped for article", article.id)
                skip_count = skip_count + 1
            end
        end -- for loop iterating through articles

        -- Synchronize remote deletions/archives to local filesystem
        if self.sync_remote_archive then
            self:logD("downloadArticles: Processing remote archives/deletions locally...")
            local deleted_locally_count = self:processRemoteDeletes(remote_article_ids)
            del_count_local = del_count_local + deleted_locally_count
        else
            self:logD("downloadArticles: Skipping processing of remote archives/deletions locally.")
        end

        self:logI("downloadArticles: Sync finished.")
        local msg_lines = {_("Sync finished:")}

        self:logI("downloadArticles: - queue_count =", queue_count)
        if queue_count > 0 then
            table.insert(msg_lines, T(N_("- Added %1 article from queue", "- Added %1 articles from queue", queue_count), queue_count))
        end

        self:logI("downloadArticles: - download_count =", download_count)
        self:logD("downloadArticles: - skip_count =", skip_count)
        table.insert(msg_lines, T(_("- Downloaded: %1"), download_count))
        if skip_count > 0 then table.insert(msg_lines, T(_("- Skipped: %1"), skip_count)) end

        self:logI("downloadArticles: - fail_count =", fail_count)
        if fail_count > 0 then
            table.insert(msg_lines, T(_("- Failed downloads: %1"), fail_count))
        end

        self:logI("downloadArticles: - del_count_local =", del_count_local)
        if del_count_local > 0 then
            if self.use_local_archive then
                table.insert(msg_lines, T(N_("- Archived %1 file locally", "- Archived %1 files locally", del_count_local), del_count_local))
            else
                table.insert(msg_lines, T(N_("- Deleted %1 file locally", "- Deleted %1 files locally", del_count_local), del_count_local))
            end
        end

        self:logI("downloadArticles: - del_count_remote =", del_count_remote)
        if del_count_remote > 0 then
            if self.delete_instead then
                 table.insert(msg_lines, T(N_("- Deleted %1 article on Readeck", "- Deleted %1 articles on Readeck", del_count_remote), del_count_remote))
            else
                 table.insert(msg_lines, T(N_("- Archived %1 article on Readeck", "- Archived %1 articles on Readeck", del_count_remote), del_count_remote))
            end
        end

        UIManager:close(info) -- Close progress message
        info = InfoMessage:new{ text = table.concat(msg_lines, "\n") }
        UIManager:show(info) -- Show summary message
        UIManager:forceRePaint()

    elseif articles == nil then
        -- Error occurred during getArticleList, message already shown
        self:logE("downloadArticles: Failed to get article list.")
        return false
    else -- articles is an empty table {}
        self:logI("downloadArticles: No new articles to download.")
        -- Combine with status update messages if any
        local msg_lines = {_("Sync finished: No new articles found.")}
        if queue_count > 0 then table.insert(msg_lines, T(N_("- Added %1 article from queue", "- Added %1 articles from queue", queue_count), queue_count)) end
        if del_count_local > 0 then
            if self.use_local_archive then table.insert(msg_lines, T(N_("- Archived %1 file locally", "- Archived %1 files locally", del_count_local), del_count_local))
            else table.insert(msg_lines, T(N_("- Deleted %1 file locally", "- Deleted %1 files locally", del_count_local), del_count_local)) end
        end
        if del_count_remote > 0 then
            if self.delete_instead then table.insert(msg_lines, T(N_("- Deleted %1 article on Readeck", "- Deleted %1 articles on Readeck", del_count_remote), del_count_remote))
            else table.insert(msg_lines, T(N_("- Archived %1 article on Readeck", "- Archived %1 articles on Readeck", del_count_remote), del_count_remote)) end
        end
        if self.sync_remote_archive and del_count_local == 0 then
             -- Check if remote deletes were processed even if no new articles downloaded
            self:logD("downloadArticles: Processing remote archives/deletions locally (no new downloads)...")
            local deleted_locally_count = self:processRemoteDeletes({}) -- Pass empty table as no unread articles were fetched
            if deleted_locally_count > 0 then
                if self.use_local_archive then table.insert(msg_lines, T(N_("- Archived %1 file locally", "- Archived %1 files locally", deleted_locally_count), deleted_locally_count))
                else table.insert(msg_lines, T(N_("- Deleted %1 file locally", "- Deleted %1 files locally", deleted_locally_count), deleted_locally_count)) end
            end
        end

        UIManager:close(info)
        info = InfoMessage:new{ text = table.concat(msg_lines, "\n") }
        UIManager:show(info)
        UIManager:forceRePaint()
    end -- articles processing

    return true -- Sync process completed (even if errors occurred in parts)
end

--- Upload any articles that were added to the queue.
-- Used when adding articles offline or called explicitly.
-- @tparam[opt=false] bool quiet Suppress the final summary info message
-- @treturn int Number of articles successfully added (or attempted) from the queue
function Readeck:uploadQueue(quiet)
    quiet = quiet or false
    local count_success = 0
    local count_attempted = 0

    if self.offline_queue and next(self.offline_queue) ~= nil then
        local queue_size = #self.offline_queue
        self:logI("uploadQueue: Processing offline queue with", queue_size, "articles.")
        local msg = T(N_("Adding 1 article from queue…", "Adding %1 articles from queue…", queue_size), queue_size)
        local info = InfoMessage:new{ text = msg }
        UIManager:show(info)
        UIManager:forceRePaint()

        -- Ensure authentication is ready before processing queue
        if not self:getAuthToken() then
             self:logE("uploadQueue: Authentication failed, cannot process queue.")
             UIManager:close(info)
             -- Error message shown by getAuthToken
             return 0
        end

        local remaining_queue = {}
        for i, articleUrl in ipairs(self.offline_queue) do
            count_attempted = count_attempted + 1
            self:logD("uploadQueue: Attempting to add URL:", articleUrl)
            -- addArticle returns true on 202 Accepted (or 200/201 if API changes)
            if self:addArticle(articleUrl) then
                self:logI("uploadQueue: Successfully queued article", articleUrl, "for adding on Readeck.")
                count_success = count_success + 1
            else
                self:logW("uploadQueue: Failed to add article", articleUrl, "to Readeck. Keeping in queue.")
                table.insert(remaining_queue, articleUrl) -- Keep failed ones for next time
            end
            -- Update progress message
            info.text = T(N_("Adding article %1 of %2 from queue…", "Adding article %1 of %2 from queue…", queue_size), i, queue_size)
            UIManager:show(info)
            UIManager:forceRePaint()
        end

        self.offline_queue = remaining_queue
        self:saveSettings()
        UIManager:close(info)

        self:logI("uploadQueue: Finished processing queue.", count_success, "succeeded,", count_attempted - count_success, "failed (kept in queue).")
    else
        self:logD("uploadQueue: Offline queue is empty.")
    end

    if not quiet then
        local final_msg
        if count_attempted > 0 then
            if count_success == count_attempted then
                final_msg = T(N_("Added %1 article from queue to Readeck.", "Added %1 articles from queue to Readeck.", count_success), count_success)
            else
                final_msg = T(_("Added %1 of %2 articles from queue. %3 failed (will retry)."), count_success, count_attempted, count_attempted - count_success)
            end
        else
            final_msg = _("Article queue is empty.")
        end
        local final_info = InfoMessage:new{ text = final_msg }
        UIManager:show(final_info)
    end

    return count_success
end

--- Compare local file IDs with the list of *unread* IDs fetched from the server.
-- Delete or archive any local files whose IDs are *not* in the provided `remote_unread_ids` table.
-- This implies the corresponding article on the server is archived, deleted, or wasn't fetched (e.g., filtered out).
-- @param table remote_unread_ids A map where keys are the string IDs of articles currently considered "unread" on the server (based on the last `getArticleList` call).
-- @treturn int Number of locally deleted or archived files.
function Readeck:processRemoteDeletes(remote_unread_ids)
    if not self.sync_remote_archive then
        self:logD("processRemoteDeletes: Skipping because sync_remote_archive is disabled.")
        return 0
    end
    if not self.directory or self.directory == "" then
         self:logW("processRemoteDeletes: Skipping because download directory is not set.")
         return 0
    end

    self:logD("processRemoteDeletes: Synchronizing local files against server's unread list...")
    -- Ensure remote_unread_ids is a table, even if empty
    remote_unread_ids = remote_unread_ids or {}
    self:logD("processRemoteDeletes: Server unread IDs count:", util.tableCount(remote_unread_ids))

    local info_text = self.use_local_archive and _("Archiving local files removed from server's unread list…") or _("Deleting local files removed from server's unread list…")
    local info = InfoMessage:new{ text = info_text }
    UIManager:show(info)
    UIManager:forceRePaint()

    local count = 0
    local local_files_scanned = 0

    -- Check if directory exists before trying to list its contents
    if lfs.attributes(self.directory, "mode") ~= "directory" then
        self:logW("processRemoteDeletes: Download directory", self.directory, "does not exist or is not a directory. Skipping.")
        UIManager:close(info)
        return 0
    end

    for entry in lfs.dir(self.directory) do
        local entry_path = self.directory .. entry
        -- Process only files, ignore directories (like 'archive') and dotfiles
        if entry ~= "." and entry ~= ".." and not entry:match("^%.") and lfs.attributes(entry_path, "mode") == "file" then
            local_files_scanned = local_files_scanned + 1
            local local_id = self:getArticleID(entry_path)

            if local_id and not remote_unread_ids[local_id] then
                -- This local file's ID is not in the list of unread articles from the server.
                -- It should be archived or deleted locally.
                if self.use_local_archive then
                    self:logI("processRemoteDeletes: Archiving local file for article ID", local_id, "(not in server unread list):", entry_path)
                    count = count + self:archiveLocalArticle(entry_path)
                else
                    self:logI("processRemoteDeletes: Deleting local file for article ID", local_id, "(not in server unread list):", entry_path)
                    count = count + self:deleteLocalArticle(entry_path)
                end
            elseif local_id then
                 self:logD("processRemoteDeletes: Local file ID", local_id, "found in server unread list; keeping.")
            else
                self:logW("processRemoteDeletes: Could not get article ID from local filename:", entry, "- Skipping.")
            end
        end
    end -- end of loop through directory entries

    self:logI("processRemoteDeletes: Scanned", local_files_scanned, "local files. Processed", count, "files for local removal/archival.")
    UIManager:close(info)
    return count
end

--- Archive (mark as read) or delete locally finished articles on the Readeck server.
-- Also handles removing items from history if configured.
-- @param[opt=false] bool quiet Suppress the final summary info message
-- @treturn number count_remote Number of articles successfully archived/deleted on the server
-- @treturn number count_local Number of articles successfully archived/deleted locally
function Readeck:uploadStatuses(quiet)
    quiet = quiet or false
    local count_remote = 0
    local count_local = 0

    if not (self.archive_finished or self.archive_read or self.archive_abandoned) then
        self:logD("uploadStatuses: Skipping because no archive/delete options are enabled.")
        return 0, 0
    end

    -- Ensure authentication is ready
    if not self:getAuthToken() then
        self:logE("uploadStatuses: Authentication failed, cannot upload statuses.")
        -- Error message shown by getAuthToken
        return 0, 0
    end

    if not self.directory or self.directory == "" then
         self:logW("uploadStatuses: Skipping because download directory is not set.")
         return 0, 0
    end

    self:logD("uploadStatuses: Syncing local article statuses to Readeck...")
    local info = InfoMessage:new{ text = _("Syncing local article statuses…") }
    UIManager:show(info)
    UIManager:forceRePaint()

    local files_processed = 0
    local files_to_process = {}

    -- Check if directory exists
    if lfs.attributes(self.directory, "mode") ~= "directory" then
        self:logW("uploadStatuses: Download directory", self.directory, "does not exist or is not a directory. Skipping.")
        UIManager:close(info)
        return 0, 0
    end

    -- First, gather list of files to process to avoid issues with modifying the list while iterating
    for entry in lfs.dir(self.directory) do
        local entry_path = self.directory .. entry
        if entry ~= "." and entry ~= ".." and not entry:match("^%.") and lfs.attributes(entry_path, "mode") == "file" then
            table.insert(files_to_process, entry_path)
        end
    end

    local total_files = #files_to_process
    self:logD("uploadStatuses: Found", total_files, "files to check.")

    for i, entry_path in ipairs(files_to_process) do
        files_processed = files_processed + 1
        self:logD("uploadStatuses: Checking file", i, "of", total_files, ":", entry_path)

        -- Update progress
        info.text = T(_("Checking status of file %1 of %2…"), i, total_files)
        UIManager:show(info)
        UIManager:forceRePaint()

        local should_process_remotely = false
        local skip_local_action = false

        if DocSettings:hasSidecarFile(entry_path) then
            self:logD("uploadStatuses:", entry_path, "has sidecar file.")
            local doc_settings = DocSettings:open(entry_path)
            local summary = doc_settings:readSetting("summary")
            local status = summary and summary.status or "new"
            local percent_finished = doc_settings:readSetting("percent_finished") or 0

            -- Determine if the article meets criteria for remote archival/deletion
            if (status == "complete" and self.archive_finished) then
                self:logD("uploadStatuses: - Status is 'complete' and archive_finished is enabled.")
                should_process_remotely = true
            elseif (status == "abandoned" and self.archive_abandoned) then
                self:logD("uploadStatuses: - Status is 'abandoned' and archive_abandoned is enabled.")
                should_process_remotely = true
            elseif (percent_finished >= 0.995 and self.archive_read) then -- Use 1.0 or very close for 100% read
                self:logD("uploadStatuses: - Percent is", percent_finished * 100, "% and archive_read is enabled.")
                should_process_remotely = true
            end

            if should_process_remotely then
                self:logI("uploadStatuses: - Article meets criteria. Archiving/deleting on remote...")
                if self:archiveArticle(entry_path) then
                    count_remote = count_remote + 1
                    self:logI("uploadStatuses: - Successfully archived/deleted on remote.")
                    -- Now handle local action if remote action succeeded
                    if self.use_local_archive then
                        self:logI("uploadStatuses: - Archiving locally...")
                        count_local = count_local + self:archiveLocalArticle(entry_path)
                    else
                        self:logI("uploadStatuses: - Deleting locally...")
                        count_local = count_local + self:deleteLocalArticle(entry_path)
                    end
                    -- Handle history removal after successful processing
                    self:handleHistoryRemoval(entry_path, status, percent_finished)
                else
                    self:logW("uploadStatuses: - Failed to archive/delete on remote. Skipping local action.")
                    skip_local_action = true -- Prevent local action if remote failed
                end
            else
                self:logD("uploadStatuses: - Article does not meet criteria for remote action.")
            end -- if should_process_remotely
        else
            self:logD("uploadStatuses:", entry_path, "does not have a sidecar file. Skipping status check.")
        end -- if hasSidecarFile
    end -- for loop

    UIManager:close(info)
    self:logI("uploadStatuses: Upload finished. Processed", files_processed, "files.")
    self:logI("uploadStatuses: - Remote actions:", count_remote)
    self:logI("uploadStatuses: - Local actions:", count_local)

    if not quiet then
        local msg_lines = {_("Status upload finished:")}
        if count_remote > 0 then
            if self.delete_instead then
                table.insert(msg_lines, T(N_("- Deleted %1 article on Readeck", "- Deleted %1 articles on Readeck", count_remote), count_remote))
            else
                table.insert(msg_lines, T(N_("- Archived %1 article on Readeck", "- Archived %1 articles on Readeck", count_remote), count_remote))
            end
        else
             table.insert(msg_lines, _("- No articles updated on Readeck."))
        end

        if count_local > 0 then
            if self.use_local_archive then
                table.insert(msg_lines, T(N_("- Archived %1 file locally", "- Archived %1 files locally", count_local), count_local))
            else
                table.insert(msg_lines, T(N_("- Deleted %1 file locally", "- Deleted %1 files locally", count_local), count_local))
            end
        end

        local final_info = InfoMessage:new{ text = table.concat(msg_lines, "\n") }
        UIManager:show(final_info)
    end -- if not quiet

    return count_remote, count_local
end

--- Add a new article to the Readeck server.
-- Includes any configured auto_labels.
-- @param string article_url Full URL of the article to add.
-- @treturn bool True if the API call returned a success status (202 Accepted typically), false otherwise.
function Readeck:addArticle(article_url)
    self:logD("addArticle: Adding URL:", article_url)

    -- Authentication check is implicitly done by callAPI, but good practice:
    if not article_url or (not self.api_token and (not self.username or not self.password)) then
        self:logE("addArticle: Cannot add article, URL missing or authentication not configured.")
        return false
    end
    -- Ensure token is available before making the call
    if not self.api_token then
        if not self:getAuthToken() then
             self:logE("addArticle: Authentication failed, cannot add article.")
             return false
        end
    end

    local body = {
        url = article_url,
    }

    -- Add auto labels if configured
    if self.auto_labels and self.auto_labels ~= "" then
        local labels_array = {}
        for label in util.gsplit(self.auto_labels, "[,]+", false) do
            local trimmed_label = label:gsub("^%s*(.-)%s*$", "%1") -- Trim whitespace
            if trimmed_label ~= "" then
                table.insert(labels_array, trimmed_label)
            end
        end
        if #labels_array > 0 then
            body.labels = labels_array
            self:logD("addArticle: Adding with auto-labels:", labels_array)
        end
    end

    local body_JSON = JSON.encode(body)
    local headers = {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json", -- Expect JSON response (even if just a message)
    }

    self:logD("addArticle: Calling API POST /bookmarks")
    -- Readeck uses POST /bookmarks, expects 202 Accepted
    local ok, result, code = self:callAPI("POST", "/bookmarks", headers, body_JSON)

    -- Treat 202 as success for this asynchronous operation
    if ok and code == 202 then
        self:logI("addArticle: Successfully sent add request for", article_url, "(queued by server).")
        return true
    elseif ok then
        -- Handle unexpected success codes if API changes (e.g., 201 Created)
        self:logW("addArticle: Add request for", article_url, "returned unexpected success code:", code)
        return true -- Still treat as success
    else
        self:logE("addArticle: Failed to send add request for", article_url, ". Code:", code or "N/A")
        return false
    end
end

--- Archive or delete an article on Readeck based on settings.
-- Uses PATCH /bookmarks/{id} with is_archived or is_deleted flags.
-- @param string path Local path of the article file.
-- @treturn bool True if the API call was successful (200 OK typically), false otherwise.
function Readeck:archiveArticle(path)
    self:logD("archiveArticle: Processing path:", path)
    local id = self:getArticleID(path)

    if not id then
        self:logW("archiveArticle: Could not extract article ID from path:", path)
        return false
    end

    local body = {}
    local action_desc = ""

    if self.delete_instead then
        body.is_deleted = true
        action_desc = "delete"
        self:logI("archiveArticle: Marking article ID", id, "for deletion on Readeck.")
    else
        body.is_archived = true
        action_desc = "archive"
        self:logI("archiveArticle: Marking article ID", id, "as archived on Readeck.")
    end

    local bodyJSON = JSON.encode(body)
    local headers = {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json", -- Expect JSON response (bookmarkUpdated)
    }

    self:logD("archiveArticle: Calling API PATCH /bookmarks/" .. id)
    local ok, result, code = self:callAPI("PATCH", "/bookmarks/" .. id, headers, bodyJSON)

    if ok and code == 200 then
        self:logI("archiveArticle: Successfully", action_desc .. "d article", id, "on Readeck.")
        self:logD("archiveArticle: Server response:", result)
        return true
    else
        self:logE("archiveArticle: Failed to", action_desc, "article", id, "on Readeck. Code:", code or "N/A")
        return false
    end
end

--- Move an article file and its sidecar to the configured archive_directory.
-- Creates the archive directory if it doesn't exist.
-- @param string path Local path of the article file.
-- @treturn int 1 if successful, 0 if not.
function Readeck:archiveLocalArticle(path)
    local result = 0
    if not self.use_local_archive or not self.archive_directory or self.archive_directory == "" then
        self:logW("archiveLocalArticle: Cannot archive locally, archive directory not set or feature disabled.")
        return 0
    end

    -- Ensure archive directory exists
    local dir_mode = lfs.attributes(self.archive_directory, "mode")
    if dir_mode == nil then
        self:logD("archiveLocalArticle: Archive directory does not exist, creating at", self.archive_directory)
        local created, err = util.makePath(self.archive_directory)
        if not created then
            self:logE("archiveLocalArticle: Failed to create archive directory:", self.archive_directory, "-", err)
            UIManager:show(InfoMessage:new{ text = T(_("Failed to create archive folder: %1"), self.archive_directory) })
            return 0
        end
    elseif dir_mode ~= "directory" then
        self:logE("archiveLocalArticle: Archive path exists but is not a directory:", self.archive_directory)
        UIManager:show(InfoMessage:new{ text = T(_("Archive path '%1' is not a valid folder."), self.archive_directory) })
        return 0
    end
     -- Add trailing slash if missing from archive dir path (less likely needed after makePath, but safe)
    if string.sub(self.archive_directory, -1) ~= "/" then
        self.archive_directory = self.archive_directory .. "/"
    end


    -- Proceed with moving the file
    if lfs.attributes(path, "mode") == "file" then
        local _, file = util.splitFilePathName(path)
        local new_path = self.archive_directory .. file

        -- Check if destination already exists to avoid overwriting (optional, FileManager:moveFile might handle it)
        if lfs.attributes(new_path) then
             self:logW("archiveLocalArticle: Destination file already exists, cannot archive:", new_path)
             -- Maybe delete the source anyway? Or skip? Skipping is safer.
             -- FileManager:deleteFile(path, true) -- Uncomment to delete source even if dest exists
             return 0 -- Indicate failure or skip
        end

        self:logD("archiveLocalArticle: Moving", path, "to", new_path)
        if FileManager:moveFile(path, new_path) then
            self:logI("archiveLocalArticle: Successfully moved file to archive:", new_path)
            -- Update sidecar location. DocSettings handles moving the .sdr directory.
            local sdr_moved = DocSettings.updateLocation(path, new_path, false) -- false = don't copy cover
             if sdr_moved then
                  self:logD("archiveLocalArticle: Successfully moved sidecar directory.")
             else
                  self:logW("archiveLocalArticle: Could not move sidecar directory (or no sidecar existed).")
             end
            result = 1
        else
             self:logE("archiveLocalArticle: Failed to move file using FileManager:", path, "->", new_path)
        end
    else
        self:logW("archiveLocalArticle: Source path is not a file:", path)
    end

    return result
end

--- Delete an article file and its sidecar locally.
-- @param string path Local path of the article file.
-- @treturn int 1 if successful, 0 if not.
function Readeck:deleteLocalArticle(path)
    local result = 0
    if lfs.attributes(path, "mode") == "file" then
        self:logD("deleteLocalArticle: Deleting local file and sidecar:", path)
        -- FileManager:deleteFile handles both the file and its .sdr directory
        if FileManager:deleteFile(path, true) then -- true = delete permanently
            self:logI("deleteLocalArticle: Successfully deleted file and sidecar:", path)
            result = 1
        else
            self:logE("deleteLocalArticle: Failed to delete file using FileManager:", path)
        end
    else
        self:logW("deleteLocalArticle: Source path is not a file:", path)
    end
    return result
end

--- Extract the Readeck article ID from the filename.
-- Expects format: [rd-id_SHORTUID] Title.epub
-- @param string path Local path of the article file.
-- @return string|nil Readeck article ID (Short UID) if found, otherwise nil.
function Readeck:getArticleID(path)
    local _, filename = util.splitFilePathName(path)
    local prefix_len = #article_id_prefix

    -- self:logD("getArticleID: Attempting to extract ID from:", filename) -- Verbose

    -- Basic check for prefix
    if filename:sub(1, prefix_len) ~= article_id_prefix then
        -- self:logD("getArticleID: Prefix mismatch.")
        return nil
    end

    -- Find the closing postfix `] `
    local endpos = filename:find(article_id_postfix, prefix_len + 1, true) -- Start search after prefix, plain search

    if not endpos then
        -- self:logD("getArticleID: Postfix mismatch.")
        return nil
    end

    -- Extract the ID between prefix and postfix
    local id = filename:sub(prefix_len + 1, endpos - 1)

    -- Basic sanity check for ID format (Readeck uses Short UIDs - alphanumeric, typically ~20 chars)
    -- This is a loose check, API might be more specific
    if id and id:match("^[A-Za-z0-9]+$") then
         -- self:logD("getArticleID: Extracted ID:", id)
         return id
    else
         self:logW("getArticleID: Extracted potential ID '", id, "' seems invalid from filename:", filename)
         return nil
    end
end

--- Refresh the file manager view if it's currently showing the download directory.
function Readeck:refreshFileManager()
    if FileManager.instance and FileManager.instance.current_dir == self.directory then
        self:logD("refreshFileManager: Refreshing file manager view.")
        FileManager.instance:onRefresh()
    else
        self:logD("refreshFileManager: File manager not active or not in the download directory, skipping refresh.")
    end
end

--- A dialog used for setting filter_label, ignore_labels and auto_labels.
-- @param table touchmenu_instance The menu instance, to update items after save.
-- @param string title Dialog title.
-- @param string description Dialog description text.
-- @param string value Current value of the setting.
-- @param function callback Function to call with the new value on save.
function Readeck:setLabelDialog(touchmenu_instance, title, description, value, callback)
    self.label_dialog = InputDialog:new{
        title = title,
        description = description,
        input = value or "", -- Ensure value is a string
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.label_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local input_text = self.label_dialog:getInputText()
                        callback(input_text) -- Callback handles saving via self:saveSettings()
                        -- No need to call saveSettings here, callback does it.
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                        UIManager:close(self.label_dialog)
                    end,
                }
            }
        },
    }
    UIManager:show(self.label_dialog)
    self.label_dialog:onShowKeyboard()
end

--- The dialog shown when clicking "Configure Readeck server/token".
function Readeck:editServerSettings()
    local text_info = T(_([[
Enter the base URL of your Readeck API (e.g., https://readeck.example.com/api).

You can authenticate using either:
1. An API Token: Create one in Readeck's web interface under Profile > API Tokens. Paste the *token value* here.
2. Username & Password: If you don't have a token, enter your Readeck username and password, along with an Application Name (e.g., "KOReader"). The plugin will request a permanent token for you.

If an API Token is provided, it will be used, and username/password will be ignored.]]), BD.dirpath(DataStorage:getSettingsDir()))

    self.settings_dialog = MultiInputDialog:new{
        title = _("Readeck Settings"),
        fields = {
             -- Field indices: 1=URL, 2=Token, 3=AppName, 4=Username, 5=Password
            {
                text = self.server_url or "",
                hint = _("Server Base URL (e.g., https://...)")
            },
            {
                text = self.api_token or "",
                hint = _("API Token (recommended, paste value here)")
            },
            {
                text = self.application_name or "KOReader Plugin",
                hint = _("Application Name (if using user/pass)")
            },
            {
                text = self.username or "",
                hint = _("Username (if no token)")
            },
            {
                text = self.password or "",
                text_type = "password",
                hint = _("Password (if no token)")
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
                    is_enter_default = true,
                    callback = function()
                        local myfields = self.settings_dialog:getFields()
                        local new_server_url = myfields[1]:gsub("/*$", "") -- remove trailing slashes
                        local new_api_token = myfields[2]
                        local new_app_name = myfields[3]
                        local new_username = myfields[4]
                        local new_password = myfields[5]

                        -- If token is newly entered or changed, clear password for security? Optional.
                        -- If user clears the token field, allow using username/password again.
                        local token_changed = (new_api_token ~= (self.api_token or ""))

                        self.server_url = new_server_url
                        self.api_token = new_api_token
                        self.application_name = new_app_name
                        self.username = new_username

                        -- Only save the new password if the token field is empty
                        -- and the password field itself was actually modified (or initially empty).
                        -- Avoid saving the "****" placeholder if user didn't touch the password field.
                        if new_api_token == "" then
                            self.password = new_password
                        else
                            -- If token is present, clear password from settings
                            self.password = nil
                        end

                        self:logI("editServerSettings: Applying settings. Server:", self.server_url, "Token:", self.api_token and "****" or "None", "App:", self.application_name, "User:", self.username or "None")
                        self:saveSettings()
                        UIManager:close(self.settings_dialog)
                        -- Optionally, trigger a token check/fetch immediately if needed
                        -- if token_changed and new_api_token == "" and new_username ~= "" then
                        --     self:getAuthToken() -- Try to fetch token immediately if creds provided and token removed
                        -- end
                    end
                },
            },
        },
    }
    UIManager:show(self.settings_dialog)
    self.settings_dialog:onShowKeyboard()
end

--- The dialog shown when clicking "Number of articles to keep locally".
function Readeck:setArticlesPerSync(touchmenu_instance)
    self.articles_dialog = InputDialog:new{
        title = _("Number of articles to sync"),
        description = _("Maximum number of unread articles to fetch from Readeck."),
        input = tostring(self.articles_per_sync),
        input_type = "number", -- Ensure numeric input
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.articles_dialog)
                    end,
                },
                {
                    text = _("Apply"),
                    is_enter_default = true,
                    callback = function()
                        local num_str = self.articles_dialog:getInputText()
                        local num = tonumber(num_str)
                        if num and num >= 1 then
                            self.articles_per_sync = math.floor(num) -- Ensure integer
                            self:logI("setArticlesPerSync: Set articles per sync to", self.articles_per_sync)
                            self:saveSettings()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        else
                            self:logW("setArticlesPerSync: Invalid input:", num_str)
                            UIManager:show(InfoMessage:new{ text = _("Please enter a valid number (1 or more).") })
                        end
                        UIManager:close(self.articles_dialog)
                    end,
                }
            }
        },
    }
    UIManager:show(self.articles_dialog)
    self.articles_dialog:onShowKeyboard()
end

--- The dialog shown when clicking "Download folder".
function Readeck:setDownloadDirectory(touchmenu_instance)
    require("ui/downloadmgr"):new{
        title = _("Select Readeck Download Folder"),
        onConfirm = function(path)
            self.directory = path
            self:logI("setDownloadDirectory: Set download directory to", path)
            self:saveSettings()
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    }:chooseDir()
end

--- The dialog shown when clicking "Archive folder" (only if use_local_archive is enabled).
function Readeck:setArchiveDirectory(touchmenu_instance)
     if not self.use_local_archive then return end -- Should be disabled in menu, but safety check

    require("ui/downloadmgr"):new{
        title = _("Select Readeck Archive Folder"),
        current_dir = self.archive_directory or self.directory or KOSettings:readSetting("home_dir") or "/mnt/onboard/",
        onConfirm = function(path)
             -- Ensure trailing slash
            if path and string.sub(path, -1) ~= "/" then
                path = path .. "/"
            end
            -- Prevent setting archive inside download dir? Or vice versa? For simplicity, allow anything for now.
            self.archive_directory = path
            self:logI("setArchiveDirectory: Set archive directory to", path)
            self:saveSettings()
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    }:chooseDir()
end

--- Save all current settings to the LuaSettings file.
function Readeck:saveSettings()
    local current_settings = {
        server_url = self.server_url,
        api_token = self.api_token,
        application_name = self.application_name,
        username = self.username,
        -- Avoid saving password if token exists
        password = (self.api_token and self.api_token ~= "") and nil or self.password,
        directory = self.directory,
        archive_directory = self.archive_directory,
        log_level = self.log_level,
        filter_label = self.filter_label,
        ignore_labels = self.ignore_labels,
        auto_labels = self.auto_labels,
        archive_finished = self.archive_finished,
        archive_read = self.archive_read,
        archive_abandoned = self.archive_abandoned,
        delete_instead = self.delete_instead,
        auto_archive = self.auto_archive,
        sync_remote_archive = self.sync_remote_archive,
        articles_per_sync = self.articles_per_sync,
        remove_finished_from_history = self.remove_finished_from_history,
        remove_read_from_history = self.remove_read_from_history,
        remove_abandoned_from_history = self.remove_abandoned_from_history,
        offline_queue = self.offline_queue,
        use_local_archive = self.use_local_archive,
    }

    self.rd_settings:saveSetting("readeck", current_settings)
    self.rd_settings:flush()
    self:logD("saveSettings: Settings saved.")
end

--- Read settings from the LuaSettings file.
-- @treturn LuaSettings object
function Readeck:readSettings()
    -- Ensure settings directory exists
    local settings_dir = DataStorage:getSettingsDir()
    if lfs.attributes(settings_dir, "mode") ~= "directory" then
        util.makePath(settings_dir)
    end
    local settings_file = settings_dir .. "/readeck.lua"
    local rd_settings = LuaSettings:open(settings_file)
    -- Read the 'readeck' table, defaulting to an empty table if it doesn't exist
    rd_settings:readSetting("readeck", {})
    self:logD("readSettings: Settings loaded from", settings_file)
    return rd_settings
end

-- Helper function to build URL query strings from a table
function Readeck:buildQueryString(params)
    if not params or not next(params) then
        return "" -- Return empty string if no parameters
    end
    local parts = {}
    -- Ensure socket.url is loaded for escaping
    local url_escape = require("socket.url").escape
    for key, value in pairs(params) do
        -- URL-encode both key and value
        table.insert(parts, url_escape(tostring(key)) .. "=" .. url_escape(tostring(value)))
    end
    return "?" .. table.concat(parts, "&")
end

--- Handler for AddReadeckArticle event.
-- Adds article URL to Readeck immediately if online, otherwise queues it.
function Readeck:onAddReadeckArticle(article_url)
    if not NetworkMgr:isOnline() then
        self:logI("onAddReadeckArticle: Network offline. Adding URL to queue:", article_url)
        self:addToOfflineQueue(article_url)
        UIManager:show(InfoMessage:new{
            text = T(_("Offline. Article will be added to Readeck in the next sync:\n%1"), BD.url(article_url)),
            timeout = 3,
        })
        return false -- Indicate queuing
    end

    -- Try to add immediately
    self:logI("onAddReadeckArticle: Network online. Attempting to add URL:", article_url)
    local info = InfoMessage:new{ text = _("Adding article to Readeck…")}
    UIManager:show(info)
    UIManager:forceRePaint()

    if self:addArticle(article_url) then
        UIManager:close(info)
        UIManager:show(InfoMessage:new{
            text = T(_("Article added request sent to Readeck:\n%1"), BD.url(article_url)),
            timeout = 3, -- Show success message longer
        })
        return true -- Indicate success/sent
    else
        -- Error message likely shown by addArticle/callAPI
        UIManager:close(info)
        -- Optionally show a generic failure message here too
        UIManager:show(InfoMessage:new{
             text = T(_("Error adding link to Readeck:\n%1"), BD.url(article_url)),
        })
        return false -- Indicate failure
    end
end

--- Handler for SynchronizeReadeck event.
function Readeck:onSynchronizeReadeck()
    local connect_callback = function()
        self:logI("onSynchronizeReadeck: Network online, starting synchronization...")
        local success = self:downloadArticles()
        if success then
            self:logI("onSynchronizeReadeck: Synchronization process completed.")
            self:refreshFileManager()
        else
             self:logE("onSynchronizeReadeck: Synchronization process failed or was interrupted.")
        end
    end

    -- Check network and run callback when online
    NetworkMgr:runWhenOnline(connect_callback)
    return true -- Event handled
end

--- Handler for UploadReadeckQueue event.
function Readeck:onUploadReadeckQueue()
    local connect_callback = function()
        self:logI("onUploadReadeckQueue: Network online, uploading queue...")
        self:uploadQueue(false) -- false = show summary message
        self:refreshFileManager() -- Refresh in case new items were added and downloaded in a previous sync
    end

    NetworkMgr:runWhenOnline(connect_callback)
    return true -- Event handled
end

--- Handler for UploadReadeckStatuses event.
function Readeck:onUploadReadeckStatuses()
    local connect_callback = function()
        self:logI("onUploadReadeckStatuses: Network online, uploading statuses...")
        self:uploadStatuses(false) -- false = show summary message
        self:refreshFileManager() -- Refresh in case local files were deleted/archived
    end

    NetworkMgr:runWhenOnline(connect_callback)
    return true -- Event handled
end

--- Handler for GoToReadeckDirectory event.
function Readeck:onGoToReadeckDirectory()
    if not self.directory or self.directory == "" then
         UIManager:show(InfoMessage:new{ text = _("Download directory not configured.") })
         self:setDownloadDirectory() -- Prompt user to set it
         return false
    end

    if self.ui.document then
        self:logD("onGoToReadeckDirectory: Closing current document.")
        self.ui:onClose() -- Close reader if open
    end

    if FileManager.instance then
        self:logD("onGoToReadeckDirectory: Opening directory in existing file manager:", self.directory)
        FileManager.instance:reinit(self.directory)
    else
        self:logD("onGoToReadeckDirectory: Showing directory in new file manager instance:", self.directory)
        FileManager:showFiles(self.directory)
    end
    return true -- Event handled
end

--- Get percent read of the currently opened document.
-- @treturn number Percentage (0.0 to 1.0) or nil if not applicable.
function Readeck:getLastPercentRead()
    if not self.ui or not self.ui.document then return nil end
    local percent = self.ui.paging and self.ui.paging:getLastPercent() or (self.ui.rolling and self.ui.rolling:getLastPercent())
    -- self:logD("getLastPercentRead: Current read percent:", percent)
    return percent -- Returns nil if neither paging nor rolling available
end

--- Add a URL to the offline queue for later upload.
-- @param string article_url The URL to queue.
function Readeck:addToOfflineQueue(article_url)
    if not article_url or article_url == "" then return end
    -- Initialize queue if it doesn't exist
    self.offline_queue = self.offline_queue or {}
    -- Avoid adding duplicates? Optional.
    -- for _, existing_url in ipairs(self.offline_queue) do
    --     if existing_url == article_url then return end -- Already queued
    -- end
    table.insert(self.offline_queue, article_url)
    self:saveSettings()
    self:logI("addToOfflineQueue: Added URL to offline queue:", article_url, "Queue size:", #self.offline_queue)
end

--- Check if the closed document should be removed from history based on settings and status.
-- Called by onCloseDocument event handler.
-- @param string path Full path of the document that was closed.
-- @param string status Reading status ("complete", "abandoned", etc.).
-- @param number percent_finished Reading percentage (0.0 to 1.0).
function Readeck:handleHistoryRemoval(path, status, percent_finished)
    local should_remove = false
    status = status or "new"
    percent_finished = percent_finished or 0

    if self.remove_finished_from_history and status == "complete" then
        should_remove = true
        self:logD("handleHistoryRemoval: Removing finished article from history:", path)
    elseif self.remove_read_from_history and percent_finished >= 0.995 then -- Consider 100% read
        should_remove = true
        self:logD("handleHistoryRemoval: Removing 100% read article from history:", path)
    elseif self.remove_abandoned_from_history and status == "abandoned" then
        should_remove = true
        self:logD("handleHistoryRemoval: Removing abandoned article from history:", path)
    end

    if should_remove then
        local removed = ReadHistory:removeItemByPath(path)
        if removed then
            self:logI("handleHistoryRemoval: Successfully removed article from history:", path)
            -- Optionally, update last directory if needed, similar to Wallabag plugin
            if self.directory and path:find(self.directory, 1, true) == 1 then
                self.ui:setLastDirForFileBrowser(self.directory)
            end
        else
            self:logW("handleHistoryRemoval: Failed to remove article from history (maybe not found?):", path)
        end
    end
end


--- Handler for the CloseDocument event.
-- Checks if the closed document is a Readeck article and if it meets criteria for history removal.
function Readeck:onCloseDocument(doc_path)
    -- Check if any history removal options are enabled first
    if not (self.remove_finished_from_history or self.remove_read_from_history or self.remove_abandoned_from_history) then
        return -- Nothing to do
    end
    -- Check if the closed document path and download directory are set
    if not doc_path or not self.directory or self.directory == "" then
         return
    end

    -- Check if the document is within the Readeck download directory
    if doc_path:find(self.directory, 1, true) == 1 then
        self:logD("onCloseDocument: Closed document is in Readeck directory:", doc_path)
        -- Get status and percent from doc_settings
        local doc_settings = DocSettings:open(doc_path)
        local summary = doc_settings:readSetting("summary")
        local status = summary and summary.status
        -- Use getLastPercentRead for potentially more up-to-date percentage than sidecar might have
        local percent_finished = self:getLastPercentRead() or doc_settings:readSetting("percent_finished") or 0

        self:handleHistoryRemoval(doc_path, status, percent_finished)
    end
end

return Readeck