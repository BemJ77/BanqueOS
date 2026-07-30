local updater = {}

local filesystem = require("core.filesystem")
local checksum = require("core.checksum")
local settings = require("config.settings")
local logger = require("core.logger")

local STARTUP_PATH = "/startup"

local function installDate()
    if os.date then return os.date("%Y-%m-%d %H:%M:%S") end
    return tostring(os.epoch and os.epoch("utc") or os.clock())
end

local function verifyCopy(file)
    local sourceHash, sourceError = checksum.file(file.sourcePath)
    local destinationHash, destinationError = checksum.file(file.destinationPath)

    if not sourceHash or not destinationHash then
        return false, sourceError or destinationError
    end

    if sourceHash ~= destinationHash then
        return false, "Empreinte differente apres copie"
    end

    return true, destinationHash
end

function updater.run(package, marker, managerVersion, onProgress)
    local regular = {}
    local startup = nil

    for _, file in ipairs(package.rawFiles) do
        if file.destinationPath == STARTUP_PATH then
            startup = file
        else
            regular[#regular + 1] = file
        end
    end

    local result = {
        success = false,
        copied = 0,
        removed = 0,
        total = package.fileCount,
        errors = {}
    }

    if not startup then
        result.errors[1] = "Le paquet ne contient pas de fichier /startup"
        return result
    end

    local newPaths = {}
    local installedFiles = {}
    local installedChecksums = {}

    for _, file in ipairs(package.rawFiles) do
        newPaths[file.destinationPath] = true
    end

    -- Supprime uniquement les anciens fichiers geres qui n'existent plus.
    for _, path in ipairs(marker.files or {}) do
        if path ~= STARTUP_PATH and not newPaths[path] and fs.exists(path) then
            local ok, err = pcall(fs.delete, path)
            if ok and not fs.exists(path) then
                result.removed = result.removed + 1
                logger.info("Ancien fichier supprime : " .. path)
            else
                result.errors[#result.errors + 1] = path .. " : " .. tostring(err)
            end
        end
    end

    if #result.errors > 0 then return result end

    for _, file in ipairs(regular) do
        if onProgress then
            onProgress(result.copied, result.total, file.displayPath, "Mise a jour")
        end

        logger.info("SOURCE      : " .. file.sourcePath)
        logger.info("DESTINATION : " .. file.destinationPath)
        local ok, err = filesystem.copyFile(file.sourcePath, file.destinationPath)
        local hash = nil
        if ok then 
            ok, hash = verifyCopy(file)
            logger.info("COPIE OK : " .. file.destinationPath)
         end

        if ok then
            result.copied = result.copied + 1
            installedFiles[#installedFiles + 1] = file.destinationPath
            installedChecksums[file.destinationPath] = hash
        else
            logger.error("ECHEC COPIE : " .. tostring(err))
            result.errors[#result.errors + 1] = file.destinationPath .. " : " .. tostring(hash or err)
        end
    end

    if #result.errors > 0 then return result end

    if onProgress then
        onProgress(result.copied, result.total, startup.displayPath, "Remplacement du startup")
    end

    local ok, err = filesystem.copyFile(startup.sourcePath, STARTUP_PATH)
    local hash = nil
    if ok then
        local checkFile = { sourcePath = startup.sourcePath, destinationPath = STARTUP_PATH }
        ok, hash = verifyCopy(checkFile)
    end

    if not ok then
        result.errors[#result.errors + 1] = STARTUP_PATH .. " : " .. tostring(hash or err)
        return result
    end

    result.copied = result.copied + 1
    installedFiles[#installedFiles + 1] = STARTUP_PATH
    installedChecksums[STARTUP_PATH] = hash

    local newMarker = {
        schema = 2,
        id = package.id,
        name = package.name,
        version = package.version,
        installDate = marker.installDate,
        updateDate = installDate(),
        manager = managerVersion,
        startup = STARTUP_PATH,
        files = installedFiles,
        checksums = installedChecksums
    }

    local markerOk, markerError = filesystem.writeTable(settings.markerPath, newMarker)
    if not markerOk then
        result.errors[#result.errors + 1] = "Marqueur : " .. tostring(markerError)
    end

    result.success = result.copied == result.total and #result.errors == 0

    if onProgress then
        onProgress(
            result.copied,
            result.total,
            result.success and "Mise a jour terminee" or "Mise a jour incomplete",
            "Termine"
        )
    end

    return result
end

return updater
