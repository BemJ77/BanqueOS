# ATM API

## Requêtes
- balance
- withdraw
- deposit
- history
- block_card

Après 3 erreurs de PIN, l'ATM bloque la carte puis envoie `block_card` au serveur afin de synchroniser le statut.
