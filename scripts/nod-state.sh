#!/bin/bash
# =============================================================================
# Stan Noda prosto z bazy - BEZ SEKRETÓW
# =============================================================================
# Komunikat na ekranie Noda nie zawsze zgadza się ze stanem serwera, a serwer
# prawie nic nie loguje. Ten skrypt czyta stan u źródła (Postgres w kontenerze):
#   - czy onboarding jest zapisany na serwerze,
#   - czy udostępnianie danych użycia jest wyłączone,
#   - jakie połączenia modeli istnieją (dostawca / metoda / status),
#   - który model jest wybrany,
#   - ile tur rozmów zakończyło się, a ile nie.
# Nie czyta kluczy, tokenów ani treści rozmów. NICZEGO NIE ZMIENIA.
#
# Uruchom na serwerze:   bash nod-state.sh
# Z porównaniem modelu:  bash nod-state.sh --model chatgpt   (albo --model apikey)
# Inny katalog Noda:     bash nod-state.sh --nod-dir /sciezka/nod
#
# docker exec idzie BEZ -i i z </dev/null - inaczej, uruchomiony przez ssh,
# zjada resztę skryptu ze standardowego wejścia.
# =============================================================================

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}[OK]${NC}    $1"; }
bad()  { echo -e "  ${RED}[UWAGA]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC}  $1"; }
info() { echo -e "  ${BLUE}[INFO]${NC}  $1"; }
header() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

NOD_DIR="$HOME/nod"
EXPECT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --nod-dir) NOD_DIR="${2:-$NOD_DIR}"; shift ;;
        --model) EXPECT="${2:-}"; shift ;;
        -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    esac
    shift
done
SELF_HOST="$NOD_DIR/deployment/self-host"

if docker info >/dev/null 2>&1; then
    DOCKER="docker"
elif sudo -n docker info >/dev/null 2>&1; then
    DOCKER="sudo docker"
else
    bad "Brak dostępu do Dockera dla $(id -un)"; exit 1
fi

if [[ ! -f "$SELF_HOST/.env" ]]; then
    bad "Brak $SELF_HOST/.env - Nod nie jest zainstalowany w $NOD_DIR"; exit 1
fi

PG=$(cd "$SELF_HOST" && $DOCKER compose --file compose.yaml --env-file .env ps -q postgres 2>/dev/null | head -1)
if [[ -z "$PG" ]]; then
    bad "Kontener postgres nie działa (docker compose ps w $SELF_HOST)"; exit 1
fi

q() { $DOCKER exec "$PG" psql -U nod -d nod -At -F ' | ' -c "$1" </dev/null 2>/dev/null; }

echo ""
echo "Stan Noda z bazy - $(date +%Y-%m-%d\ %H:%M) - tag: $(git -C "$NOD_DIR" describe --tags --exact-match 2>/dev/null || echo '?')"

header "Konto"
ACC=$(q "select onboarding_completed, usage_data from account_settings limit 1")
if [[ -z "$ACC" ]]; then
    warn "Brak danych w account_settings (onboarding jeszcze nie zaczęty albo schemat bazy się zmienił)"
else
    ONB=$(echo "$ACC" | awk -F' [|] ' '{print $1}')
    USG=$(echo "$ACC" | awk -F' [|] ' '{print $2}')
    echo "STATE_ONBOARDING_COMPLETED=$ONB"
    echo "STATE_USAGE_DATA=$USG"
    if [[ "$ONB" == "t" ]]; then ok "Onboarding zapisany na serwerze"; else warn "Onboarding nieukończony - dokończ go w przeglądarce"; fi
    if [[ "$USG" == "f" ]]; then ok "Dane użycia: wyłączone"; else bad "Dane użycia: WŁĄCZONE - Settings -> Privacy & data -> Share usage data"; fi
fi

header "Połączenia modeli (dostawca | metoda | status)"
CONN=$(q "select provider, method, status from model_connections order by created_at")
if [[ -z "$CONN" ]]; then
    warn "Brak połączeń - Settings -> Models -> Add connection"
else
    printf '%s\n' "$CONN" | while IFS= read -r l; do echo "          $l"; done
    if echo "$CONN" | grep -q ' | connected$'; then
        ok "Co najmniej jedno połączenie ma status connected"
    else
        bad "Żadne połączenie nie jest connected"
    fi
fi

