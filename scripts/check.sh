#!/bin/bash
# =============================================================================
# Audyt serwera pod Noda (PRZED i PO instalacji)
# =============================================================================
# Sprawdza wymagania (CPU, RAM, dysk, Docker, Buildx, Git, OpenSSL), łańcuch
# vps-security -> tailscale-vps, instalację Noda, dostęp przez Tailscale Serve,
# stan aplikacji z bazy (bez sekretów), backup i wersję. NICZEGO NIE ZMIENIA.
#
# Uruchom na serwerze:      bash check.sh
# Audyt PRZED instalacją:   bash check.sh --before
# Inne katalogi:            bash check.sh --nod-dir /sciezka/nod --backup-dir /sciezka/kopie
#
# Plik versions.env (przetestowany tag) skopiuj obok check.sh - bez niego
# skrypt nie porówna wersji z przetestowaną.
#
# UWAGA: skrypt działa NA serwerze. Tego, że port 4310 nie odpowiada z
# internetu, dowodzi test z Twojego komputera (wizard, Faza 5).
# =============================================================================

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${GREEN}[PASS]${NC}  $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}[FAIL]${NC}  $1"; FAIL=$((FAIL + 1)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC}  $1"; WARN=$((WARN + 1)); }
info() { echo -e "  ${BLUE}[INFO]${NC}  $1"; }
header() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

BEFORE=0
FORCE_AFTER=0
NOD_DIR="$HOME/nod"
BACKUP_DIR="$HOME/backups/nod"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --before) BEFORE=1 ;;
        --after)  FORCE_AFTER=1 ;;
        --nod-dir) NOD_DIR="${2:-$NOD_DIR}"; shift ;;
        --backup-dir) BACKUP_DIR="${2:-$BACKUP_DIR}"; shift ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    esac
    shift
done
SELF_HOST="$NOD_DIR/deployment/self-host"
ENV_FILE="$SELF_HOST/.env"

# Bez zainstalowanego Noda (brak .env) audyt sam przechodzi w tryb PRZED.
if [[ "$FORCE_AFTER" -eq 0 && ! -f "$ENV_FILE" ]]; then
    BEFORE=1
fi
[[ "$FORCE_AFTER" -eq 1 ]] && BEFORE=0

# W trybie PRZED punkty, które robi wizard, raportujemy jako WARN, nie FAIL.
softfail() {
    if [[ "$BEFORE" -eq 1 ]]; then
        warn "$1 (robi to wizard w $2)"
    else
        fail "$1"
    fi
}

# Wartość z .env bez wypisywania sekretów - używane TYLKO dla kluczy jawnych.
envval() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '"'"'"; }
# Długość wartości (do sprawdzenia, czy sekret nie jest pusty) - samej wartości nie pokazujemy.
envlen() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '\n"'"'" | wc -c | tr -d ' '; }

SUDO=""
if [[ $EUID -eq 0 ]]; then
    HAVE_ROOT=1
elif sudo -n true 2>/dev/null; then
    SUDO="sudo"
    HAVE_ROOT=1
else
    HAVE_ROOT=0
fi

DOCKER=""
if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
        DOCKER="docker"
    elif [[ $HAVE_ROOT -eq 1 ]] && $SUDO docker info >/dev/null 2>&1; then
        DOCKER="$SUDO docker"
    fi
fi

TESTED_TAG=""
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
if [[ -f "$SCRIPT_DIR/versions.env" ]]; then
    # shellcheck disable=SC1091
    . "$SCRIPT_DIR/versions.env"
    TESTED_TAG="${NOD_TESTED_TAG:-}"
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║          AUDYT SERWERA POD NODA          ║"
echo "║       $(date +%Y-%m-%d\ %H:%M)                    ║"
echo "╚══════════════════════════════════════════╝"
if [[ "$BEFORE" -eq 1 ]]; then
    echo -e "${YELLOW}Tryb: audyt PRZED${NC} - Noda jeszcze nie ma, to jest oczekiwane."
fi

