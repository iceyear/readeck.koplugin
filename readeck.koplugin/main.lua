--[[--
@module koplugin.readeck
]]

local FFIUtil = require("ffi/util")
local I18n = require("readeck.i18n")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local AnnotationExport = require("readeck.annotations.export")
local Articles = require("readeck.sync.articles")
local Client = require("readeck.net.client")
local Defaults = require("readeck.core.defaults")
local Downloads = require("readeck.sync.downloads")
local Events = require("readeck.ui.events")
local Helpers = require("readeck.core.helpers")
local LocalActions = require("readeck.sync.local_actions")
local Log = require("readeck.core.log")
local Menu = require("readeck.ui.menu")
local OAuth = require("readeck.auth.oauth")
local Periodic = require("readeck.sync.periodic")
local SettingsStorage = require("readeck.storage.settings")
local SettingsUI = require("readeck.ui.settings")
local State = require("readeck.core.state")
local StatusMessages = require("readeck.ui.status_messages")

local T = FFIUtil.template
local L = I18n.with_gettext(_, function()
    return G_reader_settings
end)

local plugin_source = debug.getinfo(1, "S").source:gsub("^@", "")
local plugin_dir = plugin_source:match("^(.*)[/\\][^/\\]+$") or "."
local PluginMetadata = dofile(plugin_dir .. "/_meta.lua")

local Readeck = WidgetContainer:extend({
    name = "readeck",
})

local deps = {
    L = L,
    T = T,
    Log = Log,
    article_id_suffix = Defaults.ARTICLE_ID_SUFFIX,
    article_id_postfix = Defaults.ARTICLE_ID_POSTFIX,
    failed = Defaults.DOWNLOAD_FAILED,
    skipped = Defaults.DOWNLOAD_SKIPPED,
    downloaded = Defaults.DOWNLOAD_DONE,
    OAUTH_DEVICE_GRANT = Defaults.OAUTH_DEVICE_GRANT,
    DEFAULT_OAUTH_SCOPES = Defaults.DEFAULT_OAUTH_SCOPES,
    PLUGIN_VERSION = PluginMetadata.version,
}

Helpers.install(Readeck, deps)
StatusMessages.install(Readeck, deps)
SettingsStorage.install(Readeck, deps)
Client.install(Readeck, deps)
OAuth.install(Readeck, deps)
Downloads.install(Readeck, deps)
LocalActions.install(Readeck, deps)
Articles.install(Readeck, deps)
Periodic.install(Readeck, deps)
AnnotationExport.install(Readeck, deps)
Menu.install(Readeck, deps)
SettingsUI.install(Readeck, deps)
Events.install(Readeck, deps)
State.install(Readeck, deps)

return Readeck
