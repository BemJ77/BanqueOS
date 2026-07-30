local menu = require("ui.menu")
local progress = require("ui.progress")
local packageManager = require("core.packages")
local installer = require("core.installer")
local verifier = require("core.verifier")
local repair = require("core.repair")
local updater = require("core.updater")
local uninstaller = require("core.uninstaller")
local installed = require("core.installed")
local version = require("core.version")
local logger = require("core.logger")
local remote = require("core.remote")

local MANAGER_VERSION = "1.0.0"

local function showResult(title, success, current, total, errors)
    local lines = {
        success and "Operation reussie" or "Operation incomplete",
        "",
        tostring(current) .. " / " .. tostring(total) .. " fichier(s)",
        tostring(#errors) .. " erreur(s)"
    }
    if #errors > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = errors[1]
    end
    menu.message({ title = title, lines = lines })
end

local function askReboot(packageName)
    if menu.confirm({
        title = "REDEMARRAGE",
        subtitle = packageName .. " est pret",
        yesText = "Oui",
        noText = "Non"
    }) then
        os.reboot()
    end
end


local function refreshPackage(folder)
    local packages = packageManager.discover()
    for _, package in ipairs(packages) do
        if package.folder == folder then return package end
    end
end

local function downloadFullPackage(package)
    local result = remote.downloadPackage(package.folder, function(current, total, file, status)
        progress.draw(
            "TELECHARGEMENT " .. string.upper(package.name),
            current, total, file, status
        )
    end)

    if not result.success then
        menu.message({
            title = "TELECHARGEMENT IMPOSSIBLE",
            lines = { result.errors[1] or "Erreur inconnue" }
        })
        return nil
    end

    return refreshPackage(package.folder)
end

local function installPackage(package)
    local allowed, err = installer.canInstall(package)

    if not allowed then
        menu.message({
            title = "INSTALLATION IMPOSSIBLE",
            lines = { err }
        })
        return
    end

    local compatible, compatibilityError =
        installer.checkCompatibility(package, MANAGER_VERSION)

    if not compatible then
        menu.message({
            title = "INCOMPATIBLE",
            lines = { compatibilityError }
        })
        return
    end

    if not menu.confirm({
        title = "CONFIRMER L'INSTALLATION",
        subtitle = package.name .. " v" .. package.version,
        yesText = "Oui",
        noText = "Non"
    }) then
        return
    end

    package = downloadFullPackage(package)
    if not package then
        return
    end

    local result = installer.install(
        package,
        MANAGER_VERSION,
        function(current, total, file, status)
            progress.draw(
                "INSTALLATION " .. string.upper(package.name),
                current,
                total,
                file,
                status
            )
        end
    )

    sleep(0.4)

    showResult(
        "INSTALLATION",
        result.success,
        result.copied,
        result.total,
        result.errors
    )

    if result.success then
        askReboot(package.name)
    end
end

local function repairPackage(package, verification)
    if #verification.missing == 0 and #verification.modified == 0 then return end

    if not menu.confirm({
        title = "REPARATION",
        subtitle = "Reparer les fichiers detectes ?",
        yesText = "Oui",
        noText = "Non"
    }) then return end

    local result = repair.run(package, verification, function(current, total, file, status)
        progress.draw("REPARATION " .. string.upper(package.name), current, total, file, status)
    end)

    sleep(0.4)
    showResult("REPARATION", result.success, result.repaired, result.total, result.errors)
    if result.success then askReboot(package.name) end
end

local function verifyPackage(package)
    local state = installed.getState(package)
    if not state.samePackage then
        menu.message({ title = "VERIFICATION IMPOSSIBLE", lines = { "Ce paquet n'est pas installe" } })
        return
    end

    -- Recharge toujours le paquet complet avant la verification.
    -- Le catalogue seul ne supprime pas les anciens fichiers sources
    -- presents dans /packages/<paquet>/files apres une mise a jour majeure.
    -- Sans ce rafraichissement, le Manager peut verifier des fichiers
    -- retires du paquet actuel et les signaler a tort comme manquants.
    package = downloadFullPackage(package)
    if not package then
        return
    end

    local result = verifier.verify(package, function(current, total, file, status)
        progress.draw("VERIFICATION " .. string.upper(package.name), current, total, file, status)
    end)

    sleep(0.4)
    menu.message({
        title = result.valid and "INSTALLATION VALIDE" or "ANOMALIES DETECTEES",
        lines = {
            tostring(result.checked) .. " / " .. tostring(result.total) .. " fichiers verifies",
            "",
            "Manquants : " .. tostring(#result.missing),
            "Modifies : " .. tostring(#result.modified),
            "Erreurs : " .. tostring(#result.errors)
        }
    })

    if not result.valid and (#result.missing > 0 or #result.modified > 0) then
        repairPackage(package, result)
    end
end

local function changelogLines(package)
    local lines = {}
    for _, entry in ipairs(package.changelog or {}) do
        lines[#lines + 1] = "VERSION " .. tostring(entry.version)
        if entry.date then lines[#lines + 1] = tostring(entry.date) end
        for _, change in ipairs(entry.changes or {}) do
            lines[#lines + 1] = "- " .. tostring(change)
        end
        lines[#lines + 1] = ""
    end
    if #lines == 0 then lines[1] = "Aucun changelog disponible" end
    return lines
end

local function updatePackage(package)
    local state = installed.getState(package)
    if not state.samePackage then
        menu.message({ title = "MISE A JOUR", lines = { "Ce paquet n'est pas installe" } })
        return
    end

    while true do
        local updateAvailable = version.compare(package.version, state.marker.version) > 0
        local items = {}
        if updateAvailable then items[#items + 1] = "Mettre a jour" end
        items[#items + 1] = "Changelog"
        items[#items + 1] = "Retour"

        local choice = menu.select({
            title = "MISE A JOUR " .. string.upper(package.name),
            subtitle = "Actuelle " .. tostring(state.marker.version) .. "  |  Disponible " .. package.version,
            items = items
        })

        if choice == #items then return end

        if updateAvailable and choice == 1 then
            if menu.confirm({
                title = "CONFIRMER LA MISE A JOUR",
                subtitle = tostring(state.marker.version) .. " -> " .. package.version,
                yesText = "Oui",
                noText = "Non"
            }) then
                package = downloadFullPackage(package)
                if not package then return end

                local result = updater.run(
                    package,
                    state.marker,
                    MANAGER_VERSION,
                    function(current, total, file, status)
                        progress.draw(
                            "MISE A JOUR " .. string.upper(package.name),
                            current,
                            total,
                            file,
                            status
                        )
                    end
                )

                sleep(0.4)
                showResult("MISE A JOUR", result.success, result.copied, result.total, result.errors)

                if result.success then
                    askReboot(package.name)
                    return
                end
            end
        else
            menu.list({
                title = "CHANGELOG " .. string.upper(package.name),
                subtitle = "Derniere version : " .. package.version,
                items = changelogLines(package)
            })
        end
    end
end

local function uninstallPackage(package)
    local state = installed.getState(package)
    if not state.samePackage then
        menu.message({ title = "DESINSTALLATION", lines = { "Ce paquet n'est pas installe" } })
        return
    end

    if not menu.confirm({
        title = "CONFIRMER LA DESINSTALLATION",
        subtitle = package.name .. "  v" .. tostring(state.marker.version),
        yesText = "Oui",
        noText = "Non"
    }) then return end

    local result = uninstaller.run(state.marker, function(current, total, file, status)
        progress.draw("DESINSTALLATION " .. string.upper(package.name), current, total, file, status)
    end)

    sleep(0.4)
    showResult("DESINSTALLATION", result.success, result.removed, result.total, result.errors)
    if result.success then askReboot("Manager") end
end

local function showInformation(package)
    local state = installed.getState(package)
    local installedVersion = state.samePackage and tostring(state.marker.version) or "Non installe"
    menu.message({
        title = "INFORMATIONS",
        lines = {
            "Nom : " .. tostring(package.name),
            "ID : " .. tostring(package.id),
            "Auteur : " .. tostring(package.author),
            "Categorie : " .. tostring(package.category),
            "Version installee : " .. installedVersion,
            "Version disponible : " .. tostring(package.version),
            "Fichiers : " .. tostring(package.fileCount),
            "Taille : " .. packageManager.formatSize(package.totalSize),
            "",
            tostring(package.description or "")
        }
    })
end

local function packageActions(package)
    while true do
        local state = installed.getState(package)
        local actions, handlers = {}, {}

        if not state.installed then
            actions[#actions + 1] = "Installer"
            handlers[#handlers + 1] = function() installPackage(package) end
        elseif state.samePackage then
            actions[#actions + 1] = "Verifier"
            handlers[#handlers + 1] = function() verifyPackage(package) end
            actions[#actions + 1] = "Mise a jour"
            handlers[#handlers + 1] = function() updatePackage(package) end
            actions[#actions + 1] = "Desinstaller"
            handlers[#handlers + 1] = function() uninstallPackage(package) end
        end

        actions[#actions + 1] = "Informations"
        handlers[#handlers + 1] = function() showInformation(package) end
        actions[#actions + 1] = "Retour"

        local choice = menu.select({
            title = string.upper(package.name),
            subtitle = state.samePackage
                and ("Installee " .. tostring(state.marker.version) .. "  |  Disponible " .. package.version)
                or ("Disponible " .. package.version),
            items = actions
        })

        if choice == #actions then return end
        handlers[choice]()
    end
end

local function synchronizePackages()
    local syncResult = remote.syncIndex(function(current, total, file, status)
        progress.draw(
            "SYNCHRONISATION GITHUB",
            current,
            total,
            file,
            status
        )
    end)

    if syncResult and syncResult.updated > 0 then
        sleep(0.4)
        menu.message({
            title = "CATALOGUE ACTUALISE",
            lines = {
                tostring(syncResult.updated)
                    .. " paquet(s) disponible(s)",
                "",
                "Les nouvelles versions sont disponibles."
            }
        })
    elseif syncResult
        and syncResult.errors
        and #syncResult.errors > 0 then

        logger.warn(
            "Synchronisation GitHub ignoree : "
                .. tostring(syncResult.errors[1])
        )
    end
end

-- Contenu identique au menu principal de la version 1.4.0.
local function packageMenu()
    synchronizePackages()

    while true do
        local packages, errors = packageManager.discover()

        if #packages == 0 then
            menu.message({
                title = "AUCUN PAQUET",
                lines = {
                    errors[1] or "Aucun paquet valide"
                }
            })
            return
        end

        local labels = {}

        for _, package in ipairs(packages) do
            local state = installed.getState(package)
            local suffix = state.samePackage
                and (
                    " [INSTALLE "
                    .. tostring(state.marker.version)
                    .. "]"
                )
                or ""

            labels[#labels + 1] =
                package.name
                .. "  v"
                .. package.version
                .. suffix
        end

        labels[#labels + 1] = "Retour"

        local choice = menu.select({
            title = "INSTALLER UN PACKAGE",
            subtitle = "Manager " .. MANAGER_VERSION,
            items = labels
        })

        if choice == #labels then
            return
        end

        packageActions(packages[choice])
    end
end

local function updateManager()
    if not fs.exists("/update-manager.lua") then
        menu.message({
            title = "MISE A JOUR IMPOSSIBLE",
            lines = {
                "Le fichier /update-manager.lua est absent.",
                "",
                "Relance l'installation legere une fois."
            }
        })
        return
    end

    local ok, updateError = pcall(function()
        shell.run(
            "/update-manager.lua",
            MANAGER_VERSION
        )
    end)

    if not ok then
        logger.error(
            "Mise a jour Manager impossible : "
                .. tostring(updateError)
        )

        menu.message({
            title = "MISE A JOUR IMPOSSIBLE",
            lines = {
                tostring(updateError)
            }
        })
    end
end

local function clearScreen()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local function getDashboardSubtitle()
    local lines = {
        { text = "Version " .. MANAGER_VERSION, color = colors.lightGray }
    }

    local packages = packageManager.discover()
    local activePackage = nil
    local activeState = nil

    for _, package in ipairs(packages) do
        local state = installed.getState(package)

        if state.samePackage then
            activePackage = package
            activeState = state
            break
        end
    end

    lines[#lines + 1] = { text = "", color = colors.white }

    if not activePackage then
        lines[#lines + 1] = {
            text = "Package actif : Aucun",
            color = colors.red
        }
        return lines
    end

    lines[#lines + 1] = {
        text = "Package actif : "
            .. activePackage.name
            .. " v"
            .. tostring(activeState.marker.version),
        color = colors.lime
    }

    if version.compare(activePackage.version, activeState.marker.version) > 0 then
        lines[#lines + 1] = {
            text = "Mise a jour disponible : v" .. tostring(activePackage.version),
            color = colors.yellow
        }
    else
        lines[#lines + 1] = {
            text = "Package a jour : v" .. tostring(activeState.marker.version),
            color = colors.lime
        }
    end

    return lines
end

local function refreshDashboardIndex()
    local result = remote.syncIndex()

    if not result or not result.success then
        local message = result
            and result.errors
            and result.errors[1]
            or "Erreur inconnue"

        logger.warn(
            "Verification des mises a jour ignoree : "
                .. tostring(message)
        )
    end
end

local function main()
    logger.info(
        "Demarrage BANQUEOS Manager "
            .. MANAGER_VERSION
    )

    -- Actualise une seule fois l'index GitHub au demarrage afin que
    -- l'etat affiche sur le tableau de bord utilise les versions distantes.
    -- En cas de panne reseau, le Manager reste utilisable avec l'index local.
    refreshDashboardIndex()

    while true do
        local choice = menu.select({
            title = "BANQUEOS MANAGER",
            subtitle = getDashboardSubtitle(),
            items = {
                "Installer un package",
                "Mettre a jour le Manager",
                "Redemarrer",
                "Quitter"
            }
        })

        if choice == 1 then
            packageMenu()
        elseif choice == 2 then
            updateManager()
        elseif choice == 3 then
            if menu.confirm({
                title = "REDEMARRAGE",
                subtitle = "Redemarrer l'ordinateur ?",
                yesText = "Oui",
                noText = "Non"
            }) then
                clearScreen()
                os.reboot()
            end
        else
            clearScreen()
            return
        end
    end
end

local ok, err = pcall(main)
if not ok then
    logger.error("Erreur fatale : " .. tostring(err))
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.red)
    term.clear()
    term.setCursorPos(1, 1)
    print("Erreur BANQUEOS Manager")
    print("")
    print(tostring(err))
end
