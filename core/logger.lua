local logger = {}

local settings = require("config.settings")

local function ensureParent(path)
    local parent = fs.getDir(path)

    if parent ~= "" and not fs.exists(parent) then
        fs.makeDir(parent)
    end
end

local function timestamp()
    if os.date then
        return os.date("%Y-%m-%d %H:%M:%S")
    end

    return tostring(os.epoch and os.epoch("utc") or os.clock())
end

function logger.write(level, message)
    ensureParent(settings.logPath)

    local handle = fs.open(settings.logPath, "a")

    if not handle then
        return false
    end

    handle.writeLine(
        "[" .. timestamp() .. "] "
        .. "[" .. tostring(level or "INFO") .. "] "
        .. tostring(message or "")
    )
    handle.close()

    return true
end

function logger.info(message)
    return logger.write("INFO", message)
end

function logger.warn(message)
    return logger.write("WARN", message)
end

function logger.error(message)
    return logger.write("ERROR", message)
end

return logger
