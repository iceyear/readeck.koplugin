local logger = require("logger")

local Log = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4,
    level = 1,
}

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
