# 🏦 BANQUEOS

BANQUEOS est un système bancaire complet pour **Minecraft** utilisant **CC:Tweaked** et **SecurityPeripheral**.

Le projet permet de gérer des comptes bancaires, des cartes bancaires, des distributeurs automatiques (ATM), ainsi qu'un système bancaire entièrement modulaire grâce à son gestionnaire de packages.

---

# ✨ Fonctionnalités

- 📦 Gestionnaire de packages intégré
- 🔄 Installation et mises à jour automatiques
- ✅ Vérification de l'intégrité des fichiers
- 🔧 Réparation automatique des installations
- 💾 Sauvegarde avant chaque mise à jour
- 📜 Consultation des changelogs
- 🌐 Téléchargement des packages depuis GitHub

---

# 🏦 Fonctionnalités du serveur

- 👤 Création de comptes bancaires
- 💰 Gestion du solde des comptes
- 📜 Historique des transactions
- 💳 Création de cartes bancaires
- 🔐 Gestion des codes PIN
- 🚫 Blocage et déblocage des cartes
- 🗂️ Gestion des cartes orphelines
- 📡 Synchronisation avec les ATM

---

# 📋 Prérequis

- Minecraft
- CC:Tweaked
- SecurityPeripheral
- Connexion HTTP activée
- Accès à Internet

---

# 🚀 Installation

Sur un ordinateur ComputerCraft neuf, exécutez simplement :

```lua
pastebin run f18kdSsE
```

L'installateur va automatiquement :

1. Télécharger le dernier installateur depuis GitHub
2. Installer BANQUEOS Manager
3. Télécharger les fichiers nécessaires
4. Configurer le système
5. Proposer un redémarrage

Aucune autre manipulation n'est nécessaire.

---

# 📦 Mise à jour

Les mises à jour sont gérées directement depuis **BANQUEOS Manager**.

Il suffit de choisir :

```
Packages
→ Mise à jour
```

Le Manager téléchargera automatiquement les nouvelles versions disponibles.

---

# 🖥️ Packages disponibles

- 🏦 Serveur bancaire
- 🏧 ATM *(à venir)*

Chaque package peut être :

- installé
- vérifié
- mis à jour
- désinstallé

indépendamment.

---

# 📂 Structure du dépôt

```
config/
core/
packages/
ui/

catalog.lua
install.lua
manager.lua
manifest.lua
startup
README.md
```

---

# 🔨 Développement

Le projet est développé en **Lua** pour **CC:Tweaked**.

Les packages sont automatiquement détectés depuis le dossier :

```
packages/
```

Chaque package possède son propre :

- package.lua
- changelog.lua
- fichiers

Le Manager construit automatiquement les informations nécessaires.

---

# 📌 Versions actuelles

| Package | Version |
|----------|---------|
| Manager | **1.0.0** |
| Server | **0.6.0** |
| ATM | *En développement* |

---

# 🛣️ Roadmap

### ✅ Version actuelle

- Gestion complète des comptes
- Gestion complète des cartes bancaires
- Gestion des PIN
- Blocage / Déblocage des cartes
- Historique des transactions

### 🚧 En développement

- Package ATM
- Synchronisation complète ATM ↔ Serveur
- Dépôts et retraits
- Consultation du solde
- Changement du code PIN depuis un ATM

### 🔮 Prévu

- Réseau bancaire
- Terminaux de paiement
- Banques centrales
- Agences bancaires

---

# 🌐 Dépôt GitHub

https://github.com/BemJ77/BanqueOS

---

# 📄 Licence

Aucune licence n'est définie pour le moment.

Tous droits réservés © BemJ77.