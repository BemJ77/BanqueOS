local ui = {}

local function size()
    return term.getSize()
end

function ui.reset()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    term.setCursorBlink(false)
end

function ui.center(y, text, color)
    local width = size()
    local x = math.max(1, math.floor((width - #text) / 2) + 1)
    term.setCursorPos(x, y)
    term.setTextColor(color or colors.white)
    term.write(text)
end

function ui.header(subtitle)
    ui.reset()
    ui.center(2, "BANQUEOS", colors.blue)
    ui.center(3, "v" .. require("banqueos.config").version, colors.gray)
    local width = size()
    term.setCursorPos(2, 5)
    term.setTextColor(colors.gray)
    term.write(string.rep("-", math.max(1, width - 2)))
    if subtitle then ui.center(6, subtitle, colors.lightBlue) end
end

function ui.footer(text)
    local width, height = size()
    term.setCursorPos(1, height)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    local shown = text or ""
    if #shown > width then shown = shown:sub(1, width) end
    term.setCursorPos(math.max(1, math.floor((width - #shown) / 2) + 1), height)
    term.write(shown)
    term.setBackgroundColor(colors.black)
end

function ui.message(y, text, color)
    local width = size()
    term.setCursorPos(1, y)
    term.setBackgroundColor(colors.black)
    term.clearLine()
    ui.center(y, text, color)
end

function ui.waitForAnyKey()
    while true do
        local event = os.pullEventRaw()
        if event == "key" or event == "char" or event == "mouse_click" then return true end
        if event == "terminate" then return false end
    end
end

function ui.readField(x, y, maxLength)
    term.setCursorPos(x, y)
    term.setTextColor(colors.cyan)
    term.setCursorBlink(true)

    -- Saisie simple, sans historique ni fonction d'autocompletion.
    local value = read()

    term.setCursorBlink(false)
    if maxLength and #value > maxLength then
        value = value:sub(1, maxLength)
    end
    return value
end

function ui.drawButton(y, label, selected)
    local text = "[ " .. label .. " ]"
    local width = size()
    local x = math.max(1, math.floor((width - #text) / 2) + 1)
    term.setCursorPos(x, y)
    term.setBackgroundColor(selected and colors.cyan or colors.gray)
    term.setTextColor(selected and colors.black or colors.white)
    term.write(text)
    term.setBackgroundColor(colors.black)
end

return ui
