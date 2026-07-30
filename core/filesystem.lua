local filesystem = {}

local function ensureParent(path)
    local parent = fs.getDir(path)

    if parent ~= "" and not fs.exists(parent) then
        fs.makeDir(parent)
    end
end

function filesystem.ensureDirectory(path)
    if path == "" or path == "/" then
        return true
    end

    if fs.exists(path) then
        return fs.isDir(path)
    end

    local ok, err = pcall(fs.makeDir, path)

    if not ok then
        return false, tostring(err)
    end

    return fs.exists(path) and fs.isDir(path)
end

function filesystem.copyFile(source, destination)
    if not fs.exists(source) or fs.isDir(source) then
        return false, "Source invalide : " .. tostring(source)
    end

    ensureParent(destination)

    if fs.exists(destination) then
        if fs.isDir(destination) then
            return false, "La destination est un dossier : " .. destination
        end

        local okDelete, deleteError = pcall(fs.delete, destination)

        if not okDelete or fs.exists(destination) then
            return false, "Suppression impossible : " .. tostring(deleteError)
        end
    end

    local okCopy, copyError = pcall(fs.copy, source, destination)

    if not okCopy then
        return false, tostring(copyError)
    end

    if not fs.exists(destination) or fs.isDir(destination) then
        return false, "Le fichier copie est introuvable"
    end

    if fs.getSize(source) ~= fs.getSize(destination) then
        return false, "Taille differente apres copie"
    end

    return true
end

function filesystem.writeTable(path, value)
    ensureParent(path)

    local temporary = path .. ".tmp"

    if fs.exists(temporary) then
        fs.delete(temporary)
    end

    local handle = fs.open(temporary, "w")

    if not handle then
        return false, "Impossible d'ouvrir " .. temporary
    end

    handle.write("return ")
    handle.write(textutils.serialize(value))
    handle.write("\n")
    handle.close()

    if fs.exists(path) then
        local okDelete, deleteError = pcall(fs.delete, path)

        if not okDelete or fs.exists(path) then
            if fs.exists(temporary) then fs.delete(temporary) end
            return false, "Suppression impossible : " .. tostring(deleteError)
        end
    end

    local okMove, moveError = pcall(fs.move, temporary, path)

    if not okMove then
        return false, tostring(moveError)
    end

    return fs.exists(path)
end

function filesystem.readTable(path)
    if not fs.exists(path) or fs.isDir(path) then
        return nil, "Fichier introuvable : " .. tostring(path)
    end

    local chunk, err = loadfile(path)

    if not chunk then
        return nil, tostring(err)
    end

    local ok, value = pcall(chunk)

    if not ok then
        return nil, tostring(value)
    end

    if type(value) ~= "table" then
        return nil, "Le fichier ne retourne pas une table"
    end

    return value
end

function filesystem.scanFiles(root)
    local files = {}

    if not fs.exists(root) or not fs.isDir(root) then
        return files
    end

    local function scan(current)
        for _, name in ipairs(fs.list(current)) do
            local path = fs.combine(current, name)

            if fs.isDir(path) then
                scan(path)
            else
                files[#files + 1] = path
            end
        end
    end

    scan(root)
    table.sort(files)
    return files
end

return filesystem
