local menu = {}
local theme = require("ui.theme")

local function centerText(y, text, color)
    local width = term.getSize()
    text = tostring(text or "")
    local x = math.floor((width - #text) / 2) + 1

    term.setTextColor(color or theme.text)
    term.setCursorPos(math.max(1, x), y)
    term.write(text)
end

local function clearScreen()
    term.setBackgroundColor(theme.background)
    term.setTextColor(theme.text)
    term.clear()
    term.setCursorPos(1, 1)
end

local function drawHeader(title, subtitle)
    centerText(2, title, theme.title)

    if type(subtitle) == "table" then
        local y = 3

        for _, line in ipairs(subtitle) do
            if type(line) == "table" then
                centerText(y, line.text or "", line.color or theme.subtitle)
            else
                centerText(y, line, theme.subtitle)
            end

            y = y + 1
        end

        return y
    end

    if subtitle then
        centerText(3, subtitle, theme.subtitle)
        return 4
    end

    return 3
end

function menu.select(options)
    local items = options.items or {}
    local selected = math.min(options.selected or 1, math.max(#items, 1))
    local offset = 0

    while true do
        clearScreen()
        local headerEndY = drawHeader(options.title or "MENU", options.subtitle)

        local width, height = term.getSize()
        local startY = math.max(6, headerEndY + 1)
        local visibleRows = math.max(1, height - startY - 2)

        if selected <= offset then
            offset = selected - 1
        elseif selected > offset + visibleRows then
            offset = selected - visibleRows
        end

        for row = 1, visibleRows do
            local index = offset + row
            local label = items[index]

            if label then
                local prefix = index == selected and "> " or "  "
                local color =
                    index == selected and theme.selected or theme.text
                local text = prefix .. tostring(label)

                if #text > width - 2 then
                    text = text:sub(1, width - 5) .. "..."
                end

                term.setCursorPos(2, startY + row - 1)
                term.setTextColor(color)
                term.write(text)
            end
        end

        centerText(
            height - 1,
            options.footer or "Fleches : naviguer  Entree : valider",
            theme.muted
        )

        local _, key = os.pullEvent("key")

        if key == keys.up then
            selected = selected - 1
            if selected < 1 then selected = #items end
        elseif key == keys.down then
            selected = selected + 1
            if selected > #items then selected = 1 end
        elseif key == keys.enter then
            return selected
        elseif key == keys.backspace or key == keys.left then
            return options.cancelValue or #items
        end
    end
end

function menu.message(options)
    clearScreen()
    local headerEndY = drawHeader(options.title or "INFORMATION", options.subtitle)

    local lines = options.lines or {}
    local _, height = term.getSize()
    local startY = math.max(
        math.max(6, headerEndY + 1),
        math.floor((height - #lines) / 2)
    )

    for index, line in ipairs(lines) do
        centerText(
            startY + index - 1,
            tostring(line),
            options.color or theme.text
        )
    end

    centerText(
        height - 1,
        options.footer or "Entree pour continuer",
        theme.muted
    )

    while true do
        local _, key = os.pullEvent("key")

        if key == keys.enter
            or key == keys.space
            or key == keys.backspace
            or key == keys.left then
            return
        end
    end
end

function menu.confirm(options)
    local choice = menu.select({
        title = options.title or "CONFIRMATION",
        subtitle = options.subtitle,
        items = {
            options.yesText or "Oui",
            options.noText or "Non"
        },
        selected = 2,
        cancelValue = 2
    })

    return choice == 1
end

function menu.list(options)
    local items = options.items or {}

    if #items == 0 then
        menu.message({
            title = options.title or "LISTE",
            lines = { "Aucun element" }
        })
        return
    end

    local selected = 1
    local offset = 0

    while true do
        clearScreen()
        local headerEndY = drawHeader(options.title or "LISTE", options.subtitle)

        local width, height = term.getSize()
        local startY = math.max(6, headerEndY + 1)
        local visibleRows = math.max(1, height - startY - 2)

        if selected <= offset then
            offset = selected - 1
        elseif selected > offset + visibleRows then
            offset = selected - visibleRows
        end

        for row = 1, visibleRows do
            local index = offset + row
            local value = items[index]

            if value then
                local prefix = index == selected and "> " or "  "
                local color =
                    index == selected and theme.selected or theme.text
                local text = prefix .. tostring(value)

                if #text > width - 2 then
                    text = text:sub(1, width - 5) .. "..."
                end

                term.setCursorPos(2, startY + row - 1)
                term.setTextColor(color)
                term.write(text)
            end
        end

        centerText(
            height - 1,
            options.footer or "Retour : revenir",
            theme.muted
        )

        local _, key = os.pullEvent("key")

        if key == keys.up then
            selected = math.max(1, selected - 1)
        elseif key == keys.down then
            selected = math.min(#items, selected + 1)
        elseif key == keys.enter
            or key == keys.backspace
            or key == keys.left then
            return
        end
    end
end

return menu
