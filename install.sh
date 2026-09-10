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
# Options: --yes (approve every step), --shop <name>, --domain <name>, --email <address>, --no-upgrade
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

# ---------- looks ----------
if [ -t 1 ]; then
    R=$'\033[0m'; B=$'\033[1m'; DIM=$'\033[2m'
    TEAL=$'\033[38;5;30m'; NAVY=$'\033[38;5;24m'; GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; WHITE=$'\033[97m'
else
    R=''; B=''; DIM=''; TEAL=''; NAVY=''; GREEN=''; RED=''; YELLOW=''; WHITE=''
fi
say()  { printf '%s\n' "${TEAL}${B}▶${R} $*"; }
ok()   { printf '%s\n' "  ${GREEN}✔${R} $*"; }
warn() { printf '%s\n' "  ${YELLOW}▲${R} $*"; }
die()  { printf '%s\n' "  ${RED}✖${R} $*" >&2; exit 1; }
note() { printf '%s\n' "  ${DIM}$*${R}"; }
hr()   { printf '%s\n' "${DIM}──────────────────────────────────────────────────────────────${R}"; }

banner() {
    printf '\n%s\n' "${NAVY}${B}   ____       _ _                      ${R}"
    printf '%s\n'   "${NAVY}${B}  / ___|  ___| | | __ _ _ __ _   _ ___ ${R}"
    printf '%s\n'   "${NAVY}${B}  \\___ \\ / _ \\ | |/ _\` | '__| | | / __|${R}"
    printf '%s\n'   "${NAVY}${B}   ___) |  __/ | | (_| | |  | |_| \\__ \\${R}"
    printf '%s\n'   "${NAVY}${B}  |____/ \\___|_|_|\\__,_|_|   \\__,_|___/${R}"
    printf '%s\n\n' "${TEAL}  One-page shop with Bitcoin payments — server installation${R}"
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
step() { STEP=$((STEP + 1)); bar "$STEP" "$STEPS" "$1"; }

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
        printf '%s\n' "${RED}Last lines of the log:${R}"; tail -n 25 "$LOG"; die "$label failed (full log: $LOG)"; fi
}

confirm() { # confirm <question> → 0 = yes
    [ "$YES" = 1 ] && { note "$1 → yes (--yes)"; return 0; }
    local a
    printf '  %s%s%s [Y/n] ' "${B}" "$1" "${R}"
    read -r a </dev/tty || a=""
    case "$a" in n|N|no|NO|non) return 1 ;; *) return 0 ;; esac
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

# ---------- arguments ----------
while [ $# -gt 0 ]; do
    case "$1" in
        --yes|-y) YES=1 ;;
        --shop) SHOP=$2; shift ;;
        --domain) DOMAIN=$2; shift ;;
        --email) EMAIL=$2; shift ;;
        --no-upgrade) DO_UPGRADE=0 ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done

banner
[ "$(id -u)" = 0 ] || { command -v sudo >/dev/null || die "Run this script as root (or install sudo)."; warn "Restarting with sudo"; exec sudo -E bash "$0" "$@"; }
[ -r /etc/os-release ] || die "Unsupported system: /etc/os-release not found."
. /etc/os-release
PM=""
case "${ID:-} ${ID_LIKE:-}" in
    *debian*|*ubuntu*) PM=apt ;;
    *fedora*|*rhel*|*centos*|*rocky*|*alma*) PM=dnf ;;
esac
[ -n "$PM" ] || die "This script supports Debian, Ubuntu, Fedora, Rocky and AlmaLinux (found: ${PRETTY_NAME:-unknown})."
ok "System: ${PRETTY_NAME:-$ID} ${DIM}(package manager: $PM)${R}"
EXISTING=$(shops)
if [ -n "$EXISTING" ]; then
    note "Shops already on this server: $(printf '%s ' $EXISTING)— this run adds another one (another domain)."
elif [ -f "$DIR/.env" ] && [ -f "$DIR/docker-compose.yml" ]; then
    warn "A shop installed with the first layout lives in $DIR; it will be converted (data kept) before continuing."
    LEGACY=1
fi

# ---------- 1. system update ----------
step "System update"
if [ "$DO_UPGRADE" = 1 ] && confirm "Update and upgrade the system packages now?"; then
    if [ "$PM" = apt ]; then
        export DEBIAN_FRONTEND=noninteractive
        run "Package lists refreshed" apt-get update -y
        run "System upgraded" apt-get upgrade -y
    else
        run "System upgraded" dnf upgrade -y
    fi
