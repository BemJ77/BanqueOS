-- BANQUEOS Manager - mise a jour autonome
-- Usage : shell.run("/update-manager.lua", "1.5.0")

local CURRENT_VERSION = tostring(({ ... })[1] or "0.0.0")
local CONFIG_PATH = "/config/repository.lua"
local TEMP_ROOT = "/downloads/manager-update"

local PROTECTED_FILES = {
    ["startup"] = true,
    ["config/repository.lua"] = true
}

local function clear()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local function pause()
    print("")
    term.setTextColor(colors.lightGray)
    print("Appuie sur une touche pour revenir.")
    term.setTextColor(colors.white)
    os.pullEvent("key")
end

local function loadTable(path)
    if not fs.exists(path) or fs.isDir(path) then
        return nil, "Fichier absent : " .. path
    end

    local chunk, loadError = loadfile(path)
    if not chunk then
        return nil, tostring(loadError)
    end

    local ok, value = pcall(chunk)
    if not ok then
        return nil, tostring(value)
    end

    if type(value) ~= "table" then
        return nil, "Table Lua attendue : " .. path
    end

    return value
end

local function splitVersion(value)
    local result = {}

    for number in tostring(value):gmatch("%d+") do
        result[#result + 1] = tonumber(number) or 0
    end

    return result
end

local function compareVersions(left, right)
    local a = splitVersion(left)
    local b = splitVersion(right)
    local count = math.max(#a, #b)

    for index = 1, count do
        local av = a[index] or 0
        local bv = b[index] or 0

        if av < bv then return -1 end
        if av > bv then return 1 end
    end

    return 0
end

local function ensureParent(path)
    local parent = fs.getDir(path)

    if parent ~= "" and not fs.exists(parent) then
        fs.makeDir(parent)
    end
end

local function httpGet(url)
    if not http or not http.get then
        return nil, "API HTTP indisponible"
    end

    local response, requestError =
        http.get(url, nil, true)

    if not response then
        return nil,
            tostring(
                requestError
                or "Telechargement impossible"
            )
    end

    local data = response.readAll()
    response.close()

    if type(data) ~= "string" or data == "" then
        return nil, "Reponse vide"
    end

    return data
end

local function writeFile(path, data)
    ensureParent(path)

    if fs.exists(path) then
        fs.delete(path)
    end

    local handle = fs.open(path, "w")
    if not handle then
        return false, "Impossible d'ecrire " .. path
    end

    local ok, writeError = pcall(function()
        handle.write(data)
    end)

    handle.close()

    if not ok then
        if fs.exists(path) then
            fs.delete(path)
        end

        return false, tostring(writeError)
    end

    return true
end

local function loadRemoteTable(url, chunkName)
    local data, downloadError = httpGet(url)
    if not data then
        return nil, downloadError
    end

    local chunk, loadError =
        load(data, "@" .. chunkName, "t", _ENV)

    if not chunk then
        return nil, tostring(loadError)
    end

    local ok, value = pcall(chunk)
    if not ok then
        return nil, tostring(value)
    end

    if type(value) ~= "table" then
        return nil, "Manifeste distant invalide"
    end

    return value
end

local function confirm(question)
    print("")
    write(question .. " [O/n] ")

    local answer = read():lower()

    return answer == ""
        or answer == "o"
        or answer == "oui"
        or answer == "y"
        or answer == "yes"
end

local function repositoryBase()
    local config, configError = loadTable(CONFIG_PATH)
    if not config then
        return nil, configError
    end

    if config.enabled ~= true then
        return nil, "Le depot GitHub est desactive"
    end

    if not config.owner or not config.repository then
        return nil, "Configuration GitHub incomplete"
    end

    return
        "https://raw.githubusercontent.com/"
        .. config.owner
        .. "/"
        .. config.repository
        .. "/"
        .. (config.branch or "main")
end

local function cleanTemporaryFiles()
    if fs.exists(TEMP_ROOT) then
        fs.delete(TEMP_ROOT)
    end

    fs.makeDir(TEMP_ROOT)
end

local function downloadManagerFiles(base, files)
    cleanTemporaryFiles()

    for index, relative in ipairs(files) do
        if type(relative) ~= "string"
            or relative == "" then

            return false,
                "Chemin Manager invalide dans manifest.lua"
        end

        -- Certains fichiers appartiennent a la machine ou au package actif.
        -- Ils restent presents dans le manifeste pour l'installation initiale,
        -- mais ne sont jamais remplaces pendant une mise a jour du Manager.
        if not PROTECTED_FILES[relative] then
            clear()
            print("MISE A JOUR BANQUEOS MANAGER")
            print("")
            print(
                tostring(index)
                .. " / "
                .. tostring(#files)
            )
            print(relative)
            print("")
            print("Telechargement...")

            local data, downloadError =
                httpGet(base .. "/" .. relative)

            if not data then
                return false,
                    relative
                    .. " : "
                    .. tostring(downloadError)
            end

            local temporary =
                TEMP_ROOT .. "/" .. relative

            local ok, writeError =
                writeFile(temporary, data)

            if not ok then
                return false, writeError
            end
        end
    end

    return true
end

local function installManagerFiles(files)
    -- manager.lua et update-manager.lua sont remplaces en dernier.
    local deferred = {
        ["manager.lua"] = true,
        ["update-manager.lua"] = true
    }

    local function installOne(relative)
        if PROTECTED_FILES[relative] then
            return true
        end

        local source = TEMP_ROOT .. "/" .. relative
        local destination = "/" .. relative

        if not fs.exists(source) then
            return false,
                "Fichier temporaire absent : " .. relative
        end

        ensureParent(destination)

        if fs.exists(destination) then
            fs.delete(destination)
        end

        fs.move(source, destination)
        return true
    end

    for _, relative in ipairs(files) do
        if not deferred[relative] then
            local ok, installError = installOne(relative)
            if not ok then
                return false, installError
            end
        end
    end

    for _, relative in ipairs({
        "manager.lua",
        "update-manager.lua"
    }) do
        local present = false

        for _, listed in ipairs(files) do
            if listed == relative then
                present = true
                break
            end
        end

        if present then
            local ok, installError = installOne(relative)
            if not ok then
                return false, installError
            end
        end
    end

    if fs.exists(TEMP_ROOT) then
        fs.delete(TEMP_ROOT)
    end

    return true
end

local function main()
    clear()

    print("MISE A JOUR BANQUEOS MANAGER")
    print("")
    print("Version installee : " .. CURRENT_VERSION)
    print("")
    print("Connexion a GitHub...")

    local base, repositoryError = repositoryBase()
    if not base then
        printError(tostring(repositoryError))
        pause()
        return
    end

    local manifest, manifestError =
        loadRemoteTable(
            base .. "/manifest.lua",
            "manifest.lua"
        )

    if not manifest then
        printError(tostring(manifestError))
        pause()
        return
    end

    local available =
        tostring(manifest.managerVersion or "0.0.0")

    clear()
    print("MISE A JOUR BANQUEOS MANAGER")
    print("")
    print("Version installee : " .. CURRENT_VERSION)
    print("Version GitHub    : " .. available)
    print("")

    if compareVersions(available, CURRENT_VERSION) <= 0 then
        term.setTextColor(colors.lime)
        print("Le Manager est deja a jour.")
        term.setTextColor(colors.white)
        pause()
        return
    end

    term.setTextColor(colors.yellow)
    print("Une nouvelle version est disponible.")
    term.setTextColor(colors.white)

    if not confirm(
        "Installer "
        .. CURRENT_VERSION
        .. " -> "
        .. available
        .. " ?"
    ) then
        print("")
        print("Mise a jour annulee.")
        sleep(0.8)
        return
    end

    if type(manifest.managerFiles) ~= "table" then
        printError(
            "La liste managerFiles est absente du manifeste."
        )
        pause()
        return
    end

    local ok, downloadError =
        downloadManagerFiles(
            base,
            manifest.managerFiles
        )

    if not ok then
        clear()
        printError("Telechargement interrompu")
        print("")
        printError(tostring(downloadError))
        pause()
        return
    end

    -- Le script de mise à jour doit également pouvoir
    -- se mettre à jour lui-même, même s'il n'est pas encore
    -- présent dans les anciens manifestes.
    local hasUpdater = false
    for _, relative in ipairs(manifest.managerFiles) do
        if relative == "update-manager.lua" then
            hasUpdater = true
            break
        end
    end

    if not hasUpdater then
        local data, updaterError =
            httpGet(base .. "/update-manager.lua")

        if not data then
            clear()
            printError("Telechargement interrompu")
            print("")
            printError(tostring(updaterError))
            pause()
            return
        end

        local okWrite, writeError =
            writeFile(
                TEMP_ROOT .. "/update-manager.lua",
                data
            )

        if not okWrite then
            clear()
            printError(tostring(writeError))
            pause()
            return
        end

        manifest.managerFiles[
            #manifest.managerFiles + 1
        ] = "update-manager.lua"
    end

    local installed, installError =
        installManagerFiles(manifest.managerFiles)

    if not installed then
        clear()
        printError("Installation incomplete")
        print("")
        printError(tostring(installError))
        pause()
        return
    end

    clear()
    term.setTextColor(colors.lime)
    print("MISE A JOUR TERMINEE")
    term.setTextColor(colors.white)
    print("")
    print(
        "BANQUEOS Manager "
        .. available
        .. " est installe."
    )
    print("")
    print("Redemarrage...")

    sleep(1.5)
    os.reboot()
end

local ok, errorMessage = pcall(main)

if not ok then
    clear()
    printError("Erreur de mise a jour")
    print("")
    printError(tostring(errorMessage))
    pause()
end