header "Wybrany model i połączenie, przez które idzie"
# Schemat (kod Noda, tag nod-v0.8.0, src/shared/models.ts + src/server/model-store.ts):
#   model_settings.selection = {"connectionId": "<uuid>", "modelId": "...", "effort": "..."}
#   model_settings.routes    = {"schedule"|"background": <selection> | "light" | null}
#   model_connections(id uuid, provider, method in api_key|subscription|oauth, status, ...)
# Dlatego metodę płatności czytamy z DOKŁADNIE tego połączenia, które wskazuje selection,
# a nie z nazwy modelu (gpt-* może iść i z subskrypcji, i z klucza API).
qs() { $DOCKER exec "$PG" psql -U nod -d nod -At -F '|' -c "$1" </dev/null 2>/dev/null; }
SEL_ERR=0
SEL=$(qs "select coalesce(s.selection->>'modelId',''), coalesce(s.selection->>'connectionId',''),
             coalesce(c.provider,''), coalesce(c.method,''), coalesce(c.status,'')
          from model_settings s
          left join model_connections c on c.id::text = s.selection->>'connectionId'
          limit 1") || SEL_ERR=1
IFS='|' read -r MODEL CONN_ID SEL_PROVIDER SEL_METHOD SEL_STATUS <<<"$SEL"
echo "STATE_SELECTED_MODEL=${MODEL:-brak}"
echo "STATE_SELECTED_CONNECTION=${SEL_PROVIDER:-?}/${SEL_METHOD:-?}/${SEL_STATUS:-?}"
if [[ "$SEL_ERR" -eq 1 ]]; then
    bad "Zapytanie o wybrany model się nie powiodło (zmieniony schemat bazy? wersja nowsza niż przetestowana?)"
elif [[ -z "$MODEL" ]]; then
    warn "Brak wybranego modelu - Settings -> Models"
elif [[ -z "$CONN_ID" ]]; then
    warn "Wybrany model $MODEL bez connectionId w selection - nie da się ustalić, kto płaci (inny schemat niż w nod-v0.8.0)"
elif [[ -z "$SEL_METHOD" ]]; then
    bad "Wybrany model $MODEL wskazuje połączenie, którego nie ma w model_connections (usunięte?) - wybierz model ponownie"
else
    info "Rozmowy: $MODEL przez połączenie $SEL_PROVIDER / $SEL_METHOD / $SEL_STATUS"
    [[ "$SEL_STATUS" == "connected" ]] || bad "Połączenie wybranego modelu ma status $SEL_STATUS, nie connected"
fi

ROUTES_ERR=0
ROUTES=$(qs "select r.key,
                case when jsonb_typeof(r.value)='object' then r.value->>'modelId' else coalesce(r.value#>>'{}','domyślny') end,
                coalesce(c.provider,''), coalesce(c.method,'')
             from model_settings s cross join lateral jsonb_each(s.routes) r
             left join model_connections c on jsonb_typeof(r.value)='object' and c.id::text = r.value->>'connectionId'
             order by 1") || ROUTES_ERR=1
if [[ "$ROUTES_ERR" -eq 1 ]]; then
    warn "Nie odczytałem modeli do harmonogramów i pracy w tle (routes) - sprawdź w Settings -> Models"
elif [[ -z "$ROUTES" ]]; then
    info "Harmonogramy i praca w tle: ustawienia domyślne (brak osobnych tras w routes)"
else
    while IFS='|' read -r LANE RMODEL RPROV RMETH; do
        info "Trasa $LANE: $RMODEL${RMETH:+ przez $RPROV / $RMETH}"
    done <<<"$ROUTES"
fi

# Porównanie z decyzją z Fazy 0 - tylko na podstawie metody połączenia, nie nazwy modelu.
# Claude i Gemini działają w Nodzie tylko z klucza API.
case "$EXPECT" in
    chatgpt)
        if [[ "$SEL_ERR" -eq 1 || -z "$CONN_ID" || -z "$SEL_METHOD" ]]; then
            warn "Nie mogę potwierdzić, że rozmowy idą z subskrypcji ChatGPT (patrz wyżej) - to NIE jest zaliczenie"
        elif [[ "$SEL_PROVIDER" == "openai" && "$SEL_METHOD" == "subscription" && "$SEL_STATUS" == "connected" ]]; then
            ok "Rozmowy idą z subskrypcji ChatGPT (openai / subscription / connected)"
        else
            bad "Deklarujesz ChatGPT, a wybrany model $MODEL idzie przez $SEL_PROVIDER / $SEL_METHOD - płacisz z tego połączenia. Przełącz model w Settings -> Models"
        fi
        if [[ -n "$ROUTES" ]] && printf '%s\n' "$ROUTES" | awk -F'|' '$4=="api_key"' | grep -q .; then
            warn "Część pracy w tle / harmonogramów idzie przez klucz API - jeśli to niezamierzone, zmień w Settings -> Models"
        fi
        ;;
    apikey)
        if [[ "$SEL_ERR" -eq 1 || -z "$CONN_ID" || -z "$SEL_METHOD" ]]; then
            warn "Nie mogę potwierdzić, z którego połączenia idą rozmowy (patrz wyżej) - to NIE jest zaliczenie"
        elif [[ "$SEL_METHOD" == "api_key" && "$SEL_STATUS" == "connected" ]]; then
            ok "Rozmowy idą z klucza API ($SEL_PROVIDER / api_key / connected)"
        else
            bad "Deklarujesz klucz API, a wybrany model $MODEL idzie przez $SEL_PROVIDER / $SEL_METHOD / $SEL_STATUS"
        fi
        info "Klucz API = płacisz za każdą turę. Domyślnie zadanie pyta o zgodę po przekroczeniu ok. 5 USD"
        ;;
    "") ;;
    *) warn "Nieznana wartość --model '$EXPECT' (chatgpt albo apikey)" ;;
esac

header "Tury rozmów (status | liczba)"
TURNS=$(q "select status, count(*) from turns group by 1 order by 1")
if [[ -z "$TURNS" ]]; then
    info "Brak tur - jeszcze nie rozmawiałeś z Nodem"
else
    printf '%s\n' "$TURNS" | while IFS= read -r l; do echo "          $l"; done
    echo "$TURNS" | grep -Eqi '^(failed|error)' && warn "Są nieudane tury - zajrzyj do rozmowy w przeglądarce"
fi
echo ""
