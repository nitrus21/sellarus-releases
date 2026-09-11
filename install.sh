#!/usr/bin/env bash
# Sellarus — one-command installation on a Linux server (VPS).
#
#   curl -fsSL https://sellarus.com/install.sh | bash
#
# What it does, step by step, asking for your approval each time:
#   1. updates the system, 2. installs what is missing (Docker), 3. opens the web ports in the firewall,
#   4. asks for the shop name, your domain, e-mail and database settings, 5. checks that the domain points here,
#   6. writes the shop into /opt/sellarus/shops/<shop> behind the shared HTTPS front (/opt/sellarus/proxy) and starts it,
#   7. prints every piece of information you need and saves it in /opt/sellarus/shops/<shop>/INSTALLATION.txt.
# Run it again to add another shop on the same server (another domain). The same script serves every version:
# it always installs the latest published image.
# Options: --yes (approve every step), --lang <en|fr|de|es|it>, --shop <name>, --domain <name>, --email <address>,
#          --no-upgrade. Environment: SELLARUS_LANG, SELLARUS_SHOP, SELLARUS_DOMAIN, SELLARUS_EMAIL, SELLARUS_BASE_URL.
set -euo pipefail

BASE_URL="${SELLARUS_BASE_URL:-https://raw.githubusercontent.com/nitrus21/sellarus-releases/main}"
IMAGE="ghcr.io/nitrus21/sellarus"
DIR=/opt/sellarus
PROXY="$DIR/proxy"
SHOPS="$DIR/shops"
STEPS=7
STEP=0
YES=0
DO_UPGRADE=1
SHOP="${SELLARUS_SHOP:-}"
DOMAIN="${SELLARUS_DOMAIN:-}"
EMAIL="${SELLARUS_EMAIL:-}"
UI="${SELLARUS_LANG:-}"
ARGS=("$@")

# ---------- looks ----------
if [ -t 1 ]; then
    R=$'\033[0m'; B=$'\033[1m'; DIM=$'\033[2m'
    TEAL=$'\033[38;5;30m'; NAVY=$'\033[38;5;24m'; GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; WHITE=$'\033[97m'
    VIOLET=$'\033[38;5;135m'
else
    R=''; B=''; DIM=''; TEAL=''; NAVY=''; GREEN=''; RED=''; YELLOW=''; WHITE=''; VIOLET=''
fi
say()  { printf '%s\n' "${TEAL}${B}▶${R} $*"; }
ok()   { printf '%s\n' "  ${GREEN}✔${R} $*"; }
warn() { printf '%s\n' "  ${YELLOW}▲${R} $*"; }
die()  { printf '%s\n' "  ${RED}✖${R} $*" >&2; exit 1; }
note() { printf '%s\n' "  ${DIM}$*${R}"; }
why()  { printf '%s\n' "  ${VIOLET}$*${R}"; }
hr()   { printf '%s\n' "${DIM}──────────────────────────────────────────────────────────────${R}"; }