# --- 1. System i zasoby ---
header "1. System i zasoby"

if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    info "System: ${PRETTY_NAME:-nieznany}"
fi

ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)  pass "Architektura: $ARCH (AMD64)" ;;
    aarch64|arm64) pass "Architektura: $ARCH (ARM64)" ;;
    *) fail "Architektura: $ARCH - Nod wspiera tylko Linux AMD64 i ARM64" ;;
esac

if [[ $EUID -eq 0 ]]; then
    warn "Pracujesz jako root - na produkcji najpierw vps-security (użytkownik nie-root z sudo)"
else
    pass "Użytkownik nie-root: $(id -un)"
fi

CPUS=$(nproc 2>/dev/null || echo 0)
if [[ "$CPUS" -ge 4 ]]; then
    pass "CPU: $CPUS rdzeni"
elif [[ "$CPUS" -ge 2 ]]; then
    pass "CPU: $CPUS rdzenie (minimum z dokumentacji; build potrwa dłużej niż ok. 7 min na 4 vCPU)"
else
    fail "CPU: $CPUS - dokumentacja Noda wymaga minimum 2 rdzeni"
fi

MEM_KB=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
AVAIL_KB=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
MEM_GB=$(( (MEM_KB + 524288) / 1048576 ))
AVAIL_GB=$(( AVAIL_KB / 1048576 ))
if [[ "$MEM_KB" -lt 5767168 ]]; then
    fail "RAM: ${MEM_GB} GB - za mało (dokumentacja: start od 8 GB; limity kontenerów to razem ok. 7 GB + Postgres)"
elif [[ "$MEM_KB" -lt 7340032 ]]; then
    warn "RAM: ${MEM_GB} GB - poniżej 8 GB z dokumentacji; przy większych zadaniach workspace może paść"
else
    pass "RAM: ${MEM_GB} GB (dostępne teraz: ok. ${AVAIL_GB} GB)"
fi

DISK_PATH="$HOME"
if [[ -n "$DOCKER" ]]; then
    DROOT=$($DOCKER info --format '{{.DockerRootDir}}' 2>/dev/null || true)
    [[ -n "$DROOT" && -d "$DROOT" ]] && DISK_PATH="$DROOT"
fi
FREE_GB=$(df -Pk "$DISK_PATH" 2>/dev/null | awk 'NR==2{print int($4/1048576)}')
FREE_GB=${FREE_GB:-0}
if [[ "$BEFORE" -eq 1 ]]; then
    if [[ "$FREE_GB" -lt 15 ]]; then
        fail "Dysk: ${FREE_GB} GB wolne na $DISK_PATH - za mało (obrazy ok. 5 GB, każdy build dokłada cache)"
    elif [[ "$FREE_GB" -lt 50 ]]; then
        warn "Dysk: ${FREE_GB} GB wolne - dokumentacja zaleca 50 GB na start"
    else
        pass "Dysk: ${FREE_GB} GB wolne na $DISK_PATH"
    fi
else
    if [[ "$FREE_GB" -lt 5 ]]; then
        fail "Dysk: ${FREE_GB} GB wolne - następna aktualizacja (build) może się nie zmieścić"
    elif [[ "$FREE_GB" -lt 15 ]]; then
        warn "Dysk: ${FREE_GB} GB wolne - każda aktualizacja dokłada kilka GB obrazów i cache (docker builder prune)"
    else
        pass "Dysk: ${FREE_GB} GB wolne na $DISK_PATH"
    fi
fi

# --- 2. Narzędzia ---
header "2. Docker i narzędzia"

if ! command -v docker >/dev/null 2>&1; then
    fail "Docker nie zainstalowany (wymagany Docker Engine 25+ z Compose v2 i Buildx)"
elif [[ -z "$DOCKER" ]]; then
    fail "Docker jest, ale $(id -un) nie ma do niego dostępu (dodaj do grupy docker i zaloguj się ponownie)"
