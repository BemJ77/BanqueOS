# BANQUEOS

Depot du **BANQUEOS Manager** et de ses packages CC:Tweaked.

## Installation du Manager

Depuis un ordinateur CC:Tweaked avec HTTP active, telecharger puis executer `install.lua`.

Le Manager installe ensuite le package **Serveur** depuis `packages/server`.

## Structure

- `manager.lua` : interface principale du Manager
- `install.lua` : installation legere depuis GitHub
- `manifest.lua` : version et liste des fichiers du Manager
- `catalog.lua` : catalogue des packages telechargeables
- `packages/server/files/` : version installable du Serveur BANQUEOS 0.3.2

Le code du Serveur 0.3.2 est conserve sans modification dans le package afin de garder la version stable fonctionnelle.
