local config = require("banqueos.config")
local database = require("banqueos.core.database")

local network = {}

local function findWirelessModem()
    local modem = peripheral.find("modem", function(_, candidate)
        local ok, wireless = pcall(candidate.isWireless)
        return ok and wireless
    end)

    if not modem then return nil, nil end
    return modem, peripheral.getName(modem)
end

local function openRednet()
    local modem, name = findWirelessModem()
    if not modem then return nil, "Aucun modem sans fil detecte" end
    if not rednet.isOpen(name) then rednet.open(name) end
    return name
end

local function responseCodeForError(err)
    if err == "Carte introuvable" then return "CARD_NOT_FOUND" end
    if err == "Compte associe introuvable" then return "ACCOUNT_NOT_FOUND" end
    if err == "Carte bloquee" then return "CARD_BLOCKED" end
    if err == "Solde insuffisant" then return "INSUFFICIENT_FUNDS" end
    if err == "Montant invalide" then return "INVALID_AMOUNT" end
    return "SERVER_ERROR"
end

local function validateAtm(senderId, message)
    if tostring(message.atmVersion or "") ~= config.requiredAtmVersion then
        return nil, {
            kind = "response",
            relayId = message.relayId,
            success = false,
            code = "ATM_UPDATE_REQUIRED",
            requiredVersion = config.requiredAtmVersion,
        }
    end
    local atm, registerError = database.registerAtm(
        message.atmUuid,
        senderId,
        message.atmVersion,
        message.cashTotal
    )
    if not atm then
        return nil, {
            kind = "response",
            relayId = message.relayId,
            success = false,
            code = registerError or "ATM_REJECTED",
        }
    end
    return atm
end

local function processBankRequest(request)
    if type(request) ~= "table" then
        return { success = false, code = "INVALID_REQUEST" }
    end

    local requestType = tostring(request.type or "")
    local cardId = tostring(request.cardId or "")

    if requestType == "block_card" then
        local card, err = database.updateCardStatus(cardId, "blocked")
        if not card then return { success = false, code = responseCodeForError(err) } end
        return { success = true, code = "CARD_BLOCKED", status = "blocked" }
    end

    local account, card, err = database.getAccountForCard(cardId)
    if not account then return { success = false, code = responseCodeForError(err) } end
    if tostring(card.status or "active") ~= "active" then
        return { success = false, code = "CARD_BLOCKED", status = "blocked" }
    end

    if requestType == "balance" then
        return {
            success = true,
            code = "OK",
            balance = tonumber(account.balance) or 0,
            status = tostring(card.status or "active"),
        }
    elseif requestType == "withdraw" then
        local updated, withdrawErr = database.withdrawByCard(cardId, request.amount)
        if not updated then return { success = false, code = responseCodeForError(withdrawErr) } end
        return { success = true, code = "OK", balance = updated.balance, status = card.status }
    elseif requestType == "deposit" then
        local updated, depositErr = database.depositByCard(cardId, request.amount)
        if not updated then return { success = false, code = responseCodeForError(depositErr) } end
        return { success = true, code = "OK", balance = updated.balance, status = card.status }
    elseif requestType == "history" then
        local history, historyErr = database.getHistoryForCard(cardId, 20)
        if not history then return { success = false, code = responseCodeForError(historyErr) } end
        return { success = true, code = "OK", history = history, status = card.status }
    end

    return { success = false, code = "UNKNOWN_REQUEST" }
end

