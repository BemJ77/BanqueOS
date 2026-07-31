local storage = require("banqueos.core.storage")

local database = { data = nil }

local function defaultData()
    return {
        schemaVersion = 1,
        accounts = {},
        cards = {},
        atms = {},
    }
end

local function ensureParent(path)
    local parent = fs.getDir(path)
    if parent ~= "" and not fs.exists(parent) then fs.makeDir(parent) end
end

function database.load()
    ensureParent(storage.getDataFile())
    if not fs.exists(storage.getDataFile()) then
        database.data = defaultData()
        database.save()
        return database.data
    end

    local handle = assert(fs.open(storage.getDataFile(), "r"), "Impossible d'ouvrir la base des comptes")
    local raw = handle.readAll()
    handle.close()

    local parsed = textutils.unserialize(raw)
    if type(parsed) ~= "table" or type(parsed.accounts) ~= "table" then
        error("Base des comptes invalide ou corrompue")
    end
    parsed.cards = type(parsed.cards) == "table" and parsed.cards or {}
    parsed.atms = type(parsed.atms) == "table" and parsed.atms or {}

    -- Migration automatique des anciens comptes qui ne pouvaient avoir
    -- qu'une seule carte via le champ cardId.
    local migrated = false
    for _, account in pairs(parsed.accounts) do
        if type(account.cardIds) ~= "table" then
            account.cardIds = {}
            migrated = true
        end

        if account.cardId ~= nil then
            local alreadyPresent = false
            for _, existingCardId in ipairs(account.cardIds) do
                if existingCardId == account.cardId then
                    alreadyPresent = true
                    break
                end
            end
            if not alreadyPresent then
                table.insert(account.cardIds, account.cardId)
            end
            account.cardId = nil
            migrated = true
        end
    end

    database.data = parsed
    if migrated then database.save() end
    return database.data
end

function database.save()
    assert(database.data, "Base non chargee")
    ensureParent(storage.getDataFile())
    local temporary = storage.getDataFile() .. ".tmp"
    local handle = assert(fs.open(temporary, "w"), "Impossible d'ecrire la sauvegarde")
    handle.write(textutils.serialize(database.data, { compact = false }))
    handle.close()
    if fs.exists(storage.getDataFile()) then fs.delete(storage.getDataFile()) end
    fs.move(temporary, storage.getDataFile())
end

function database.accountExists(accountNumber)
    return database.data.accounts[accountNumber] ~= nil
end

function database.generateAccountNumber()
    for _ = 1, 10000 do
        local number = string.format("%06d", math.random(0, 999999))
        if not database.accountExists(number) then return number end
    end
    return nil, "Impossible de generer un numero de compte unique"
end

function database.createAccount(owner, accountNumber, biometricPlayer, biometricUUID, initialAmount)
    if database.accountExists(accountNumber) then return nil, "Ce numero de compte existe deja" end

    local history = {}
    if initialAmount > 0 then
        history[1] = {
            date = os.date("%Y-%m-%d %H:%M"),
            type = "initial_deposit",
            amount = initialAmount,
            balance = initialAmount,
            label = "Ouverture du compte",
        }
    end

    local account = {
        owner = owner,
        accountNumber = accountNumber,
        biometric = {
            player = biometricPlayer,
            uuid = biometricUUID,
        },
        balance = initialAmount,
        cardIds = {},
        history = history,
        active = true,
        createdAt = os.date("%Y-%m-%d %H:%M:%S"),
    }

    database.data.accounts[accountNumber] = account
    database.save()
    return account
end

function database.listAccounts()
    local list = {}
    for _, account in pairs(database.data.accounts) do
        table.insert(list, account)
    end
    table.sort(list, function(a, b) return a.accountNumber < b.accountNumber end)
    return list
end

function database.getAccount(accountNumber)
    return database.data.accounts[accountNumber]
end

