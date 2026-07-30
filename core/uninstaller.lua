local uninstaller = {}

local filesystem = require("core.filesystem")
local settings = require("config.settings")
local logger = require("core.logger")

local MANAGER_STARTUP = [[shell.run("/manager.lua")
]]

local function writeManagerStartup()
    local handle = fs.open("/startup", "w")

    if not handle then
        return false, "Impossible d'ecrire /startup"
    end

    handle.write(MANAGER_STARTUP)
    handle.close()
    return true
end

local function removeEmptyParents(path)
    local parent = fs.getDir(path)

    while parent ~= "" and parent ~= "/" do
        if not fs.exists(parent) or not fs.isDir(parent) then
            parent = fs.getDir(parent)
        elseif #fs.list(parent) == 0 then
            fs.delete(parent)
            parent = fs.getDir(parent)
        else
            break
        end
    end
end

function uninstaller.run(marker, onProgress)
    local managed = marker.files or {}
    local result = {
        success = false,
        removed = 0,
        total = #managed,
        errors = {}
    }

    -- /startup est traite en dernier afin que le Manager reste recuperable.
    local regular = {}
    local hasStartup = false

    for _, path in ipairs(managed) do
        if path == "/startup" then
            hasStartup = true
        else
            regular[#regular + 1] = path
        end
    end

    for index, path in ipairs(regular) do
        if onProgress then
            onProgress(index - 1, result.total, path, "Suppression")
        end

        if fs.exists(path) then
            local ok, err = pcall(fs.delete, path)
            if not ok or fs.exists(path) then
                result.errors[#result.errors + 1] = path .. " : " .. tostring(err)
            else
                result.removed = result.removed + 1
                removeEmptyParents(path)
                logger.info("Fichier supprime : " .. path)
            end
        else
            result.removed = result.removed + 1
        end
    end

    if #result.errors == 0 then
        local ok, err = writeManagerStartup()
        if ok then
            if hasStartup then result.removed = result.removed + 1 end
            logger.info("Startup du Manager restaure")
        else
            result.errors[#result.errors + 1] = tostring(err)
        end
    end

    if #result.errors == 0 and fs.exists(settings.markerPath) then
        local ok, err = pcall(fs.delete, settings.markerPath)
        if not ok or fs.exists(settings.markerPath) then
            result.errors[#result.errors + 1] =
                settings.markerPath .. " : " .. tostring(err)
        end
    end

    result.success = #result.errors == 0

    if onProgress then
        onProgress(
            result.removed,
            result.total,
            result.success and "Desinstallation terminee" or "Desinstallation incomplete",
            "Termine"
        )
    end

    return result
end

return uninstaller