# ---------- languages ----------
# Explanations are translated; technical names (Docker, apt, DNS, commands…) stay in English and are written
# between braces in the texts so that they are shown in yellow: "{Docker} is running".
declare -A T_en T_fr T_de T_es T_it
T_en=(
    [tagline]="Your online shop, ready in minutes — server installation"
    [sys]="System: %s (package manager: {%s})"
    [shops_existing]="Shops already on this server: %s— this run adds another one (another domain)."
    [legacy]="A shop installed with the first layout lives in %s; it will be converted (data kept) before continuing."
    [err_root]="Run this script as root: type {sudo -i}, then run the command again."
    [restart_sudo]="Restarting with {sudo}"
    [err_os]="Unsupported system: {/etc/os-release} not found."
    [err_distro]="This script supports Debian, Ubuntu, Fedora, Rocky and AlmaLinux (found: %s)."
    [unknown_opt]="unknown option: %s"
    [run_failed]="%s failed (full log: %s)"
    [log_tail]="Last lines of the log:"
    [yes_auto]="→ yes (--yes)"
    [step1]="System update"
    [why1]="The server's software is brought up to date before anything is installed, so the shop runs on a healthy system."
    [q_upgrade]="Update and upgrade the system packages now?"
    [pkg_refreshed]="Package lists refreshed"
    [sys_upgraded]="System upgraded"
    [upgrade_skipped]="System upgrade skipped."
    [step2]="Dependencies"
    [why2]="Sellarus runs inside {Docker}. This step looks at what is already on the server and installs only what is missing — nothing is downloaded twice."
    [q_tools]="Install %s?"
    [err_curl]="{curl} is required."
    [installed]="Installed: %s"
    [tools_present]="{curl} and certificates already present"
    [docker_present]="{Docker} already installed: %s"
    [q_docker]="{Docker} is missing. Install it now (official Docker packages)?"
    [err_docker]="{Docker} is required."
    [docker_installed]="{Docker} installed"
    [err_docker_down]="{Docker} does not answer. Check {systemctl status docker} and run the script again."
    [docker_running]="{Docker} is running"
    [stack_files]="Stack files downloaded"
    [legacy_convert]="Converting the existing shop to the new layout (data kept)"
    [step3]="Network"
    [why3]="The shop must be reachable on the web ports {80} (HTTP) and {443} (HTTPS). If a local firewall exists, this step opens them."
    [front_running]="The HTTPS front of this server is already running (ports 80 and 443 are its own)"
    [q_ufw]="Open ports 80 and 443 in {ufw}?"
    [ufw_ok]="{ufw}: ports 80/443 open"
    [q_fw]="Open the http and https services in {firewalld}?"
    [fw_ok]="{firewalld}: http/https open"
    [no_fw]="No local firewall to configure (check the firewall of your provider: ports 80 and 443 must be open)"
    [port_busy]="Port %s is already in use on this server (another web server?). Stop it, then run the script again."
    [ports_free]="Ports 80 and 443 are free"
    [step4]="Your settings"
    [why4]="A few questions: the domain of the shop, an e-mail for the certificate, a short name and the database. Press Enter to accept what is proposed between brackets."
    [public_ip]="Public address of this server: %s"
    [q_domain_more]="Domain name of the new shop (required: the other shops are told apart by their domain)"
    [q_domain]="Domain name of the shop (empty = no domain, HTTP on the IP address only)"
    [err_domain]="'%s' does not look like a domain name."
    [err_domain_used]="%s is already the domain of the shop '%s'."
    [q_email]="Your e-mail (for the HTTPS certificate: expiry notices)"
    [err_email]="'%s' does not look like an e-mail address."
    [err_ip_shop]="The shop '%s' already answers on the bare server address: a second shop needs a domain name."
    [err_need_domain]="A domain name is required to add a shop next to %s."
    [q_shop]="Short name of this shop on the server (letters, digits, dashes)"
    [err_shop_invalid]="Invalid name '%s' (letters, digits, dashes, 31 characters at most)."
    [err_shop_yes]="Invalid --shop value."
    [err_shop_exists]="A shop named '%s' already exists on this server."
    [err_shop_used]="Shop name already used."
    [q_db_name]="Database name"
    [q_db_user]="Database user"
    [q_db_pass]="Database password (Enter = generated)"
    [q_db_root]="Database root password (Enter = generated)"
    [step5]="Domain check"
    [why5]="The domain must point to this server's public address so that the HTTPS certificate can be issued. A {DNS} record created a few minutes ago may not be visible yet."
    [dns_ok]="%s points to this server (%s)"
    [dns_warn]="%s does not point to this server yet (resolves to: %s, server: %s)"
    [dns_hint]="At your domain registrar, add a {DNS} record:  {A}  %s  →  %s"
    [dns_hint2]="(and 'www' too if you want www.%s). Changes can take a few minutes to spread."
    [q_recheck]="Check again?"
    [q_continue]="Continue anyway? (the certificate will be obtained automatically once the domain points here)"
    [stopped_domain]="Installation stopped. Run the script again when the domain is ready."
    [no_domain]="No domain: the shop will answer on http://%s without HTTPS. Add a domain later with: {sellarus domain %s your-domain.tld}"
    [step6]="Installation"
    [why6]="The shop's files are written, the {Docker} images are fetched (only the missing ones) and the containers are started."
    [settings_written]="Settings written to %s"
    [site_declared]="Site declared in the HTTPS front: proxy/sites/%s.caddy"
    [q_start]="Download the Sellarus image and start the shop now?"
    [stopped_start]="Stopped before starting. Later: {sellarus start %s}"
    [images_present]="Images already present — checking for a newer Sellarus version"
    [images_uptodate]="Images already present and up to date — nothing downloaded"
    [images_updated]="A newer Sellarus version was downloaded"
    [images_dl]="Images downloaded (Sellarus, MariaDB, Caddy)"
    [front_started]="HTTPS front started"
    [front_reload_warn]="The front did not reload; {sellarus proxy restart} will do it"
    [shop_started]="Shop containers started"
    [waiting]="waiting for the shop to answer"
    [err_no_answer]="The shop does not answer yet. Look at: {sellarus logs %s web}"
    [running]="Sellarus %s is running"
    [step7]="Done"
    [why7]="Everything below is what you need to finish the setup in your browser and to manage the shop later."
    [installed_banner]="Sellarus is installed."
    [sum_title]="Sellarus %s — shop \"%s\" — installation summary (%s)"
    [sum_addr]="Shop address"
    [sum_finish]="Finish the setup"
    [sum_finish_note]="(create your administrator account in the browser)"
    [sum_admin]="Back-office"
    [sum_db]="Database (inside Docker, not reachable from the Internet)"
    [sum_hostport]="host / port"
    [sum_prefilled]="(pre-filled in the installer)"
    [sum_name]="name"
    [sum_user]="user"
    [sum_pass]="password"
    [sum_root]="root password"
    [sum_files]="Files"
    [sum_files_note]="(docker-compose.yml, .env — keep .env private)"
    [sum_front]="HTTPS front"
    [sum_front_note]="(shared by every shop of this server; this shop: sites/%s.caddy)"
    [sum_data]="Data"
    [sum_data_note]="Docker volumes %s_www (site), %s_db (database)"
    [sum_others]="Other shops here"
    [sum_none]="none"
    [sum_others_note]="(run the installation script again to add one)"
    [sum_cmds]="Everyday commands"
    [cmd_list]="the shops of this server"
    [cmd_status]="containers and version"
    [cmd_update]="update to the latest version (the back-office \"Update\" screen works too)"
    [cmd_backup]="database dump + files into %s"
    [cmd_logs]="follow the logs"
    [cmd_domain]="change the domain"
    [cmd_restart]="restart this shop"
    [keep_note]="Keep these details in a safe place: the database passwords are shown only here (and in the file below)."
    [saved_note]="This summary is saved in %s (readable by root only). Log: %s"
    [cert_note]="The HTTPS certificate is obtained automatically the first time %s is opened; give it a minute."
    [next_step]="Next step: open %s"
)
T_fr=(
    [tagline]="Votre boutique en ligne, prête en quelques minutes — installation sur serveur"
    [sys]="Système : %s (gestionnaire de paquets : {%s})"
    [shops_existing]="Boutiques déjà sur ce serveur : %s— ce passage en ajoute une autre (autre domaine)."
    [legacy]="Une boutique installée avec la première disposition se trouve dans %s ; elle sera convertie (données conservées) avant de continuer."
    [err_root]="Lancez ce script en root : tapez {sudo -i}, puis relancez la commande."
    [restart_sudo]="Relance avec {sudo}"
    [err_os]="Système non pris en charge : {/etc/os-release} introuvable."
    [err_distro]="Ce script prend en charge Debian, Ubuntu, Fedora, Rocky et AlmaLinux (trouvé : %s)."
    [unknown_opt]="option inconnue : %s"
    [run_failed]="%s a échoué (journal complet : %s)"
    [log_tail]="Dernières lignes du journal :"
    [yes_auto]="→ oui (--yes)"
    [step1]="Mise à jour du système"
    [why1]="Les logiciels du serveur sont mis à jour avant toute installation, pour que la boutique tourne sur un système sain."
    [q_upgrade]="Mettre à jour les paquets du système maintenant ?"
    [pkg_refreshed]="Listes de paquets actualisées"
    [sys_upgraded]="Système mis à jour"
    [upgrade_skipped]="Mise à jour du système ignorée."
    [step2]="Dépendances"
    [why2]="Sellarus fonctionne dans {Docker}. Cette étape regarde ce qui est déjà sur le serveur et n'installe que ce qui manque — rien n'est téléchargé deux fois."
    [q_tools]="Installer %s ?"
    [err_curl]="{curl} est indispensable."
    [installed]="Installé : %s"
    [tools_present]="{curl} et les certificats sont déjà présents"
    [docker_present]="{Docker} déjà installé : %s"
    [q_docker]="{Docker} est absent. L'installer maintenant (paquets officiels Docker) ?"
    [err_docker]="{Docker} est indispensable."
    [docker_installed]="{Docker} installé"
    [err_docker_down]="{Docker} ne répond pas. Vérifiez {systemctl status docker} puis relancez le script."
    [docker_running]="{Docker} est en marche"
    [stack_files]="Fichiers de la pile téléchargés"
    [legacy_convert]="Conversion de la boutique existante vers la nouvelle disposition (données conservées)"
    [step3]="Réseau"
    [why3]="La boutique doit être joignable sur les ports web {80} (HTTP) et {443} (HTTPS). S'il y a un pare-feu local, cette étape les ouvre."
    [front_running]="Le front HTTPS de ce serveur tourne déjà (les ports 80 et 443 sont à lui)"
    [q_ufw]="Ouvrir les ports 80 et 443 dans {ufw} ?"
    [ufw_ok]="{ufw} : ports 80/443 ouverts"
    [q_fw]="Ouvrir les services http et https dans {firewalld} ?"
    [fw_ok]="{firewalld} : http/https ouverts"
    [no_fw]="Aucun pare-feu local à configurer (vérifiez le pare-feu de votre hébergeur : les ports 80 et 443 doivent être ouverts)"
    [port_busy]="Le port %s est déjà utilisé sur ce serveur (un autre serveur web ?). Arrêtez-le, puis relancez le script."
    [ports_free]="Les ports 80 et 443 sont libres"
    [step4]="Vos réglages"
    [why4]="Quelques questions : le domaine de la boutique, un e-mail pour le certificat, un nom court et la base de données. Appuyez sur Entrée pour accepter ce qui est proposé entre crochets."
    [public_ip]="Adresse publique de ce serveur : %s"
    [q_domain_more]="Nom de domaine de la nouvelle boutique (obligatoire : les boutiques se distinguent par leur domaine)"
    [q_domain]="Nom de domaine de la boutique (vide = pas de domaine, HTTP sur l'adresse IP seulement)"
    [err_domain]="« %s » ne ressemble pas à un nom de domaine."
    [err_domain_used]="%s est déjà le domaine de la boutique « %s »."
    [q_email]="Votre e-mail (pour le certificat HTTPS : avis d'expiration)"
    [err_email]="« %s » ne ressemble pas à une adresse e-mail."
    [err_ip_shop]="La boutique « %s » répond déjà sur l'adresse nue du serveur : une deuxième boutique a besoin d'un nom de domaine."
    [err_need_domain]="Un nom de domaine est nécessaire pour ajouter une boutique à côté de %s."
    [q_shop]="Nom court de cette boutique sur le serveur (lettres, chiffres, tirets)"
    [err_shop_invalid]="Nom invalide « %s » (lettres, chiffres, tirets, 31 caractères au plus)."
    [err_shop_yes]="Valeur --shop invalide."
    [err_shop_exists]="Une boutique nommée « %s » existe déjà sur ce serveur."
    [err_shop_used]="Nom de boutique déjà utilisé."
    [q_db_name]="Nom de la base de données"
    [q_db_user]="Utilisateur de la base de données"
    [q_db_pass]="Mot de passe de la base (Entrée = généré)"
    [q_db_root]="Mot de passe root de la base (Entrée = généré)"
    [step5]="Contrôle du domaine"
    [why5]="Le domaine doit pointer vers l'adresse publique de ce serveur pour que le certificat HTTPS soit délivré. Un enregistrement {DNS} créé il y a quelques minutes peut ne pas être visible encore."
    [dns_ok]="%s pointe vers ce serveur (%s)"
    [dns_warn]="%s ne pointe pas encore vers ce serveur (résout vers : %s, serveur : %s)"
    [dns_hint]="Chez votre registrar, ajoutez un enregistrement {DNS} :  {A}  %s  →  %s"
    [dns_hint2]="(et « www » aussi si vous voulez www.%s). La propagation peut prendre quelques minutes."
    [q_recheck]="Vérifier à nouveau ?"
    [q_continue]="Continuer quand même ? (le certificat sera obtenu automatiquement dès que le domaine pointera ici)"
    [stopped_domain]="Installation arrêtée. Relancez le script quand le domaine sera prêt."
    [no_domain]="Pas de domaine : la boutique répondra sur http://%s sans HTTPS. Ajoutez un domaine plus tard avec : {sellarus domain %s votre-domaine.tld}"
    [step6]="Installation"
    [why6]="Les fichiers de la boutique sont écrits, les images {Docker} sont récupérées (seulement celles qui manquent) et les conteneurs démarrés."
    [settings_written]="Réglages écrits dans %s"
    [site_declared]="Site déclaré dans le front HTTPS : proxy/sites/%s.caddy"
    [q_start]="Télécharger l'image Sellarus et démarrer la boutique maintenant ?"
    [stopped_start]="Arrêt avant le démarrage. Plus tard : {sellarus start %s}"
    [images_present]="Images déjà présentes — recherche d'une version Sellarus plus récente"
    [images_uptodate]="Images déjà présentes et à jour — rien téléchargé"
    [images_updated]="Une version Sellarus plus récente a été récupérée"
    [images_dl]="Images téléchargées (Sellarus, MariaDB, Caddy)"
    [front_started]="Front HTTPS démarré"
    [front_reload_warn]="Le front ne s'est pas rechargé ; {sellarus proxy restart} s'en chargera"
    [shop_started]="Conteneurs de la boutique démarrés"
    [waiting]="en attente de la réponse de la boutique"
    [err_no_answer]="La boutique ne répond pas encore. Regardez : {sellarus logs %s web}"
    [running]="Sellarus %s est en marche"
    [step7]="Terminé"
    [why7]="Tout ce qui suit est ce dont vous avez besoin pour finir l'installation dans votre navigateur et gérer la boutique ensuite."
    [installed_banner]="Sellarus est installé."
    [sum_title]="Sellarus %s — boutique « %s » — résumé de l'installation (%s)"
    [sum_addr]="Adresse de la boutique"
    [sum_finish]="Terminer l'installation"
    [sum_finish_note]="(créez votre compte administrateur dans le navigateur)"
    [sum_admin]="Administration"
    [sum_db]="Base de données (dans Docker, injoignable depuis Internet)"
    [sum_hostport]="hôte / port"
    [sum_prefilled]="(prérempli dans l'assistant)"
    [sum_name]="nom"
    [sum_user]="utilisateur"
    [sum_pass]="mot de passe"
    [sum_root]="mot de passe root"
    [sum_files]="Fichiers"
    [sum_files_note]="(docker-compose.yml, .env — gardez .env privé)"
    [sum_front]="Front HTTPS"
    [sum_front_note]="(partagé par toutes les boutiques de ce serveur ; cette boutique : sites/%s.caddy)"
    [sum_data]="Données"
    [sum_data_note]="volumes Docker %s_www (site), %s_db (base de données)"
    [sum_others]="Autres boutiques ici"
    [sum_none]="aucune"
    [sum_others_note]="(relancez le script d'installation pour en ajouter une)"
    [sum_cmds]="Commandes du quotidien"
    [cmd_list]="les boutiques de ce serveur"
    [cmd_status]="conteneurs et version"
    [cmd_update]="mise à jour vers la dernière version (l'écran « Mise à jour » de l'administration fonctionne aussi)"
    [cmd_backup]="sauvegarde de la base + des fichiers dans %s"
    [cmd_logs]="suivre les journaux"
    [cmd_domain]="changer le domaine"
    [cmd_restart]="redémarrer cette boutique"
    [keep_note]="Conservez ces informations en lieu sûr : les mots de passe de la base ne sont affichés qu'ici (et dans le fichier ci-dessous)."
    [saved_note]="Ce résumé est enregistré dans %s (lisible par root seulement). Journal : %s"
    [cert_note]="Le certificat HTTPS est obtenu automatiquement à la première ouverture de %s ; laissez-lui une minute."
    [next_step]="Étape suivante : ouvrez %s"
)
T_de=(
    [tagline]="Ihr Online-Shop, in wenigen Minuten bereit — Installation auf dem Server"
    [sys]="System: %s (Paketverwaltung: {%s})"
    [shops_existing]="Shops bereits auf diesem Server: %s— dieser Durchlauf fügt einen weiteren hinzu (andere Domain)."
    [legacy]="Ein Shop mit der ersten Ordnerstruktur liegt in %s; er wird vor dem Weitermachen umgestellt (Daten bleiben erhalten)."
    [err_root]="Führen Sie dieses Skript als root aus: {sudo -i} eingeben, dann den Befehl erneut starten."
    [restart_sudo]="Neustart mit {sudo}"
    [err_os]="Nicht unterstütztes System: {/etc/os-release} nicht gefunden."
    [err_distro]="Dieses Skript unterstützt Debian, Ubuntu, Fedora, Rocky und AlmaLinux (gefunden: %s)."
    [unknown_opt]="unbekannte Option: %s"
    [run_failed]="%s ist fehlgeschlagen (vollständiges Protokoll: %s)"
    [log_tail]="Letzte Zeilen des Protokolls:"
    [yes_auto]="→ ja (--yes)"
    [step1]="Systemaktualisierung"
    [why1]="Die Software des Servers wird vor jeder Installation aktualisiert, damit der Shop auf einem gesunden System läuft."
    [q_upgrade]="Systempakete jetzt aktualisieren?"
    [pkg_refreshed]="Paketlisten aktualisiert"
    [sys_upgraded]="System aktualisiert"
    [upgrade_skipped]="Systemaktualisierung übersprungen."
    [step2]="Abhängigkeiten"
    [why2]="Sellarus läuft in {Docker}. Dieser Schritt prüft, was bereits auf dem Server ist, und installiert nur das Fehlende — nichts wird zweimal heruntergeladen."
    [q_tools]="%s installieren?"
    [err_curl]="{curl} wird benötigt."
    [installed]="Installiert: %s"
    [tools_present]="{curl} und Zertifikate bereits vorhanden"
    [docker_present]="{Docker} bereits installiert: %s"
    [q_docker]="{Docker} fehlt. Jetzt installieren (offizielle Docker-Pakete)?"
    [err_docker]="{Docker} wird benötigt."
    [docker_installed]="{Docker} installiert"
    [err_docker_down]="{Docker} antwortet nicht. Prüfen Sie {systemctl status docker} und starten Sie das Skript erneut."
    [docker_running]="{Docker} läuft"
    [stack_files]="Stack-Dateien heruntergeladen"
    [legacy_convert]="Bestehender Shop wird auf die neue Struktur umgestellt (Daten bleiben erhalten)"
    [step3]="Netzwerk"
    [why3]="Der Shop muss über die Web-Ports {80} (HTTP) und {443} (HTTPS) erreichbar sein. Gibt es eine lokale Firewall, öffnet dieser Schritt sie."
    [front_running]="Das HTTPS-Frontend dieses Servers läuft bereits (Ports 80 und 443 gehören ihm)"
    [q_ufw]="Ports 80 und 443 in {ufw} öffnen?"
    [ufw_ok]="{ufw}: Ports 80/443 offen"
    [q_fw]="Dienste http und https in {firewalld} öffnen?"
    [fw_ok]="{firewalld}: http/https offen"
    [no_fw]="Keine lokale Firewall zu konfigurieren (prüfen Sie die Firewall Ihres Anbieters: Ports 80 und 443 müssen offen sein)"
    [port_busy]="Port %s wird auf diesem Server bereits verwendet (ein anderer Webserver?). Beenden Sie ihn und starten Sie das Skript erneut."
    [ports_free]="Ports 80 und 443 sind frei"
    [step4]="Ihre Einstellungen"
    [why4]="Einige Fragen: die Domain des Shops, eine E-Mail für das Zertifikat, ein Kurzname und die Datenbank. Mit Enter übernehmen Sie den Vorschlag in eckigen Klammern."
    [public_ip]="Öffentliche Adresse dieses Servers: %s"
    [q_domain_more]="Domain des neuen Shops (Pflicht: die Shops werden über ihre Domain unterschieden)"
    [q_domain]="Domain des Shops (leer = keine Domain, nur HTTP über die IP-Adresse)"
    [err_domain]="„%s“ sieht nicht wie ein Domainname aus."
    [err_domain_used]="%s ist bereits die Domain des Shops „%s“."
    [q_email]="Ihre E-Mail (für das HTTPS-Zertifikat: Ablaufhinweise)"
    [err_email]="„%s“ sieht nicht wie eine E-Mail-Adresse aus."
    [err_ip_shop]="Der Shop „%s“ antwortet bereits auf der bloßen Serveradresse: ein zweiter Shop braucht eine Domain."
    [err_need_domain]="Für einen weiteren Shop neben %s ist eine Domain erforderlich."
    [q_shop]="Kurzname dieses Shops auf dem Server (Buchstaben, Ziffern, Bindestriche)"
    [err_shop_invalid]="Ungültiger Name „%s“ (Buchstaben, Ziffern, Bindestriche, höchstens 31 Zeichen)."
    [err_shop_yes]="Ungültiger Wert für --shop."
    [err_shop_exists]="Ein Shop namens „%s“ existiert bereits auf diesem Server."
    [err_shop_used]="Shop-Name bereits vergeben."
    [q_db_name]="Name der Datenbank"
    [q_db_user]="Benutzer der Datenbank"
    [q_db_pass]="Passwort der Datenbank (Enter = generiert)"
    [q_db_root]="Root-Passwort der Datenbank (Enter = generiert)"
    [step5]="Domain-Prüfung"
    [why5]="Die Domain muss auf die öffentliche Adresse dieses Servers zeigen, damit das HTTPS-Zertifikat ausgestellt werden kann. Ein vor wenigen Minuten angelegter {DNS}-Eintrag ist eventuell noch nicht sichtbar."
    [dns_ok]="%s zeigt auf diesen Server (%s)"
    [dns_warn]="%s zeigt noch nicht auf diesen Server (löst auf zu: %s, Server: %s)"
    [dns_hint]="Legen Sie bei Ihrem Domain-Anbieter einen {DNS}-Eintrag an:  {A}  %s  →  %s"
    [dns_hint2]="(und auch „www“, wenn Sie www.%s möchten). Die Verbreitung kann einige Minuten dauern."
    [q_recheck]="Erneut prüfen?"
    [q_continue]="Trotzdem fortfahren? (das Zertifikat wird automatisch geholt, sobald die Domain hierher zeigt)"
    [stopped_domain]="Installation abgebrochen. Starten Sie das Skript erneut, sobald die Domain bereit ist."
    [no_domain]="Keine Domain: der Shop antwortet auf http://%s ohne HTTPS. Domain später hinzufügen mit: {sellarus domain %s ihre-domain.tld}"
    [step6]="Installation"
    [why6]="Die Dateien des Shops werden geschrieben, die {Docker}-Images geholt (nur die fehlenden) und die Container gestartet."
    [settings_written]="Einstellungen geschrieben nach %s"
    [site_declared]="Site im HTTPS-Frontend eingetragen: proxy/sites/%s.caddy"
    [q_start]="Sellarus-Image herunterladen und den Shop jetzt starten?"
    [stopped_start]="Vor dem Start angehalten. Später: {sellarus start %s}"
    [images_present]="Images bereits vorhanden — Suche nach einer neueren Sellarus-Version"
    [images_uptodate]="Images bereits vorhanden und aktuell — nichts heruntergeladen"
    [images_updated]="Eine neuere Sellarus-Version wurde heruntergeladen"
    [images_dl]="Images heruntergeladen (Sellarus, MariaDB, Caddy)"
    [front_started]="HTTPS-Frontend gestartet"
    [front_reload_warn]="Das Frontend wurde nicht neu geladen; {sellarus proxy restart} erledigt das"
    [shop_started]="Shop-Container gestartet"
    [waiting]="warte auf Antwort des Shops"
    [err_no_answer]="Der Shop antwortet noch nicht. Sehen Sie nach: {sellarus logs %s web}"
    [running]="Sellarus %s läuft"
    [step7]="Fertig"
    [why7]="Alles Folgende brauchen Sie, um die Einrichtung im Browser abzuschließen und den Shop später zu verwalten."
    [installed_banner]="Sellarus ist installiert."
    [sum_title]="Sellarus %s — Shop „%s“ — Zusammenfassung der Installation (%s)"
    [sum_addr]="Adresse des Shops"
    [sum_finish]="Einrichtung abschließen"
    [sum_finish_note]="(legen Sie Ihr Administratorkonto im Browser an)"
    [sum_admin]="Verwaltung"
    [sum_db]="Datenbank (in Docker, nicht aus dem Internet erreichbar)"
    [sum_hostport]="Host / Port"
    [sum_prefilled]="(im Assistenten vorausgefüllt)"
    [sum_name]="Name"
    [sum_user]="Benutzer"
    [sum_pass]="Passwort"
    [sum_root]="Root-Passwort"
    [sum_files]="Dateien"
    [sum_files_note]="(docker-compose.yml, .env — halten Sie .env geheim)"
    [sum_front]="HTTPS-Frontend"
    [sum_front_note]="(von allen Shops dieses Servers geteilt; dieser Shop: sites/%s.caddy)"
    [sum_data]="Daten"
    [sum_data_note]="Docker-Volumes %s_www (Site), %s_db (Datenbank)"
    [sum_others]="Weitere Shops hier"
    [sum_none]="keine"
    [sum_others_note]="(starten Sie das Installationsskript erneut, um einen hinzuzufügen)"
    [sum_cmds]="Befehle für den Alltag"
    [cmd_list]="die Shops dieses Servers"
    [cmd_status]="Container und Version"
    [cmd_update]="auf die neueste Version aktualisieren (der Bildschirm „Aktualisierung“ der Verwaltung geht auch)"
    [cmd_backup]="Datenbank-Dump + Dateien nach %s"
    [cmd_logs]="Protokolle verfolgen"
    [cmd_domain]="Domain ändern"
    [cmd_restart]="diesen Shop neu starten"
    [keep_note]="Bewahren Sie diese Angaben sicher auf: die Datenbank-Passwörter werden nur hier angezeigt (und in der Datei unten)."
    [saved_note]="Diese Zusammenfassung ist gespeichert in %s (nur für root lesbar). Protokoll: %s"
    [cert_note]="Das HTTPS-Zertifikat wird beim ersten Aufruf von %s automatisch geholt; geben Sie ihm eine Minute."
    [next_step]="Nächster Schritt: öffnen Sie %s"
)
T_es=(
    [tagline]="Su tienda en línea, lista en pocos minutos — instalación en el servidor"
    [sys]="Sistema: %s (gestor de paquetes: {%s})"
    [shops_existing]="Tiendas ya presentes en este servidor: %s— esta ejecución añade otra (otro dominio)."
    [legacy]="Una tienda instalada con la primera disposición está en %s; se convertirá (datos conservados) antes de continuar."
    [err_root]="Ejecute este script como root: escriba {sudo -i} y vuelva a lanzar el comando."
    [restart_sudo]="Reinicio con {sudo}"
    [err_os]="Sistema no compatible: {/etc/os-release} no encontrado."
    [err_distro]="Este script admite Debian, Ubuntu, Fedora, Rocky y AlmaLinux (encontrado: %s)."
    [unknown_opt]="opción desconocida: %s"
    [run_failed]="%s ha fallado (registro completo: %s)"
    [log_tail]="Últimas líneas del registro:"
    [yes_auto]="→ sí (--yes)"
    [step1]="Actualización del sistema"
    [why1]="El software del servidor se actualiza antes de instalar nada, para que la tienda funcione sobre un sistema sano."
    [q_upgrade]="¿Actualizar los paquetes del sistema ahora?"
    [pkg_refreshed]="Listas de paquetes actualizadas"
    [sys_upgraded]="Sistema actualizado"
    [upgrade_skipped]="Actualización del sistema omitida."
    [step2]="Dependencias"
    [why2]="Sellarus funciona dentro de {Docker}. Este paso revisa lo que ya hay en el servidor e instala solo lo que falta — nada se descarga dos veces."
    [q_tools]="¿Instalar %s?"
    [err_curl]="{curl} es imprescindible."
    [installed]="Instalado: %s"
    [tools_present]="{curl} y los certificados ya están presentes"
    [docker_present]="{Docker} ya instalado: %s"
    [q_docker]="Falta {Docker}. ¿Instalarlo ahora (paquetes oficiales de Docker)?"
    [err_docker]="{Docker} es imprescindible."
    [docker_installed]="{Docker} instalado"
    [err_docker_down]="{Docker} no responde. Compruebe {systemctl status docker} y vuelva a lanzar el script."
    [docker_running]="{Docker} está en marcha"
    [stack_files]="Archivos de la pila descargados"
    [legacy_convert]="Conversión de la tienda existente a la nueva disposición (datos conservados)"
    [step3]="Red"
    [why3]="La tienda debe ser accesible en los puertos web {80} (HTTP) y {443} (HTTPS). Si hay un cortafuegos local, este paso los abre."
    [front_running]="El frontal HTTPS de este servidor ya está en marcha (los puertos 80 y 443 son suyos)"
    [q_ufw]="¿Abrir los puertos 80 y 443 en {ufw}?"
    [ufw_ok]="{ufw}: puertos 80/443 abiertos"
    [q_fw]="¿Abrir los servicios http y https en {firewalld}?"
    [fw_ok]="{firewalld}: http/https abiertos"
    [no_fw]="Ningún cortafuegos local que configurar (revise el cortafuegos de su proveedor: los puertos 80 y 443 deben estar abiertos)"
    [port_busy]="El puerto %s ya está en uso en este servidor (¿otro servidor web?). Deténgalo y vuelva a lanzar el script."
    [ports_free]="Los puertos 80 y 443 están libres"
    [step4]="Sus ajustes"
    [why4]="Unas pocas preguntas: el dominio de la tienda, un correo para el certificado, un nombre corto y la base de datos. Pulse Intro para aceptar lo propuesto entre corchetes."
    [public_ip]="Dirección pública de este servidor: %s"
    [q_domain_more]="Nombre de dominio de la nueva tienda (obligatorio: las tiendas se distinguen por su dominio)"
    [q_domain]="Nombre de dominio de la tienda (vacío = sin dominio, HTTP solo por la dirección IP)"
    [err_domain]="«%s» no parece un nombre de dominio."
    [err_domain_used]="%s ya es el dominio de la tienda «%s»."
    [q_email]="Su correo electrónico (para el certificado HTTPS: avisos de caducidad)"
    [err_email]="«%s» no parece una dirección de correo."
    [err_ip_shop]="La tienda «%s» ya responde en la dirección del servidor sin dominio: una segunda tienda necesita un nombre de dominio."
    [err_need_domain]="Se necesita un nombre de dominio para añadir una tienda junto a %s."
    [q_shop]="Nombre corto de esta tienda en el servidor (letras, cifras, guiones)"
    [err_shop_invalid]="Nombre no válido «%s» (letras, cifras, guiones, 31 caracteres como máximo)."
    [err_shop_yes]="Valor de --shop no válido."
    [err_shop_exists]="Ya existe una tienda llamada «%s» en este servidor."
    [err_shop_used]="Nombre de tienda ya utilizado."
    [q_db_name]="Nombre de la base de datos"
    [q_db_user]="Usuario de la base de datos"
    [q_db_pass]="Contraseña de la base de datos (Intro = generada)"
    [q_db_root]="Contraseña root de la base de datos (Intro = generada)"
    [step5]="Comprobación del dominio"
    [why5]="El dominio debe apuntar a la dirección pública de este servidor para que se emita el certificado HTTPS. Un registro {DNS} creado hace pocos minutos puede no ser visible todavía."
    [dns_ok]="%s apunta a este servidor (%s)"
    [dns_warn]="%s todavía no apunta a este servidor (resuelve a: %s, servidor: %s)"
    [dns_hint]="En su registrador de dominios, añada un registro {DNS}:  {A}  %s  →  %s"
    [dns_hint2]="(y también «www» si quiere www.%s). La propagación puede tardar unos minutos."
    [q_recheck]="¿Comprobar de nuevo?"
    [q_continue]="¿Continuar de todos modos? (el certificado se obtendrá automáticamente cuando el dominio apunte aquí)"
    [stopped_domain]="Instalación detenida. Vuelva a lanzar el script cuando el dominio esté listo."
    [no_domain]="Sin dominio: la tienda responderá en http://%s sin HTTPS. Añada un dominio más tarde con: {sellarus domain %s su-dominio.tld}"
    [step6]="Instalación"
    [why6]="Se escriben los archivos de la tienda, se obtienen las imágenes {Docker} (solo las que faltan) y se arrancan los contenedores."
    [settings_written]="Ajustes escritos en %s"
    [site_declared]="Sitio declarado en el frontal HTTPS: proxy/sites/%s.caddy"
    [q_start]="¿Descargar la imagen de Sellarus y arrancar la tienda ahora?"
    [stopped_start]="Detenido antes del arranque. Más tarde: {sellarus start %s}"
    [images_present]="Imágenes ya presentes — buscando una versión de Sellarus más reciente"
    [images_uptodate]="Imágenes ya presentes y al día — nada descargado"
    [images_updated]="Se ha descargado una versión de Sellarus más reciente"
    [images_dl]="Imágenes descargadas (Sellarus, MariaDB, Caddy)"
    [front_started]="Frontal HTTPS arrancado"
    [front_reload_warn]="El frontal no se recargó; {sellarus proxy restart} lo hará"
    [shop_started]="Contenedores de la tienda arrancados"
    [waiting]="esperando la respuesta de la tienda"
    [err_no_answer]="La tienda todavía no responde. Mire: {sellarus logs %s web}"
    [running]="Sellarus %s está en marcha"
    [step7]="Hecho"
    [why7]="Todo lo que sigue es lo que necesita para terminar la configuración en el navegador y gestionar la tienda después."
    [installed_banner]="Sellarus está instalado."
    [sum_title]="Sellarus %s — tienda «%s» — resumen de la instalación (%s)"
    [sum_addr]="Dirección de la tienda"
    [sum_finish]="Terminar la configuración"
    [sum_finish_note]="(cree su cuenta de administrador en el navegador)"
    [sum_admin]="Administración"
    [sum_db]="Base de datos (dentro de Docker, inaccesible desde Internet)"
    [sum_hostport]="host / puerto"
    [sum_prefilled]="(rellenado de antemano en el asistente)"
    [sum_name]="nombre"
    [sum_user]="usuario"
    [sum_pass]="contraseña"
    [sum_root]="contraseña root"
    [sum_files]="Archivos"
    [sum_files_note]="(docker-compose.yml, .env — mantenga .env en privado)"
    [sum_front]="Frontal HTTPS"
    [sum_front_note]="(compartido por todas las tiendas de este servidor; esta tienda: sites/%s.caddy)"
    [sum_data]="Datos"
    [sum_data_note]="volúmenes Docker %s_www (sitio), %s_db (base de datos)"
    [sum_others]="Otras tiendas aquí"
    [sum_none]="ninguna"
    [sum_others_note]="(vuelva a lanzar el script de instalación para añadir una)"
    [sum_cmds]="Comandos del día a día"
    [cmd_list]="las tiendas de este servidor"
    [cmd_status]="contenedores y versión"
    [cmd_update]="actualizar a la última versión (la pantalla «Actualización» de la administración también sirve)"
    [cmd_backup]="volcado de la base de datos + archivos en %s"
    [cmd_logs]="seguir los registros"
    [cmd_domain]="cambiar el dominio"
    [cmd_restart]="reiniciar esta tienda"
    [keep_note]="Guarde estos datos en un lugar seguro: las contraseñas de la base de datos solo se muestran aquí (y en el archivo de abajo)."
    [saved_note]="Este resumen está guardado en %s (legible solo por root). Registro: %s"
    [cert_note]="El certificado HTTPS se obtiene automáticamente la primera vez que se abre %s; dele un minuto."
    [next_step]="Siguiente paso: abra %s"
)
T_it=(
    [tagline]="Il tuo negozio online, pronto in pochi minuti — installazione sul server"
    [sys]="Sistema: %s (gestore dei pacchetti: {%s})"
    [shops_existing]="Negozi già presenti su questo server: %s— questa esecuzione ne aggiunge un altro (altro dominio)."
    [legacy]="Un negozio installato con la prima disposizione si trova in %s; verrà convertito (dati conservati) prima di continuare."
    [err_root]="Esegui questo script come root: digita {sudo -i}, poi rilancia il comando."
    [restart_sudo]="Riavvio con {sudo}"
    [err_os]="Sistema non supportato: {/etc/os-release} non trovato."
    [err_distro]="Questo script supporta Debian, Ubuntu, Fedora, Rocky e AlmaLinux (trovato: %s)."
    [unknown_opt]="opzione sconosciuta: %s"
    [run_failed]="%s non è riuscito (registro completo: %s)"
    [log_tail]="Ultime righe del registro:"
    [yes_auto]="→ sì (--yes)"
    [step1]="Aggiornamento del sistema"
    [why1]="Il software del server viene aggiornato prima di qualsiasi installazione, così il negozio gira su un sistema sano."
    [q_upgrade]="Aggiornare i pacchetti del sistema adesso?"
    [pkg_refreshed]="Elenchi dei pacchetti aggiornati"
    [sys_upgraded]="Sistema aggiornato"
    [upgrade_skipped]="Aggiornamento del sistema saltato."
    [step2]="Dipendenze"
    [why2]="Sellarus gira dentro {Docker}. Questo passaggio controlla cosa c'è già sul server e installa solo ciò che manca — nulla viene scaricato due volte."
    [q_tools]="Installare %s?"
    [err_curl]="{curl} è indispensabile."
    [installed]="Installato: %s"
    [tools_present]="{curl} e i certificati sono già presenti"
    [docker_present]="{Docker} già installato: %s"
    [q_docker]="{Docker} manca. Installarlo adesso (pacchetti ufficiali Docker)?"
    [err_docker]="{Docker} è indispensabile."
    [docker_installed]="{Docker} installato"
    [err_docker_down]="{Docker} non risponde. Controlla {systemctl status docker} e rilancia lo script."
    [docker_running]="{Docker} è in esecuzione"
    [stack_files]="File dello stack scaricati"
    [legacy_convert]="Conversione del negozio esistente alla nuova disposizione (dati conservati)"
    [step3]="Rete"
    [why3]="Il negozio deve essere raggiungibile sulle porte web {80} (HTTP) e {443} (HTTPS). Se c'è un firewall locale, questo passaggio le apre."
    [front_running]="Il front HTTPS di questo server è già in esecuzione (le porte 80 e 443 sono sue)"
    [q_ufw]="Aprire le porte 80 e 443 in {ufw}?"
    [ufw_ok]="{ufw}: porte 80/443 aperte"
    [q_fw]="Aprire i servizi http e https in {firewalld}?"
    [fw_ok]="{firewalld}: http/https aperti"
    [no_fw]="Nessun firewall locale da configurare (controlla il firewall del tuo fornitore: le porte 80 e 443 devono essere aperte)"
    [port_busy]="La porta %s è già usata su questo server (un altro server web?). Fermalo, poi rilancia lo script."
    [ports_free]="Le porte 80 e 443 sono libere"
    [step4]="Le tue impostazioni"
    [why4]="Qualche domanda: il dominio del negozio, un'e-mail per il certificato, un nome breve e il database. Premi Invio per accettare ciò che è proposto tra parentesi quadre."
    [public_ip]="Indirizzo pubblico di questo server: %s"
    [q_domain_more]="Nome di dominio del nuovo negozio (obbligatorio: i negozi si distinguono per il loro dominio)"
    [q_domain]="Nome di dominio del negozio (vuoto = nessun dominio, HTTP solo sull'indirizzo IP)"
    [err_domain]="«%s» non sembra un nome di dominio."
    [err_domain_used]="%s è già il dominio del negozio «%s»."
    [q_email]="La tua e-mail (per il certificato HTTPS: avvisi di scadenza)"
    [err_email]="«%s» non sembra un indirizzo e-mail."
    [err_ip_shop]="Il negozio «%s» risponde già sull'indirizzo nudo del server: un secondo negozio ha bisogno di un nome di dominio."
    [err_need_domain]="Serve un nome di dominio per aggiungere un negozio accanto a %s."
    [q_shop]="Nome breve di questo negozio sul server (lettere, cifre, trattini)"
    [err_shop_invalid]="Nome non valido «%s» (lettere, cifre, trattini, al massimo 31 caratteri)."
    [err_shop_yes]="Valore di --shop non valido."
    [err_shop_exists]="Un negozio chiamato «%s» esiste già su questo server."
    [err_shop_used]="Nome del negozio già usato."
    [q_db_name]="Nome del database"
    [q_db_user]="Utente del database"
    [q_db_pass]="Password del database (Invio = generata)"
    [q_db_root]="Password root del database (Invio = generata)"
    [step5]="Controllo del dominio"
    [why5]="Il dominio deve puntare all'indirizzo pubblico di questo server perché il certificato HTTPS possa essere rilasciato. Un record {DNS} creato pochi minuti fa potrebbe non essere ancora visibile."
    [dns_ok]="%s punta a questo server (%s)"
    [dns_warn]="%s non punta ancora a questo server (risolve a: %s, server: %s)"
    [dns_hint]="Presso il tuo registrar, aggiungi un record {DNS}:  {A}  %s  →  %s"
    [dns_hint2]="(e anche «www» se vuoi www.%s). La propagazione può richiedere qualche minuto."
    [q_recheck]="Controllare di nuovo?"
    [q_continue]="Continuare comunque? (il certificato sarà ottenuto automaticamente appena il dominio punterà qui)"
    [stopped_domain]="Installazione interrotta. Rilancia lo script quando il dominio sarà pronto."
    [no_domain]="Nessun dominio: il negozio risponderà su http://%s senza HTTPS. Aggiungi un dominio più tardi con: {sellarus domain %s tuo-dominio.tld}"
    [step6]="Installazione"
    [why6]="I file del negozio vengono scritti, le immagini {Docker} recuperate (solo quelle mancanti) e i container avviati."
    [settings_written]="Impostazioni scritte in %s"
    [site_declared]="Sito dichiarato nel front HTTPS: proxy/sites/%s.caddy"
    [q_start]="Scaricare l'immagine Sellarus e avviare il negozio adesso?"
    [stopped_start]="Fermato prima dell'avvio. Più tardi: {sellarus start %s}"
    [images_present]="Immagini già presenti — ricerca di una versione Sellarus più recente"
    [images_uptodate]="Immagini già presenti e aggiornate — nulla scaricato"
    [images_updated]="È stata scaricata una versione Sellarus più recente"
    [images_dl]="Immagini scaricate (Sellarus, MariaDB, Caddy)"
    [front_started]="Front HTTPS avviato"
    [front_reload_warn]="Il front non si è ricaricato; {sellarus proxy restart} se ne occuperà"
    [shop_started]="Container del negozio avviati"
    [waiting]="in attesa della risposta del negozio"
    [err_no_answer]="Il negozio non risponde ancora. Guarda: {sellarus logs %s web}"
    [running]="Sellarus %s è in esecuzione"
    [step7]="Fatto"
    [why7]="Tutto ciò che segue è quello che ti serve per completare la configurazione nel browser e gestire il negozio in seguito."
    [installed_banner]="Sellarus è installato."
    [sum_title]="Sellarus %s — negozio «%s» — riepilogo dell'installazione (%s)"
    [sum_addr]="Indirizzo del negozio"
    [sum_finish]="Completare la configurazione"
    [sum_finish_note]="(crea il tuo account amministratore nel browser)"
    [sum_admin]="Amministrazione"
    [sum_db]="Database (dentro Docker, non raggiungibile da Internet)"
    [sum_hostport]="host / porta"
    [sum_prefilled]="(precompilato nell'assistente)"
    [sum_name]="nome"
    [sum_user]="utente"
    [sum_pass]="password"
    [sum_root]="password root"
    [sum_files]="File"
    [sum_files_note]="(docker-compose.yml, .env — tieni .env privato)"
    [sum_front]="Front HTTPS"
    [sum_front_note]="(condiviso da tutti i negozi di questo server; questo negozio: sites/%s.caddy)"
    [sum_data]="Dati"
    [sum_data_note]="volumi Docker %s_www (sito), %s_db (database)"
    [sum_others]="Altri negozi qui"
    [sum_none]="nessuno"
    [sum_others_note]="(rilancia lo script di installazione per aggiungerne uno)"
    [sum_cmds]="Comandi di tutti i giorni"
    [cmd_list]="i negozi di questo server"
    [cmd_status]="container e versione"
    [cmd_update]="aggiornare all'ultima versione (funziona anche la schermata «Aggiornamento» dell'amministrazione)"
    [cmd_backup]="dump del database + file in %s"
    [cmd_logs]="seguire i registri"
    [cmd_domain]="cambiare il dominio"
    [cmd_restart]="riavviare questo negozio"
    [keep_note]="Conserva questi dati in un luogo sicuro: le password del database sono mostrate solo qui (e nel file qui sotto)."
    [saved_note]="Questo riepilogo è salvato in %s (leggibile solo da root). Registro: %s"
    [cert_note]="Il certificato HTTPS viene ottenuto automaticamente alla prima apertura di %s; dagli un minuto."
    [next_step]="Prossimo passo: apri %s"
)

