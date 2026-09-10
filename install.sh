#!/usr/bin/env bash
# Sellarus — one-command installation on a fresh Linux server (VPS).
#
#   curl -fsSL https://sellarus.com/install.sh | bash
#
# What it does, step by step, asking for your approval each time:
#   1. updates the system, 2. installs what is missing (Docker), 3. opens the web ports in the firewall,
#   4. asks for your domain, e-mail and database settings, 5. checks that the domain points to this server,
#   6. writes the Sellarus stack into /opt/sellarus and starts it (HTTPS certificate obtained automatically),
#   7. prints every piece of information you need and saves it in /opt/sellarus/INSTALLATION.txt.
# The same script serves every version: it always installs the latest published image.
# Options: --yes (approve every step), --domain <name>, --email <address>, --no-upgrade
set -euo pipefail

BASE_URL="${SELLARUS_BASE_URL:-https://raw.githubusercontent.com/nitrus21/sellarus-releases/main}"
IMAGE="ghcr.io/nitrus21/sellarus"
DIR=/opt/sellarus
STEPS=7
STEP=0
YES=0
DO_UPGRADE=1
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

# ---------- arguments ----------
while [ $# -gt 0 ]; do
    case "$1" in
        --yes|-y) YES=1 ;;
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
if [ -f "$DIR/.env" ]; then
    warn "Sellarus is already installed in $DIR."
    note "Use ${B}sellarus update${R} to update it, or remove $DIR to start over."
    exit 0
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

# ---------- 3. firewall and ports ----------
step "Network"
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

# ---------- 4. settings ----------
step "Your settings"
PUBLIC_IP=$(curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null || curl -fsS --max-time 8 https://ifconfig.me 2>/dev/null || true)
[ -n "$PUBLIC_IP" ] && note "Public address of this server: $PUBLIC_IP"
[ -n "$DOMAIN" ] || ask DOMAIN "Domain name of the shop (empty = no domain, HTTP on the IP address only)" ""
DOMAIN=$(printf '%s' "$DOMAIN" | tr 'A-Z' 'a-z' | sed 's#^https\?://##; s#/.*$##')
if [ -n "$DOMAIN" ]; then
    printf '%s' "$DOMAIN" | grep -Eq '^([a-z0-9-]+\.)+[a-z]{2,}$' || die "'$DOMAIN' does not look like a domain name."
    [ -n "$EMAIL" ] || ask EMAIL "Your e-mail (for the HTTPS certificate: expiry notices)" ""
    printf '%s' "$EMAIL" | grep -Eq '^[^@ ]+@[^@ ]+\.[a-z]{2,}$' || die "'$EMAIL' does not look like an e-mail address."
fi
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
    warn "No domain: the shop will answer on http://$PUBLIC_IP without HTTPS. Add a domain later by editing $DIR/.env (DOMAIN=...) and running: sellarus restart"
fi

# ---------- 6. stack ----------
step "Installation"
mkdir -p "$DIR" && chmod 700 "$DIR" && cd "$DIR"
run "Stack files downloaded" sh -c "curl -fsSL '$BASE_URL/stack/docker-compose.yml' -o docker-compose.yml && curl -fsSL '$BASE_URL/stack/Caddyfile' -o Caddyfile && curl -fsSL '$BASE_URL/sellarus' -o /usr/local/bin/sellarus && chmod +x /usr/local/bin/sellarus"
{
    echo "DOMAIN=${DOMAIN:-:80}"
    echo "ACME_EMAIL=${EMAIL:-admin@localhost}"
    echo "DB_NAME=$DB_NAME"
    echo "DB_USER=$DB_USER"
    echo "DB_PASSWORD=$DB_PASSWORD"
    echo "DB_ROOT_PASSWORD=$DB_ROOT_PASSWORD"
    echo "DB_PREFIX=$DB_PREFIX"
    echo "SELLARUS_TAG=latest"
} > .env
chmod 600 .env
ok "Settings written to $DIR/.env"
confirm "Download the Sellarus image and start the shop now?" || die "Stopped before starting. Later: cd $DIR && docker compose up -d"
run "Images downloaded (Sellarus, MariaDB, Caddy)" docker compose pull
run "Containers started" docker compose up -d
printf '  %s' "${DIM}waiting for the shop to answer"
for _ in $(seq 1 60); do
    if docker compose exec -T web sh -c 'curl -fsS -o /dev/null http://localhost/install.php' >/dev/null 2>&1; then break; fi
    printf '.'; sleep 2
done
printf '%s\n' "${R}"
docker compose exec -T web sh -c 'curl -fsS -o /dev/null http://localhost/install.php' >/dev/null 2>&1 || die "The shop does not answer yet. Look at: sellarus logs web"
VERSION=$(docker compose exec -T web sh -c "grep -o \"VB_VERSION', '[^']*'\" /var/www/html/app/bootstrap.php | grep -o '[0-9][0-9.]*'" 2>/dev/null | tr -d '\r' || echo "?")
ok "Sellarus $VERSION is running"

# ---------- 7. summary ----------
step "Done"
if [ -n "$DOMAIN" ]; then URL="https://$DOMAIN"; else URL="http://${PUBLIC_IP:-<server IP>}"; fi
SUMMARY=$(cat <<EOF
Sellarus $VERSION — installation summary ($(date '+%Y-%m-%d %H:%M'))

Shop address          : $URL
Finish the setup      : $URL/install.php   (create your administrator account in the browser)
Back-office           : $URL/admin/login.php

Database (inside Docker, not reachable from the Internet)
  host / port         : db / 3306   (pre-filled in the installer)
  name                : $DB_NAME
  user                : $DB_USER
  password            : $DB_PASSWORD
  root password       : $DB_ROOT_PASSWORD

Files                 : $DIR   (docker-compose.yml, Caddyfile, .env — keep .env private)
Data                  : Docker volumes sellarus_www (site), sellarus_db (database), sellarus_caddy_data (certificates)

Everyday commands
  sellarus status     : containers and version
  sellarus update     : update to the latest version (the back-office "Update" screen works too)
  sellarus backup     : database dump + files into $DIR/backups/
  sellarus logs web   : follow the logs
  sellarus restart    : restart everything
EOF
)
printf '%s\n' "$SUMMARY" > "$DIR/INSTALLATION.txt"; chmod 600 "$DIR/INSTALLATION.txt"
hr
printf '%s\n' "${GREEN}${B}Sellarus is installed.${R}"
hr
printf '%s\n' "$SUMMARY" | sed "s/^\(Shop address\|Finish the setup\|Back-office\)\(.*\)$/${B}\1\2${R}/"
hr
printf '%s\n' "${DIM}This summary is saved in $DIR/INSTALLATION.txt (readable by root only). Log: $LOG${R}"
[ -n "$DOMAIN" ] && note "The HTTPS certificate is obtained automatically the first time $DOMAIN is opened; give it a minute."
printf '\n%s%s%s\n\n' "${TEAL}${B}" "Next step: open $URL/install.php" "${R}"
