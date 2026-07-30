-- BANQUEOS Manager - installation legere
local OWNER, REPOSITORY, BRANCH = "BemJ77", "BanqueOS", "main"
local BASE = "https://raw.githubusercontent.com/" .. OWNER .. "/" .. REPOSITORY .. "/" .. BRANCH

local function parent(path)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
end

local function get(url)
    if not http or not http.get then return nil, "API HTTP indisponible" end
    local response, err = http.get(url, nil, true)
    if not response then return nil, tostring(err or "Telechargement impossible") end
    local data = response.readAll()
    response.close()
    if type(data) ~= "string" or data == "" then return nil, "Reponse vide" end
    return data
end

local function writeFile(path, data)
    parent(path)
    if fs.exists(path) then fs.delete(path) end
    local file = fs.open(path, "w")
    if not file then return false, "Impossible d'ecrire " .. path end
    local ok, err = pcall(function() file.write(data) end)
    file.close()
    if not ok then
        if fs.exists(path) then fs.delete(path) end
        return false, tostring(err)
    end
    return true
end

local function download(relative)
    write("Telechargement " .. relative .. " ... ")
    local data, err = get(BASE .. "/" .. relative)
    if not data then printError("ECHEC"); return false, err end
    local ok, writeErr = writeFile("/" .. relative, data)
    if not ok then printError("ECHEC"); return false, writeErr end
    print("OK")
    return true
end

local function loadManifest()
    local data, err = get(BASE .. "/manifest.lua")
    if not data then return nil, err end
    local chunk, loadErr = load(data, "@manifest.lua", "t", _ENV)
    if not chunk then return nil, loadErr end
    local ok, value = pcall(chunk)
    if not ok then return nil, value end
    if type(value) ~= "table" or type(value.managerFiles) ~= "table" then
        return nil, "Manifeste invalide"
    end
    return value
end

term.clear()
term.setCursorPos(1, 1)
print("INSTALLATION BANQUEOS MANAGER")
print("Manager uniquement")
print("")

local manifest, manifestErr = loadManifest()
if not manifest then printError(tostring(manifestErr)); return end

-- Nettoie les anciens essais et libere l'espace.
for _, path in ipairs({
    "/config", "/core", "/ui", "/packages", "/downloads",
    "/manager.lua", "/startup", "/catalog.lua",
    "/manifest.lua", "/update-manager.lua"
}) do
    if fs.exists(path) then fs.delete(path) end
end

for _, relative in ipairs(manifest.managerFiles) do
    local ok, err = download(relative)
    if not ok then
        printError("Installation interrompue : " .. tostring(err))
        print("Libre : " .. tostring(fs.getFreeSpace("/")) .. " octets")
        return
    end
end

for _, relative in ipairs({ "catalog.lua", "manifest.lua", "update-manager.lua" }) do
    local ok, err = download(relative)
    if not ok then printError(tostring(err)); return end
end

local config = table.concat({
    "return {",
    "    enabled = true,",
    '    owner = "' .. OWNER .. '",',
    '    repository = "' .. REPOSITORY .. '",',
    '    branch = "' .. BRANCH .. '"',
    "}",
    ""
}, "\n")

local ok, err = writeFile("/config/repository.lua", config)
if not ok then printError(tostring(err)); return end

print("")
print("Installation terminee.")
print("Les paquets seront telecharges a la demande.")
write("Redemarrer maintenant ? [O/n] ")
local answer = read():lower()
if answer == "" or answer == "o" or answer == "oui" or answer == "y" then
    os.reboot()
end