# tx <key> [args…] : translated text with %s filled in; {terms} kept as is. tr_ colours the {terms} yellow, tp strips the braces.
tx() {
    local key=$1; shift
    local -n tbl="T_$UI"
    local s="${tbl[$key]:-${T_en[$key]:-$key}}"
    # shellcheck disable=SC2059
    printf "$s" "$@"
}
tr_() {
    local s; s=$(tx "$@")
    while [[ $s == *'{'*'}'* ]]; do
        local pre=${s%%\{*} rest=${s#*\{}
        local term=${rest%%\}*} post=${rest#*\}}
        s="${pre}${YELLOW}${term}${R}${post}"
    done
    printf '%s' "$s"
}
tp() { local s; s=$(tx "$@"); s=${s//\{/}; printf '%s' "${s//\}/}"; }

detect_lang() {
    local l="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
    l=${l%%[._@]*}; l=${l%%_*}
    case "$l" in fr|de|es|it) printf '%s' "$l" ;; *) printf 'en' ;; esac
}
choose_lang() {
    local def; def=$(detect_lang)
    case "$UI" in en|fr|de|es|it) return ;; esac
    if [ "$YES" = 1 ] || [ ! -r /dev/tty ]; then UI=$def; return; fi
    printf '\n  %sLanguage / Langue / Sprache / Idioma / Lingua%s\n' "${B}" "${R}"
    printf '  [1] English   [2] Français   [3] Deutsch   [4] Español   [5] Italiano   [%s] ' "$def"
    local a; read -r a </dev/tty || a=""
    case "$a" in 1|en) UI=en ;; 2|fr) UI=fr ;; 3|de) UI=de ;; 4|es) UI=es ;; 5|it) UI=it ;; *) UI=$def ;; esac
}

