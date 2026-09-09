# Sellarus — versions publiées

Ce dépôt ne contient que les archives de version de **Sellarus**, un site vitrine une page,
auto-installable (PHP / MySQL), avec panier, commande et paiement en Bitcoin.

Chaque version est publiée dans l'onglet **Releases** avec :

- `sellarus-<version>.zip` : l'application complète (à déposer sur un hébergement PHP ≥ 8.1, puis ouvrir `install.php`) ;
- `sellarus-<version>.zip.sha256` : l'empreinte de l'archive, vérifiée par la mise à jour automatique ;
- `update.json` : le flux de mise à jour au format simple.

Les sites Sellarus installés vérifient ce dépôt depuis leur écran **Mise à jour** (rien à configurer) :
`https://api.github.com/repos/nitrus21/sellarus-releases/releases/latest`.
