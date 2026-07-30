local storage = require("banqueos.core.storage")

local database = { data = nil }

local function defaultData()
    return {
        schemaVersion = 1,
        accounts = {},
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
    for _, account in pairs(database.data.accounts) do
        if type(account.cardIds) == "table" then
            for _, existingCardId in ipairs(account.cardIds) do
                if existingCardId == cardId then return true end
            end
        elseif account.cardId == cardId then
            -- Compatibilite avec une base ancienne pas encore migree.
            return true
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

function database.assignCardId(accountNumber, cardId)
    local account = database.getAccount(accountNumber)
    if not account then return nil, "Compte introuvable" end

    account.cardIds = account.cardIds or {}

    for _, existingCardId in ipairs(account.cardIds) do
        if existingCardId == cardId then
            return account
        end
    end

    if database.cardIdExists(cardId) then
        return nil, "Ce CardID est deja utilise"
    end

    table.insert(account.cardIds, cardId)
    database.save()
    return account
end

return database
