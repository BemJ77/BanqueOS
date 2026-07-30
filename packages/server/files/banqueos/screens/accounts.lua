local ui = require("banqueos.core.ui")
local money = require("banqueos.core.money")
local database = require("banqueos.core.database")

local accountsScreen = {}
local DEG = string.char(176)

local function writeAt(x, y, text, color)
    term.setCursorPos(x, y)
    term.setBackgroundColor(colors.black)
    term.setTextColor(color or colors.white)
    term.write(text)
end

local function accountHeader(account)
    writeAt(2, 8, "Compte N" .. DEG .. " : ", colors.white)
    writeAt(14, 8, account.accountNumber, colors.cyan)
    writeAt(24, 8, "Nom : ", colors.white)
    writeAt(30, 8, account.owner, colors.cyan)
end

local function choose(title, entries, startY, footer, drawExtra)
    local selected = 1
    while true do
        ui.header(title)
        if drawExtra then drawExtra() end
        for i, entry in ipairs(entries) do
            local text = (i == selected and "> " or "  ") .. entry
            writeAt(4, startY + (i - 1) * 2, text, i == selected and colors.cyan or colors.white)
        end
        ui.footer(footer or "Fleches:naviguer  Entree:valider  Back:retour")
        local event, key = os.pullEventRaw()
        if event == "terminate" then return nil end
        if event == "key" then
            if key == keys.backspace then return nil end
            if key == keys.up then selected = selected == 1 and #entries or selected - 1 end
            if key == keys.down then selected = selected == #entries and 1 or selected + 1 end
            if key == keys.enter or key == keys.numPadEnter then return selected end
        end
    end
end

local function selectAccount()
    local accounts = database.listAccounts()
    if #accounts == 0 then
        ui.header("Consultation des comptes")
        ui.message(10, "Aucun compte bancaire disponible", colors.red)
        ui.footer("Appuyez sur une touche pour revenir")
        ui.waitForAnyKey()
        return nil
    end
    local selected, first = 1, 1
    local visible = 7
    while true do
        ui.header("Consultation des comptes")
        for row = 1, visible do
            local index = first + row - 1
            local account = accounts[index]
            if account then
                local text = "Compte N" .. DEG .. " : " .. account.accountNumber .. "   Nom : " .. account.owner
                writeAt(2, 8 + row, text, index == selected and colors.cyan or colors.white)
            end
        end
        ui.footer("Fleches:naviguer  Entree:valider  Back:retour")
        local event, key = os.pullEventRaw()
        if event == "terminate" then return nil end
        if event == "key" then
            if key == keys.backspace then return nil end
            if key == keys.up then selected = selected == 1 and #accounts or selected - 1 end
            if key == keys.down then selected = selected == #accounts and 1 or selected + 1 end
            if key == keys.enter or key == keys.numPadEnter then return accounts[selected] end
            if selected < first then first = selected end
            if selected >= first + visible then first = selected - visible + 1 end
        end
    end
end

