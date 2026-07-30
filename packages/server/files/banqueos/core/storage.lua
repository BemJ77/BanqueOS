local config = require("banqueos.config")

local storage = {
    mountPath = nil,
    dataFile = nil,
    driveName = nil,
    activeUUID = nil,
}

local function join(base, child)
    return fs.combine(base, child)
end

local function ensureParent(path)
    local parent = fs.getDir(path)
    if parent ~= "" and not fs.exists(parent) then
        fs.makeDir(parent)
    end
end

local function readSerialized(path)
    if not fs.exists(path) then return nil end
    local handle = fs.open(path, "r")
    if not handle then return nil end
    local raw = handle.readAll()
    handle.close()
    return textutils.unserialize(raw)
end

local function writeSerialized(path, value)
    ensureParent(path)
    local handle = assert(fs.open(path, "w"), "Impossible d'ecrire " .. path)
    handle.write(textutils.serialize(value, { compact = false }))
    handle.close()
end

local function randomHex(length)
    local out = {}
    for i = 1, length do
        out[i] = string.format("%x", math.random(0, 15))
    end
    return table.concat(out)
end

local function generateUUID()
    return table.concat({
        randomHex(8), randomHex(4), randomHex(4), randomHex(4), randomHex(12)
    }, "-")
end

local function readMarker(mountPath)
    local marker = readSerialized(join(mountPath, config.diskMarkerFile))
    if type(marker) ~= "table" or marker.type ~= "BANQUEOS_DATA_DISK" then
        return nil
    end
    return marker
end

local function writeMarker(mountPath, uuid, createdAt)
    writeSerialized(join(mountPath, config.diskMarkerFile), {
        type = "BANQUEOS_DATA_DISK",
        schemaVersion = 2,
        uuid = uuid,
        createdAt = createdAt or os.date("%Y-%m-%d %H:%M:%S"),
    })
end

local function readBinding()
    local binding = readSerialized(config.activeDiskFile)
    if type(binding) ~= "table" or type(binding.uuid) ~= "string" or binding.uuid == "" then
        return nil
    end
    return binding
end

local function writeBinding(uuid)
    writeSerialized(config.activeDiskFile, {
        type = "BANQUEOS_SERVER_BINDING",
        schemaVersion = 1,
        uuid = uuid,
        linkedAt = os.date("%Y-%m-%d %H:%M:%S"),
    })
end

local function mountedDisks()
    local disks = {}

    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "drive" and disk.isPresent(name) then
            local mountPath = disk.getMountPath(name)
            if mountPath and fs.exists(mountPath) then
                local marker = readMarker(mountPath)
                table.insert(disks, {
                    driveName = name,
                    mountPath = mountPath,
                    marker = marker,
                    blank = #fs.list(mountPath) == 0,
                })
            end
        end
    end

    return disks
end

local function activate(entry, uuid)
    storage.driveName = entry.driveName
    storage.mountPath = entry.mountPath
    storage.activeUUID = uuid
    storage.dataFile = join(entry.mountPath, config.diskAccountsFile)

    local directory = join(entry.mountPath, config.diskDataDirectory)
    if not fs.exists(directory) then fs.makeDir(directory) end

    return {
        driveName = storage.driveName,
        mountPath = storage.mountPath,
        dataFile = storage.dataFile,
        uuid = storage.activeUUID,
    }
end

function storage.inspect()
    local binding = readBinding()
    local disks = mountedDisks()

    if binding then
        for _, entry in ipairs(disks) do
            if entry.marker and entry.marker.uuid == binding.uuid then
                return "READY", entry, binding
            end
        end
        return "BOUND_DISK_MISSING", disks, binding
    end

    if #disks == 0 then
        return "NO_DISK"
    end

    if #disks > 1 then
        return "TOO_MANY_DISKS", disks
    end

    local entry = disks[1]
    if entry.marker and type(entry.marker.uuid) == "string" and entry.marker.uuid ~= "" then
        return "UNBOUND_BANQUEOS_DISK", entry
    end

    if entry.marker and not entry.marker.uuid then
        return "LEGACY_BANQUEOS_DISK", entry
    end

    if entry.blank then
        return "BLANK_DISK", entry
    end

    return "NON_BLANK_DISK", entry
end

function storage.openBoundDisk(entry, binding)
    return activate(entry, binding.uuid)
end

function storage.initializeBlankDisk(entry)
    local uuid = generateUUID()
    local createdAt = os.date("%Y-%m-%d %H:%M:%S")
    writeMarker(entry.mountPath, uuid, createdAt)
    writeBinding(uuid)
    local info = activate(entry, uuid)
    info.initialized = true
    return info
end

function storage.upgradeLegacyDisk(entry)
    local uuid = generateUUID()
    local createdAt = entry.marker and entry.marker.createdAt or os.date("%Y-%m-%d %H:%M:%S")
    writeMarker(entry.mountPath, uuid, createdAt)
    writeBinding(uuid)
    local info = activate(entry, uuid)
    info.upgraded = true
    return info
end

function storage.hasLegacyData()
    return fs.exists(config.legacyDataFile)
end

function storage.migrateLegacyData()
    assert(storage.dataFile, "Disquette BANQUEOS non initialisee")
    if fs.exists(storage.dataFile) or not fs.exists(config.legacyDataFile) then
        return false
    end
    ensureParent(storage.dataFile)
    fs.copy(config.legacyDataFile, storage.dataFile)
    return true
end

function storage.getDataFile()
    assert(storage.dataFile, "Disquette BANQUEOS non initialisee")
    return storage.dataFile
end

function storage.isAvailable()
    if not storage.driveName or not disk.isPresent(storage.driveName) then return false end
    local mountPath = disk.getMountPath(storage.driveName)
    if mountPath ~= storage.mountPath then return false end
    local marker = mountPath and readMarker(mountPath) or nil
    return marker ~= nil and marker.uuid == storage.activeUUID
end

function storage.findActiveDisk()
    local binding = readBinding()
    if not binding then return nil end
    for _, entry in ipairs(mountedDisks()) do
        if entry.marker and entry.marker.uuid == binding.uuid then
            return activate(entry, binding.uuid)
        end
    end
    return nil
end

function storage.getDriveName()
    return storage.driveName
end

function storage.getActiveUUID()
    return storage.activeUUID
end

return storage
