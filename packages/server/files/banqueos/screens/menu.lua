local ui = require("banqueos.core.ui")

local menu = {}

local entries = {
    "Creer un compte",
    "Liste des comptes",
    "Consulter un compte",
    "Creer une carte bancaire",
}

local function draw(selected)
    ui.header(nil)
    local startY = 7
    local width = term.getSize()
    for index, label in ipairs(entries) do
        local prefix = index == selected and "> " or "  "
        local text = prefix .. label
        local x = math.max(2, math.floor((width - #text) / 2) + 1)
        term.setCursorPos(x, startY + ((index - 1) * 2))
        term.setTextColor(index == selected and colors.cyan or colors.white)
        term.write(text)
    end
    ui.footer("Fleches : naviguer    Entree : valider")
end

function menu.select()
    local selected = 1
    while true do
        draw(selected)
        local event, key = os.pullEventRaw()
        if event == "terminate" then return nil end
        if event == "key" then
            if key == keys.up then
                selected = selected == 1 and #entries or selected - 1
            elseif key == keys.down then
                selected = selected == #entries and 1 or selected + 1
            elseif key == keys.enter or key == keys.numPadEnter then
                return selected
            end
        end
    end
end

return menu
