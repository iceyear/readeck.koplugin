local UIManager = require("ui/uimanager")

local ProgressMessage = {}

local function call_method(object, name, ...)
    if type(object) ~= "table" or type(object[name]) ~= "function" then
        return false
    end
    return pcall(object[name], object, ...)
end

local function get_moved_offset(info)
    if type(info) ~= "table" or type(info.movable) ~= "table" then
        return nil
    end
    if type(info.movable.getMovedOffset) ~= "function" then
        return nil
    end
    local ok, offset = pcall(info.movable.getMovedOffset, info.movable)
    if ok then
        return offset
    end
    return nil
end

local function restore_moved_offset(info, offset)
    if not offset or type(info) ~= "table" or type(info.movable) ~= "table" then
        return
    end
    if type(info.movable.setMovedOffset) == "function" then
        pcall(info.movable.setMovedOffset, info.movable, offset)
    end
end

function ProgressMessage.update(info, text)
    if type(info) ~= "table" or type(text) ~= "string" then
        return false
    end
    if info.text == text then
        return true
    end
    if type(info.free) ~= "function" or type(info.init) ~= "function" then
        return false
    end

    local offset = get_moved_offset(info)
    local ok = pcall(function()
        info.text = text
        info:free()
        info.dimen = nil
        info[1] = nil
        info:init()
        restore_moved_offset(info, offset)
    end)
    if not ok then
        return false
    end

    if type(UIManager.setDirty) == "function" then
        UIManager:setDirty("all", "ui")
    end
    call_method(UIManager, "forceRePaint")
    return true
end

return ProgressMessage
