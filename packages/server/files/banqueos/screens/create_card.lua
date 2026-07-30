local ui = require("banqueos.core.ui")
local database = require("banqueos.core.database")

local createCard = {}

local ACCOUNT_LABEL = "Compte N" .. string.char(176) .. " : "

local function writeAt(x, y, text, color)
    term.setCursorPos(x, y)
    term.setTextColor(color or colors.white)
    term.setBackgroundColor(colors.black)
    term.write(text)
end

local function clearLine(y)
    local width = term.getSize()
    term.setCursorPos(1, y)
    term.setBackgroundColor(colors.black)
    term.write(string.rep(" ", width))
end

local function selectedAccountLine(account)
    return "N" .. string.char(176) .. " " .. account.accountNumber .. "  " .. account.owner
end

local function selectAccount()
    local accounts = database.listAccounts()
    if #accounts == 0 then
        ui.header("Creation de carte bancaire")
        ui.message(10, "Aucun compte bancaire disponible", colors.red)
        ui.footer("Appuyez sur une touche pour revenir")
        ui.waitForAnyKey()
        return nil
    end

    local selected = 1
    local firstVisible = 1
    local visibleRows = 7

    while true do
        ui.header("Creation de carte bancaire")
        writeAt(3, 6, "Selectionnez un compte :", colors.white)

        for row = 1, visibleRows do
            local y = 7 + row
            clearLine(y)
            local index = firstVisible + row - 1
            local account = accounts[index]
            if account then
                local text = selectedAccountLine(account)
                writeAt(5, y, text, index == selected and colors.cyan or colors.white)
            end
        end

        if #accounts > visibleRows then
            writeAt(3, 16, string.format("Compte %d/%d", selected, #accounts), colors.gray)
        end
        ui.footer("Fleches : naviguer   Entree : valider   Echap : annuler")

        local event, key = os.pullEventRaw()
        if event == "terminate" then return nil end
        if event == "key" then
            if key == keys.escape then
                return nil
            elseif key == keys.up then
                selected = selected == 1 and #accounts or selected - 1
            elseif key == keys.down then
                selected = selected == #accounts and 1 or selected + 1
            elseif key == keys.enter or key == keys.numPadEnter then
                return accounts[selected]
            end

            if selected < firstVisible then
                firstVisible = selected
            elseif selected >= firstVisible + visibleRows then
                firstVisible = selected - visibleRows + 1
            end
        end
    end
end

local function redraw(state, step, blinkVisible, errorMessage)
    ui.header("Creation de carte bancaire")

    if state.account then
        writeAt(3, 7, ACCOUNT_LABEL, colors.white)
        writeAt(3 + #ACCOUNT_LABEL, 7, state.account.accountNumber, colors.cyan)
        local nameLabel = "   Nom : "
        local nameX = 3 + #ACCOUNT_LABEL + #state.account.accountNumber
        writeAt(nameX, 7, nameLabel, colors.white)
        writeAt(nameX + #nameLabel, 7, state.account.owner, colors.cyan)
    end

    if step >= 2 then
        if state.cardInserted then
            writeAt(3, 9, "Carte inseree", colors.green)
        elseif blinkVisible ~= false then
            writeAt(3, 9, "Veuillez inserer une carte", colors.orange)
        end
    end

    if step >= 3 then
        writeAt(3, 11, "CardID : ", colors.white)
        writeAt(12, 11, state.cardIdDisplay or state.cardId or "XXXX", colors.cyan)
    end

    if step >= 4 then
        writeAt(3, 13, "Saisissez un code PIN a 4 chiffres", colors.white)
        if state.pin then
            writeAt(3, 14, "Code PIN : ", colors.white)
            writeAt(14, 14, state.pin, colors.cyan)
        else
            writeAt(3, 14, "Code PIN : ", colors.white)
            writeAt(14, 14, state.pinDisplay or "", colors.cyan)
        end
    end

    if errorMessage then
        ui.message(16, errorMessage, colors.red)
    end

    if step >= 5 then
        ui.drawButton(17, "VALIDER", true)
    end

    ui.footer("Echap : annuler")
end

local function waitForCard(state, writer)
    if writer.hasCard and writer.hasCard() then
        state.cardInserted = true
        redraw(state, 2, true)
        sleep(0.5)
        return true
    end

    local visible = true
    redraw(state, 2, visible)
    local timer = os.startTimer(0.8)

    while true do
        local event, a = os.pullEventRaw()
        if event == "terminate" or (event == "key" and a == keys.escape) then
            return false
        elseif event == "timer" and a == timer then
            visible = not visible
            clearLine(9)
            if visible then writeAt(3, 9, "Veuillez inserer une carte", colors.orange) end
            timer = os.startTimer(0.8)
        elseif event == "bank_card_inserted" then
            state.cardInserted = true
            redraw(state, 2, true)
            sleep(0.5)
            return true
        end
    end
end

local function animateCardId(state, finalId)
    state.cardIdDisplay = "XXXX"
    redraw(state, 3, true)
    sleep(0.2)

    local revealed = ""
    for position = 1, 4 do
        for digit = 0, 9 do
            state.cardIdDisplay = revealed .. tostring(digit) .. string.rep("X", 4 - position)
            redraw(state, 3, true)
            sleep(0.018)
        end
        revealed = finalId:sub(1, position)
        state.cardIdDisplay = revealed .. string.rep("X", 4 - position)
        redraw(state, 3, true)
        sleep(0.06)
    end

    state.cardId = finalId
    state.cardIdDisplay = finalId
    redraw(state, 3, true)
    sleep(0.2)
end

local function readPin(state, keypad)
    if keypad.clear then keypad.clear() end
    if keypad.setMaxLength then keypad.setMaxLength(4) end
    if keypad.setLocked then keypad.setLocked(false) end

    state.pin = nil
    state.pinDisplay = ""
    redraw(state, 4, true)

    while true do
        local event, a, b = os.pullEventRaw()
        if event == "terminate" or (event == "key" and a == keys.escape) then
            if keypad.setLocked then keypad.setLocked(true) end
            return false
        elseif event == "keypad_press" then
            local key = b
            if key == "C" then
                state.pinDisplay = ""
            elseif key and key:match("^%d$") and #state.pinDisplay < 4 then
                state.pinDisplay = state.pinDisplay .. key
            end
            redraw(state, 4, true)
        elseif event == "keypad_submit" then
            local value = tostring(b or "")
            if value:match("^%d%d%d%d$") then
                state.pin = value
                state.pinDisplay = value
                if keypad.flashGreen then keypad.flashGreen(20) end
                if keypad.beep then keypad.beep("success") end
                if keypad.setLocked then keypad.setLocked(true) end
                redraw(state, 4, true)
                sleep(0.5)
                return true
            end

            if keypad.flashRed then keypad.flashRed(20) end
            if keypad.beep then keypad.beep("error") end
            if keypad.clear then keypad.clear() end
            state.pinDisplay = ""
            redraw(state, 4, true, "Le code PIN doit contenir exactement 4 chiffres")
            sleep(1.2)
            redraw(state, 4, true)
        elseif event == "bank_card_removed" then
            if keypad.setLocked then keypad.setLocked(true) end
            state.cardInserted = false
            redraw(state, 2, true, "La carte a ete retiree")
            sleep(1.2)
            return nil, "CARD_REMOVED"
        end
    end
end

local function waitForValidation(state)
    while true do
        redraw(state, 5, true)
        local event, key = os.pullEventRaw()
        if event == "terminate" then return false end
        if event == "bank_card_removed" then
            state.cardInserted = false
            redraw(state, 5, true, "La carte a ete retiree")
            sleep(1.2)
            return nil, "CARD_REMOVED"
        elseif event == "key" then
            if key == keys.escape then return false end
            if key == keys.enter or key == keys.numPadEnter then return true end
        end
    end
end

local function encodeCard(state, writer)
    if not writer.hasCard or not writer.hasCard() then
        return nil, "Aucune carte inseree"
    end

    local ok, err = pcall(function()
        writer.beginWrite(
            state.account.owner,
            "active",
            state.pin,
            state.cardId,
            ""
        )
    end)
    if not ok then return nil, tostring(err) end

    ui.header("Encodage de la carte")
    ui.message(10, "Encodage en cours...", colors.orange)
    ui.footer("Ne retirez pas la carte")

    while true do
        local event, _, value = os.pullEventRaw()
        if event == "terminate" then return nil, "Operation interrompue" end
        if event == "bank_card_write_done" then
            if value == false then return nil, "Echec de l'encodage" end
            return true
        elseif event == "bank_card_write_error" then
            return nil, tostring(value or "Erreur inconnue")
        elseif event == "bank_card_removed" then
            return nil, "La carte a ete retiree pendant l'encodage"
        end
    end
end

function createCard.show()
    local writer = peripheral.find("bank_card_writer")
    if not writer then
        ui.header("Creation de carte bancaire")
        ui.message(10, "Aucun Bank Card Writer connecte", colors.red)
        ui.footer("Appuyez sur une touche pour revenir")
        ui.waitForAnyKey()
        return
    end

    local keypad = peripheral.find("keypad")
    if not keypad then
        ui.header("Creation de carte bancaire")
        ui.message(10, "Aucun Keypad connecte", colors.red)
        ui.footer("Appuyez sur une touche pour revenir")
        ui.waitForAnyKey()
        return
    end

    local account = selectAccount()
    if not account then return end

    local state = {
        account = account,
        cardInserted = false,
        cardId = nil,
        cardIdDisplay = nil,
        pin = nil,
        pinDisplay = "",
    }

    while true do
        if not waitForCard(state, writer) then return end

        local cardId, cardError = database.generateCardId()
        if not cardId then
            redraw(state, 3, true, cardError)
            ui.waitForAnyKey()
            return
        end
        animateCardId(state, cardId)

        local pinOk, pinError = readPin(state, keypad)
        if pinOk then
            local valid, validationError = waitForValidation(state)
            if valid then break end
            if validationError ~= "CARD_REMOVED" then return end
        elseif pinError ~= "CARD_REMOVED" then
            return
        end

        state.cardId = nil
        state.cardIdDisplay = nil
        state.pin = nil
        state.pinDisplay = ""
    end

    local encoded, encodeError = encodeCard(state, writer)
    if not encoded then
        redraw(state, 5, true, encodeError)
        ui.footer("Appuyez sur une touche pour revenir")
        ui.waitForAnyKey()
        return
    end

    local saved, saveError = database.assignCardId(state.account.accountNumber, state.cardId)
    if not saved then
        ui.header("Carte encodee")
        ui.message(9, "Carte encodee, mais sauvegarde impossible", colors.red)
        ui.message(11, tostring(saveError), colors.white)
        ui.footer("Appuyez sur une touche pour revenir")
        ui.waitForAnyKey()
        return
    end

    ui.header("Carte bancaire creee")
    ui.message(9, "Carte encodee avec succes", colors.green)
    ui.message(11, "Titulaire : " .. state.account.owner, colors.white)
    ui.message(12, ACCOUNT_LABEL .. state.account.accountNumber, colors.white)
    ui.message(13, "CardID : " .. state.cardId, colors.cyan)
    ui.footer("Appuyez sur une touche pour revenir")
    ui.waitForAnyKey()
end

return createCard
