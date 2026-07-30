local backup={}

local function ts()
 if os.date then return os.date("%Y-%m-%d_%H-%M-%S") end
 return tostring(os.epoch("utc"))
end

function backup.create(name)
 local dir="/backups/"..ts().."_"..(name or "package")
 if not fs.exists("/backups") then fs.makeDir("/backups") end
 fs.makeDir(dir)
 return dir
end

return backup
