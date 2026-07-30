local checksum = {}

-- Empreinte FNV-1a 32 bits, suffisante pour détecter les modifications
-- accidentelles dans les petits fichiers ComputerCraft.
local OFFSET = 2166136261
local PRIME = 16777619
local MODULO = 4294967296

local function bxor(a, b)
    if bit32 and bit32.bxor then
        return bit32.bxor(a, b)
    end

    if bit and bit.bxor then
        return bit.bxor(a, b)
    end

    local result = 0
    local power = 1

    while a > 0 or b > 0 do
        local abit = a % 2
        local bbit = b % 2

        if abit ~= bbit then
            result = result + power
        end

        a = math.floor(a / 2)
        b = math.floor(b / 2)
        power = power * 2
    end

    return result
end

function checksum.string(value)
    local hash = OFFSET
    value = tostring(value or "")

    for index = 1, #value do
        hash = bxor(hash, value:byte(index))
        hash = (hash * PRIME) % MODULO
    end

    return string.format("%08x", hash)
end

function checksum.file(path)
    if not fs.exists(path) or fs.isDir(path) then
        return nil, "Fichier introuvable : " .. tostring(path)
    end

    local handle = fs.open(path, "rb") or fs.open(path, "r")

    if not handle then
        return nil, "Impossible d'ouvrir : " .. tostring(path)
    end

    local data = handle.readAll()
    handle.close()

    return checksum.string(data)
end

return checksum
