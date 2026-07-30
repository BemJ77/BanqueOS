local ui = require("banqueos.core.ui")

local placeholder = {}

function placeholder.show(title)
    ui.header(title)
    ui.message(11, "Fonctionnalite disponible prochainement", colors.orange)
    ui.footer("Appuyez sur une touche pour revenir")
    ui.waitForAnyKey()
end

return placeholder
