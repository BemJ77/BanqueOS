local remote = {}
local logger = require("core.logger")
local CONFIG = "/config/repository.lua"
local CATALOG = "/downloads/catalog.lua"

local function loadTable(path)
    if not fs.exists(path) or fs.isDir(path) then return nil, "Fichier absent : " .. path end
    local chunk, err = loadfile(path)
    if not chunk then return nil, err end
    local ok, value = pcall(chunk)
    if not ok then return nil, value end
    if type(value) ~= "table" then return nil, "Table Lua attendue : " .. path end
    return value
end

local function repository()
    local cfg, err = loadTable(CONFIG)
    if not cfg then return nil, err end
    if cfg.enabled ~= true then return nil, "Depot GitHub non configure" end
    return cfg
end

local function baseUrl(cfg)
    return "https://raw.githubusercontent.com/" .. cfg.owner .. "/"
        .. cfg.repository .. "/" .. (cfg.branch or "main")
end

local function ensureParent(path)
    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
end

local function download(url, destination)
    if not http or not http.get then return false, "API HTTP indisponible" end
    local separator = url:find("?", 1, true) and "&" or "?"
    local cacheKey = tostring(
        os.epoch and os.epoch("utc")
        or math.floor(os.clock() * 1000)
    )

    local freshUrl = url .. separator .. "cache=" .. cacheKey

    local response, err = http.get(freshUrl, nil, true)
    if not response then return false, tostring(err or "Telechargement impossible") end
    local data = response.readAll()
    response.close()
    if type(data) ~= "string" or data == "" then return false, "Reponse vide" end

    ensureParent(destination)
    if fs.exists(destination) then fs.delete(destination) end
    local file = fs.open(destination, "w")
    if not file then return false, "Impossible d'ecrire " .. destination end
    local ok, writeErr = pcall(function() file.write(data) end)
    file.close()
    if not ok then
        if fs.exists(destination) then fs.delete(destination) end
        return false, tostring(writeErr)
    end
    return true
end

local function getCatalog()
    local cfg, err = repository()
    if not cfg then return nil, nil, err end
    if not fs.exists("/downloads") then fs.makeDir("/downloads") end
    local base = baseUrl(cfg)
    local ok, downloadErr = download(base .. "/catalog.lua", CATALOG)
    if not ok then return nil, nil, downloadErr end
    local catalog, catalogErr = loadTable(CATALOG)
    if not catalog then return nil, nil, catalogErr end
    return catalog, base
end

local function findEntry(catalog, folder)
    for _, entry in ipairs(catalog.packages or {}) do
        if entry.folder == folder then return entry end
    end
end

function remote.syncIndex(onProgress)
    local result = { success = false, updated = 0, errors = {} }
    local catalog, base, err = getCatalog()
    if not catalog then result.errors[1] = err; return result end

    if not fs.exists("/packages") then fs.makeDir("/packages") end
    local entries = catalog.packages or {}
    local total, current = #entries * 2, 0

    for _, entry in ipairs(entries) do
        local root = "/packages/" .. entry.folder
        if not fs.exists(root) then fs.makeDir(root) end
        if not fs.exists(root .. "/files") then fs.makeDir(root .. "/files") end

        for _, name in ipairs({ "package.lua", "changelog.lua" }) do
            if onProgress then onProgress(current, total, entry.folder .. "/" .. name, "Index GitHub") end
            local ok, downloadErr = download(
                base .. "/packages/" .. entry.folder .. "/" .. name,
                root .. "/" .. name
            )
            if not ok then
                result.errors[#result.errors + 1] =
                    entry.folder .. "/" .. name .. " : " .. tostring(downloadErr)
            end
            current = current + 1
        end
        result.updated = result.updated + 1
    end

    if onProgress then onProgress(total, total, "Index actualise", "Termine") end
    result.success = #result.errors == 0
    return result
end

function remote.downloadPackage(folder, onProgress)
    local result = { success = false, downloaded = 0, total = 0, errors = {} }
    local catalog, base, err = getCatalog()
    if not catalog then result.errors[1] = err; return result end

    local entry = findEntry(catalog, folder)
    if not entry then
        result.errors[1] = "Paquet absent du catalogue : " .. tostring(folder)
        return result
    end

    result.total = #(entry.files or {})
    local root = "/packages/" .. folder
    if fs.exists(root) then fs.delete(root) end
    fs.makeDir(root)

    for index, relative in ipairs(entry.files or {}) do
        if onProgress then
            onProgress(index - 1, result.total, folder .. "/" .. relative, "Telechargement")
        end
        local ok, downloadErr = download(
            base .. "/packages/" .. folder .. "/" .. relative,
            root .. "/" .. relative
        )
        if not ok then
            result.errors[1] = folder .. "/" .. relative .. " : " .. tostring(downloadErr)
            logger.error(result.errors[1])
            return result
        end
        result.downloaded = result.downloaded + 1
    end

    if onProgress then onProgress(result.total, result.total, "Paquet telecharge", "Termine") end
    result.success = true
    return result
end

return remote
