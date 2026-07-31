local ui = require("banqueos.core.ui")
local database = require("banqueos.core.database")

local cardsScreen = {}
local DEG = string.char(176)

local function writeAt(x, y, text, color)
    term.setCursorPos(x, y)
    term.setBackgroundColor(colors.black)
    term.setTextColor(color or colors.white)
    term.write(text)
end

local function accountName(card)
    local account = card.accountNumber and database.getAccount(card.accountNumber) or nil
    return account and account.owner or "Orpheline"
end

local function cardSummary(card)
    local width = term.getSize()
    local prefix = "CardID : " .. tostring(card.cardId or "????") .. "   Compte associe : "
    local owner = accountName(card)
    local maxOwner = math.max(1, width - #prefix - 2)
    if #owner > maxOwner then owner = owner:sub(1, math.max(1, maxOwner - 1)) .. "." end
    return prefix .. owner
end

local function drawCardDetails(card)
    writeAt(2, 8, cardSummary(card), colors.white)
    writeAt(2, 10, "PIN : " .. tostring(card.pin or "????") .. "   Statut : ", colors.white)
    local status = tostring(card.status or "active")
    writeAt(27, 10, status, status == "blocked" and colors.red or colors.green)
end

local function choose(title, entries, startY, drawExtra)
    local selected = 1
    while true do
        ui.header(title)
        if drawExtra then drawExtra() end
        for i, entry in ipairs(entries) do
            local text = (i == selected and "> " or "  ") .. entry
            writeAt(4, startY + (i - 1) * 2, text, i == selected and colors.cyan or colors.white)
        end
        ui.footer("Fleches:naviguer  Entree:valider  Back:retour")
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

local function confirm(title, message)
    local selected = 2
    while true do
        ui.header(title)
        ui.message(10, message, colors.white)
        ui.drawButton(13, "OUI", selected == 1)
        ui.drawButton(15, "NON", selected == 2)
        ui.footer("Fleches:choisir  Entree:valider  Back:retour")
        local event, key = os.pullEventRaw()
        if event == "terminate" or (event == "key" and key == keys.backspace) then return false end
        if event == "key" and (key == keys.up or key == keys.down) then selected = selected == 1 and 2 or 1 end
        if event == "key" and (key == keys.enter or key == keys.numPadEnter) then return selected == 1 end
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

local function readInsertedCard(writer)
    if not writer.readCard then return nil, "Mettez a jour SecurityPeripheral" end
    local ok, card = pcall(writer.readCard)
    if not ok then return nil, tostring(card) end
    if type(card) ~= "table" then return nil, "Lecture de la carte impossible" end
    card.cardId = tostring(card.cardId or "")
    return card
end

local function waitSelectedCard(writer, selectedCard, title)
    local visible, timer = true, os.startTimer(0.8)
    local wrong = false
    while true do
        ui.header(title)
        writeAt(3, 9, "Inserez la carte N" .. DEG .. " " .. selectedCard.cardId, colors.white)
        if wrong then
            writeAt(3, 12, "Erreur : mauvaise carte", colors.red)
            writeAt(3, 14, "Retirez-la puis inserez la bonne carte", colors.white)
        elseif visible then
            writeAt(3, 12, "Attente carte", colors.orange)
        end
        ui.footer("Back:retour")

        if writer.hasCard and writer.hasCard() then
            local inserted, err = readInsertedCard(writer)
            if not inserted then
                writeAt(3, 12, err, colors.red); sleep(1.5); return nil
            elseif inserted.cardId == tostring(selectedCard.cardId) then
                writeAt(3, 12, "Carte inseree", colors.green); sleep(0.5); return inserted
            else
                wrong = true
            end
        else
            wrong = false
        end

        local event, value = os.pullEventRaw()
        if event == "terminate" or (event == "key" and value == keys.backspace) then return nil end
        if event == "timer" and value == timer then visible = not visible; timer = os.startTimer(0.8) end
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

local function rewriteCard(writer, currentCard)
    local ok, err = pcall(function()
        writer.beginWrite(
            tostring(currentCard.owner or ""),
            tostring(currentCard.status or "active"),
            tostring(currentCard.pin or ""),
            tostring(currentCard.cardId or ""),
            tostring(currentCard.data or "")
        )
    end)
    if not ok then return nil, tostring(err) end
    return waitWriteResult()
end

local function modifyPin(card)
    local writer = peripheral.find("bank_card_writer")
    local keypad = peripheral.find("keypad")
    if not writer or not keypad then
        ui.header("Modification du code PIN")
        ui.message(10, not writer and "Aucun Bank Card Writer connecte" or "Aucun Keypad connecte", colors.red)
        ui.footer("Appuyez sur une touche pour revenir"); ui.waitForAnyKey(); return
    end
    local currentCard = waitSelectedCard(writer, card, "Modification du code PIN")
    if not currentCard then return end
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
    currentCard.pin = pin
    ui.header("Modification du code PIN"); ui.message(10, "Encodage en cours...", colors.orange); ui.footer("Ne retirez pas la carte")
    local done, err = rewriteCard(writer, currentCard)
    if not done then ui.message(13, tostring(err), colors.red); sleep(1.5); return end
    database.updateCardPin(card.cardId, pin); card.pin = pin
    ui.header("Modification du code PIN"); ui.message(11, "Code PIN modifie avec succes", colors.green)
    ui.footer("Appuyez sur une touche pour revenir"); ui.waitForAnyKey()
end

local function deleteCard(card)
    if not confirm("Suppression de carte", "Voulez-vous supprimer cette carte ?") then return false end
    local writer = peripheral.find("bank_card_writer")
    if not writer then ui.header("Suppression de carte"); ui.message(10, "Aucun Bank Card Writer connecte", colors.red); ui.waitForAnyKey(); return false end
    if not writer.clearCard then
        ui.header("Suppression de carte"); ui.message(10, "Mettez a jour SecurityPeripheral", colors.red)
        ui.message(12, "Fonction clearCard() manquante", colors.white); ui.footer("Appuyez sur une touche"); ui.waitForAnyKey(); return false
    end
    if not waitSelectedCard(writer, card, "Suppression de carte") then return false end
    ui.header("Suppression de carte"); drawCardDetails(card); ui.drawButton(17, "VALIDER", true); ui.footer("Entree:valider  Back:retour")
    while true do
        local event, key = os.pullEventRaw()
        if event == "terminate" or (event == "key" and key == keys.backspace) then return false end
        if event == "key" and (key == keys.enter or key == keys.numPadEnter) then break end
    end
    local ok, err = pcall(writer.clearCard)
    if not ok then ui.message(15, tostring(err), colors.red); sleep(1.5); return false end
    local done, writeErr = waitWriteResult()
    if not done then ui.message(15, tostring(writeErr), colors.red); sleep(1.5); return false end
    database.deleteCard(card.cardId)
    ui.header("Suppression de carte"); ui.message(11, "Carte reinitialisee et supprimee", colors.green)
    ui.footer("Appuyez sur une touche pour revenir"); ui.waitForAnyKey(); return true
end

local function blockCard(card)
    if tostring(card.status or "active") == "blocked" then
        ui.header("Blocage de carte"); ui.message(11, "Cette carte est deja bloquee", colors.orange)
        ui.footer("Appuyez sur une touche pour revenir"); ui.waitForAnyKey(); return
    end
    if not confirm("Blocage de carte", "Voulez-vous bloquer cette carte ?") then return end
    database.updateCardStatus(card.cardId, "blocked")
    card.status = "blocked"
    ui.header("Blocage de carte"); ui.message(11, "Carte bloquee sur le serveur", colors.green)
    ui.message(13, "L'ATM synchronisera son statut", colors.orange)
    ui.footer("Appuyez sur une touche pour revenir"); ui.waitForAnyKey()
end

local function cardMenu(card)
    while true do
        local choice = choose("Consultation des cartes", {
            "Modifier code PIN", "Supprimer Carte", "Blocage Carte"
        }, 13, function() drawCardDetails(card) end)
        if not choice then return false end
        if choice == 1 then modifyPin(card)
        elseif choice == 2 then return deleteCard(card)
        elseif choice == 3 then blockCard(card) end
    end
end

local function consultCards()
    while true do
        local cards = database.listCards()
        if #cards == 0 then
            ui.header("Consultation des cartes"); ui.message(11, "Aucune carte bancaire disponible", colors.gray)
            ui.footer("Appuyez sur une touche pour revenir"); ui.waitForAnyKey(); return
        end
        local selected, first, visible = 1, 1, 8
        while true do
            ui.header("Consultation des cartes")
            for row = 1, visible do
                local index = first + row - 1
                local card = cards[index]
                if card then writeAt(2, 8 + row, cardSummary(card), index == selected and colors.cyan or colors.white) end
            end
            ui.footer("Fleches:naviguer  Entree:valider  Back:retour")
            local event, key = os.pullEventRaw()
            if event == "terminate" or (event == "key" and key == keys.backspace) then return end
            if event == "key" then
                if key == keys.up then selected = selected == 1 and #cards or selected - 1 end
                if key == keys.down then selected = selected == #cards and 1 or selected + 1 end
                if key == keys.enter or key == keys.numPadEnter then
                    local deleted = cardMenu(cards[selected])
                    if deleted then break end
                end
                if selected < first then first = selected end
                if selected >= first + visible then first = selected - visible + 1 end
            end
        end
    end
end

local function unlockCard()
    local writer = peripheral.find("bank_card_writer")
    if not writer then
        ui.header("Deblocage Carte"); ui.message(11, "Aucun Bank Card Writer connecte", colors.red)
        ui.footer("Appuyez sur une touche pour revenir"); ui.waitForAnyKey(); return
    end
    local visible, timer = true, os.startTimer(0.8)
    local inserted, record, errorMessage
    while not inserted do
        ui.header("Deblocage Carte")
        writeAt(3, 9, "Inserez la carte a debloquer", colors.white)
        if errorMessage then writeAt(3, 12, errorMessage, colors.red)
        elseif visible then writeAt(3, 12, "Attente carte", colors.orange) end
        ui.footer("Back:retour")
        if writer.hasCard and writer.hasCard() then
            inserted, errorMessage = readInsertedCard(writer)
            if inserted then
                record = database.getCard(inserted.cardId)
                if not record then inserted = nil; errorMessage = "Carte inconnue du serveur" end
            end
        end
        if not inserted then
            local event, value = os.pullEventRaw()
            if event == "terminate" or (event == "key" and value == keys.backspace) then return end
            if event == "timer" and value == timer then visible = not visible; timer = os.startTimer(0.8) end
        end
    end

    while true do
        ui.header("Deblocage Carte")
        writeAt(3, 9, "Carte inseree", colors.green)
        writeAt(2, 12, cardSummary(record), colors.white)
        ui.drawButton(16, "VALIDER", true)
        ui.footer("Entree:valider  Back:retour")
        local event, key = os.pullEventRaw()
        if event == "terminate" or (event == "key" and key == keys.backspace) then return end
        if event == "key" and (key == keys.enter or key == keys.numPadEnter) then break end
    end

    inserted.status = "active"
    ui.header("Deblocage Carte"); ui.message(10, "Encodage en cours...", colors.orange); ui.footer("Ne retirez pas la carte")
    local done, err = rewriteCard(writer, inserted)
    if not done then ui.message(13, tostring(err), colors.red); sleep(1.5); return end
    database.updateCardStatus(inserted.cardId, "active")
    ui.header("Deblocage Carte"); ui.message(11, "Carte debloquee avec succes", colors.green)
    ui.footer("Appuyez sur une touche pour revenir"); ui.waitForAnyKey()
end

function cardsScreen.show()
    while true do
        local choice = choose("Gestion des cartes", {"Consulter les cartes", "Deblocage carte"}, 10)
        if not choice then return end
        if choice == 1 then consultCards() else unlockCard() end
    end
end

return cardsScreen