function database.cardIdExists(cardId)
    if database.data.cards and database.data.cards[cardId] then return true end
    for _, account in pairs(database.data.accounts) do
        if type(account.cardIds) == "table" then
            for _, existingCardId in ipairs(account.cardIds) do
                if existingCardId == cardId then return true end
            end
        end
    end
    return false
end

function database.generateCardId()
    for _ = 1, 10000 do
        local cardId = string.format("%04d", math.random(0, 9999))
        if not database.cardIdExists(cardId) then return cardId end
    end
    return nil, "Impossible de generer un CardID unique"
end

function database.assignCardId(accountNumber, cardId, cardData)
    local account = database.getAccount(accountNumber)
    if not account then return nil, "Compte introuvable" end
    account.cardIds = account.cardIds or {}
    local present = false
    for _, existingCardId in ipairs(account.cardIds) do
        if existingCardId == cardId then present = true break end
    end
    if not present then table.insert(account.cardIds, cardId) end
    database.data.cards = database.data.cards or {}
    local record = database.data.cards[cardId] or {}
    record.cardId = cardId
    record.accountNumber = accountNumber
    record.owner = (cardData and cardData.owner) or record.owner or account.owner
    record.status = (cardData and cardData.status) or record.status or "active"
    record.pin = (cardData and cardData.pin) or record.pin
    record.data = (cardData and cardData.data) or record.data or ""
    database.data.cards[cardId] = record
    database.save()
    return account
end

function database.listCardsForAccount(accountNumber)
    local account = database.getAccount(accountNumber)
    local result = {}
    if not account then return result end
    database.data.cards = database.data.cards or {}
    for _, cardId in ipairs(account.cardIds or {}) do
        local card = database.data.cards[cardId] or { cardId = cardId, accountNumber = accountNumber, status = "active" }
        table.insert(result, card)
    end
    table.sort(result, function(a,b) return tostring(a.cardId) < tostring(b.cardId) end)
    return result
end

function database.updateCardPin(cardId, pin)
    database.data.cards = database.data.cards or {}
    local card = database.data.cards[cardId]
    if not card then return nil, "Carte introuvable" end
    card.pin = pin
    database.save()
    return card
end

function database.removeCardFromAccount(accountNumber, cardId)
    local account = database.getAccount(accountNumber)
    if not account then return nil, "Compte introuvable" end
    for i = #(account.cardIds or {}), 1, -1 do
        if account.cardIds[i] == cardId then table.remove(account.cardIds, i) end
    end
    if database.data.cards then database.data.cards[cardId] = nil end
    database.save()
    return true
end

function database.setBalance(accountNumber, newBalance)
    local account = database.getAccount(accountNumber)
    if not account then return nil, "Compte introuvable" end
    local old = tonumber(account.balance) or 0
    account.balance = newBalance
    account.history = account.history or {}
    table.insert(account.history, {
        date = os.date("%Y-%m-%d %H:%M"),
        type = "manual_balance_update",
        amount = newBalance - old,
        balance = newBalance,
        label = "Modification manuelle du solde",
    })
    database.save()
    return account
end

function database.deleteAccount(accountNumber)
    if not database.getAccount(accountNumber) then return nil, "Compte introuvable" end
    -- Les enregistrements de cartes sont volontairement conserves : ils deviennent orphelins.
    database.data.accounts[accountNumber] = nil
    database.save()
    return true
end


function database.getCard(cardId)
    database.data.cards = database.data.cards or {}
    return database.data.cards[tostring(cardId)]
end

function database.listCards()
    database.data.cards = database.data.cards or {}
    local result = {}
    for cardId, card in pairs(database.data.cards) do
        card.cardId = tostring(card.cardId or cardId)
        table.insert(result, card)
    end
    table.sort(result, function(a, b) return tostring(a.cardId) < tostring(b.cardId) end)
    return result
end

function database.updateCardStatus(cardId, status)
    local card = database.getCard(cardId)
    if not card then return nil, "Carte introuvable" end
    card.status = tostring(status)
    database.save()
    return card