banner() {
    printf '\n%s\n' "${NAVY}${B}   ____       _ _                      ${R}"
    printf '%s\n'   "${NAVY}${B}  / ___|  ___| | | __ _ _ __ _   _ ___ ${R}"
    printf '%s\n'   "${NAVY}${B}  \\___ \\ / _ \\ | |/ _\` | '__| | | / __|${R}"
    printf '%s\n'   "${NAVY}${B}   ___) |  __/ | | (_| | |  | |_| \\__ \\${R}"
    printf '%s\n'   "${NAVY}${B}  |____/ \\___|_|_|\\__,_|_|   \\__,_|___/${R}"
    printf '%s\n\n' "${TEAL}  $(tp tagline)${R}"
}

# Progress bar of the whole installation: bar <step> <total> <label>
bar() {
    local cur=$1 total=$2 label=$3 width=32 filled empty
    filled=$(( cur * width / total )); empty=$(( width - filled ))
    printf '\n%s[' "${B}"
    printf '%*s' "$filled" '' | tr ' ' '█'
    printf '%*s' "$empty" '' | tr ' ' '░'
    printf '] %d/%d%s  %s%s%s\n' "$cur" "$total" "${R}" "${B}" "$label" "${R}"
}
# step <title> [explanation] : bar + title, then the explanation in violet
step() { STEP=$((STEP + 1)); bar "$STEP" "$STEPS" "$1"; [ -n "${2:-}" ] && why "$2"; return 0; }

