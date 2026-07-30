local installed = {}

local settings = require("config.settings")
local filesystem = require("core.filesystem")

function installed.read()
    return filesystem.readTable(settings.markerPath)
end

function installed.getState(package)
    local marker = installed.read()

    if not marker then
        return {
            installed = false,
            samePackage = false,
            sameVersion = false
        }
    end

    return {
        installed = true,
        marker = marker,
        samePackage = marker.id == package.id,
        sameVersion =
            marker.id == package.id
            and marker.version == package.version
    }
end

return installed