function network.startupScan()
    local modemName = openRednet()
    if not modemName then return {}, false end

    rednet.broadcast({
        kind = "server_probe",
        requiredVersion = config.requiredAtmVersion,
    }, config.networkProtocol)

    local timer = os.startTimer(config.atmStartupScanSeconds)
    local outdated = {}

    while true do
        local event, a, b, c = os.pullEventRaw()
        if event == "timer" and a == timer then break end
        if event == "rednet_message" and c == config.networkProtocol and type(b) == "table" then
            if b.kind == "hello" and b.atmUuid then
                local atm = database.registerAtm(b.atmUuid, a, b.atmVersion, b.cashTotal)
                rednet.send(a, {
                    kind = "hello_ack",
                    accepted = tostring(b.atmVersion or "") == config.requiredAtmVersion,
                    atmNumber = atm.number,
                    requiredVersion = config.requiredAtmVersion,
                    serverId = os.getComputerID(),
                }, config.networkProtocol)
                if tostring(b.atmVersion or "") ~= config.requiredAtmVersion then
                    outdated[atm.number] = true
                end
            end
        end
    end

    local list = {}
    for number in pairs(outdated) do list[#list + 1] = number end
    table.sort(list)
    return list, true
end


function network.pingAtms(atms)
    local modemName = openRednet()
    if not modemName then return {} end

    local pending = {}
    local results = {}

    for _, atm in ipairs(atms or {}) do
        local computerId = tonumber(atm.computerId)
        if computerId then
            local pingId = string.format(
                "ping-%d-%d-%d",
                os.getComputerID(),
                tonumber(atm.number) or 0,
                os.epoch("utc")
            )
            pending[pingId] = {
                uuid = tostring(atm.uuid),
                computerId = computerId,
            }
            rednet.send(computerId, {
                kind = "atm_ping",
                pingId = pingId,
            }, config.networkProtocol)
        end
    end

    local timer = os.startTimer(tonumber(config.atmPingTimeoutSeconds) or 1.2)

    while next(pending) do
        local event, senderId, message, protocol = os.pullEventRaw()

        if event == "timer" and senderId == timer then break end
        if event == "terminate" then break end

        if event == "rednet_message"
            and protocol == config.networkProtocol
            and type(message) == "table"
            and message.kind == "atm_ping_response"
            and pending[message.pingId]
        then
            local item = pending[message.pingId]
            if senderId == item.computerId then
                results[item.uuid] = {
                    success = message.success == true,
                    version = tostring(message.version or ""),
                    stock = tonumber(message.stock) or 0,
                }
                pending[message.pingId] = nil
            end
        end
    end

    return results
end

function network.serviceLoop()
    local modemName = openRednet()
    if not modemName then
        while true do
            local event = os.pullEventRaw()
            if event == "terminate" then return "TERMINATE" end
        end
    end

    while true do
        local event, senderId, message, protocol = os.pullEventRaw()
        if event == "terminate" then return "TERMINATE" end

        if event == "rednet_message" and protocol == config.networkProtocol and type(message) == "table" then
            if message.kind == "hello" and message.atmUuid then
                local atm = database.registerAtm(message.atmUuid, senderId, message.atmVersion, message.cashTotal)
                if not atm then
                    rednet.send(senderId, {
                        kind = "hello_ack",
                        accepted = false,
                        code = "ATM_SUPPRIME",
                        requiredVersion = config.requiredAtmVersion,
                        serverId = os.getComputerID(),
                    }, config.networkProtocol)
                else
                rednet.send(senderId, {
                    kind = "hello_ack",
                    accepted = tostring(message.atmVersion or "") == config.requiredAtmVersion,
                    atmNumber = atm.number,
                    requiredVersion = config.requiredAtmVersion,
                    serverId = os.getComputerID(),
                }, config.networkProtocol)
                end

            elseif message.kind == "status_check" then
                local atm, rejection = validateAtm(senderId, message)
                if not atm then
                    rejection.kind = "status_response"
                    rednet.send(senderId, rejection, config.networkProtocol)
                else
                    local card = database.getCard(message.cardId)
                    rednet.send(senderId, {
                        kind = "status_response",
                        relayId = message.relayId,
                        success = card ~= nil,
                        code = card and "OK" or "CARD_NOT_FOUND",
                        status = card and tostring(card.status or "active") or nil,
                    }, config.networkProtocol)
                end

            elseif message.kind == "request" then
                local atm, rejection = validateAtm(senderId, message)
                if not atm then
                    rednet.send(senderId, rejection, config.networkProtocol)
                else
                    local response = processBankRequest(message.request)
                    response.kind = "response"
                    response.relayId = message.relayId
                    response.atmNumber = atm.number
                    rednet.send(senderId, response, config.networkProtocol)
                end
            end
        end
    end
end

return network