else
    if [[ "$DOCKER" == "docker" ]]; then
        pass "Docker działa bez sudo dla $(id -un)"
    else
        warn "Docker działa tylko przez sudo - wizard zakłada grupę docker (sudo usermod -aG docker $(id -un), potem nowe logowanie)"
    fi
    DV=$($DOCKER version --format '{{.Server.Version}}' 2>/dev/null || echo "")
    DV_MAJOR=${DV%%.*}
    if [[ "$DV_MAJOR" =~ ^[0-9]+$ && "$DV_MAJOR" -ge 25 ]]; then
        pass "Docker Engine $DV"
    else
        fail "Docker Engine ${DV:-nieznany} - wymagane 25+"
    fi
    CV=$($DOCKER compose version --short 2>/dev/null || echo "")
    CV_MAJOR=${CV#v}; CV_MAJOR=${CV_MAJOR%%.*}
    if [[ "$CV_MAJOR" =~ ^[0-9]+$ && "$CV_MAJOR" -ge 2 ]]; then
        pass "Docker Compose $CV (plugin, v2 lub nowszy)"
    else
        fail "Docker Compose v2 niedostępny (docker compose version) - stary docker-compose v1 nie wystarczy"
    fi
    BV=$($DOCKER buildx version 2>/dev/null | awk '{print $2}' | head -1)
    if [[ -n "$BV" ]]; then
        pass "Docker Buildx $BV"
    else
        fail "Brak Docker Buildx - build Noda skończy się błędem 'the --chmod option requires BuildKit' (pakiet docker-buildx-plugin)"
    fi
fi

for tool in git openssl curl; do
    if command -v "$tool" >/dev/null 2>&1; then
        pass "$tool: obecny"
    else
        fail "$tool: brak (sudo apt-get install -y $tool)"
    fi
done
if command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1; then
    pass "sha256sum/shasum: obecny"
else
    fail "Brak sha256sum i shasum (pakiet coreutils)"
fi
HAVE_PY=0
if command -v python3 >/dev/null 2>&1; then
    HAVE_PY=1
    pass "python3: obecny (używany do odczytu stanu Tailscale)"
else
    # python3 czyta stan Tailscale (zalogowanie, nazwa, certyfikaty). Po instalacji to kontrola obowiązkowa.
    softfail "Brak python3 - nie sprawdzę stanu Tailscale (sudo apt-get install -y python3)" "Fazie 1 (doinstaluj przed Fazą 3)"
fi

# --- 3. Łańcuch: vps-security -> tailscale-vps ---
header "3. Łańcuch: vps-security i tailscale-vps"

if command -v ufw >/dev/null 2>&1 && [[ $HAVE_ROOT -eq 1 ]]; then
    if $SUDO ufw status 2>/dev/null | grep -q "Status: active"; then
        pass "ufw aktywny (stan po vps-security)"
    else
        warn "ufw nieaktywny - jeśli zamykasz porty firewallem dostawcy (np. panel Hostingera), to OK; inaczej najpierw vps-security"
    fi
else
    info "ufw brak lub bez uprawnień - firewall sprawdza audyt z vps-security / tailscale-vps"
fi

TS_DNS=""
TS_RUNNING=0
if command -v tailscale >/dev/null 2>&1; then
    pass "Tailscale zainstalowany: $(tailscale version 2>/dev/null | head -1)"
    if [[ $HAVE_PY -eq 1 ]]; then
        TS_JSON=$(tailscale status --json 2>/dev/null || echo '{}')
        BACKEND=$(echo "$TS_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("BackendState",""))' 2>/dev/null || echo "")
        if [[ "$BACKEND" == "Running" ]]; then
            TS_RUNNING=1
            TS_DNS=$(echo "$TS_JSON" | python3 -c 'import json,sys; print((json.load(sys.stdin).get("Self") or {}).get("DNSName","").rstrip("."))' 2>/dev/null || echo "")
            pass "Serwer w tailnecie jako ${TS_DNS:-?}"
            CERTS=$(echo "$TS_JSON" | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("CertDomains") or []))' 2>/dev/null || echo 0)
            if [[ "$CERTS" -gt 0 ]]; then
                pass "HTTPS Certificates włączone w tailnecie (Tailscale Serve dostanie prawdziwy certyfikat)"
            else
                warn "HTTPS Certificates wyglądają na wyłączone - konsola Tailscale: DNS -> MagicDNS i HTTPS Certificates (klik użytkownika)"
            fi
        else
            fail "Tailscale nie jest zalogowany (BackendState: ${BACKEND:-brak}) - najpierw tailscale-vps"
        fi
    elif [[ "$BEFORE" -eq 0 ]]; then
        fail "Nie mogę sprawdzić, czy Tailscale jest zalogowany i jak nazywa się serwer (brak python3)"
    fi
else
    fail "Brak Tailscale - ten poradnik wystawia Noda tylko przez Tailscale Serve; najpierw https://szewowsky.github.io/tailscale-vps/"
fi

# --- 4. Porty i sąsiedzi ---
header "4. Porty i inne usługi na serwerze"

L4310=$(ss -tlnH 2>/dev/null | awk '{print $4}' | grep -E ':4310$' | sort -u | tr '\n' ' ')
if [[ -z "$L4310" ]]; then
    if [[ "$BEFORE" -eq 1 ]]; then
        pass "Port 4310 wolny"
    else
        fail "Nic nie słucha na porcie 4310 - serwer Noda nie działa"
    fi
else
    PUBLIC_4310=0
    for a in $L4310; do
        case "$a" in
            127.0.0.1:*|\[::1\]:*) ;;
            100.*|\[fd7a:*) info "  $a - adres tailnetu (Tailscale Serve)" ;;
            *) PUBLIC_4310=1 ;;
        esac
    done
    if [[ "$PUBLIC_4310" -eq 1 ]]; then
        fail "Port 4310 słucha na adresie publicznym ($L4310) - ma być tylko 127.0.0.1 (NOD_BIND_ADDRESS); Docker omija ufw"
    elif [[ "$BEFORE" -eq 1 ]]; then
        warn "Port 4310 już zajęty ($L4310) - poprzednia instalacja Noda albo inna usługa; sprawdź przed Fazą 2"
    else
        pass "Serwer Noda słucha tylko lokalnie: $L4310"
    fi
