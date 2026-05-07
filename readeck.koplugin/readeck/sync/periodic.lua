local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")

local Periodic = {}

function Periodic.install(Readeck, deps)
    local Log = deps.Log

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
end

return Periodic
