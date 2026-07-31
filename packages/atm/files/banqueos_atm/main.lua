local config = require("config")

local function ensureParent(path)
    local parent = fs.getDir(path)
    if parent ~= "" and not fs.exists(parent) then fs.makeDir(parent) end
end

local function loadState()
    ensureParent(config.stateFile)
    if fs.exists(config.stateFile) then
        local handle = fs.open(config.stateFile, "r")
        local state = textutils.unserialize(handle.readAll())
        handle.close()
        if type(state) == "table" and state.uuid then return state end
    end
    local state = {
        uuid = string.format("%d-%d-%06d", os.getComputerID(), os.epoch("utc"), math.random(0, 999999)),
        serverId = nil,
        atmNumber = nil,
    }
    local handle = fs.open(config.stateFile, "w")
    handle.write(textutils.serialize(state))
    handle.close()
    return state
end

local function saveState(state)
    ensureParent(config.stateFile)
    local handle = assert(fs.open(config.stateFile, "w"))
    handle.write(textutils.serialize(state))
    handle.close()
end

local function findWirelessModem()
    local modem = peripheral.find("modem", function(_, candidate)
        local ok, wireless = pcall(candidate.isWireless)
        return ok and wireless
    end)

    if not modem then return nil, nil end
    return modem, peripheral.getName(modem)
end

local function findAtm()
    return peripheral.find("atm")
end

local function openNetwork()
    local modem, name = findWirelessModem()
    if not modem then error("Aucun modem sans fil detecte") end
    if not rednet.isOpen(name) then rednet.open(name) end
end

local function showStatus(title, lines, color)
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.blue)
    print("BANQUEOS ATM")
    term.setTextColor(color or colors.white)
    print("")
    print(title)
    print("")
    for _, line in ipairs(lines or {}) do print(line) end
end

local function discoverServer(state)
    showStatus("Connexion au Serveur...", {})
    rednet.broadcast({
        kind = "hello",
        atmUuid = state.uuid,
        atmVersion = config.version,
        computerId = os.getComputerID(),
    }, config.protocol)

    local timer = os.startTimer(config.discoveryTimeoutSeconds)
    while true do
        local event, a, b, c = os.pullEventRaw()
        if event == "timer" and a == timer then
            return nil, "Serveur BANQUEOS introuvable"
        end
        if event == "rednet_message" and c == config.protocol and type(b) == "table"
            and b.kind == "hello_ack" then
            state.serverId = tonumber(b.serverId) or a
            state.atmNumber = tonumber(b.atmNumber)
            saveState(state)
            if not b.accepted then
                return nil, "Mise a jour requise : " .. tostring(b.requiredVersion)
            end
            return state.serverId
        end
    end
end

local function relay()
    math.randomseed(os.epoch("utc") % 2147483647)
    openNetwork()

    local atm = findAtm()
    if not atm then error("Aucun peripherique ATM detecte") end

    local state = loadState()
    local serverId, discoverError = discoverServer(state)
    if not serverId then
        showStatus("ATM indisponible", { discoverError }, colors.red)
        while true do
            local event = os.pullEventRaw()
            if event == "terminate" then return end
        end
    end

    showStatus(
        string.format("ATM N° %03d connecte", tonumber(state.atmNumber) or 0),
        { "Version " .. config.version, "Relais de communication actif" },
        colors.green
    )

    local pending = {}
    local heartbeatTimer = os.startTimer(config.heartbeatSeconds)

    while true do
        local event, a, b, c, d = os.pullEventRaw()

        if event == "terminate" then return end

        if event == "atm_request" then
            local atmId, requestId, request = a, b, c
            local relayId = string.format("%d-%d-%06d", os.getComputerID(), os.epoch("utc"), math.random(0, 999999))
            pending[relayId] = {
                requestId = requestId,
                expiresAt = os.epoch("utc") + config.requestTimeoutSeconds * 1000,
            }
            rednet.send(serverId, {
                kind = "request",
                relayId = relayId,
                atmUuid = state.uuid,
                atmNumber = state.atmNumber,
                atmVersion = config.version,
                atmId = atmId,
                request = request,
            }, config.protocol)

        elseif event == "atm_card_inserted" then
            local atmId, card = a, b
            if type(card) == "table" and card.id then
                local relayId = "status-" .. tostring(os.epoch("utc"))
                pending[relayId] = {
                    statusCheck = true,
                    cardStatus = tostring(card.status or "active"),
                    expiresAt = os.epoch("utc") + config.requestTimeoutSeconds * 1000,
                }
                rednet.send(serverId, {
                    kind = "status_check",
                    relayId = relayId,
                    atmUuid = state.uuid,
                    atmNumber = state.atmNumber,
                    atmVersion = config.version,
                    atmId = atmId,
                    cardId = tostring(card.id),
                    cardStatus = tostring(card.status or "active"),
                }, config.protocol)
            end

        elseif event == "rednet_message" and a == serverId and c == config.protocol and type(b) == "table" then
            if b.kind == "server_probe" then
                rednet.send(serverId, {
                    kind = "hello",
                    atmUuid = state.uuid,
                    atmVersion = config.version,
                    computerId = os.getComputerID(),
                }, config.protocol)

            elseif b.kind == "hello_ack" or b.kind == "heartbeat_ack" then
                state.atmNumber = tonumber(b.atmNumber) or state.atmNumber
                saveState(state)
                if not b.accepted then
                    showStatus("Mise a jour requise", {
                        "Version installee : " .. config.version,
                        "Version requise : " .. tostring(b.requiredVersion),
                    }, colors.red)
                end

            elseif b.kind == "response" and b.relayId and pending[b.relayId] then
                local item = pending[b.relayId]
                pending[b.relayId] = nil
                if b.code == "ATM_UPDATE_REQUIRED" then
                    showStatus("Mise a jour requise", {
                        "Veuillez mettre a jour cet ATM.",
                        "Version requise : " .. tostring(b.requiredVersion),
                    }, colors.red)
                end
                local response = {}
                for key, value in pairs(b) do
                    if key ~= "kind" and key ~= "relayId" and key ~= "atmNumber" then
                        response[key] = value
                    end
                end
                pcall(atm.reply, item.requestId, response)

            elseif b.kind == "status_response" and b.relayId and pending[b.relayId] then
                local item = pending[b.relayId]
                pending[b.relayId] = nil
                if b.success and b.status and tostring(b.status) ~= item.cardStatus then
                    if type(atm.setCardStatus) == "function" then
                        pcall(atm.setCardStatus, tostring(b.status))
                    end
                end
            end

        elseif event == "timer" and a == heartbeatTimer then
            rednet.send(serverId, {
                kind = "heartbeat",
                atmUuid = state.uuid,
                atmNumber = state.atmNumber,
                atmVersion = config.version,
            }, config.protocol)
            heartbeatTimer = os.startTimer(config.heartbeatSeconds)
        end

        local now = os.epoch("utc")
        for relayId, item in pairs(pending) do
            if now >= item.expiresAt then
                pending[relayId] = nil
                if item.requestId then
                    pcall(atm.reply, item.requestId, {
                        success = false,
                        code = "SERVER_TIMEOUT",
                    })
                end
            end
        end
    end
end

relay()