fi

WEB=$(ss -tlnH 2>/dev/null | awk '{print $4}' | grep -E ':(80|443)$' | sed -E 's/.*:([0-9]+)$/\1/' | sort -un | tr '\n' ' ')
if [[ -n "$WEB" ]]; then
    info "Porty $WEB zajęte (inne WWW / proxy) - tryb Tailscale Serve ich nie potrzebuje i nie rusza"
fi

if [[ -n "$DOCKER" ]]; then
    OTHERS=$($DOCKER ps --format '{{.Names}}' 2>/dev/null | grep -vE '^nod-' || true)
    N_OTHERS=$(printf '%s' "$OTHERS" | grep -c . || true)
    if [[ "$N_OTHERS" -gt 0 ]]; then
        info "Inne kontenery na serwerze: $N_OTHERS ($(printf '%s' "$OTHERS" | head -8 | tr '\n' ' '))"
        if [[ "$MEM_KB" -le 17825792 ]]; then
            warn "Nod (limity ok. 7 GB + Postgres) i $N_OTHERS innych kontenerów na ${MEM_GB} GB RAM - przy dwóch agentach jeden może wywołać brak pamięci drugiego"
        fi
    else
        info "Brak innych kontenerów"
    fi
fi

# --- 5. Instalacja Noda ---
header "5. Instalacja Noda ($NOD_DIR)"

INSTALLED_TAG=""
if [[ -d "$NOD_DIR/.git" ]]; then
    INSTALLED_TAG=$(git -C "$NOD_DIR" describe --tags --exact-match 2>/dev/null || true)
    if [[ -n "$INSTALLED_TAG" ]]; then
        pass "Kod Noda: tag $INSTALLED_TAG (commit $(git -C "$NOD_DIR" rev-parse --short HEAD 2>/dev/null))"
    else
        warn "Kod Noda nie stoi na tagu (commit $(git -C "$NOD_DIR" rev-parse --short HEAD 2>/dev/null)) - poradnik zakłada tag nod-v*"
    fi
