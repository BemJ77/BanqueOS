local progress = {}
local theme = require("ui.theme")

local function center(y, text, color)
    local width = term.getSize()
    text = tostring(text or "")
    local x = math.floor((width - #text) / 2) + 1

    term.setCursorPos(math.max(1, x), y)
    term.setTextColor(color or theme.text)
    term.write(text)
end

function progress.draw(title, current, total, file, status)
    local width, height = term.getSize()

    term.setBackgroundColor(theme.background)
    term.setTextColor(theme.text)
    term.clear()

    center(2, title or "INSTALLATION", theme.title)
    center(4, status or "Copie des fichiers", theme.subtitle)

    total = math.max(tonumber(total) or 0, 1)
    current = math.max(0, math.min(tonumber(current) or 0, total))

    local percent = math.floor((current / total) * 100)
    local barWidth = math.max(10, width - 10)
    local filled = math.floor((current / total) * barWidth)
    local x = math.floor((width - barWidth) / 2) + 1
    local y = math.floor(height / 2)

    term.setCursorPos(x, y)
    term.setBackgroundColor(theme.progressEmpty)
    term.write(string.rep(" ", barWidth))

    if filled > 0 then
        term.setCursorPos(x, y)
        term.setBackgroundColor(theme.progressFilled)
        term.write(string.rep(" ", filled))
    end

    term.setBackgroundColor(theme.background)
    center(y + 2, tostring(percent) .. " %", theme.selected)
    center(
        y + 4,
        tostring(current) .. " / " .. tostring(total) .. " fichiers",
        theme.text
    )

    local displayFile = tostring(file or "")

    if #displayFile > width - 4 then
        displayFile = "..." .. displayFile:sub(-(width - 7))
    end

    center(y + 6, displayFile, theme.muted)
end

return progress
