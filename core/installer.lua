local installer = {}

local filesystem = require("core.filesystem")
local logger = require("core.logger")
local settings = require("config.settings")
local version = require("core.version")
local checksum = require("core.checksum")
local installed = require("core.installed")

local STARTUP_PATH = "/startup"

local function installDate()
    if os.date then
        return os.date("%Y-%m-%d %H:%M:%S")
    end

    return tostring(os.epoch and os.epoch("utc") or os.clock())
end

local function isStartupFile(file)
    return file.destinationPath == STARTUP_PATH
end

local function verifyCopiedFile(file)
    if not fs.exists(file.destinationPath)
        or fs.isDir(file.destinationPath) then
        return false, "Le fichier copie est introuvable"
    end

    local sourceHash, sourceError = checksum.file(file.sourcePath)
    local destinationHash, destinationError =
        checksum.file(file.destinationPath)

    if not sourceHash or not destinationHash then
        return false, sourceError or destinationError
    end

    if sourceHash ~= destinationHash then
        return false, "Empreinte differente apres copie"
    end

    return true, destinationHash
end

function installer.checkCompatibility(package, managerVersion)
    if not version.isAtLeast(managerVersion, package.minManager) then
        return false,
            "Manager "
            .. package.minManager
            .. " minimum requis"
    end

    return true
end

function installer.canInstall(package)
    local state = installed.getState(package)

    if state.sameVersion then
        return false, "Cette version est deja installee"
    end

    if state.installed and not state.samePackage then
        return false,
            "Un autre paquet est deja installe : "
            .. tostring(state.marker.id)
    end

    return true
end

function installer.install(package, managerVersion, onProgress)
    local result = {
        success = false,
        copied = 0,
        total = package.fileCount,
        errors = {}
    }

    logger.info(
        "Debut installation "
        .. package.id
        .. " "
        .. package.version
    )

    local compatible, compatibilityError =
        installer.checkCompatibility(package, managerVersion)

    if not compatible then
        result.errors[#result.errors + 1] = compatibilityError
        logger.error(compatibilityError)
        return result
    end

    local allowed, installError = installer.canInstall(package)

    if not allowed then
        result.errors[#result.errors + 1] = installError
        logger.warn(installError)
        return result
    end

    local regularFiles = {}
    local startupFile = nil

    for _, file in ipairs(package.rawFiles) do
        if isStartupFile(file) then
            startupFile = file
        else
            regularFiles[#regularFiles + 1] = file
        end
    end

    if not startupFile then
        local message =
            "Le paquet ne contient pas de fichier /startup"

        result.errors[#result.errors + 1] = message
        logger.error(message)
        return result
    end

    local installedFiles = {}
    local installedChecksums = {}

    -- Tous les fichiers metier sont copies avant de toucher au startup.
    for _, file in ipairs(regularFiles) do
        if onProgress then
            onProgress(
                result.copied,
                result.total,
                file.displayPath,
                "Copie des fichiers"
            )
        end

        local ok, err = filesystem.copyFile(
            file.sourcePath,
            file.destinationPath
        )

        local copiedHash = nil

        if ok then
            ok, copiedHash = verifyCopiedFile(file)

            if not ok then
                err = copiedHash
                copiedHash = nil
            end
        end

        if ok then
            result.copied = result.copied + 1
            installedFiles[#installedFiles + 1] =
                file.destinationPath
            installedChecksums[file.destinationPath] =
                copiedHash

            logger.info(
                "Copie verifiee : " .. file.destinationPath
            )
        else
            local message =
                file.destinationPath .. " : " .. tostring(err)

            result.errors[#result.errors + 1] = message
            logger.error(message)
        end
    end

    -- En cas d'echec, le startup du Manager est conserve.
    if #result.errors > 0
        or result.copied ~= #regularFiles then

        logger.error(
            "Installation interrompue avant remplacement du startup"
        )

        if onProgress then
            onProgress(
                result.copied,
                result.total,
                "Startup du Manager conserve",
                "Installation interrompue"
            )
        end

        return result
    end

    -- Le startup du role remplace celui du Manager en derniere copie.
    if onProgress then
        onProgress(
            result.copied,
            result.total,
            startupFile.displayPath,
            "Remplacement du startup"
        )
    end

    local startupOk, startupError =
        filesystem.copyFile(
            startupFile.sourcePath,
            STARTUP_PATH
        )

    local startupHash = nil

    if startupOk then
        local startupForVerification = {
            sourcePath = startupFile.sourcePath,
            destinationPath = STARTUP_PATH
        }

        startupOk, startupHash =
            verifyCopiedFile(startupForVerification)

        if not startupOk then
            startupError = startupHash
            startupHash = nil
        end
    end

    if not startupOk then
        local message =
            STARTUP_PATH .. " : " .. tostring(startupError)

        result.errors[#result.errors + 1] = message
        logger.error(message)
        return result
    end

    result.copied = result.copied + 1
    installedFiles[#installedFiles + 1] = STARTUP_PATH
    installedChecksums[STARTUP_PATH] = startupHash

    logger.info("Startup du paquet installe : " .. STARTUP_PATH)

    local marker = {
        schema = 2,
        id = package.id,
        name = package.name,
        version = package.version,
        installDate = installDate(),
        manager = managerVersion,
        startup = STARTUP_PATH,
        files = installedFiles,
        checksums = installedChecksums
    }

    local markerOk, markerError =
        filesystem.writeTable(settings.markerPath, marker)

    if not markerOk then
        local message =
            "Marqueur d'installation : "
            .. tostring(markerError)

        result.errors[#result.errors + 1] = message
        logger.error(message)
    end

    result.success =
        result.copied == result.total
        and #result.errors == 0

    if onProgress then
        onProgress(
            result.copied,
            result.total,
            result.success
                and "Installation terminee"
                or "Installation terminee avec erreurs",
            "Termine"
        )
    end

    if result.success then
        logger.info(
            "Installation reussie : "
            .. tostring(result.copied)
            .. " fichier(s)"
        )
    else
        logger.error(
            "Installation incomplete : "
            .. tostring(result.copied)
            .. "/"
            .. tostring(result.total)
        )
    end

    return result
end

return installer
