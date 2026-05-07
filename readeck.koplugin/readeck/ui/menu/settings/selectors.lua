local BD = require("ui/bidi")
local NetworkMgr = require("ui/network/manager")
local RadioButtonWidget = require("ui/widget/radiobuttonwidget")
local UIManager = require("ui/uimanager")

local I18n = require("readeck.i18n")
local Log = require("readeck.core.log")

local Selectors = {}

function Selectors.install(Readeck, deps)
    local L = deps.L
    local T = deps.T

    function Readeck:getLanguageOverrideLabel()
        local language = self.language_override or ""
        if language == "" then
            return L("Follow KOReader language")
        end
        if language == "en" then
            return I18n.language_native_name("en")
        end
        if language == "zh-cn" then
            return I18n.language_native_name("zh-cn")
        end
        return language
    end

    function Readeck:setLanguageOverride(touchmenu_instance)
        local options = {
            { "", L("Follow KOReader language") },
            { "en", I18n.language_native_name("en") },
            { "zh-cn", I18n.language_native_name("zh-cn") },
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

    function Readeck:getLogLevelLabel()
        local level = Log:normalizeLevel(self.log_level)
        if level == "debug" then
            return L("Debug")
        end
        if level == "warn" then
            return L("Warnings")
        end
        if level == "error" then
            return L("Errors")
        end
        return L("Info")
    end

    function Readeck:setLogLevel(touchmenu_instance)
        local options = {
            { "error", L("Errors") },
            { "warn", L("Warnings") },
            { "info", L("Info") },
            { "debug", L("Debug") },
        }
        local current = Log:normalizeLevel(self.log_level)
        local radio_buttons = {}
        for _, option in ipairs(options) do
            table.insert(radio_buttons, {
                { text = option[2], provider = option[1], checked = current == option[1] },
            })
        end

        UIManager:show(RadioButtonWidget:new({
            title_text = L("Log level"),
            cancel_text = L("Cancel"),
            ok_text = L("Apply"),
            radio_buttons = radio_buttons,
            callback = function(radio)
                if radio then
                    self.log_level = Log:setLevel(radio.provider)
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

    function Readeck:getHighlightFeaturePolicyLabel()
        local policy = self.highlight_feature_policy or "auto"
        if policy == "modern" then
            return L("Modern Readeck (0.22.2+)")
        end
        if policy == "legacy" then
            return L("Legacy Readeck (before 0.22.2)")
        end
        return L("Auto-detect from server")
    end

    function Readeck:setHighlightFeaturePolicy(touchmenu_instance)
        local options = {
            {
                "auto",
                L("Auto-detect from server"),
                L("Fetch /api/info and use the Readeck server version/features."),
            },
            {
                "modern",
                L("Modern Readeck (0.22.2+)"),
                L("Always sync highlight notes and transparent color."),
            },
            {
                "legacy",
                L("Legacy Readeck (before 0.22.2)"),
                L("Do not send highlight notes or transparent color."),
            },
        }
        local radio_buttons = {}
        for _, option in ipairs(options) do
            table.insert(radio_buttons, {
                {
                    text = option[2],
                    provider = option[1],
                    checked = (self.highlight_feature_policy or "auto") == option[1],
                    info_text = option[3],
                },
            })
        end

        UIManager:show(RadioButtonWidget:new({
            title_text = L("Readeck server features"),
            cancel_text = L("Cancel"),
            ok_text = L("Apply"),
            radio_buttons = radio_buttons,
            callback = function(radio)
                if radio then
                    self.highlight_feature_policy = radio.provider
                    if self.highlight_feature_policy == "auto" then
                        NetworkMgr:runWhenOnline(function()
                            self:refreshServerInfo(true, true)
                        end)
                    end
                    self:saveSettings()
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end
            end,
        }))
    end

    function Readeck:getHighlightSyncPolicyLabel()
        if self.highlight_sync_policy == "respect_remote_deletions" then
            return L("Respect remote deletions")
        end
        return L("Preserve local highlights")
    end

    function Readeck:setHighlightSyncPolicy(touchmenu_instance)
        local options = {
            {
                "preserve_local",
                L("Preserve local highlights"),
                L("Remote-deleted highlights may be restored to Readeck. This is safest for avoiding data loss."),
            },
            {
                "respect_remote_deletions",
                L("Respect remote deletions"),
                L("Highlights deleted in Readeck stay local in KOReader but are not re-uploaded."),
            },
        }
        local radio_buttons = {}
        for _, option in ipairs(options) do
            table.insert(radio_buttons, {
                {
                    text = option[2],
                    provider = option[1],
                    checked = (self.highlight_sync_policy or "preserve_local") == option[1],
                    info_text = option[3],
                },
            })
        end

        UIManager:show(RadioButtonWidget:new({
            title_text = L("Highlight sync conflict policy"),
            cancel_text = L("Cancel"),
            ok_text = L("Apply"),
            radio_buttons = radio_buttons,
            callback = function(radio)
                if radio then
                    self.highlight_sync_policy = radio.provider
                    self:saveSettings()
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end
            end,
        }))
    end

    function Readeck:getHighlightConflictPolicyLabel()
        local policy = self.highlight_conflict_policy or "merge"
        if policy == "remote_wins" then
            return L("Readeck overwrites KOReader")
        end
        if policy == "local_wins" then
            return L("KOReader overwrites Readeck")
        end
        return L("Merge local and remote changes")
    end

    function Readeck:setHighlightConflictPolicy(touchmenu_instance)
        local options = {
            {
                "merge",
                L("Merge local and remote changes"),
                L(
                    "Use the last synced state to merge note/color edits and preserve both notes when both sides changed."
                ),
            },
            {
                "remote_wins",
                L("Readeck overwrites KOReader"),
                L("Remote note and color changes replace the linked KOReader highlight."),
            },
            {
                "local_wins",
                L("KOReader overwrites Readeck"),
                L("Local note and color changes replace the linked Readeck annotation."),
            },
        }
        local radio_buttons = {}
        for _, option in ipairs(options) do
            table.insert(radio_buttons, {
                {
                    text = option[2],
                    provider = option[1],
                    checked = (self.highlight_conflict_policy or "merge") == option[1],
                    info_text = option[3],
                },
            })
        end

        UIManager:show(RadioButtonWidget:new({
            title_text = L("Highlight update strategy"),
            cancel_text = L("Cancel"),
            ok_text = L("Apply"),
            radio_buttons = radio_buttons,
            callback = function(radio)
                if radio then
                    self.highlight_conflict_policy = radio.provider
                    self:saveSettings()
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end
            end,
        }))
    end

    function Readeck:buildServerSettingsMenuItems()
        return {
            {
                text_func = function()
                    local server = self.server_url
                    if not server or server == "" then
                        server = L("Not set")
                    end
                    return T(L("Server URL: %1"), BD.url(server))
                end,
                keep_menu_open = true,
                callback = function()
                    self:editServerSettings()
                end,
            },
            {
                text_func = function()
                    return T(L("Readeck server features: %1"), Readeck.getHighlightFeaturePolicyLabel(self))
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    Readeck.setHighlightFeaturePolicy(self, touchmenu_instance)
                end,
            },
        }
    end
end

return Selectors
