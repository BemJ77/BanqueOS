local ui = require("banqueos.core.ui")
local money = require("banqueos.core.money")
local database = require("banqueos.core.database")

local createAccount = {}

-- Le symbole degre est ecrit sur un seul octet pour rester compatible
-- avec le jeu de caracteres du terminal ComputerCraft.
local ACCOUNT_LABEL = "N" .. string.char(176) .. " de compte : "

local function writeAt(x, y, text, color)
    term.setCursorPos(x, y)
    term.setTextColor(color or colors.white)
    term.write(text)
end

local function clearInputArea(x, y)
    local width = term.getSize()
    term.setCursorPos(x, y)
    term.write(string.rep(" ", math.max(0, width - x + 1)))
    term.setCursorPos(x, y)
end

local function redraw(state, step, blinkVisible)
    ui.header("Creation de compte")

    -- Etape 1 : nom du titulaire.
    writeAt(3, 8, "Nom de l'utilisateur : ", colors.white)
    if state.owner then
        writeAt(25, 8, state.owner, colors.cyan)
    end

    -- Etape 2 : numero de compte.
    if step >= 2 then
        writeAt(3, 10, ACCOUNT_LABEL, colors.white)
        writeAt(3 + #ACCOUNT_LABEL, 10, state.accountDisplay or state.accountNumber or "XXXXXX", colors.cyan)
    end

    -- Etape 3 : identification biometrique.
    if step >= 3 then
        writeAt(3, 12, "ID joueur : ", colors.white)
        if state.biometricUUID then
            writeAt(15, 12, "Scan valide", colors.green)
            writeAt(3, 13, "Joueur : " .. (state.biometricPlayer or "Inconnu"), colors.white)
        elseif blinkVisible ~= false then
            writeAt(15, 12, "Attente du scan biometrique", colors.orange)
            writeAt(3, 13, "Veuillez passer votre main sur le lecteur", colors.white)
        end
    end

    -- Etape 4 : montant initial.
    if step >= 4 then
        writeAt(3, 15, "Montant initial : ", colors.white)
        if state.initialAmount ~= nil then
            writeAt(21, 15, money.formatEuros(state.initialAmount), colors.cyan)
        elseif state.amountInput then
            writeAt(21, 15, state.amountInput .. " €", colors.cyan)
        end
    end

    if step >= 5 then
        ui.drawButton(18, "VALIDER", state.ready)
    end

    ui.footer("Back : annuler")
end

local function showError(state, step, text)
    redraw(state, step, true)
    ui.message(17, text, colors.red)
    sleep(1.5)
end

local function askOwner(state)
    redraw(state, 1, true)
    local inputX = 25
    clearInputArea(inputX, 8)
    local value = ui.readField(inputX, 8, 25)
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then return nil, "Le nom est obligatoire" end
    state.owner = value
    return true
end

local function animateAccountNumber(state, finalNumber)
    state.accountDisplay = "XXXXXX"
    redraw(state, 2, true)
    sleep(0.2)

    local revealed = ""
    for position = 1, 6 do
        -- Chaque chiffre defile rapidement plusieurs fois avant de s'arreter.
        for cycle = 1, 1 do
            for digit = 0, 9 do
                state.accountDisplay = revealed .. tostring(digit) .. string.rep("X", 6 - position)
                redraw(state, 2, true)
                sleep(0.012)
            end
        end
        revealed = finalNumber:sub(1, position)
        state.accountDisplay = revealed .. string.rep("X", 6 - position)
        redraw(state, 2, true)
        sleep(0.05)
    end

    state.accountNumber = finalNumber
    state.accountDisplay = finalNumber
    redraw(state, 2, true)
    sleep(0.2)
end

local function waitForBiometric(state)
    local biolock = peripheral.find("biolock")
    if not biolock then return nil, "Aucun Biolock connecte" end

    if biolock.hasScan and biolock.hasScan() and biolock.clearLastScan then
        biolock.clearLastScan()
    end

    local visible = true
    redraw(state, 3, true)
    local timer = os.startTimer(0.8)

    while true do
        local event, a, b, c = os.pullEventRaw()
        if event == "terminate" or (event == "key" and a == keys.backspace) then
            return false, "CANCELLED"
        elseif event == "timer" and a == timer then
            visible = not visible
            local message = "Attente du scan biometrique"
            writeAt(15, 12, string.rep(" ", #message), colors.orange)
            if visible then
                writeAt(15, 12, message, colors.orange)
            end
            timer = os.startTimer(0.8)
        elseif event == "bio_scan" then
            state.biometricPlayer = b
            state.biometricUUID = c
            redraw(state, 3, true)
            sleep(0.7)
            return true
        end
    end
end

local function askInitialAmount(state)
    redraw(state, 4, true)
    local inputX = 21
    clearInputArea(inputX, 15)
    term.setCursorPos(inputX, 15)
    local raw = ui.readField(inputX, 15, 16)
    local value = money.parseEuros(raw)
    if value == nil then return nil, "Montant invalide" end
    state.amountInput = nil
    state.initialAmount = value
    return true
end

local function waitForValidation(state)
    state.ready = true
    while true do
        redraw(state, 5, true)
        local event, key = os.pullEventRaw()
        if event == "terminate" then return false end
        if event == "key" then
            if key == keys.backspace then return false end
            if key == keys.enter or key == keys.numPadEnter then return true end
        end
    end
end

function createAccount.show()
    local state = {
        owner = nil,
        accountNumber = nil,
        accountDisplay = nil,
        biometricPlayer = nil,
        biometricUUID = nil,
        initialAmount = nil,
        amountInput = nil,
        cardId = nil,
        history = {},
        ready = false,
    }

    while true do
        local ok, err = askOwner(state)
        if ok then break end
        showError(state, 1, err)
    end

    local number, numberError = database.generateAccountNumber()
    if not number then
        showError(state, 2, numberError)
        ui.waitForAnyKey()
        return
    end
    animateAccountNumber(state, number)

    local scanOk, scanError = waitForBiometric(state)
    if not scanOk then
        if scanError ~= "CANCELLED" then
            showError(state, 3, scanError)
            ui.waitForAnyKey()
        end
        return
    end

    while true do
        local ok, err = askInitialAmount(state)
        if ok then break end
        showError(state, 4, err)
    end

    if not waitForValidation(state) then return end

    local account, saveError = database.createAccount(
        state.owner,
        state.accountNumber,
        state.biometricPlayer,
        state.biometricUUID,
        state.initialAmount
    )

    if not account then
        showError(state, 5, saveError)
        ui.waitForAnyKey()
        return
    end

    ui.header("Compte cree")
    ui.message(9, "Compte cree avec succes", colors.green)
    ui.message(11, "Titulaire : " .. account.owner, colors.white)

    local line = ACCOUNT_LABEL .. account.accountNumber
    local width = term.getSize()
    local startX = math.max(1, math.floor((width - #line) / 2) + 1)
    writeAt(startX, 12, ACCOUNT_LABEL, colors.white)
    writeAt(startX + #ACCOUNT_LABEL, 12, account.accountNumber, colors.cyan)

    ui.message(13, "Solde : " .. money.formatEuros(account.balance), colors.white)
    ui.footer("Appuyez sur une touche pour revenir")
    ui.waitForAnyKey()
end

return createAccount
