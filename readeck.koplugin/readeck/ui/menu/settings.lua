local Dialogs = require("readeck.ui.menu.settings.dialogs")
local Items = require("readeck.ui.menu.settings.items")
local Selectors = require("readeck.ui.menu.settings.selectors")

local SettingsMenu = {}

function SettingsMenu.install(Readeck, deps)
    Selectors.install(Readeck, deps)
    Dialogs.install(Readeck, deps)
    Items.install(Readeck, deps)
end

return SettingsMenu
