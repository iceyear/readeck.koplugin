local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")

local Dialogs = {}

function Dialogs.install(Readeck, deps)
    local L = deps.L
    local T = deps.T
    local PLUGIN_VERSION = deps.PLUGIN_VERSION or L("unknown")

    function Readeck:confirmResetSettings(touchmenu_instance)
        UIManager:show(ConfirmBox:new({
            text = L([[Restore all Readeck settings to defaults?

This will clear the server URL, API token, OAuth tokens, download queue, and sync options.]]),
            ok_text = L("Restore"),
            ok_callback = function()
                self:resetSettingsToDefaults()
                if touchmenu_instance then
                    touchmenu_instance:updateItems()
                end
                UIManager:show(InfoMessage:new({
                    text = L("Readeck settings restored to defaults."),
                }))
            end,
        }))
    end

    function Readeck:showHelpDialog()
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
    end

    function Readeck:showAboutDialog()
        UIManager:show(InfoMessage:new({
            text = T(
                L([[Readeck for KOReader
Version: %1
License: MIT
Source: https://github.com/iceyear/readeck.koplugin

Synchronises articles with a Readeck server.

More details: https://readeck.org]]),
                PLUGIN_VERSION
            ),
        }))
    end
end

return Dialogs