else
    note "System upgrade skipped."
fi

# ---------- 2. dependencies ----------
step "Dependencies"
need=()
for tool in curl ca-certificates; do
    if [ "$tool" = ca-certificates ]; then [ -d /etc/ssl/certs ] || need+=("$tool"); else command -v "$tool" >/dev/null || need+=("$tool"); fi
done
if [ ${#need[@]} -gt 0 ]; then
    confirm "Install ${need[*]}?" || die "curl is required."
    if [ "$PM" = apt ]; then run "Installed: ${need[*]}" apt-get install -y "${need[@]}"; else run "Installed: ${need[*]}" dnf install -y "${need[@]}"; fi
else
    ok "curl and certificates already present"
fi
if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
    ok "Docker already installed: $(docker --version | sed 's/,.*//')"
else
    confirm "Docker is missing. Install it now (official Docker packages)?" || die "Docker is required."
    run "Docker installed" sh -c 'curl -fsSL https://get.docker.com | sh'
fi
systemctl enable --now docker >>"$LOG" 2>&1 || true
docker info >/dev/null 2>&1 || die "Docker does not answer. Check 'systemctl status docker' and run the script again."
ok "Docker is running"
# the stack files (always the current ones) and the sellarus command
mkdir -p "$PROXY/sites" "$SHOPS" && chmod 700 "$DIR" "$SHOPS"
run "Stack files downloaded" sh -c "curl -fsSL '$BASE_URL/stack/proxy/docker-compose.yml' -o '$PROXY/docker-compose.yml' && curl -fsSL '$BASE_URL/stack/proxy/Caddyfile' -o '$PROXY/Caddyfile' && curl -fsSL '$BASE_URL/sellarus' -o /usr/local/bin/sellarus && chmod +x /usr/local/bin/sellarus"
if [ "${LEGACY:-0}" = 1 ]; then
    say "Converting the existing shop to the new layout (data kept)"
    SELLARUS_BASE_URL="$BASE_URL" sellarus migrate
    EXISTING=$(shops)
fi

# ---------- 3. firewall and ports ----------
step "Network"
if proxy_running; then
    ok "The HTTPS front of this server is already running (ports 80 and 443 are its own)"
else
    if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q '^Status: active'; then
        if confirm "Open ports 80 and 443 in ufw?"; then ufw allow 80/tcp >>"$LOG" 2>&1; ufw allow 443/tcp >>"$LOG" 2>&1; ufw allow 443/udp >>"$LOG" 2>&1; ok "ufw: ports 80/443 open"; fi
    elif command -v firewall-cmd >/dev/null && firewall-cmd --state >/dev/null 2>&1; then
        if confirm "Open the http and https services in firewalld?"; then firewall-cmd --permanent --add-service=http >>"$LOG" 2>&1; firewall-cmd --permanent --add-service=https >>"$LOG" 2>&1; firewall-cmd --reload >>"$LOG" 2>&1; ok "firewalld: http/https open"; fi
    else
        ok "No local firewall to configure ${DIM}(check the firewall of your provider: ports 80 and 443 must be open)${R}"
    fi
    for port in 80 443; do
        if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$port\$"; then
            die "Port $port is already in use on this server (another web server?). Stop it, then run the script again."
        fi
    done
    ok "Ports 80 and 443 are free"
fi

# ---------- 4. settings ----------
step "Your settings"
PUBLIC_IP=$(curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null || curl -fsS --max-time 8 https://ifconfig.me 2>/dev/null || true)
[ -n "$PUBLIC_IP" ] && note "Public address of this server: $PUBLIC_IP"
IP_SHOP=$(grep -ls '^:80 {' "$PROXY"/sites/*.caddy 2>/dev/null | head -n1 | xargs -r basename | sed 's/\.caddy$//' || true)
if [ -n "$EXISTING" ]; then
    [ -n "$DOMAIN" ] || ask DOMAIN "Domain name of the new shop (required: the other shops are told apart by their domain)" ""
else
    [ -n "$DOMAIN" ] || ask DOMAIN "Domain name of the shop (empty = no domain, HTTP on the IP address only)" ""
fi
DOMAIN=$(printf '%s' "$DOMAIN" | tr 'A-Z' 'a-z' | sed 's#^https\?://##; s#/.*$##')
if [ -n "$DOMAIN" ]; then
    printf '%s' "$DOMAIN" | grep -Eq '^([a-z0-9-]+\.)+[a-z]{2,}$' || die "'$DOMAIN' does not look like a domain name."
    for s in $EXISTING; do [ "$(grep -o '^DOMAIN=.*' "$SHOPS/$s/.env" | cut -d= -f2-)" = "$DOMAIN" ] && die "$DOMAIN is already the domain of the shop '$s'."; done
    if [ -f "$PROXY/.env" ]; then EMAIL=${EMAIL:-$(grep -o '^ACME_EMAIL=.*' "$PROXY/.env" | cut -d= -f2-)}; [ "$EMAIL" = admin@localhost ] && EMAIL=""; fi
    [ -n "$EMAIL" ] || ask EMAIL "Your e-mail (for the HTTPS certificate: expiry notices)" ""
    printf '%s' "$EMAIL" | grep -Eq '^[^@ ]+@[^@ ]+\.[a-z]{2,}$' || die "'$EMAIL' does not look like an e-mail address."
    DEF_SHOP=$(printf '%s' "$DOMAIN" | sed 's/^www\.//' | cut -d. -f1 | tr -c 'a-z0-9-' '-' | sed 's/-*$//')
else
    [ -z "$IP_SHOP" ] || die "The shop '$IP_SHOP' already answers on the bare server address: a second shop needs a domain name."
    [ -z "$EXISTING" ] || die "A domain name is required to add a shop next to $(printf '%s ' $EXISTING)."
    DEF_SHOP=boutique
fi
[ -n "$DEF_SHOP" ] || DEF_SHOP=boutique
while :; do
    [ -n "$SHOP" ] || ask SHOP "Short name of this shop on the server (letters, digits, dashes)" "$DEF_SHOP"
    SHOP=$(printf '%s' "$SHOP" | tr 'A-Z' 'a-z')
    if ! printf '%s' "$SHOP" | grep -Eq '^[a-z0-9][a-z0-9-]{0,30}$' || [ "$SHOP" = proxy ]; then warn "Invalid name '$SHOP' (letters, digits, dashes, 31 characters at most)."; SHOP=""; [ "$YES" = 1 ] && die "Invalid --shop value."; continue; fi
    if [ -f "$SHOPS/$SHOP/.env" ]; then warn "A shop named '$SHOP' already exists on this server."; SHOP=""; [ "$YES" = 1 ] && die "Shop name already used."; continue; fi
    break
done
ask DB_NAME "Database name" "sellarus"
ask DB_USER "Database user" "sellarus"
ask DB_PASSWORD "Database password (Enter = generated)" "$(password)" secret
ask DB_ROOT_PASSWORD "Database root password (Enter = generated)" "$(password)" secret
DB_PREFIX=vb_

# ---------- 5. domain check ----------
step "Domain check"
if [ -n "$DOMAIN" ]; then
    while :; do
        RESOLVED=$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk '{print $1}' | head -n1 || true)
        if [ -n "$RESOLVED" ] && { [ -z "$PUBLIC_IP" ] || [ "$RESOLVED" = "$PUBLIC_IP" ]; }; then
            ok "$DOMAIN points to this server ($RESOLVED)"; break
        fi
        warn "$DOMAIN does not point to this server yet ${DIM}(resolves to: ${RESOLVED:-nothing}, server: ${PUBLIC_IP:-?})${R}"
        note "At your domain registrar, add a DNS record:  ${B}A${R}  ${B}$DOMAIN${R}  →  ${B}${PUBLIC_IP:-<server IP>}${R}"
        note "(and 'www' too if you want www.$DOMAIN). Changes can take a few minutes to spread."
        if confirm "Check again?"; then sleep 5; continue; fi
        confirm "Continue anyway? (the certificate will be obtained automatically once the domain points here)" || die "Installation stopped. Run the script again when the domain is ready."
        break
    done
else
    warn "No domain: the shop will answer on http://$PUBLIC_IP without HTTPS. Add a domain later with: sellarus domain $SHOP your-domain.tld"
fi

# ---------- 6. stack ----------
step "Installation"
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
ok "Settings written to $SHOP_DIR/.env"
if [ ! -f "$PROXY/.env" ]; then
    { echo "ACME_EMAIL=${EMAIL:-admin@localhost}"; echo "HTTP_PORT=80"; echo "HTTPS_PORT=443"; } > "$PROXY/.env"; chmod 600 "$PROXY/.env"
elif [ -n "$EMAIL" ] && grep -q '^ACME_EMAIL=admin@localhost' "$PROXY/.env"; then
    sed -i "s/^ACME_EMAIL=.*/ACME_EMAIL=$EMAIL/" "$PROXY/.env"
fi
{
    printf '# Shop "%s" — generated by Sellarus (sellarus domain %s ...). Edit by hand if you know Caddy.\n' "$SHOP" "$SHOP"
    printf '%s {\n\tencode zstd gzip\n\treverse_proxy sellarus-%s:80\n}\n' "${DOMAIN:-:80}" "$SHOP"
} > "$PROXY/sites/$SHOP.caddy"
ok "Site declared in the HTTPS front: proxy/sites/$SHOP.caddy"
confirm "Download the Sellarus image and start the shop now?" || die "Stopped before starting. Later: sellarus start $SHOP"
cd "$SHOP_DIR"
run "Images downloaded (Sellarus, MariaDB, Caddy)" sh -c "docker compose pull && docker compose --project-directory '$PROXY' pull"
run "HTTPS front started" docker compose --project-directory "$PROXY" up -d
if [ -n "$EXISTING" ]; then docker compose --project-directory "$PROXY" exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile >>"$LOG" 2>&1 || warn "The front did not reload; 'sellarus proxy restart' will do it"; fi
run "Shop containers started" docker compose up -d
printf '  %s' "${DIM}waiting for the shop to answer"
for _ in $(seq 1 60); do
    if docker compose exec -T web sh -c 'curl -fsS -o /dev/null http://localhost/install.php' >/dev/null 2>&1; then break; fi
    printf '.'; sleep 2
done
printf '%s\n' "${R}"
docker compose exec -T web sh -c 'curl -fsS -o /dev/null http://localhost/install.php' >/dev/null 2>&1 || die "The shop does not answer yet. Look at: sellarus logs $SHOP web"
VERSION=$(docker compose exec -T web sh -c "grep -o \"VB_VERSION', '[^']*'\" /var/www/html/app/bootstrap.php | grep -o '[0-9][0-9.]*'" 2>/dev/null | tr -d '\r' || echo "?")
ok "Sellarus $VERSION is running"

# ---------- 7. summary ----------
step "Done"
if [ -n "$DOMAIN" ]; then URL="https://$DOMAIN"; else URL="http://${PUBLIC_IP:-<server IP>}"; fi
OTHERS=""; for s in $(shops); do [ "$s" = "$SHOP" ] || OTHERS="$OTHERS $s"; done
SUMMARY=$(cat <<EOF
Sellarus $VERSION — shop "$SHOP" — installation summary ($(date '+%Y-%m-%d %H:%M'))

Shop address          : $URL
Finish the setup      : $URL/install.php   (create your administrator account in the browser)
Back-office           : $URL/admin/login.php

Database (inside Docker, not reachable from the Internet)
  host / port         : db / 3306   (pre-filled in the installer)
  name                : $DB_NAME
  user                : $DB_USER
  password            : $DB_PASSWORD
  root password       : $DB_ROOT_PASSWORD

Files                 : $SHOP_DIR   (docker-compose.yml, .env — keep .env private)
HTTPS front           : $PROXY   (shared by every shop of this server; this shop: sites/$SHOP.caddy)
Data                  : Docker volumes sellarus-${SHOP}_www (site), sellarus-${SHOP}_db (database)
Other shops here      :${OTHERS:- none}   (run the installation script again to add one)

Everyday commands
  sellarus list               : the shops of this server
  sellarus status $SHOP       : containers and version
  sellarus update $SHOP       : update to the latest version (the back-office "Update" screen works too)
  sellarus backup $SHOP       : database dump + files into $SHOP_DIR/backups/
  sellarus logs $SHOP web     : follow the logs
  sellarus domain $SHOP <d>   : change the domain
  sellarus restart $SHOP      : restart this shop
EOF
)
printf '%s\n' "$SUMMARY" > "$SHOP_DIR/INSTALLATION.txt"; chmod 600 "$SHOP_DIR/INSTALLATION.txt"
hr
printf '%s\n' "${GREEN}${B}Sellarus is installed.${R}"
hr
printf '%s\n' "$SUMMARY" | sed "s/^\(Shop address\|Finish the setup\|Back-office\)\(.*\)$/${B}\1\2${R}/"
hr
printf '%s\n' "${DIM}This summary is saved in $SHOP_DIR/INSTALLATION.txt (readable by root only). Log: $LOG${R}"
[ -n "$DOMAIN" ] && note "The HTTPS certificate is obtained automatically the first time $DOMAIN is opened; give it a minute."
printf '\n%s%s%s\n\n' "${TEAL}${B}" "Next step: open $URL/install.php" "${R}"
