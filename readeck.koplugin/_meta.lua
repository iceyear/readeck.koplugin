local _ = require("gettext")
local Defaults = require("readeck.core.defaults")
local L = require("readeck.i18n").with_gettext(_, function()
    return G_reader_settings
end)
return {
    name = "readeck",
    version = Defaults.PLUGIN_VERSION,
    fullname = L("Readeck"),
    description = L([[Synchronises articles with a Readeck server.]]),
}