end

function database.deleteCard(cardId)
    cardId = tostring(cardId)
    for _, account in pairs(database.data.accounts or {}) do
        for i = #(account.cardIds or {}), 1, -1 do
            if tostring(account.cardIds[i]) == cardId then table.remove(account.cardIds, i) end
        end
    end
    database.data.cards = database.data.cards or {}
    database.data.cards[cardId] = nil
    database.save()
    return true
end


local function appendHistory(account, operationType, amount, label)
    account.history = account.history or {}
    table.insert(account.history, 1, {
        date = os.date("%Y-%m-%d %H:%M"),
        type = operationType,
        amount = amount,
        balance = account.balance,
        label = label,
    })
    while #account.history > 100 do table.remove(account.history) end
end

function database.getAccountForCard(cardId)
    local card = database.getCard(cardId)
    if not card then return nil, nil, "Carte introuvable" end
    local account = database.getAccount(card.accountNumber)
    if not account then return nil, card, "Compte associe introuvable" end
    return account, card
end

function database.depositByCard(cardId, amount)
    amount = tonumber(amount)
    if not amount or amount <= 0 then return nil, "Montant invalide" end
    local account, card, err = database.getAccountForCard(cardId)
    if not account then return nil, err end
    if tostring(card.status or "active") ~= "active" then return nil, "Carte bloquee" end
    account.balance = math.floor(((tonumber(account.balance) or 0) + amount) * 100 + 0.5) / 100
    appendHistory(account, "deposit", amount, "Depot especes ATM")
    database.save()
    return account
end

function database.withdrawByCard(cardId, amount)
    amount = tonumber(amount)
    if not amount or amount <= 0 then return nil, "Montant invalide" end
    local account, card, err = database.getAccountForCard(cardId)
    if not account then return nil, err end
    if tostring(card.status or "active") ~= "active" then return nil, "Carte bloquee" end
    local balance = tonumber(account.balance) or 0
    if balance + 0.0001 < amount then return nil, "Solde insuffisant" end
    account.balance = math.floor((balance - amount) * 100 + 0.5) / 100
    appendHistory(account, "withdraw", -amount, "Retrait ATM")
    database.save()
    return account
end

function database.getHistoryForCard(cardId, limit)
    local account, card, err = database.getAccountForCard(cardId)
    if not account then return nil, err end
    if tostring(card.status or "active") ~= "active" then return nil, "Carte bloquee" end
    local result = {}
    local history = account.history or {}
    limit = math.max(1, math.min(tonumber(limit) or 20, 20))
    for i = 1, math.min(#history, limit) do
        local item = history[i]
        result[#result + 1] = {
            date = tostring(item.date or ""),
            type = tostring(item.type or ""),
            amount = tonumber(item.amount) or 0,
            balance = tonumber(item.balance) or 0,
            label = tostring(item.label or ""),
        }
    end
    return result
end

function database.registerAtm(atmUuid, computerId, version)
    database.data.atms = database.data.atms or {}
    atmUuid = tostring(atmUuid)
    local atm = database.data.atms[atmUuid]
    if not atm then
        local used = {}
        for _, value in pairs(database.data.atms) do
            used[tonumber(value.number)] = true
        end
        local number = 1
        while used[number] do number = number + 1 end
        atm = {
            uuid = atmUuid,
            number = number,
            createdAt = os.date("%Y-%m-%d %H:%M:%S"),
        }
        database.data.atms[atmUuid] = atm
    end
    atm.computerId = tonumber(computerId)
    atm.version = tostring(version or "")
    atm.lastSeen = os.epoch("utc")
    database.save()
    return atm
end

function database.listAtms()
    database.data.atms = database.data.atms or {}
    local result = {}
    for _, atm in pairs(database.data.atms) do result[#result + 1] = atm end
    table.sort(result, function(a, b) return tonumber(a.number) < tonumber(b.number) end)
    return result
end

return database