else
    softfail "Brak kodu Noda w $NOD_DIR" "Fazie 2"
fi

if [[ -f "$ENV_FILE" ]]; then
    PERM=$(stat -c '%a' "$ENV_FILE" 2>/dev/null || stat -f '%Lp' "$ENV_FILE" 2>/dev/null)
    if [[ "$PERM" == "600" ]]; then
        pass ".env ma prawa 600"
    else
        fail ".env ma prawa $PERM - ma być 600 (chmod 600 $ENV_FILE)"
    fi
    for k in NOD_AUTH_TOKEN NOD_VAULT_KEY NOD_POSTGRES_PASSWORD; do
        if [[ "$(envlen "$k")" -ge 16 ]]; then
            pass "$k ustawiony (wartości nie pokazuję)"
        else
            fail "$k pusty albo za krótki - setup.sh nie wygenerował sekretu"
        fi
    done
    CPN=$(envval COMPOSE_PROJECT_NAME)
    if [[ -n "$CPN" ]]; then
        info "COMPOSE_PROJECT_NAME=$CPN"
    else
        warn "Brak COMPOSE_PROJECT_NAME w .env - nazwy kontenerów będą zależne od katalogu"
    fi
    BIND=$(envval NOD_BIND_ADDRESS)
    if [[ -z "$BIND" || "$BIND" == "127.0.0.1" ]]; then
        pass "NOD_BIND_ADDRESS=${BIND:-127.0.0.1 (domyślne)}"
    else
        fail "NOD_BIND_ADDRESS=$BIND - w tym poradniku ma być 127.0.0.1 (na zewnątrz wystawia tylko Tailscale Serve)"
    fi
    PUBURL=$(envval NOD_PUBLIC_URL)
    if [[ "$PUBURL" =~ ^https://[A-Za-z0-9.-]+\.ts\.net:4310$ ]]; then
        pass "NOD_PUBLIC_URL=$PUBURL (sam origin, adres tailnetu)"
    elif [[ "$PUBURL" =~ ^https?://[^/?#]+$ ]]; then
        warn "NOD_PUBLIC_URL=$PUBURL - poprawny origin, ale nie adres tailnetu; ten poradnik obsługuje tylko Tailscale Serve"
    else
        fail "NOD_PUBLIC_URL='${PUBURL}' - ma być sam origin bez ścieżki, np. https://<serwer>.<tailnet>.ts.net:4310"
    fi
    AN=$(envval NOD_ANALYTICS_ENABLED)
    if [[ "$AN" == "false" ]]; then
        pass "NOD_ANALYTICS_ENABLED=false"
    else
        warn "NOD_ANALYTICS_ENABLED='${AN}' - zalecane false"
    fi
else
    softfail "Brak $ENV_FILE" "Fazie 3"
fi

PG_CID=""
if [[ -n "$DOCKER" && -f "$ENV_FILE" ]]; then
    PS_OUT=$(cd "$SELF_HOST" && $DOCKER compose --file compose.yaml --env-file .env ps -a --format '{{.Service}}|{{.State}}|{{.Health}}' 2>/dev/null || true)
    N_RUN=$(printf '%s\n' "$PS_OUT" | grep -c '|running|' || true)
    if [[ "$N_RUN" -ge 6 ]]; then
        pass "Kontenery Noda działają: $N_RUN"
    else
        fail "Działa $N_RUN kontenerów Noda z 6 (docker compose ps w $SELF_HOST)"
    fi
    for svc in server browser postgres workspace-network; do
        H=$(printf '%s\n' "$PS_OUT" | awk -F'|' -v s="$svc" '$1==s{print $3}' | head -1)
        if [[ "$H" == "healthy" ]]; then
            pass "$svc: healthy"
        else
            # Te cztery usługi mają healthcheck w compose Noda - pusty Health = usługi nie ma albo nie działa.
            ST=$(printf '%s\n' "$PS_OUT" | awk -F'|' -v s="$svc" '$1==s{print $2}' | head -1)
            if [[ "$BEFORE" -eq 1 && -z "$H" ]]; then
                warn "$svc: brak healthchecka albo usługi (stan: $ST)"
            else
                fail "$svc: ${H:-brak stanu health} (kontener: ${ST:-nie istnieje}) - oczekiwane healthy"
            fi
        fi
    done
    IDS=$(cd "$SELF_HOST" && $DOCKER compose --file compose.yaml --env-file .env ps -q 2>/dev/null || true)
    if [[ -n "$IDS" ]]; then
        # shellcheck disable=SC2086
        LOOP=$($DOCKER inspect -f '{{.Name}} {{.RestartCount}}' $IDS 2>/dev/null | awk '$2>3{print $1"("$2")"}' | tr '\n' ' ')
        if [[ -n "$LOOP" ]]; then
            warn "Kontenery z wieloma restartami: $LOOP - docker logs --tail 50 <nazwa>"
        else
            pass "Brak pętli restartów"
        fi
        PG_CID=$(cd "$SELF_HOST" && $DOCKER compose --file compose.yaml --env-file .env ps -q postgres 2>/dev/null | head -1)
    fi
elif [[ "$BEFORE" -eq 0 ]]; then
    fail "Nie mogę sprawdzić kontenerów (brak dostępu do Dockera albo .env)"
fi

# --- 6. Dostęp przez Tailscale Serve ---
header "6. Dostęp (Tailscale Serve)"

if [[ "$BEFORE" -eq 1 ]]; then
    info "Tailscale Serve dla portu 4310 ustawia wizard w Fazie 5"
elif [[ "$TS_RUNNING" -eq 1 ]]; then
    SERVE=$(tailscale serve status 2>/dev/null || $SUDO tailscale serve status 2>/dev/null || true)
    if echo "$SERVE" | grep -q ':4310' && echo "$SERVE" | grep -q '127.0.0.1:4310'; then
        pass "tailscale serve: https :4310 -> http://127.0.0.1:4310"
    else
        fail "tailscale serve nie wystawia 4310 (sudo tailscale serve --bg --https=4310 http://127.0.0.1:4310)"
    fi
    if echo "$SERVE" | grep -qi 'funnel'; then
        fail "Tailscale Funnel jest włączony - to publikuje usługę w internecie (tailscale funnel reset)"
    fi
    PUBHOST=$(envval NOD_PUBLIC_URL | sed -E 's#^https?://##; s#:[0-9]+$##')
    if [[ -n "$TS_DNS" && "$PUBHOST" == "$TS_DNS" ]]; then
        pass "NOD_PUBLIC_URL zgadza się z nazwą serwera w tailnecie"
    else
        fail "NOD_PUBLIC_URL ($PUBHOST) różni się od nazwy w tailnecie ($TS_DNS) - Nod odrzuci żądania (403 'This host is not permitted')"
    fi
    URL=$(envval NOD_PUBLIC_URL)
    if [[ -n "$URL" ]]; then
        CODE=$(curl -sS -o /dev/null -m 10 -w '%{http_code}' "$URL/" 2>/dev/null || true)
        if [[ "$CODE" == "200" ]]; then
            pass "Strona $URL odpowiada 200 z ważnym certyfikatem"
        elif [[ "$CODE" == "000" || -z "$CODE" ]]; then
            warn "Serwer nie dosięga własnego adresu tailnetu (MagicDNS na serwerze?) - test 200/401 zrób z komputera (Faza 5)"
        else
            fail "Strona $URL odpowiada $CODE (oczekiwane 200)"
        fi
        if [[ "$CODE" == "200" ]]; then
            S=$(curl -sS -o /dev/null -m 10 -w '%{http_code}' "$URL/api/session" 2>/dev/null || true)
            if [[ "$S" == "401" ]]; then
                pass "/api/session bez tokenu: 401"
            else
                fail "/api/session bez tokenu: $S (oczekiwane 401)"
            fi
        fi
    fi
fi
PUB_IP=$(curl -4 -fsS --max-time 5 https://ifconfig.me 2>/dev/null || true)
if [[ -n "$PUB_IP" ]]; then
    info "Publiczny IPv4 serwera: $PUB_IP - z komputera: curl -m 5 http://$PUB_IP:4310/ ma NIE odpowiedzieć"
fi

# --- 7. Stan aplikacji (z bazy, bez sekretów) ---
header "7. Stan Noda z bazy (bez sekretów)"

q() { $DOCKER exec "$PG_CID" psql -U nod -d nod -At -F '|' -c "$1" </dev/null 2>/dev/null; }
# W trybie PO odczyt bazy jest kontrolą obowiązkową: błąd zapytania (exit != 0) = FAIL,
# pusta tabela (exit 0, brak wierszy) = osobny komunikat.

if [[ "$BEFORE" -eq 1 ]]; then
    info "Onboarding, model i dane użycia sprawdza wizard w Fazie 6 (scripts/nod-state.sh)"
elif [[ -z "$PG_CID" ]]; then
    fail "Nie znalazłem kontenera postgres - nie sprawdzę onboardingu, danych użycia ani modelu"
else
    ACC_RC=0
    ACC=$(q "select onboarding_completed, usage_data from account_settings limit 1") || ACC_RC=$?
    if [[ "$ACC_RC" -ne 0 ]]; then
        fail "Zapytanie do account_settings się nie powiodło (exit $ACC_RC: baza niedostępna albo zmieniony schemat)"
    elif [[ -z "$ACC" ]]; then
        warn "Brak wiersza account_settings albo zmieniony schemat bazy - otwórz Noda w przeglądarce i przejdź onboarding"
    else
        ONB=${ACC%%|*}
        USG=${ACC##*|}
        if [[ "$ONB" == "t" ]]; then
            pass "Onboarding ukończony (zapisany na serwerze)"
        else
            warn "Onboarding nieukończony - zrób go w PRZEGLĄDARCE, dopiero potem aplikacja desktopowa"
        fi
        if [[ "$USG" == "f" ]]; then
            pass "Udostępnianie danych użycia wyłączone"
        else
            warn "Udostępnianie danych użycia WŁĄCZONE - Settings -> Privacy & data -> Share usage data"
        fi
    fi
    CONN_RC=0
    CONN=$(q "select provider, method, status from model_connections order by created_at") || CONN_RC=$?
    if [[ "$CONN_RC" -ne 0 ]]; then
        fail "Zapytanie do model_connections się nie powiodło (exit $CONN_RC)"
    elif [[ -z "$CONN" ]]; then
        warn "Brak podłączonego modelu (Settings -> Models -> Add connection)"
    elif echo "$CONN" | grep -q '|connected$'; then
        pass "Połączenia modeli: $(echo "$CONN" | tr '\n' ' ')"
    else
        warn "Żadne połączenie modelu nie ma statusu connected: $(echo "$CONN" | tr '\n' ' ')"
    fi
    MODEL_RC=0
    MODEL=$(q "select selection::jsonb->>'modelId' from model_settings limit 1") || MODEL_RC=$?
    if [[ "$MODEL_RC" -ne 0 ]]; then
        fail "Zapytanie do model_settings się nie powiodło (exit $MODEL_RC)"
    elif [[ -n "$MODEL" ]]; then
        info "Wybrany model: $MODEL (porównanie z Twoją decyzją: bash nod-state.sh --model chatgpt|apikey)"
    fi
fi

# --- 8. Utrzymanie: backup i wersja ---
header "8. Backup i wersja"

if [[ -d "$BACKUP_DIR" ]]; then
    LAST=$(find "$BACKUP_DIR" -mindepth 2 -maxdepth 2 -name complete -printf '%T@ %h\n' 2>/dev/null | sort -n | tail -1)
else
    LAST=""
fi
if [[ -n "$LAST" ]]; then
    AGE_D=$(( ( $(date +%s) - ${LAST%%.*} ) / 86400 ))
    LAST_DIR=${LAST#* }
    if [[ "$AGE_D" -gt 14 ]]; then
        warn "Ostatni backup ma $AGE_D dni ($LAST_DIR) - zrób nowy: bash backup.sh"
    else
        pass "Backup z plikiem complete: $LAST_DIR ($AGE_D dni)"
    fi
    BPERM=$(stat -c '%a' "$LAST_DIR" 2>/dev/null || echo "?")
    if [[ "$BPERM" == "700" ]]; then
        pass "Katalog backupu ma prawa 700 (zawiera sekrety z .env)"
    else
        warn "Katalog backupu ma prawa $BPERM - zawiera sekrety, ustaw chmod 700"
    fi
elif [[ "$BEFORE" -eq 1 ]]; then
    info "Brak backupu w $BACKUP_DIR - pierwszy robi wizard w Fazie 8"
else
    fail "Brak backupu z plikiem complete w $BACKUP_DIR - bash backup.sh (wizard, Faza 8)"
fi

LATEST=$(git ls-remote --tags --refs https://github.com/n8n-io/nod.git 'nod-v*' 2>/dev/null \
    | awk '{sub("refs/tags/","",$2); print $2}' | grep -E '^nod-v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
[[ -n "$LATEST" ]] && info "Najnowszy tag Noda na GitHubie: $LATEST"
[[ -n "$TESTED_TAG" ]] && info "Ostatni tag przetestowany w tym poradniku: $TESTED_TAG"
[[ -z "$TESTED_TAG" ]] && warn "Brak versions.env obok check.sh - nie porównuję z przetestowanym tagiem"
if [[ -n "$INSTALLED_TAG" ]]; then
    if [[ -n "$TESTED_TAG" && "$INSTALLED_TAG" != "$TESTED_TAG" ]]; then
        warn "Zainstalowany $INSTALLED_TAG różni się od przetestowanego $TESTED_TAG - działa na Twoje ryzyko, zajrzyj do CHANGELOG.md"
    fi
    if [[ -n "$LATEST" && "$INSTALLED_TAG" != "$LATEST" ]]; then
        warn "Jest nowsza wersja: $LATEST (u Ciebie $INSTALLED_TAG) - aktualizacja ręcznie z backupem, INSTRUKCJA.md"
    fi
    if [[ "$INSTALLED_TAG" == "${TESTED_TAG:-x}" && "$INSTALLED_TAG" == "${LATEST:-x}" ]]; then
        pass "Wersja $INSTALLED_TAG = przetestowana = najnowsza"
    fi
fi

# --- Podsumowanie ---
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║              PODSUMOWANIE                ║"
echo "╠══════════════════════════════════════════╣"
echo -e "║  ${GREEN}PASS: $PASS${NC}  ${RED}FAIL: $FAIL${NC}  ${YELLOW}WARN: $WARN${NC}          ║"
echo "╚══════════════════════════════════════════╝"

if [[ "$BEFORE" -eq 1 && $FAIL -eq 0 ]]; then
    echo -e "\n${GREEN}Serwer gotowy pod Noda${NC} - brakuje tylko samego Noda, robią to Fazy 2-5.\n"
elif [[ $FAIL -eq 0 ]]; then
    echo -e "\n${GREEN}Wygląda dobrze!${NC} Że port 4310 nie odpowiada z internetu, potwierdź z komputera: curl -m 5 http://${PUB_IP:-IP}:4310/\n"
elif [[ $FAIL -le 2 ]]; then
    echo -e "\n${YELLOW}Kilka rzeczy do poprawienia - sprawdź punkty na czerwono.${NC}\n"
else
    echo -e "\n${RED}Serwer jeszcze nie jest gotowy - zacznij od punktów na czerwono.${NC}\n"
fi
