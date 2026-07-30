local packages = {}

local settings = require("config.settings")
local filesystem = require("core.filesystem")

local function scanDirectory(root, relative, result, directories)
    local current = relative == "" and root or fs.combine(root, relative)

    for _, name in ipairs(fs.list(current)) do
        local childRelative = relative == "" and name or fs.combine(relative, name)
        local child = fs.combine(root, childRelative)

        if fs.isDir(child) then
            directories.count = directories.count + 1
            scanDirectory(root, childRelative, result, directories)
        else
            result[#result + 1] = {
                relativePath = childRelative,
                displayPath = "/" .. childRelative,
                sourcePath = child,
                destinationPath = "/" .. childRelative,
                size = fs.getSize(child)
            }
        end
    end
end

function packages.discover()
    local found = {}
    local errors = {}
    local root = settings.packagesRoot

    if not fs.exists(root) then
        return found, { "Dossier introuvable : " .. root }
    end

    for _, folderName in ipairs(fs.list(root)) do
        local packageRoot = fs.combine(root, folderName)

        if fs.isDir(packageRoot) then
            local metadataPath = fs.combine(packageRoot, "package.lua")
            local changelogPath = fs.combine(packageRoot, "changelog.lua")
            local filesRoot = fs.combine(packageRoot, "files")

            if fs.exists(metadataPath) and fs.exists(filesRoot) then
                local metadata, err = filesystem.readTable(metadataPath)

                if metadata then
                    local changelog = {}
                    if fs.exists(changelogPath) then
                        local loaded, changelogError = filesystem.readTable(changelogPath)
                        if loaded then
                            changelog = loaded
                        else
                            errors[#errors + 1] = folderName .. " changelog : " .. tostring(changelogError)
                        end
                    end

                    local rawFiles = {}
                    local directories = { count = 0 }
                    scanDirectory(filesRoot, "", rawFiles, directories)
                    table.sort(rawFiles, function(a, b) return a.relativePath < b.relativePath end)

                    local totalSize = 0
                    for _, file in ipairs(rawFiles) do totalSize = totalSize + file.size end

                    found[#found + 1] = {
                        folder = folderName,
                    id = metadata.id or folderName,
                        name = metadata.name or folderName,
                        version = metadata.version or "0.0.0",
                        author = metadata.author or "Inconnu",
                        description = metadata.description or "",
                        category = metadata.category or "Autre",
                        startup = metadata.startup or "/startup",
                        minManager = metadata.minManager or "0.0.0",
                        icon = metadata.icon,
                        root = packageRoot,
                        filesRoot = filesRoot,
                        changelog = changelog,
                        fileCount = #rawFiles,
                        directoryCount = directories.count,
                        totalSize = totalSize,
                        rawFiles = rawFiles
                    }
                else
                    errors[#errors + 1] = folderName .. " : " .. tostring(err)
                end
            end
        end
    end

    table.sort(found, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
    return found, errors
end

function packages.formatSize(size)
    size = tonumber(size) or 0
    if size < 1024 then return tostring(size) .. " o" end
    if size < 1024 * 1024 then return string.format("%.1f Ko", size / 1024) end
    return string.format("%.2f Mo", size / 1024 / 1024)
end

return packages