# Runs a long command with a spinner and an elapsed-time counter; output kept in a log shown on failure.
LOG=$(mktemp /tmp/sellarus-install.XXXXXX)
run() {
    local label=$1; shift
    local start=$SECONDS frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
    "$@" >>"$LOG" 2>&1 &
    local pid=$!
    if [ -t 1 ]; then
        while kill -0 "$pid" 2>/dev/null; do
            printf '\r  %s%s%s %s %s(%ds)%s   ' "${TEAL}" "${frames:i%10:1}" "${R}" "$label" "${DIM}" "$((SECONDS - start))" "${R}"
            i=$((i + 1)); sleep 0.15
        done
        printf '\r\033[K'
    fi
    if wait "$pid"; then ok "$label ${DIM}($((SECONDS - start)) s)${R}"; else
        printf '%s\n' "${RED}$(tp log_tail)${R}"; tail -n 25 "$LOG"; die "$(tr_ run_failed "$label" "$LOG")"; fi
}

confirm() { # confirm <question> → 0 = yes
    [ "$YES" = 1 ] && { note "$1 $(tp yes_auto)"; return 0; }
    local a
    printf '  %s%s%s [Y/n] ' "${B}" "$1" "${R}"
    read -r a </dev/tty || a=""
    case "$a" in n|N|no|NO|non|nein|nee) return 1 ;; *) return 0 ;; esac
}
ask() { # ask <var> <question> <default> [secret]
    local var=$1 q=$2 def=$3 secret=${4:-} v
    [ "$YES" = 1 ] && [ -n "$def" ] && { printf -v "$var" '%s' "$def"; note "$q → $def"; return; }
    if [ -n "$secret" ]; then printf '  %s%s%s [%s] ' "${B}" "$q" "${R}" "${DIM}generated${R}"; read -rs v </dev/tty; printf '\n'
    else printf '  %s%s%s [%s] ' "${B}" "$q" "${R}" "$def"; read -r v </dev/tty; fi
    printf -v "$var" '%s' "${v:-$def}"
}
password() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24; }
fetch() { curl -fsSL "$BASE_URL/$1" -o "$2"; }
shops() { [ -d "$SHOPS" ] && for d in "$SHOPS"/*/; do [ -f "$d/.env" ] && basename "$d"; done; return 0; }
proxy_running() { [ -f "$PROXY/docker-compose.yml" ] && [ -n "$(docker compose --project-directory "$PROXY" ps -q caddy 2>/dev/null)" ]; }
have_image() { docker image inspect "$1" >/dev/null 2>&1; }

# ---------- arguments ----------
while [ $# -gt 0 ]; do
    case "$1" in
        --yes|-y) YES=1 ;;
        --lang) UI=$2; shift ;;
        --shop) SHOP=$2; shift ;;
        --domain) DOMAIN=$2; shift ;;
        --email) EMAIL=$2; shift ;;
        --no-upgrade) DO_UPGRADE=0 ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done

choose_lang
export SELLARUS_LANG="$UI"
banner
if [ "$(id -u)" != 0 ]; then
    command -v sudo >/dev/null && [ -r "$0" ] || die "$(tr_ err_root)"
    warn "$(tr_ restart_sudo)"; exec sudo -E bash "$0" "${ARGS[@]}"
fi
[ -r /etc/os-release ] || die "$(tr_ err_os)"
. /etc/os-release
PM=""
case "${ID:-} ${ID_LIKE:-}" in
    *debian*|*ubuntu*) PM=apt ;;
    *fedora*|*rhel*|*centos*|*rocky*|*alma*) PM=dnf ;;
esac
[ -n "$PM" ] || die "$(tr_ err_distro "${PRETTY_NAME:-unknown}")"
ok "$(tr_ sys "${PRETTY_NAME:-$ID}" "$PM")"
EXISTING=$(shops)
if [ -n "$EXISTING" ]; then
    note "$(tr_ shops_existing "$(printf '%s ' $EXISTING)")"
elif [ -f "$DIR/.env" ] && [ -f "$DIR/docker-compose.yml" ]; then
    warn "$(tr_ legacy "$DIR")"
    LEGACY=1
fi

# ---------- 1. system update ----------
step "$(tp step1)" "$(tr_ why1)"
if [ "$DO_UPGRADE" = 1 ] && confirm "$(tr_ q_upgrade)"; then
    if [ "$PM" = apt ]; then
        export DEBIAN_FRONTEND=noninteractive
        run "$(tp pkg_refreshed)" apt-get update -y
        run "$(tp sys_upgraded)" apt-get upgrade -y
    else
        run "$(tp sys_upgraded)" dnf upgrade -y
    fi
else
    note "$(tr_ upgrade_skipped)"
fi

# ---------- 2. dependencies ----------
step "$(tp step2)" "$(tr_ why2)"
need=()
for tool in curl ca-certificates; do
    if [ "$tool" = ca-certificates ]; then [ -d /etc/ssl/certs ] || need+=("$tool"); else command -v "$tool" >/dev/null || need+=("$tool"); fi
done
if [ ${#need[@]} -gt 0 ]; then
    confirm "$(tr_ q_tools "${need[*]}")" || die "$(tr_ err_curl)"
    if [ "$PM" = apt ]; then run "$(tp installed "${need[*]}")" apt-get install -y "${need[@]}"; else run "$(tp installed "${need[*]}")" dnf install -y "${need[@]}"; fi
else
    ok "$(tr_ tools_present)"
fi
if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
    ok "$(tr_ docker_present "$(docker --version | sed 's/,.*//')")"
else
    confirm "$(tr_ q_docker)" || die "$(tr_ err_docker)"
    run "$(tp docker_installed)" sh -c 'curl -fsSL https://get.docker.com | sh'
fi
systemctl enable --now docker >>"$LOG" 2>&1 || true
docker info >/dev/null 2>&1 || die "$(tr_ err_docker_down)"
ok "$(tr_ docker_running)"
# the stack files (always the current ones) and the sellarus command
mkdir -p "$PROXY/sites" "$SHOPS" && chmod 700 "$DIR" "$SHOPS"
run "$(tp stack_files)" sh -c "curl -fsSL '$BASE_URL/stack/proxy/docker-compose.yml' -o '$PROXY/docker-compose.yml' && curl -fsSL '$BASE_URL/stack/proxy/Caddyfile' -o '$PROXY/Caddyfile' && curl -fsSL '$BASE_URL/sellarus' -o /usr/local/bin/sellarus && chmod +x /usr/local/bin/sellarus"
if [ "${LEGACY:-0}" = 1 ]; then
    say "$(tr_ legacy_convert)"
    SELLARUS_BASE_URL="$BASE_URL" sellarus migrate
    EXISTING=$(shops)
fi

# ---------- 3. firewall and ports ----------
step "$(tp step3)" "$(tr_ why3)"
if proxy_running; then
    ok "$(tr_ front_running)"
else
    if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q '^Status: active'; then
        if confirm "$(tr_ q_ufw)"; then ufw allow 80/tcp >>"$LOG" 2>&1; ufw allow 443/tcp >>"$LOG" 2>&1; ufw allow 443/udp >>"$LOG" 2>&1; ok "$(tr_ ufw_ok)"; fi
    elif command -v firewall-cmd >/dev/null && firewall-cmd --state >/dev/null 2>&1; then
        if confirm "$(tr_ q_fw)"; then firewall-cmd --permanent --add-service=http >>"$LOG" 2>&1; firewall-cmd --permanent --add-service=https >>"$LOG" 2>&1; firewall-cmd --reload >>"$LOG" 2>&1; ok "$(tr_ fw_ok)"; fi
    else
        ok "$(tr_ no_fw)"
    fi
    for port in 80 443; do
        if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$port\$"; then
            die "$(tr_ port_busy "$port")"
        fi
    done
    ok "$(tr_ ports_free)"
fi

# ---------- 4. settings ----------
step "$(tp step4)" "$(tr_ why4)"
PUBLIC_IP=$(curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null || curl -fsS --max-time 8 https://ifconfig.me 2>/dev/null || true)
[ -n "$PUBLIC_IP" ] && note "$(tr_ public_ip "$PUBLIC_IP")"
IP_SHOP=$(grep -ls '^:80 {' "$PROXY"/sites/*.caddy 2>/dev/null | head -n1 | xargs -r basename | sed 's/\.caddy$//' || true)
if [ -n "$EXISTING" ]; then
    [ -n "$DOMAIN" ] || ask DOMAIN "$(tr_ q_domain_more)" ""
else
    [ -n "$DOMAIN" ] || ask DOMAIN "$(tr_ q_domain)" ""
fi
DOMAIN=$(printf '%s' "$DOMAIN" | tr 'A-Z' 'a-z' | sed 's#^https\?://##; s#/.*$##')
if [ -n "$DOMAIN" ]; then
    printf '%s' "$DOMAIN" | grep -Eq '^([a-z0-9-]+\.)+[a-z]{2,}$' || die "$(tr_ err_domain "$DOMAIN")"
    for s in $EXISTING; do [ "$(grep -o '^DOMAIN=.*' "$SHOPS/$s/.env" | cut -d= -f2-)" = "$DOMAIN" ] && die "$(tr_ err_domain_used "$DOMAIN" "$s")"; done
    if [ -f "$PROXY/.env" ]; then EMAIL=${EMAIL:-$(grep -o '^ACME_EMAIL=.*' "$PROXY/.env" | cut -d= -f2-)}; [ "$EMAIL" = admin@localhost ] && EMAIL=""; fi
    [ -n "$EMAIL" ] || ask EMAIL "$(tr_ q_email)" ""
    printf '%s' "$EMAIL" | grep -Eq '^[^@ ]+@[^@ ]+\.[a-z]{2,}$' || die "$(tr_ err_email "$EMAIL")"
    DEF_SHOP=$(printf '%s' "$DOMAIN" | sed 's/^www\.//' | cut -d. -f1 | tr -c 'a-z0-9-' '-' | sed 's/-*$//')
else
    [ -z "$IP_SHOP" ] || die "$(tr_ err_ip_shop "$IP_SHOP")"
    [ -z "$EXISTING" ] || die "$(tr_ err_need_domain "$(printf '%s ' $EXISTING)")"
    DEF_SHOP=boutique
fi
[ -n "$DEF_SHOP" ] || DEF_SHOP=boutique
while :; do
    [ -n "$SHOP" ] || ask SHOP "$(tr_ q_shop)" "$DEF_SHOP"
    SHOP=$(printf '%s' "$SHOP" | tr 'A-Z' 'a-z')
    if ! printf '%s' "$SHOP" | grep -Eq '^[a-z0-9][a-z0-9-]{0,30}$' || [ "$SHOP" = proxy ]; then warn "$(tr_ err_shop_invalid "$SHOP")"; SHOP=""; [ "$YES" = 1 ] && die "$(tr_ err_shop_yes)"; continue; fi
    if [ -f "$SHOPS/$SHOP/.env" ]; then warn "$(tr_ err_shop_exists "$SHOP")"; SHOP=""; [ "$YES" = 1 ] && die "$(tr_ err_shop_used)"; continue; fi
    break
done
ask DB_NAME "$(tr_ q_db_name)" "sellarus"
ask DB_USER "$(tr_ q_db_user)" "sellarus"
ask DB_PASSWORD "$(tr_ q_db_pass)" "$(password)" secret
ask DB_ROOT_PASSWORD "$(tr_ q_db_root)" "$(password)" secret
DB_PREFIX=vb_

# ---------- 5. domain check ----------
step "$(tp step5)" "$(tr_ why5)"
if [ -n "$DOMAIN" ]; then
    while :; do
        RESOLVED=$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk '{print $1}' | head -n1 || true)
        if [ -n "$RESOLVED" ] && { [ -z "$PUBLIC_IP" ] || [ "$RESOLVED" = "$PUBLIC_IP" ]; }; then
            ok "$(tr_ dns_ok "$DOMAIN" "$RESOLVED")"; break
        fi
        warn "$(tr_ dns_warn "$DOMAIN" "${RESOLVED:-—}" "${PUBLIC_IP:-?}")"
        note "$(tr_ dns_hint "$DOMAIN" "${PUBLIC_IP:-<server IP>}")"
        note "$(tr_ dns_hint2 "$DOMAIN")"
        if confirm "$(tr_ q_recheck)"; then sleep 5; continue; fi
        confirm "$(tr_ q_continue)" || die "$(tr_ stopped_domain)"
        break
    done
else
    warn "$(tr_ no_domain "$PUBLIC_IP" "$SHOP")"
fi

# ---------- 6. stack ----------
step "$(tp step6)" "$(tr_ why6)"
SHOP_DIR="$SHOPS/$SHOP"
mkdir -p "$SHOP_DIR" && chmod 700 "$SHOP_DIR"
fetch stack/shop/docker-compose.yml "$SHOP_DIR/docker-compose.yml"
{
    echo "SHOP=$SHOP"
    echo "COMPOSE_PROJECT_NAME=sellarus-$SHOP"
    echo "DOMAIN=$DOMAIN"
    echo "DB_NAME=$DB_NAME"
    echo "DB_USER=$DB_USER"
    echo "DB_PASSWORD=$DB_PASSWORD"
    echo "DB_ROOT_PASSWORD=$DB_ROOT_PASSWORD"
    echo "DB_PREFIX=$DB_PREFIX"
    echo "SELLARUS_TAG=latest"
} > "$SHOP_DIR/.env"
chmod 600 "$SHOP_DIR/.env"
ok "$(tr_ settings_written "$SHOP_DIR/.env")"
if [ ! -f "$PROXY/.env" ]; then
    { echo "ACME_EMAIL=${EMAIL:-admin@localhost}"; echo "HTTP_PORT=80"; echo "HTTPS_PORT=443"; } > "$PROXY/.env"; chmod 600 "$PROXY/.env"
elif [ -n "$EMAIL" ] && grep -q '^ACME_EMAIL=admin@localhost' "$PROXY/.env"; then
    sed -i "s/^ACME_EMAIL=.*/ACME_EMAIL=$EMAIL/" "$PROXY/.env"
fi
{
    printf '# Shop "%s" — generated by Sellarus (sellarus domain %s ...). Edit by hand if you know Caddy.\n' "$SHOP" "$SHOP"
    printf '%s {\n\tencode zstd gzip\n\treverse_proxy sellarus-%s:80\n}\n' "${DOMAIN:-:80}" "$SHOP"
} > "$PROXY/sites/$SHOP.caddy"
ok "$(tr_ site_declared "$SHOP")"
confirm "$(tr_ q_start)" || die "$(tr_ stopped_start "$SHOP")"
cd "$SHOP_DIR"
# Images already on the server are kept; only the Sellarus image is checked for a newer version.
if have_image "$IMAGE:latest" && have_image mariadb:11 && have_image caddy:2; then
    BEFORE=$(docker image inspect --format '{{.Id}}' "$IMAGE:latest")
    run "$(tp images_present)" docker pull "$IMAGE:latest"
    if [ "$(docker image inspect --format '{{.Id}}' "$IMAGE:latest")" = "$BEFORE" ]; then ok "$(tr_ images_uptodate)"; else ok "$(tr_ images_updated)"; fi
else
    run "$(tp images_dl)" sh -c "docker compose pull && docker compose --project-directory '$PROXY' pull"
fi
run "$(tp front_started)" docker compose --project-directory "$PROXY" up -d
if [ -n "$EXISTING" ]; then docker compose --project-directory "$PROXY" exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile >>"$LOG" 2>&1 || warn "$(tr_ front_reload_warn)"; fi
run "$(tp shop_started)" docker compose up -d
printf '  %s' "${DIM}$(tp waiting)"
for _ in $(seq 1 60); do
    if docker compose exec -T web sh -c 'curl -fsS -o /dev/null http://localhost/install.php' >/dev/null 2>&1; then break; fi
    printf '.'; sleep 2
done
printf '%s\n' "${R}"
docker compose exec -T web sh -c 'curl -fsS -o /dev/null http://localhost/install.php' >/dev/null 2>&1 || die "$(tr_ err_no_answer "$SHOP")"
VERSION=$(docker compose exec -T web sh -c "grep -o \"VB_VERSION', '[^']*'\" /var/www/html/app/bootstrap.php | grep -o '[0-9][0-9.]*'" 2>/dev/null | tr -d '\r' || echo "?")
ok "$(tr_ running "$VERSION")"

# ---------- 7. summary ----------
step "$(tp step7)" "$(tr_ why7)"
if [ -n "$DOMAIN" ]; then URL="https://$DOMAIN"; else URL="http://${PUBLIC_IP:-<server IP>}"; fi
OTHERS=""; for s in $(shops); do [ "$s" = "$SHOP" ] || OTHERS="$OTHERS $s"; done
# clen <text>: length in characters whatever the server locale (accented labels must not break the alignment)
clen() { local n; n=$(printf '%s' "$1" | LC_ALL=C.UTF-8 wc -m 2>/dev/null | tr -d ' '); [ -n "$n" ] && [ "$n" -gt 0 ] || n=$(printf '%s' "$1" | wc -c | tr -d ' '); printf '%s' "$n"; }
W=$(clen "  sellarus domain $SHOP <d>"); [ "$W" -lt 24 ] && W=24
L() { local bytes; bytes=$(printf '%s' "$1" | wc -c | tr -d ' '); printf "%-$(( W + bytes - $(clen "$1") ))s: %s\n" "$1" "$2"; }   # aligned "label : value" line
if [ -n "$OTHERS" ]; then OTHERS_TXT=${OTHERS# }; else OTHERS_TXT=$(tp sum_none); fi
SUMMARY=$(
    tp sum_title "$VERSION" "$SHOP" "$(date '+%Y-%m-%d %H:%M')"; printf '\n\n'
    L "$(tp sum_addr)" "$URL"
    L "$(tp sum_finish)" "$URL/install.php   $(tp sum_finish_note)"
    L "$(tp sum_admin)" "$URL/admin/login.php"
    printf '\n%s\n' "$(tp sum_db)"
    L "  $(tp sum_hostport)" "db / 3306   $(tp sum_prefilled)"
    L "  $(tp sum_name)" "$DB_NAME"
    L "  $(tp sum_user)" "$DB_USER"
    L "  $(tp sum_pass)" "$DB_PASSWORD"
    L "  $(tp sum_root)" "$DB_ROOT_PASSWORD"
    printf '\n'
    L "$(tp sum_files)" "$SHOP_DIR   $(tp sum_files_note)"
    L "$(tp sum_front)" "$PROXY   $(tp sum_front_note "$SHOP")"
    L "$(tp sum_data)" "$(tp sum_data_note "sellarus-$SHOP" "sellarus-$SHOP")"
    L "$(tp sum_others)" "$OTHERS_TXT   $(tp sum_others_note)"
    printf '\n%s\n' "$(tp sum_cmds)"
    L "  sellarus list" "$(tp cmd_list)"
    L "  sellarus status $SHOP" "$(tp cmd_status)"
    L "  sellarus update $SHOP" "$(tp cmd_update)"
    L "  sellarus backup $SHOP" "$(tp cmd_backup "$SHOP_DIR/backups/")"
    L "  sellarus logs $SHOP web" "$(tp cmd_logs)"
    L "  sellarus domain $SHOP <d>" "$(tp cmd_domain)"
    L "  sellarus restart $SHOP" "$(tp cmd_restart)"
)
printf '%s\n' "$SUMMARY" > "$SHOP_DIR/INSTALLATION.txt"; chmod 600 "$SHOP_DIR/INSTALLATION.txt"
hr
printf '%s\n' "${GREEN}${B}$(tp installed_banner)${R}"
hr
# The summary is shown in green so that it stands out; the three addresses in bold.
printf '%s\n' "$SUMMARY" | sed "s/^\($(tp sum_addr)\|$(tp sum_finish)\|$(tp sum_admin)\)\(.*\)$/${B}\1\2${R}${GREEN}/; s/^/${GREEN}/; s/$/${R}/"
hr
why "$(tp keep_note)"
printf '%s\n' "${DIM}$(tp saved_note "$SHOP_DIR/INSTALLATION.txt" "$LOG")${R}"
[ -n "$DOMAIN" ] && note "$(tr_ cert_note "$DOMAIN")"
printf '\n%s%s%s\n\n' "${TEAL}${B}" "$(tp next_step "$URL/install.php")" "${R}"
