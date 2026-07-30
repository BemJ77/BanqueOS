local repair = {}

local filesystem = require("core.filesystem")
local checksum = require("core.checksum")
local logger = require("core.logger")

local STARTUP_PATH = "/startup"

local function verifyCopy(file)
    local sourceHash, sourceError = checksum.file(file.sourcePath)
    local destinationHash, destinationError = checksum.file(file.destinationPath)

    if not sourceHash or not destinationHash then
        return false, sourceError or destinationError
    end

    if sourceHash ~= destinationHash then
        return false, "Empreinte differente apres copie"
    end

    return true
end

function repair.run(package, verification, onProgress)
    local broken = {}
    local brokenPaths = {}

    for _, path in ipairs(verification.missing or {}) do
        brokenPaths[path] = true
    end

    for _, path in ipairs(verification.modified or {}) do
        brokenPaths[path] = true
    end

    local startupFile = nil

    for _, file in ipairs(package.rawFiles) do
        if brokenPaths[file.destinationPath] then
            if file.destinationPath == STARTUP_PATH then
                startupFile = file
            else
                broken[#broken + 1] = file
            end
        end
    end

    if startupFile then
        broken[#broken + 1] = startupFile
    end

    local result = {
        success = false,
        repaired = 0,
        total = #broken,
        errors = {}
    }

    for index, file in ipairs(broken) do
        if onProgress then
            onProgress(index - 1, result.total, file.displayPath, "Reparation")
        end

        local ok, err = filesystem.copyFile(file.sourcePath, file.destinationPath)

        if ok then
            ok, err = verifyCopy(file)
        end

        if ok then
            result.repaired = result.repaired + 1
            logger.info("Fichier repare : " .. file.destinationPath)
        else
            local message = file.destinationPath .. " : " .. tostring(err)
            result.errors[#result.errors + 1] = message
            logger.error(message)
        end
    end

    result.success = result.repaired == result.total and #result.errors == 0

    if onProgress then
        onProgress(
            result.repaired,
            result.total,
            result.success and "Reparation terminee" or "Reparation incomplete",
            "Termine"
        )
    end

    return result
end

return repair
