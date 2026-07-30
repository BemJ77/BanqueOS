local verifier = {}

local checksum = require("core.checksum")

function verifier.verify(package, onProgress)
    local result = {
        valid = false,
        checked = 0,
        total = package.fileCount,
        missing = {},
        modified = {},
        errors = {}
    }

    for index, file in ipairs(package.rawFiles) do
        if onProgress then
            onProgress(
                index - 1,
                result.total,
                file.displayPath,
                "Verification"
            )
        end

        if not fs.exists(file.destinationPath)
            or fs.isDir(file.destinationPath) then

            result.missing[#result.missing + 1] =
                file.destinationPath
        else
            local sourceHash, sourceError =
                checksum.file(file.sourcePath)

            local destinationHash, destinationError =
                checksum.file(file.destinationPath)

            if not sourceHash or not destinationHash then
                result.errors[#result.errors + 1] =
                    file.destinationPath
                    .. " : "
                    .. tostring(sourceError or destinationError)
            elseif sourceHash ~= destinationHash then
                result.modified[#result.modified + 1] =
                    file.destinationPath
            end
        end

        result.checked = result.checked + 1
    end

    table.sort(result.missing)
    table.sort(result.modified)
    table.sort(result.errors)

    result.valid =
        #result.missing == 0
        and #result.modified == 0
        and #result.errors == 0

    if onProgress then
        onProgress(
            result.total,
            result.total,
            result.valid
                and "Installation valide"
                or "Anomalies detectees",
            "Termine"
        )
    end

    return result
end

return verifier
