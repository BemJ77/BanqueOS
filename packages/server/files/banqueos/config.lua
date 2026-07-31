return {
    name = "BANQUEOS",
    version = "0.8.0",

    -- Identite de la disquette bancaire.
    diskMarkerFile = ".banqueos_disk",
    diskDataDirectory = "banqueos",
    diskAccountsFile = "banqueos/accounts.db",

    -- Liaison permanente entre ce serveur et sa disquette active.
    activeDiskFile = "/banqueos/config/active_disk.id",

    -- Ancien emplacement utilise avant le stockage sur disquette.
    legacyDataFile = "/banqueos/data/accounts.db",

    historyLimit = 100,

    -- Communication sans fil BANQUEOS.
    networkProtocol = "banqueos.network.v1",
    requiredAtmVersion = "0.2.0",
    atmStartupScanSeconds = 2.5,
    atmHeartbeatTimeoutSeconds = 45,
}
