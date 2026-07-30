local version = {}

local function parse(value)
    local parts = {}
    value = tostring(value or "0.0.0")

    for number in value:gmatch("%d+") do
        parts[#parts + 1] = tonumber(number) or 0
    end

    return {
        parts[1] or 0,
        parts[2] or 0,
        parts[3] or 0
    }
end

function version.compare(a, b)
    local left = parse(a)
    local right = parse(b)

    for index = 1, 3 do
        if left[index] < right[index] then
            return -1
        elseif left[index] > right[index] then
            return 1
        end
    end

    return 0
end

function version.isAtLeast(current, required)
    return version.compare(current, required) >= 0
end

return version
