local config = dofile("/banqueos_atm/config.lua")

local function ensureParent(path)
    local parent = fs.getDir(path)
    if parent ~= "" and not fs.exists(parent) then
        fs.makeDir(parent)
    end
end

local function loadState()
    ensureParent(config.stateFile)

    if fs.exists(config.stateFile) then
        local handle = fs.open(config.stateFile, "r")
        local state = textutils.unserialize(handle.readAll())
        handle.close()

        if type(state) == "table" and state.uuid then
            return state
        end
    end

    local state = {
        uuid = string.format(
            "%d-%d-%06d",
            os.getComputerID(),
            os.epoch("utc"),
            math.random(0, 999999)
        ),
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

    if not modem then
        return nil, nil
    end

    return modem, peripheral.getName(modem)
end

local function findAtm()
    return peripheral.find("atm")
end

local function openNetwork()
    local modem, name = findWirelessModem()

    if not modem then
        error("Aucun modem sans fil detecte")
    end

    if not rednet.isOpen(name) then
        rednet.open(name)
    end
end

local function getCashTotal(atm)
    if type(atm.getCashStock) ~= "function" then
        return 0
    end

    local ok, stock = pcall(atm.getCashStock)
    if not ok or type(stock) ~= "table" then
        return 0
    end

    local total = 0
    for denomination, count in pairs(stock) do
        total = total
            + (tonumber(denomination) or 0)
            * (tonumber(count) or 0)
    end

    return math.floor(total * 100 + 0.5) / 100
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

    for _, line in ipairs(lines or {}) do
        print(line)
    end
end

local function showUnavailable()
    showStatus(
        "ATM indisponible",
        { "Serveur BANQUEOS introuvable" },
        colors.red
    )
end

local function showConnected(state)
    showStatus(
        string.format(
            "ATM N° %03d connecte",
            tonumber(state.atmNumber) or 0
        ),
        {
            "Version " .. config.version,
            "Relais de communication actif",
        },
        colors.green
    )
end

local function sendHello(state, atm)
    rednet.broadcast({
        kind = "hello",
        atmUuid = state.uuid,
        atmVersion = config.version,
        computerId = os.getComputerID(),
        cashTotal = getCashTotal(atm),
    }, config.protocol)
end

local function waitForHelloAck(state, timeoutSeconds)
    local timer = os.startTimer(timeoutSeconds)

    while true do
        local event, a, b, c = os.pullEventRaw()

        if event == "terminate" then
            return nil, "TERMINATE"
        end

        if event == "timer" and a == timer then
            return nil, "TIMEOUT"
        end

        if event == "rednet_message"
            and c == config.protocol
            and type(b) == "table"
            and b.kind == "hello_ack"
        then
            state.serverId = tonumber(b.serverId) or a
            state.atmNumber = tonumber(b.atmNumber) or state.atmNumber
            saveState(state)

            if not b.accepted then
                return nil, {
                    code = b.code or "ATM_UPDATE_REQUIRED",
                    requiredVersion = b.requiredVersion,
                }
            end

            return state.serverId
        end
    end
end

local function connectToServer(state, atm, timeoutSeconds)
    sendHello(state, atm)
    return waitForHelloAck(
        state,
        timeoutSeconds or config.discoveryTimeoutSeconds
    )
end

local function waitAndReconnect(state, atm)
    showUnavailable()

    while true do
        local reconnectTimer = os.startTimer(config.reconnectSeconds)

        while true do
            local event, value = os.pullEventRaw()

            if event == "terminate" then
                return nil, "TERMINATE"
            end

            if event == "timer" and value == reconnectTimer then
                break
            end
        end

        local serverId, err = connectToServer(
            state,
            atm,
            config.connectionCheckTimeoutSeconds
        )

        if serverId then
            showConnected(state)
            return serverId
        end

        if type(err) == "table"
            and err.code == "ATM_UPDATE_REQUIRED"
        then
            showStatus(
                "ATM indisponible",
                {
                    "Mise a jour requise : "
                        .. tostring(err.requiredVersion),
                },
                colors.red
            )
        else
            showUnavailable()
        end
    end
end

local function verifyConnection(state, atm)
    local serverId, err = connectToServer(
        state,
        atm,
        config.connectionCheckTimeoutSeconds
    )

    if serverId then
        return serverId
    end

    if type(err) == "table"
        and err.code == "ATM_UPDATE_REQUIRED"
    then
        showStatus(
            "ATM indisponible",
            {
                "Mise a jour requise : "
                    .. tostring(err.requiredVersion),
            },
            colors.red
        )
    else
        showUnavailable()
    end

    return nil, err
end

local function replyUnavailable(atm, requestId)
    pcall(atm.reply, requestId, {
        success = false,
        code = "SERVER_UNAVAILABLE",
    })
end

local function relay()
    math.randomseed(os.epoch("utc") % 2147483647)
    openNetwork()

    local atm = findAtm()
    if not atm then
        error("Aucun peripherique ATM detecte")
    end

    local state = loadState()
    local serverId, connectionError = connectToServer(
        state,
        atm,
        config.discoveryTimeoutSeconds
    )

    if not serverId then
        if connectionError == "TERMINATE" then
            return
        end

        serverId, connectionError = waitAndReconnect(state, atm)
        if not serverId then
            return
        end
    else
        showConnected(state)
    end

    local pending = {}

    while true do
        local event, a, b, c = os.pullEventRaw()

        if event == "terminate" then
            return
        end

        if event == "atm_request" then
            local atmId, requestId, request = a, b, c

            local connectedServer = verifyConnection(state, atm)
            if not connectedServer then
                replyUnavailable(atm, requestId)

                connectedServer = waitAndReconnect(state, atm)
                if not connectedServer then
                    return
                end

                serverId = connectedServer
            else
                serverId = connectedServer

                local relayId = string.format(
                    "%d-%d-%06d",
                    os.getComputerID(),
                    os.epoch("utc"),
                    math.random(0, 999999)
                )

                pending[relayId] = {
                    requestId = requestId,
                    expiresAt = os.epoch("utc")
                        + config.requestTimeoutSeconds * 1000,
                }

                rednet.send(serverId, {
                    kind = "request",
                    relayId = relayId,
                    atmUuid = state.uuid,
                    atmNumber = state.atmNumber,
                    atmVersion = config.version,
                    cashTotal = getCashTotal(atm),
                    atmId = atmId,
                    request = request,
                }, config.protocol)
            end

        elseif event == "atm_card_inserted" then
            local atmId, card = a, b

            local connectedServer = verifyConnection(state, atm)
            if not connectedServer then
                connectedServer = waitAndReconnect(state, atm)
                if not connectedServer then
                    return
                end
                serverId = connectedServer
            else
                serverId = connectedServer
            end

            if type(card) == "table" and card.id then
                local relayId = "status-" .. tostring(os.epoch("utc"))

                pending[relayId] = {
                    statusCheck = true,
                    cardStatus = tostring(card.status or "active"),
                    expiresAt = os.epoch("utc")
                        + config.requestTimeoutSeconds * 1000,
                }

                rednet.send(serverId, {
                    kind = "status_check",
                    relayId = relayId,
                    atmUuid = state.uuid,
                    atmNumber = state.atmNumber,
                    atmVersion = config.version,
                    cashTotal = getCashTotal(atm),
                    atmId = atmId,
                    cardId = tostring(card.id),
                    cardStatus = tostring(card.status or "active"),
                }, config.protocol)
            end

        elseif event == "rednet_message"
            and a == serverId
            and c == config.protocol
            and type(b) == "table"
            and b.kind == "atm_ping"
        then
            rednet.send(serverId, {
                kind = "atm_ping_response",
                pingId = b.pingId,
                success = true,
                version = config.version,
                stock = getCashTotal(atm),
            }, config.protocol)

        elseif event == "rednet_message"
            and a == serverId
            and c == config.protocol
            and type(b) == "table"
        then
            if b.kind == "hello_ack" then
                state.atmNumber = tonumber(b.atmNumber)
                    or state.atmNumber
                saveState(state)

                if not b.accepted then
                    showStatus(
                        "ATM indisponible",
                        {
                            "Mise a jour requise : "
                                .. tostring(b.requiredVersion),
                        },
                        colors.red
                    )
                end

            elseif b.kind == "response"
                and b.relayId
                and pending[b.relayId]
            then
                local item = pending[b.relayId]
                pending[b.relayId] = nil

                local response = {}
                for key, value in pairs(b) do
                    if key ~= "kind"
                        and key ~= "relayId"
                        and key ~= "atmNumber"
                    then
                        response[key] = value
                    end
                end

                pcall(atm.reply, item.requestId, response)

            elseif b.kind == "status_response"
                and b.relayId
                and pending[b.relayId]
            then
                local item = pending[b.relayId]
                pending[b.relayId] = nil

                if b.success
                    and b.status
                    and tostring(b.status) ~= item.cardStatus
                    and type(atm.setCardStatus) == "function"
                then
                    pcall(atm.setCardStatus, tostring(b.status))
                end
            end
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
