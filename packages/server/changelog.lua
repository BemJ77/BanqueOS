return {
    {
        version = "0.4.3",
        changes = {
            "Ajout de la possibilite d'associer plusieurs cartes bancaires a un meme compte.",
            "Migration automatique de l'ancien champ cardId vers la liste cardIds.",
        },
    },

    {
        version = "0.4.2",
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
