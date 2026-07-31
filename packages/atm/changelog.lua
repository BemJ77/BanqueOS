return {
    {
        version = "0.2.1",
        date = "2026-07-31",
        changes = {
            "Suppression du heartbeat permanent",
            "Ajout de la reponse aux pings du Serveur",
            "La reponse de ping contient uniquement succes, version et stock",
        }
    },
    {
        version = "0.2.0",
        date = "2026-07-31",
        changes = {
            "Transmission du stock actuel de l'ATM au Serveur",
            "Calcul du stock total avec atm.getCashStock()"
        }
    },
    {
        version = "0.1.3",
        date = "2026-07-31",
        changes = {
            "Chargement absolu de la configuration ATM",
            "Correction definitive du demarrage depuis /banqueos_atm/main.lua"
        }
    },
    {
        version = "0.1.2",
        date = "2026-07-31",
        changes = {
            "Correction du chemin de chargement du fichier config.lua"
        }
    },
    {
        version = "0.1.1",
        date = "2026-07-31",
        changes = {
            "Correction de la detection du nom du modem sans fil"
        }
    },
    {
        version = "0.1.0",
        date = "2026-07-31",
        changes = {
            "Premiere version du relais ATM",
            "Transmission des atm_request au Serveur par modem sans fil",
            "Synchronisation du statut des cartes lors de leur insertion",
            "Enregistrement et verification stricte de la version de l'ATM",
            "Attribution automatique d'un numero ATM par le Serveur"
        }
    }
}