local function showHistory(account)
    local history = account.history or {}
    local offset = math.max(1, #history - 7 + 1)
    while true do
        ui.header("Historique des transactions")
        accountHeader(account)
        if #history == 0 then
            ui.message(12, "Aucune transaction", colors.gray)
        else
            for row = 1, 7 do
                local item = history[offset + row - 1]
                if item then
                    local sign = item.amount and item.amount >= 0 and "+" or ""
                    local line = string.format("%s  %s%s  Solde:%s", item.date or "", sign,
                        money.formatEuros(item.amount or 0), money.formatEuros(item.balance or 0))
                    writeAt(2, 10 + row, line:sub(1, term.getSize()), colors.white)
                end
            end
        end
        ui.footer("Fleches:defiler  Back:retour")
        local event, key = os.pullEventRaw()
        if event == "terminate" or (event == "key" and key == keys.backspace) then return end
        if event == "key" and #history > 7 then
            if key == keys.up then offset = math.max(1, offset - 1) end
            if key == keys.down then offset = math.min(#history - 6, offset + 1) end
        end
    end
end

local function modifyBalance(account)
    while true do
        ui.header("Modification du solde")
        accountHeader(account)
        ui.center(11, "Solde : " .. money.formatEuros(account.balance), colors.yellow)
        writeAt(3, 14, "Nouveau solde : ", colors.white)
        term.setCursorPos(19, 14)
        local raw = ui.readField(19, 14, 18)
        local value = money.parseEuros(raw)
        if value then
            ui.drawButton(17, "VALIDER", true)
            ui.footer("Entree:valider  Back:retour")
            while true do
                local event, key = os.pullEventRaw()
                if event == "terminate" or (event == "key" and key == keys.backspace) then return end
                if event == "key" and (key == keys.enter or key == keys.numPadEnter) then
                    local ok, err = database.setBalance(account.accountNumber, value)
                    if not ok then ui.message(18, tostring(err), colors.red); sleep(1.5); return end
                    account.balance = value
                    ui.header("Modification du solde")
                    ui.message(11, "Solde modifie avec succes", colors.green)
                    ui.footer("Appuyez sur une touche pour revenir")
                    ui.waitForAnyKey()
                    return
                end
            end
        else
            ui.message(16, "Montant invalide", colors.red)
            sleep(1.2)
        end
    end
end

local function waitWriteResult()
    while true do
        local event, _, value = os.pullEventRaw()
        if event == "terminate" then return nil, "Operation interrompue" end
        if event == "bank_card_write_done" then return value ~= false end
        if event == "bank_card_write_error" then return nil, tostring(value or "Erreur d'encodage") end
        if event == "bank_card_removed" then return nil, "Carte retiree pendant l'encodage" end
    end
end

local function waitSelectedCard(writer, card, title)
    local visible, timer = true, os.startTimer(0.8)
    while true do
        ui.header(title)
        writeAt(3, 9, "Inserez la carte N" .. DEG .. " " .. card.cardId, colors.white)
        if visible then writeAt(3, 12, "Attente carte", colors.orange) end
        ui.footer("Back:retour")
        if writer.hasCard and writer.hasCard() then
            -- L'encodeur ne permet pas de lire le CardID. L'utilisateur confirme donc
            -- la carte demandee en l'inserant dans l'encodeur.
            writeAt(3, 12, "Carte inseree", colors.green)
            sleep(0.5)
            return true
        end
        local event, value = os.pullEventRaw()
        if event == "terminate" or (event == "key" and value == keys.backspace) then return false end
        if event == "timer" and value == timer then visible = not visible; timer = os.startTimer(0.8) end
        if event == "bank_card_inserted" then return true end
    end
end

local function readPin(keypad, draw)
    if keypad.clear then keypad.clear() end
    if keypad.setMaxLength then keypad.setMaxLength(12) end
    if keypad.setLocked then keypad.setLocked(false) end
    local display = ""
    while true do
        draw(display)
        local event, a, b = os.pullEventRaw()
        if event == "terminate" or (event == "key" and a == keys.backspace) then
            if keypad.setLocked then keypad.setLocked(true) end
            return nil
        elseif event == "keypad_press" then
            if b == "C" then display = "" elseif b and b:match("^%d$") and #display < 12 then display = display .. b end
        elseif event == "keypad_submit" then
            local value = tostring(b or "")
            if value:match("^%d%d%d%d$") then
                if keypad.setLocked then keypad.setLocked(true) end
                return value
            end
            if keypad.flashRed then keypad.flashRed(20) end
            if keypad.beep then keypad.beep("error") end
            if keypad.clear then keypad.clear() end
            display = ""
            draw(display, "Le code PIN doit contenir exactement 4 chiffres")
            sleep(1.2)
        end
    end
end

local function modifyPin(account, card)
    local writer = peripheral.find("bank_card_writer")
    local keypad = peripheral.find("keypad")
    if not writer or not keypad then
        ui.header("Modification du code PIN")
        ui.message(10, not writer and "Aucun Bank Card Writer connecte" or "Aucun Keypad connecte", colors.red)
        ui.footer("Appuyez sur une touche pour revenir"); ui.waitForAnyKey(); return
    end
    if not waitSelectedCard(writer, card, "Modification du code PIN") then return end
    local function draw(display, err)
        ui.header("Modification du code PIN")
        writeAt(3, 8, "Carte N" .. DEG .. " : " .. card.cardId, colors.white)
        writeAt(3, 10, "Carte inseree", colors.green)
        writeAt(3, 13, "Saisissez un nouveau code PIN a 4 chiffres", colors.white)
        writeAt(3, 15, "Code PIN : " .. (display or ""), colors.cyan)
        if err then ui.message(17, err, colors.red) end
        ui.footer("Back:retour")
    end
    local pin = readPin(keypad, draw)
    if not pin then return end
    draw(pin); ui.drawButton(18, "VALIDER", true)
    while true do
        local event, key = os.pullEventRaw()
        if event == "terminate" or (event == "key" and key == keys.backspace) then return end
        if event == "key" and (key == keys.enter or key == keys.numPadEnter) then break end
    end
    local ok, err = pcall(writer.beginWrite, nil, nil, pin, nil, nil)
    if not ok then ui.message(17, tostring(err), colors.red); sleep(1.5); return end
    ui.header("Modification du code PIN"); ui.message(10, "Encodage en cours...", colors.orange); ui.footer("Ne retirez pas la carte")
    local done, writeErr = waitWriteResult()
    if not done then ui.message(13, tostring(writeErr), colors.red); sleep(1.5); return end
    database.updateCardPin(card.cardId, pin)
    card.pin = pin
    ui.header("Modification du code PIN"); ui.message(11, "Code PIN modifie avec succes", colors.green)
    ui.footer("Appuyez sur une touche pour revenir"); ui.waitForAnyKey()
end

local function confirm(title, message)
    local selected = 2
    while true do
        ui.header(title); ui.message(10, message, colors.white)
        ui.drawButton(13, "OUI", selected == 1); ui.drawButton(15, "NON", selected == 2)
        ui.footer("Fleches:choisir  Entree:valider  Back:retour")
        local event, key = os.pullEventRaw()
        if event == "terminate" or (event == "key" and key == keys.backspace) then return false end
        if event == "key" and (key == keys.up or key == keys.down) then selected = selected == 1 and 2 or 1 end
        if event == "key" and (key == keys.enter or key == keys.numPadEnter) then return selected == 1 end
    end
end

local function deleteCard(account, card)
    if not confirm("Suppression de carte", "Voulez-vous supprimer cette carte ?") then return end
    local writer = peripheral.find("bank_card_writer")
    if not writer then ui.header("Suppression de carte"); ui.message(10, "Aucun Bank Card Writer connecte", colors.red); ui.waitForAnyKey(); return end
    if not writer.clearCard then
        ui.header("Suppression de carte"); ui.message(10, "Mettez a jour SecurityPeripheral", colors.red)
        ui.message(12, "Fonction clearCard() manquante", colors.white); ui.footer("Appuyez sur une touche"); ui.waitForAnyKey(); return
    end
    if not waitSelectedCard(writer, card, "Suppression de carte") then return end
    ui.header("Suppression de carte"); accountHeader(account); ui.drawButton(17, "VALIDER", true); ui.footer("Entree:valider  Back:retour")
    while true do
        local event, key = os.pullEventRaw()
        if event == "terminate" or (event == "key" and key == keys.backspace) then return end
        if event == "key" and (key == keys.enter or key == keys.numPadEnter) then break end
    end
    local ok, err = pcall(writer.clearCard)
    if not ok then ui.message(15, tostring(err), colors.red); sleep(1.5); return end
    local done, writeErr = waitWriteResult()
    if not done then ui.message(15, tostring(writeErr), colors.red); sleep(1.5); return end
    database.removeCardFromAccount(account.accountNumber, card.cardId)
    ui.header("Suppression de carte"); ui.message(11, "Carte reinitialisee et supprimee", colors.green)
    ui.footer("Appuyez sur une touche pour revenir"); ui.waitForAnyKey()
end

local function cardMenu(account, card)
    while true do
        ui.header("Carte bancaire associee")
        accountHeader(account)
        writeAt(2, 10, "CardID : " .. card.cardId .. "   PIN : " .. (card.pin or "????") .. "   Statut : ", colors.white)
        writeAt(49, 10, card.status or "active", (card.status == "blocked") and colors.red or colors.green)
        local choice = choose("Carte bancaire associee", {"Modifier code PIN", "Supprimer carte"}, 13, nil, function()
            accountHeader(account)
            writeAt(2, 10, "CardID : " .. card.cardId .. "   PIN : " .. (card.pin or "????") .. "   Statut : ", colors.white)
            writeAt(49, 10, card.status or "active", (card.status == "blocked") and colors.red or colors.green)
        end)
        if not choice then return end
        if choice == 1 then modifyPin(account, card) else deleteCard(account, card); return end
    end
end

local function cardsMenu(account)
    while true do
        local cards = database.listCardsForAccount(account.accountNumber)
        if #cards == 0 then ui.header("Cartes bancaires associees"); accountHeader(account); ui.message(12, "Aucune carte associee", colors.gray); ui.footer("Back:retour"); while true do local e,k=os.pullEventRaw(); if e=="terminate" or (e=="key" and k==keys.backspace) then return end end end
        local selected = 1
        while true do
            ui.header("Cartes bancaires associees"); accountHeader(account)
            for i, card in ipairs(cards) do
                local prefix = i == selected and "> " or "  "
                writeAt(2, 10 + i, prefix .. "CardID : " .. card.cardId .. "  PIN : " .. (card.pin or "????") .. "  Statut : ", i == selected and colors.cyan or colors.white)
                local status = card.status or "active"
                writeAt(48, 10 + i, status, status == "blocked" and colors.red or colors.green)
            end
            ui.footer("Fleches:naviguer  Entree:valider  Back:retour")
            local event,key=os.pullEventRaw()
            if event=="terminate" or (event=="key" and key==keys.backspace) then return end
            if event=="key" and key==keys.up then selected=selected==1 and #cards or selected-1 end
            if event=="key" and key==keys.down then selected=selected==#cards and 1 or selected+1 end
            if event=="key" and (key==keys.enter or key==keys.numPadEnter) then cardMenu(account,cards[selected]); break end
        end
    end
end

local function accountMenu(account)
    while true do
        ui.header("Consultation des comptes")
        accountHeader(account)
        ui.center(10, "Solde : " .. money.formatEuros(account.balance), colors.yellow)
        local choice = choose("Consultation des comptes", {
            "Consulter historique", "Modifier solde", "Cartes bancaires associees", "Suppression compte"
        }, 12, nil, function()
            accountHeader(account)
            ui.center(10, "Solde : " .. money.formatEuros(account.balance), colors.yellow)
        end)
        if not choice then return end
        if choice == 1 then showHistory(account)
        elseif choice == 2 then modifyBalance(account)
        elseif choice == 3 then cardsMenu(account)
        elseif choice == 4 then
            if confirm("Suppression du compte", "Voulez-vous supprimer ce compte ?") then
                database.deleteAccount(account.accountNumber)
                ui.header("Suppression du compte"); ui.message(11, "Compte supprime avec succes", colors.green)
                ui.message(13, "Les cartes associees sont conservees", colors.orange)
                ui.footer("Appuyez sur une touche pour revenir"); ui.waitForAnyKey(); return
            end
        end
    end
end

function accountsScreen.show()
    while true do
        local account = selectAccount()
        if not account then return end
        accountMenu(account)
    end
end

return accountsScreen
