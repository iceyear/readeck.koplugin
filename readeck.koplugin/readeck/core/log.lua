local logger = require("logger")

local Log = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4,
    level = 2,
}

local level_values = {
    debug = Log.DEBUG,
    info = Log.INFO,
    warn = Log.WARN,
    error = Log.ERROR,
}

local level_names = {
    [Log.DEBUG] = "debug",
    [Log.INFO] = "info",
    [Log.WARN] = "warn",
    [Log.ERROR] = "error",
}

function Log:normalizeLevel(level)
    if type(level) == "number" then
        return level_names[level] or "info"
    end
    level = tostring(level or ""):lower()
    return level_values[level] and level or "info"
end

function Log:setLevel(level)
    local normalized = self:normalizeLevel(level)
    self.level = level_values[normalized]
    return normalized
end

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

return Log
