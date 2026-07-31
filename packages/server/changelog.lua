return {
    {
        version = "0.8.3",
        date = "2026-07-31",
        changes = {
            "Passage automatique au menu principal apres 5 secondes",
            "Conservation du passage immediat avec une touche"
        }
    },
    {
        version = "0.8.2",
        date = "2026-07-31",
        changes = {
            "Mise a jour de la version ATM requise vers 0.2.3"
        }
    },
    {
        version = "0.8.1",
        date = "2026-07-31",
        changes = {
            "Ajout du numero ATM sur la ligne d'etat",
            "Remplacement du heartbeat par un ping a la demande",
            "Verification de l'etat uniquement dans Gestion des ATM",
            "Affichage du stock comme indisponible si l'ATM ne repond pas",
        }
    },
    {
        version = "0.8.0",
        date = "2026-07-31",
        changes = {
            "Ajout de la ligne Recherche des ATM au chargement",
            "Ajout du menu Gestion des ATM",
            "Affichage de l'etat, de la version, du nom et du stock actuel",
            "Ajout du renommage et de la suppression des ATM"
        }
    },
    {
        version = "0.7.3",
        date = "2026-07-31",
        changes = {
            "Mise a jour de la version ATM requise vers 0.1.3"
        }
    },
    {
        version = "0.7.2",
        date = "2026-07-31",
        changes = {
            "Mise a jour de la version ATM requise vers 0.1.2"
        }
    },
    {
        version = "0.7.1",
        date = "2026-07-31",
        changes = {
            "Correction de l'ouverture du modem sans fil"
        }
    },
    {
        version = "0.7.0",
        date = "2026-07-31",
        changes = {
            "Ajout de la communication sans fil avec le package ATM",
            "Ajout des requetes balance, withdraw, deposit, history et block_card",
            "Enregistrement permanent des ATM et attribution d'un numero",
            "Refus des ATM dont la version n'est pas exactement a jour",
            "Avertissement au demarrage pour les ATM a mettre a jour"
        }
    },
    {
        version = "0.6.0",
        date = "2026-07-31",
        changes = {
            "Ajout du menu Gestion des cartes",
            "Ajout de la consultation de toutes les cartes, y compris les cartes orphelines",
            "Ajout du blocage administratif d'une carte dans la base serveur",
            "Ajout du deblocage avec lecture et reencodage du statut de la carte",
            "Reutilisation de la modification du PIN et de la suppression de carte"
        }
    },

    {
        version = "0.5.3",
        date = "2026-07-31",
        changes = {
            "Ajout de writer.readCard() pour les reecritures partielles",
            "Conservation des donnees existantes lors du changement de PIN",
            "Verification du CardID avant reecriture"
        }
    },

    {
        version = "0.5.2",
        date = "2026-07-31",
        changes = {
            "Correction de la modification du code PIN",
            "Conservation des autres donnees de la carte pendant le reencodage",
        },
    },

    {
        version = "0.5.1",
        date = "31/07/2026",
        changes = {
            "Correction de l'affichage du statut des cartes",
            "Verification du CardID avant modification ou suppression d'une carte",
            "Message d'erreur lorsqu'une mauvaise carte est inseree"
        }
    },
    {
        version = "0.5.0",
        date = "2026-07-31",
        changes = {
            "Ajout du menu Consultation des comptes",
            "Ajout de l'historique et de la modification du solde",
            "Ajout de la gestion des cartes associees",
            "Ajout de la modification du PIN et de la suppression de carte",
            "Ajout de la suppression de compte avec conservation des cartes orphelines",
        },
    },

    {
        version = "0.4.4",
        type = "fix",
        changes = {
            "Remplacement de Echap par Back dans la creation de compte.",
            "Ajustement du pied de page de creation de carte.",
            "Synchronisation des metadonnees du package Serveur."
        }
    },
    {
        version = "0.4.3",
        date = "2026-07-30",
        changes = {
            "Ajout de la possibilite d'associer plusieurs cartes bancaires a un meme compte.",
            "Migration automatique de l'ancien champ cardId vers la liste cardIds.",
        },
    },

    {
        version = "0.4.2",
        date = "2026-07-30",
        changes = {
            "Correction de la disposition de la selection des comptes",
            "Message clignotant pour les cartes bancaires deja encodees",
        },
    },

    {
        version = "0.4.1",
        changes = {
            "Remplacement de la touche Echap par Back pour revenir en arriere.",
            "Correction de l'affichage du compte selectionne sous le titre du module.",
            "Reinitialisation complete de la saisie apres un code PIN invalide.",
            "Verification qu'une carte bancaire est vierge avant sa creation."
        }
    },
    {
        version = "0.4.0",
        changes = {
            "Ajout de la creation de cartes bancaires depuis le Serveur.",
            "Selection du compte, attente de la carte et generation animee du CardID.",
            "Saisie du code PIN sur Keypad et encodage via Bank Card Writer.",
            "Enregistrement du CardID dans le fichier du compte."
        }
    },
    {
        version = "0.3.2",
        changes = {
            "Version stable initiale distribuee par BANQUEOS Manager.",
            "Gestion de la base bancaire sur disquette liee par UUID.",
            "Creation et consultation des comptes via l'interface Serveur."
        }
    }
}
