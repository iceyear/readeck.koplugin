--[[--
Readeck plugin loader.

@module koplugin.readeck.init
]]

local Plugin = require("plugin")
local DataStorage = require("datastorage")

local ReadeckPlugin = Plugin:new{
    name = "Readeck",
    version = "1.1.0", -- Initial version based on Wallabag structure
    -- Git commit hash can be added here later if versioning via Git
    -- commit = "abcdef1",
    description = _("Synchronize read-it-later articles with a Readeck server."),
    -- Add authors based on Wallabag plugin + your adaptation
    authors = {"Olivier Meunier", "Wallabag plugin authors", "[Your Name/Alias]"},
    -- Link to Readeck or the plugin's repository if available
    -- website = "https://github.com/user/koreader-readeck",
    -- Specify dependencies if any beyond standard KOReader modules
    -- depends = {},
}

function ReadeckPlugin:init()
    -- Check if required modules are available (optional but good practice)
    local json_ok, _ = pcall(require, "json")
    local socket_ok, _ = pcall(require, "socket.http")
    if not (json_ok and socket_ok) then
        self.disabled = true
        self.reason = "Missing required Lua libraries (json, luasocket)."
        return
    end

    -- Load the main plugin logic
    local Readeck = require("koplugin/readeck/main")
    self.readeck = Readeck:new{ ui = self.ui }

    -- Check if MultiInputDialog loaded correctly
    local mid_ok, _ = pcall(require, "ui/widget/multiinputdialog")
    if not mid_ok then
         self.disabled = true
         self.reason = "Failed to load MultiInputDialog widget."
         self.readeck = nil -- Clean up partially initialized object
         return
    end

    -- Add plugin to DataStorage update checks if needed (e.g., for settings migration)
    -- DataStorage:registerPluginForUpdate(self)
end

-- Optional: Handle plugin updates (e.g., migrating settings)
-- function ReadeckPlugin:onPluginUpdate(old_version)
--     if old_version < Version:new("1.0.0") then
--         -- Migrate settings if needed
--     end
--     return true -- Indicate update was handled
-- end

return ReadeckPlugin