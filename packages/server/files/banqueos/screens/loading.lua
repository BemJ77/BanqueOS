local ui = require("banqueos.core.ui")
local config = require("banqueos.config")

local loading = {}

local function line(y, text, color, delay)
    ui.message(y, text, color)
    sleep(delay or 0.25)
end

function loading.show(diskInfo)
    ui.reset()
    ui.center(4, "BANQUEOS", colors.blue)
    ui.center(6, "Systeme bancaire central", colors.lightBlue)
    ui.center(8, "Version " .. config.version, colors.gray)

    line(11, "Initialisation...", colors.white)
    line(12, "Verification de la liaison UUID...", colors.white)
    line(13, "Disquette active reconnue.", colors.green)

    if diskInfo and diskInfo.migrated then
        line(14, "Ancienne base copiee sur la disquette.", colors.orange)
    elseif diskInfo and diskInfo.initialized then
        line(14, "Nouvelle disquette initialisee et liee.", colors.orange)
    elseif diskInfo and diskInfo.upgraded then
        line(14, "Ancienne disquette liee par UUID.", colors.orange)
    else
        line(14, "Chargement des comptes...", colors.white)
    end

    line(15, "Recherche des ATM...", colors.white)
    line(16, "Systeme pret.", colors.green)
    ui.footer("Une touche : continuer   Auto : 5 sec")

    local timer = os.startTimer(5)
    while true do
        local event, value = os.pullEventRaw()

        if event == "terminate" then
            return false
        elseif event == "key" then
            return true
        elseif event == "timer" and value == timer then
            return true
        end
    end
end

return loading
