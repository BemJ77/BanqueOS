local ui = require("banqueos.core.ui")
local storage = require("banqueos.core.storage")
local database = require("banqueos.core.database")
local loading = require("banqueos.screens.loading")
local menu = require("banqueos.screens.menu")
local createAccount = require("banqueos.screens.create_account")
local createCard = require("banqueos.screens.create_card")
local accounts = require("banqueos.screens.accounts")
local cards = require("banqueos.screens.cards")
local atms = require("banqueos.screens.atms")
local network = require("banqueos.core.network")

local main = {}

local function confirmation(title, lines, yesLabel, noLabel)
    local selected = 1
    while true do
        ui.header(title)
        local y = 9
        for _, line in ipairs(lines) do
            ui.message(y, line, colors.white)
            y = y + 1
        end

        ui.drawButton(y + 2, yesLabel or "OUI", selected == 1)
        ui.drawButton(y + 4, noLabel or "NON", selected == 2)
        ui.footer("Fleches : choisir   Entree : valider   Echap : annuler")

        local event, key = os.pullEventRaw()
        if event == "terminate" then return false end
        if event == "key" then
            if key == keys.up or key == keys.down then
                selected = selected == 1 and 2 or 1
            elseif key == keys.enter then
                return selected == 1
            elseif key == keys.escape then
                return false
            end
        end
    end
end

local function showWaiting(title, lines, footer)
    ui.header(title)
    local y = 9
    for index, line in ipairs(lines) do
        ui.message(y, line, index == 1 and colors.orange or colors.white)
        y = y + 1
    end
    ui.footer(footer or "Inserez la disquette BANQUEOS")
end

local function waitForInitialDisk()
    while true do
        local status, value, binding = storage.inspect()

        if status == "READY" then
            return storage.openBoundDisk(value, binding)
        elseif status == "BLANK_DISK" then
            local accepted = confirmation("Initialisation", {
                "Une disquette vierge a ete detectee.",
                "Voulez-vous l'initialiser comme", 
                "disquette bancaire BANQUEOS ?",
            })
            if accepted then return storage.initializeBlankDisk(value) end
            showWaiting("Initialisation annulee", {
                "La disquette n'a pas ete modifiee.",
                "Retirez-la ou appuyez sur Echap pour quitter.",
            })
        elseif status == "LEGACY_BANQUEOS_DISK" then
            local accepted = confirmation("Mise a niveau", {
                "Une ancienne disquette BANQUEOS", 
                "sans UUID a ete detectee.",
                "La lier definitivement a ce serveur ?",
            }, "LIER", "ANNULER")
            if accepted then return storage.upgradeLegacyDisk(value) end
        elseif status == "BOUND_DISK_MISSING" then
            showWaiting("Base bancaire verrouillee", {
                "La disquette active est absente.",
                "Ce serveur n'accepte que la disquette", 
                "qui lui est liee par UUID.",
            })
        elseif status == "UNBOUND_BANQUEOS_DISK" then
            showWaiting("Disquette refusee", {
                "Cette disquette BANQUEOS n'est pas", 
                "liee a ce serveur.",
                "Inserez la disquette active.",
            })
        elseif status == "NON_BLANK_DISK" then
            showWaiting("Disquette non compatible", {
                "Cette disquette contient deja des fichiers.",
                "Elle ne sera pas modifiee.",
            })
        elseif status == "TOO_MANY_DISKS" then
            showWaiting("Plusieurs disquettes", {
                "Ne laissez qu'une seule disquette", 
                "dans les lecteurs du serveur.",
            })
        else
            showWaiting("Base bancaire absente", {
                "Aucune disquette n'a ete detectee.",
                "Inserez la disquette BANQUEOS", 
                "ou une disquette vierge.",
            })
        end

        local event, key = os.pullEventRaw()
        if event == "terminate" or (event == "key" and key == keys.escape) then return nil end
    end
end

local function offerLegacyMigration()
    if not storage.hasLegacyData() or fs.exists(storage.getDataFile()) then return false end
    local accepted = confirmation("Ancienne base detectee", {
        "Une base locale de l'ancienne version existe.",
        "La copier sur la disquette bancaire ?",
    }, "MIGRER", "IGNORER")
    if accepted then return storage.migrateLegacyData() end
    return false
end

local function applicationLoop()
    while true do
        local choice = menu.select()
        if not choice then return "EXIT" end

        if choice == 1 then
            createAccount.show()
        elseif choice == 2 then
            accounts.show()
        elseif choice == 3 then
            createCard.show()
        elseif choice == 4 then
            cards.show()
        elseif choice == 5 then
            atms.show()
        end
    end
end

local function diskWatcher()
    local activeDrive = storage.getDriveName()
    while true do
        local event, side = os.pullEventRaw()
        if event == "terminate" then return "TERMINATE" end
        if event == "disk_eject" and side == activeDrive then
            return "DISK_REMOVED"
        end
    end
end

local function runProtectedSession()
    local reason = "EXIT"
    parallel.waitForAny(
        function() reason = applicationLoop() end,
        function() reason = diskWatcher() end,
        function() reason = network.serviceLoop() end
    )
    return reason
end

local function waitForActiveDisk()
    while true do
        local info = storage.findActiveDisk()
        if info then return info end

        local status, disks = storage.inspect()
        local hasInsertedDisk = status == "BOUND_DISK_MISSING"
            and type(disks) == "table"
            and #disks > 0

        if hasInsertedDisk then
            showWaiting("Disquette non reconnue", {
                "Cette disquette n'est pas",
                "associee a ce serveur.",
                "",
                "Veuillez reinserer la",
                "disquette active.",
            })
        else
            showWaiting("Base bancaire retiree", {
                "Toutes les operations sont suspendues.",
                "Reinserez la disquette active.",
            })
        end

        local event = os.pullEventRaw()
        if event == "terminate" then return nil end
    end
end


local function showOutdatedAtms(atmNumbers)
    if type(atmNumbers) ~= "table" or #atmNumbers == 0 then return end
    ui.header("Mise a jour ATM requise")
    local y = 9
    for _, number in ipairs(atmNumbers) do
        ui.message(y, string.format("Veuillez mettre a jour ATM N° %03d.", number), colors.orange)
        y = y + 2
    end
    ui.footer("Appuyez sur une touche pour continuer")
    os.pullEvent("key")
end

function main.run()
    math.randomseed(os.epoch("utc") % 2147483647)

    local diskInfo = waitForInitialDisk()
    if not diskInfo then return end

    diskInfo.migrated = offerLegacyMigration()
    database.load()

    local outdatedAtms = {}
    local scanOk
    outdatedAtms, scanOk = network.startupScan()

    if not loading.show(diskInfo) then return end
    showOutdatedAtms(outdatedAtms)

    while true do
        local reason = runProtectedSession()
        if reason == "EXIT" or reason == "TERMINATE" then return end

        if reason == "DISK_REMOVED" then
            local restored = waitForActiveDisk()
            if not restored then return end
            database.load()
            ui.header("Base bancaire restauree")
            ui.message(10, "Disquette active reconnue par UUID.", colors.green)
            ui.message(12, "Retour au menu principal.", colors.white)
            sleep(1.2)
        end
    end
end

return main
