#!/bin/bash
# =============================================================================
# Backup Noda - opakowanie na oficjalny deployment/self-host/backup.sh
# =============================================================================
# Pilnuje tego, o co łatwo się potknąć:
#   - ścieżka docelowa musi być BEZWZGLĘDNA i katalog NIE może istnieć,
#   - na czas kopii Nod zatrzymuje serwer, przeglądarkę i workspace
#     (zwykle kilkanaście sekund), potem sam je uruchamia,
#   - kopia zawiera .env z NOD_AUTH_TOKEN i NOD_VAULT_KEY, więc dostaje chmod 700.
#     Sama baza bez NOD_VAULT_KEY nie odtworzy zapisanych dostępów.
#
# Uruchom na serwerze:
#   bash backup.sh                              # -> ~/backups/nod/RRRR-MM-DD_GGMM
#   bash backup.sh /home/<user>/backups/nod/przed-aktualizacja
# Inny katalog Noda:  NOD_DIR=/sciezka/nod bash backup.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

die()  { echo -e "${RED}[FAIL]${NC}  $1" >&2; exit 1; }
ok()   { echo -e "${GREEN}[PASS]${NC}  $1"; }
note() { echo -e "${YELLOW}[UWAGA]${NC} $1"; }

NOD_DIR="${NOD_DIR:-$HOME/nod}"
SELF_HOST="$NOD_DIR/deployment/self-host"
DEST="${1:-$HOME/backups/nod/$(date +%Y-%m-%d_%H%M)}"

case "$DEST" in
    /*) ;;
    *) die "Ścieżka musi być bezwzględna (zaczynać się od /), dostałem: $DEST" ;;
esac
[[ -e "$DEST" ]] && die "$DEST już istnieje - backup.sh Noda wymaga nowego, nieistniejącego katalogu"
[[ -f "$SELF_HOST/backup.sh" ]] || die "Nie ma $SELF_HOST/backup.sh - czy Nod jest w $NOD_DIR?"
[[ -f "$SELF_HOST/.env" ]] || die "Nie ma $SELF_HOST/.env - nie ma czego kopiować"

PARENT=$(dirname "$DEST")
mkdir -p "$PARENT"
chmod 700 "$PARENT"

note "Na czas kopii (zwykle kilkanaście sekund) serwer, przeglądarka i workspace Noda stoją."
note "Trwające zadanie może się przerwać - nie rób backupu w środku długiej pracy Noda."
START=$(date +%s)
(cd "$SELF_HOST" && sh backup.sh "$DEST")
END=$(date +%s)

[[ -d "$DEST" ]] || die "backup.sh Noda nie utworzył $DEST"
chmod -R go-rwx "$DEST"
chmod 700 "$DEST"

if [[ -f "$DEST/complete" ]]; then
    ok "Kopia gotowa w $(( END - START )) s: $DEST (plik complete jest)"
else
    die "W $DEST brak pliku complete - kopia niepełna, nie licz na nią"
fi
echo "      Rozmiar: $(du -sh "$DEST" | cut -f1)"
echo "      Pliki:   $(find "$DEST" -maxdepth 1 -mindepth 1 -printf '%f ' 2>/dev/null)"

if docker info >/dev/null 2>&1; then
    STATE=$(cd "$SELF_HOST" && docker compose --file compose.yaml --env-file .env ps --format '{{.Service}}|{{.State}}' 2>/dev/null | awk -F'|' '$1=="server"{print $2}')
    if [[ "$STATE" == "running" ]]; then
        ok "Serwer Noda znowu działa"
    else
        note "Serwer Noda ma stan '${STATE:-brak}' - sprawdź: docker compose --file compose.yaml --env-file .env ps"
    fi
fi

echo ""
note "Ta kopia zawiera sekrety (.env: NOD_AUTH_TOKEN, NOD_VAULT_KEY). Trzymaj ją poza"
note "repozytorium, poza czatem z AI i poza folderami synchronizowanymi do chmury bez szyfrowania."
note "Kopia tylko na tym serwerze nie chroni przed utratą serwera - przenieś ją też gdzie indziej."
