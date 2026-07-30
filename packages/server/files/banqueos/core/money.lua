local money = {}

function money.parseEuros(value)
    if type(value) ~= "string" then return nil end
    local normalized = value:gsub("%s", ""):gsub(",", ".")
    if not normalized:match("^%d+%.?%d*$") then return nil end
    local amount = tonumber(normalized)
    if not amount or amount < 0 then return nil end
    local rounded = math.floor(amount * 100 + 0.5) / 100
    return rounded
end

function money.formatEuros(amount)
    amount = tonumber(amount) or 0
    local whole = math.floor(amount)
    local cents = math.floor((amount - whole) * 100 + 0.5)
    if cents >= 100 then
        whole = whole + 1
        cents = 0
    end
    return string.format("%d,%02d euros", whole, cents)
end

return money
