local ui = require("banqueos.core.ui")
local money = require("banqueos.core.money")
local database = require("banqueos.core.database")
local config = require("banqueos.config")

local screen = {}

local function writeAt(x, y, text, color)
    term.setCursorPos(x, y)
    term.setBackgroundColor(colors.black)
    term.setTextColor(color or colors.white)
    term.write(text)
end

local function getState(atm)
    local age = os.epoch("utc") - (tonumber(atm.lastSeen) or 0)
    local connected = age <= (tonumber(config.atmHeartbeatTimeoutSeconds) or 45) * 1000

    if not connected then
        return "Deconnecte", colors.orange
    end

    if tostring(atm.version or "") ~= tostring(config.requiredAtmVersion) then
        return "Erreur", colors.red
    end

    return "En ligne", colors.green
end

local function selectAtm()
    local selected, first = 1, 1
    local visible = 8

    while true do
        local atms = database.listAtms()
        if #atms == 0 then
            ui.header("Gestion des ATM")
            ui.message(11, "Aucun ATM enregistre", colors.gray)
            ui.footer("Back:retour")
            local event, key = os.pullEventRaw()
            if event == "terminate" or (event == "key" and key == keys.backspace) then
                return nil
            end
        else
            if selected > #atms then selected = #atms end
            if first > selected then first = selected end

            ui.header("Gestion des ATM")
            for row = 1, visible do
                local index = first + row - 1
                local atm = atms[index]
                if atm then
                    local text = string.format("ATM %03d", tonumber(atm.number) or 0)
                    if tostring(atm.name or "") ~= "" then
                        text = text .. "   " .. tostring(atm.name)
                    end
                    writeAt(4, 8 + row, (index == selected and "> " or "  ") .. text,
                        index == selected and colors.cyan or colors.white)
                end
            end
            ui.footer("Fleches:naviguer  Entree:valider  Back:retour")

            local event, key = os.pullEventRaw()
            if event == "terminate" then return nil end
            if event == "key" then
                if key == keys.backspace then return nil end
                if key == keys.up then selected = selected == 1 and #atms or selected - 1 end
                if key == keys.down then selected = selected == #atms and 1 or selected + 1 end
                if key == keys.enter or key == keys.numPadEnter then return atms[selected] end
                if selected < first then first = selected end
                if selected >= first + visible then first = selected - visible + 1 end
            end
        end
    end
end

local function confirmDelete(atm)
    local selected = 2
    while true do
        ui.header("Suppression ATM")
        ui.message(10, string.format("Supprimer ATM %03d ?", tonumber(atm.number) or 0), colors.orange)
        ui.message(12, "Il ne sera plus accepte par ce serveur.", colors.white)
        ui.drawButton(15, "SUPPRIMER", selected == 1)
        ui.drawButton(17, "ANNULER", selected == 2)
        ui.footer("Fleches:choisir  Entree:valider  Back:retour")

        local event, key = os.pullEventRaw()
        if event == "terminate" or (event == "key" and key == keys.backspace) then return false end
        if event == "key" then
            if key == keys.up or key == keys.down then selected = selected == 1 and 2 or 1 end
            if key == keys.enter or key == keys.numPadEnter then return selected == 1 end
        end
    end
end

local function renameAtm(atm)
    ui.header("Renommer ATM")
    ui.message(9, string.format("ATM %03d", tonumber(atm.number) or 0), colors.cyan)
    writeAt(3, 12, "Nouveau nom : ", colors.white)
    local name = ui.readField(17, 12, 24)

    local updated, err = database.renameAtm(atm.uuid, name)
    ui.header("Renommer ATM")
    if updated then
        ui.message(11, name == "" and "Nom supprime" or "ATM renomme avec succes", colors.green)
    else
        ui.message(11, tostring(err), colors.red)
    end
    ui.footer("Appuyez sur une touche pour revenir")
    ui.waitForAnyKey()
end

local function details(atm)
    local selected = 1
    while true do
        local current
        for _, item in ipairs(database.listAtms()) do
            if tostring(item.uuid) == tostring(atm.uuid) then current = item break end
        end
        if not current then return end
        atm = current

        ui.header("Gestion des ATM")
        local state, stateColor = getState(atm)

        writeAt(3, 8, "Etat : ", colors.white)
        writeAt(10, 8, state, stateColor)
        writeAt(25, 8, "Version : ", colors.white)
        writeAt(35, 8, tostring(atm.version or "?"), colors.cyan)

        local y = 10
        if tostring(atm.name or "") ~= "" then
            writeAt(3, y, "Nom : ", colors.white)
            writeAt(9, y, tostring(atm.name), colors.cyan)
            y = y + 2
        end

        writeAt(3, y, "Stock actuel : ", colors.white)
        writeAt(18, y, money.formatEuros(tonumber(atm.cashTotal) or 0), colors.yellow)

        local menuY = y + 3
        local choices = { "Renommer", "Supprimer" }
        for index, label in ipairs(choices) do
            writeAt(5, menuY + (index - 1) * 2,
                (index == selected and "> " or "  ") .. label,
                index == selected and colors.cyan or colors.white)
        end

        ui.footer("Fleches:naviguer  Entree:valider  Back:retour")
        local event, key = os.pullEventRaw()
        if event == "terminate" or (event == "key" and key == keys.backspace) then return end
        if event == "key" then
            if key == keys.up then selected = selected == 1 and #choices or selected - 1 end
            if key == keys.down then selected = selected == #choices and 1 or selected + 1 end
            if key == keys.enter or key == keys.numPadEnter then
                if selected == 1 then
                    renameAtm(atm)
                elseif selected == 2 and confirmDelete(atm) then
                    database.deleteAtm(atm.uuid)
                    ui.header("Suppression ATM")
                    ui.message(11, "ATM supprime du serveur", colors.green)
                    ui.footer("Appuyez sur une touche pour revenir")
                    ui.waitForAnyKey()
                    return
                end
            end
        end
    end
end

function screen.show()
    while true do
        local atm = selectAtm()
        if not atm then return end
        details(atm)
    end
end

return screen
