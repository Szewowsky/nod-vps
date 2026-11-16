# /nod-setup - Wizard: Nod (agent AI od n8n) na Twoim VPS, dostęp tylko przez Tailscale

Cel: po tym wizardzie na serwerze użytkownika działa Nod - open-source'owy agent AI od n8n Labs
z własnym "komputerem" (kontenery Docker z Linuksem i przeglądarką Chromium). Nod jest widoczny
**wyłącznie z urządzeń w tailnecie** pod adresem `https://<serwer>.<tailnet>.ts.net:4310`
z prawdziwym certyfikatem, bez domeny i bez otwierania portów. Model jest podłączony (ChatGPT
Plus/Pro albo klucz API), onboarding zapisany na serwerze, jest backup i audyt PO.

Użytkownik podaje dane serwera i odpowiada na pytania z Fazy 0 - Claude prowadzi. Logowania
(onboarding, ChatGPT, klucz API w interfejsie Noda) użytkownik robi sam w przeglądarce.

Wywołanie: `/nod-setup` (ostatni przetestowany tag z `scripts/versions.env`) albo
`/nod-setup --latest` (najnowszy tag z GitHuba - nieprzetestowany w tym poradniku).
Argumenty: $ARGUMENTS

## ZŁOTA ZASADA (powtarzaj ją użytkownikowi)

**Najpierw onboarding w przeglądarce, dopiero potem aplikacja na komputer.**
Aplikacja desktopowa połączona ze zdalnym serwerem psuje ostatni ekran onboardingu ("Setup needs
another try. These settings are not supported."), mimo że serwer zapisał wszystko poprawnie. Ten
błąd jest w kodzie aplikacji (stan na `nod-v0.8.0`), wizard go nie naprawi - omija go kolejnością.

## KROK ZERO - łańcuch poradników

```
vps-security  ->  tailscale-vps  ->  nod-vps
(hardening)       (SSH za tailnetem)  (Nod + dostęp przez Tailscale Serve)
```

Ten wizard **NIE robi hardeningu** i **NIE instaluje Tailscale**. Zakłada stan po:

- https://szewowsky.github.io/vps-security/ - użytkownik nie-root z sudo, logowanie kluczem, firewall,
- https://szewowsky.github.io/tailscale-vps/ - serwer i komputer użytkownika w tym samym tailnecie.

Brak Tailscale na serwerze → **STOP**, wyślij użytkownika do `tailscale-vps`. W tym poradniku
nie ma innej drogi wejścia do Noda.

## ZAKRES (MVP) - powiedz to użytkownikowi w Fazie 0

- Serwer: VPS z Linuksem AMD64 albo ARM64. Mac mini i inne komputery domowe - poza zakresem
  (dokumentacja Noda: https://github.com/n8n-io/nod, sekcja self-host).
- Dostęp: **tylko Tailscale Serve**. Własna domena z reverse proxy (Traefik, Caddy, nginx) i tunel
  SSH - jeszcze nie obsługiwane przez ten poradnik.
- Model: subskrypcja ChatGPT (Plus albo Pro) albo klucz API. Claude i Gemini działają w Nodzie
  **tylko z kluczem API** - subskrypcje Claude/Gemini nie działają.

## BASH-GUARD WORKAROUND

Komendy SSH mogą być blokowane przez bash-guard hook na komputerze użytkownika (blokuje `sudo`,
`chmod` oraz `curl | sh` nawet w komendzie zdalnej). Każdy krok z `sudo` - **pisz skrypt .sh lokalnie
heredokiem, kopiuj przez SCP, wykonaj zdalnie**:

```bash
# 1. Zapisz komendy do pliku lokalnie (heredoc cat > /tmp/fX.sh <<'EOS' ... EOS)
# 2. Skopiuj na serwer:
scp -P PORT /tmp/fX.sh USER@HOST:/tmp/fX.sh
# 3. Wykonaj zdalnie:
ssh -p PORT USER@HOST "bash /tmp/fX.sh; rm -f /tmp/fX.sh"
```

`sudo` wewnątrz **heredoca** zapisywanego do pliku przechodzi. W komendzie inline, w `printf`
i w `ssh USER@HOST "sudo ..."` jest **blokowane**. Kroki z `sudo` w tym wizardzie: F1c (plan B),
F5a. Kroki bez `sudo` też idą heredokiem, gdy mają więcej niż jedną linię - łatwiej je czytać.

**Tailscale SSH może zatrzymać komendę.** Jeśli użytkownik wchodzi na serwer przez Tailscale SSH,
`ssh` potrafi wypisać `Tailscale SSH requires an additional check` z linkiem i czekać. To nie błąd:
podaj link użytkownikowi, on potwierdza w przeglądarce, komenda rusza dalej. Nie zakładaj, że
komendy zdalne zawsze są nieinteraktywne.

## ZASADY (NIGDY NIE ŁAMAĆ)

1. **Nie dotykaj konfiguracji SSH ani firewalla.** Żadnego `sshd_config`, `ufw allow`, reguł w panelu
   dostawcy. Nod słucha na `127.0.0.1:4310`, a na zewnątrz wystawia go tylko Tailscale Serve - żaden
   publiczny port nie jest potrzebny.
2. **Nigdy `tailscale funnel`.** `serve` = Twoja sieć, `funnel` = cały internet. Nod z jednym tokenem
   bez 2FA nie może stać w internecie.
3. **Sekrety nie przechodzą przez czat.** Nigdy nie wypisuj zawartości `.env` ani `NOD_AUTH_TOKEN`,
   `NOD_VAULT_KEY`, `NOD_POSTGRES_PASSWORD`. Do sprawdzania używaj długości wartości (`wc -c`)
   i `grep` na nazwach kluczy. Token trafia do **schowka** użytkownika (Faza 5c), nie do czatu.
   Klucz API modelu użytkownik wkleja sam w interfejsie Noda.
4. **Sekrety generuje `setup.sh` Noda.** Nie wymyślaj ich, nie podmieniaj. Jeśli `.env` już istnieje -
   **nie uruchamiaj `setup.sh` ponownie**: nowy `NOD_VAULT_KEY` = utrata zapisanych dostępów.
5. **Nie ustawiaj innego `NOD_PUBLIC_URL` niż adres tailnetu.** Nod wpuszcza tylko żądania z nagłówkiem
   Host równym temu adresowi. Jeden sposób wejścia naraz.
6. **Nie podłączaj aplikacji desktopowej przed ukończonym onboardingiem w przeglądarce** (złota zasada).
7. **ZAWSZE czekaj na wynik komendy** przed następną. Nie łącz faz. Nie zgaduj, że coś się udało.
8. **Jeśli test fazy nie przechodzi - STOP.** Pokaż output, zapytaj użytkownika. Nie naprawiaj na ślepo,
   nie przebudowuj wszystkiego "na wszelki wypadek".
9. **Stan sprawdzaj w bazie, nie na ekranie** (`scripts/nod-state.sh`). Komunikat Noda bywa inny niż
   to, co serwer faktycznie zapisał, a logi serwera są prawie puste.
10. **Nie mów użytkownikowi, że Nod jest bezpieczny.** To research preview: jeden token daje pełny
    dostęp do agenta i podpiętych kont, kontener `runtime` ma dostęp do socketu Dockera. Mów, co
    zrobiłeś, i jakie ryzyka zostają.

## Nazewnictwo w komendach

`HOST` (adres, pod którym użytkownik wchodzi na SSH - po `tailscale-vps` to adres `100.x.y.z` albo
nazwa z tailnetu), `PORT` (port SSH), `USER` (użytkownik SSH), `PUB_IP` (publiczny IPv4 serwera, tylko
do testu negatywnego), `TAG` (wersja Noda), `NOD_URL` (`https://<serwer>.<tailnet>.ts.net:4310`) to
placeholdery. **ZAWSZE podstawiaj faktyczne wartości** z Fazy 0 i Fazy 3.

Na serwerze:
- kod Noda: `~/nod`, katalog z compose: `~/nod/deployment/self-host`, sekrety: `.env` w tym katalogu,
- skrypty z tego repo: `~/nod-vps/` (wizard kopiuje je w Fazie 1; zostają do codziennej obsługi),
- backupy: `~/backups/nod/<nowy-katalog>`,
- projekt compose: `nod` (kontenery `nod-server-1`, `nod-postgres-1` itd.).

Wszystkie komendy compose z katalogu `~/nod/deployment/self-host` i zawsze z
`--file compose.yaml --env-file .env`.

---

## Faza 0 - Dane i decyzje

Najpierw wczytaj wersje (z katalogu sklonowanego repo `nod-vps`):

```bash
. ./scripts/versions.env && echo "PRZETESTOWANY=$NOD_TESTED_TAG ($NOD_TESTED_DATE)"
git ls-remote --tags --refs "$NOD_REPO" 'nod-v*' | awk '{sub("refs/tags/","",$2); print $2}' \
  | grep -E '^nod-v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1
```

Oczekiwany wynik: `PRZETESTOWANY=nod-v0.8.0 (2026-11-16)` i najnowszy tag z GitHuba. Filtr
`grep -E` celowo pomija tagi przedpremierowe (np. `-beta`).

Zapytaj użytkownika (AskUserQuestion) o:

1. **Adres SSH serwera** (`HOST`) - po `tailscale-vps` publiczne SSH jest zamknięte, więc to adres
   `100.x.y.z` albo nazwa z tailnetu.
2. **Użytkownik SSH** (`USER`) - nie-root z `vps-security`. Root tylko na testowej maszynie.
3. **Port SSH** (`PORT`) - 22 albo własny.
4. **Publiczny IPv4 serwera** (`PUB_IP`) - tylko do testu, że port 4310 NIE odpowiada z internetu.
   Nie wie? `check.sh` w Fazie 1 go wypisze.
5. **Łańcuch:** "Przeszedłeś `vps-security`? A `tailscale-vps`?" Brak `tailscale-vps` → STOP (nie ma
   drogi wejścia). Brak `vps-security` na produkcji → STOP i odeślij; na testowej maszynie użytkownik
   decyduje świadomie, zapisz to.
6. **Model:**
   - A. **ChatGPT Plus albo Pro** (subskrypcja) - w Fazie 6 poprowadzisz przez wklejenie adresu
     callbacku. Bez osobnych opłat za tokeny, ale zadanie i tak pyta o zgodę po ok. 5 USD liczonych
     po cenach API.
   - B. **Klucz API** (Anthropic, OpenAI, inny) - płatne za każdą turę. Orientacyjnie: jedna krótka
     odpowiedź mocnego modelu z wysokim wysiłkiem to kilka-kilkanaście centów.
   Claude i Gemini - tylko B.
7. **Aplikacja desktopowa** (Mac/Windows/Linux) - tak/nie. Jeśli tak, robisz ją w Fazie 7, nigdy wcześniej.
8. **Prywatność:** udostępnianie danych użycia i śladów rozmów - zalecane wyłączone; e-mail w onboardingu
   - zalecane puste (trafia do zewnętrznej usługi mailingowej). Czy ukryć przycisk "Send feedback"
   (`NOD_FEEDBACK_ENABLED=false`)? Zalecane: tak.
9. **Backup:** katalog bazowy na serwerze (domyślnie `~/backups/nod`) i czy użytkownik chce potem
   skopiować kopię poza serwer.
10. **Wersja:** domyślnie `NOD_TESTED_TAG`. Jeśli wywołano `--latest` albo użytkownik chce najnowszy
    tag - powiedz wprost: "Ta wersja nie była testowana w tym poradniku, Nod wychodzi czasem kilka razy
    dziennie; jeśli coś się nie zgadza z opisem faz, wróć do przetestowanego tagu." Zapisz `TAG`.

**Test zaliczenia:** wszystkie 10 odpowiedzi zebrane, nic nie zgadywane, `TAG` zapisany w czacie.

**FAIL - co zrobić:** użytkownik chce domenę albo tunel SSH → powiedz jednym zdaniem, że ten poradnik
tego jeszcze nie obsługuje, i zaproponuj Tailscale (wymaga `tailscale-vps`). Chce postawić Noda na
Macu → poza zakresem, odeślij do dokumentacji Noda.

---

## Faza 1 - Połączenie, skrypty na serwer, audyt PRZED

### 1a. Połączenie i komputer użytkownika

```bash
cat > /tmp/f1a.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
echo SSH_OK
whoami
sudo -n true && echo SUDO_OK
mkdir -p ~/nod-vps && echo DIR_OK
EOS
scp -P PORT /tmp/f1a.sh USER@HOST:/tmp/f1a.sh
ssh -p PORT -o ConnectTimeout=10 USER@HOST "bash /tmp/f1a.sh; rm -f /tmp/f1a.sh"
```

Oczekiwany wynik: `SSH_OK`, nazwa użytkownika, `SUDO_OK`, `DIR_OK`.

Na komputerze użytkownika (to on otworzy Noda w przeglądarce, więc musi być w tailnecie):

```bash
if command -v tailscale >/dev/null 2>&1; then TS=tailscale
elif [ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]; then TS=/Applications/Tailscale.app/Contents/MacOS/Tailscale
else TS=""; echo "BRAK_TAILSCALE_CLI"; fi
[ -n "$TS" ] && "$TS" status | head -5
```

Oczekiwany wynik: lista z tym komputerem i z serwerem (adresy `100.x.y.z`).

**FAIL - co zrobić:**
- brak `SUDO_OK` → sudo pyta o hasło. Komendy z `sudo` (F1c, F5a) użytkownik wykona sam w swoim terminalu.
- `BRAK_TAILSCALE_CLI` → na komputerze nie ma Tailscale (Mac: App Store, reszta: tailscale.com/download).
  Bez niego Nod nie będzie widoczny w przeglądarce - STOP, wróć do `tailscale-vps`.
- serwera nie ma w `tailscale status` na komputerze → inne konto Tailscale albo aplikacja wyłączona.
  Bez tego Nod nie będzie widoczny w przeglądarce - STOP, wróć do `tailscale-vps`.
- `Tailscale SSH requires an additional check` → link dla użytkownika (patrz BASH-GUARD WORKAROUND).

### 1b. Skrypty na serwer i audyt PRZED

Uruchamiaj z katalogu sklonowanego repo `nod-vps`. Ścieżki jawnie z `./`:

```bash
scp -P PORT ./scripts/check.sh ./scripts/nod-state.sh ./scripts/backup.sh ./scripts/versions.env USER@HOST:~/nod-vps/
ssh -p PORT USER@HOST "bash ~/nod-vps/check.sh --before 2>&1 | tee ~/nod-vps/check-before.txt"
```

Flaga `--before`: brak Noda raportuje jako WARN, nie FAIL. Skrypt rozpoznaje to też sam (brak `.env`).

Sprawdzasz w wyniku:

| Punkt | Wymagane |
|---|---|
| Architektura | AMD64 albo ARM64 - inaczej STOP |
| CPU | >= 2 rdzenie (build ok. 7 min na 4 vCPU, na 2 dłużej) |
| RAM | >= 8 GB PASS; 6-8 GB WARN (działa, ale ciasno); < 6 GB FAIL |
| Dysk | < 15 GB FAIL; < 50 GB WARN (dokumentacja zaleca 50 GB); obrazy ok. 5 GB |
| Docker Engine | 25+ |
| Compose | v2 lub nowszy (`docker compose`, nie `docker-compose`) |
| Buildx | obecny |
| git, openssl, curl, sha256sum | obecne |
| Tailscale | zainstalowany, zalogowany |
| HTTPS Certificates | włączone (WARN = klik użytkownika w konsoli Tailscale, przed Fazą 5) |
| Port 4310 | wolny |
| Inne kontenery | informacyjnie; WARN przy <= 16 GB RAM i innych usługach (np. Rakazo, n8n) |

Zapisz w czacie `PUB_IP` z linii "Publiczny IPv4 serwera", jeśli użytkownik go nie znał.

**Test zaliczenia:** zero FAIL w sekcjach 1-4.

**To jest normalne w audycie PRZED:** sekcje 5-8 (instalacja, dostęp, stan, backup) to WARN albo INFO.
Robią to Fazy 2-8.

**FAIL - co zrobić:**
- RAM < 6 GB → STOP. Powiedz wprost: limity kontenerów Noda to razem ok. 7 GB plus Postgres;
  potrzebny większy plan VPS.
- Docker brak, za stary, brak Compose v2 albo Buildx → **1c**.
- Docker działa tylko przez sudo → **1c** (sama grupa `docker`).
- Brak git/openssl/curl → 1c doinstaluje je razem z Dockerem.
- Tailscale niezalogowany / brak → STOP, `tailscale-vps`.
- Port 4310 zajęty → `ss -tlnp | grep 4310` (przez heredoc z sudo, żeby widzieć proces). Poprzedni Nod?
  Zapytaj użytkownika. Nie ubijaj cudzych usług.

### 1c. Plan B: Docker z oficjalnego repozytorium (tylko gdy 1b to pokazał)

Zapytaj użytkownika o zgodę - to instalacja pakietów systemowych. Docker z repozytorium Ubuntu bywa
stary i bez Buildx. Skrypt nic nie robi, jeśli wszystko już jest:

```bash
cat > /tmp/f1c.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
NEED=0
docker compose version >/dev/null 2>&1 || NEED=1
docker buildx version >/dev/null 2>&1 || NEED=1
if [ "$NEED" -eq 1 ]; then
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ca-certificates curl gnupg git openssl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl enable --now docker
  echo "DOCKER_INSTALLED"
else
  echo "DOCKER_ALREADY_OK"
fi
if ! id -nG "$(id -un)" | grep -qw docker; then
  sudo usermod -aG docker "$(id -un)"
  echo "ADDED_TO_DOCKER_GROUP"
fi
EOS
scp -P PORT /tmp/f1c.sh USER@HOST:/tmp/f1c.sh
ssh -p PORT USER@HOST "bash /tmp/f1c.sh; rm -f /tmp/f1c.sh"
```

Skrypt jest pod Ubuntu (repozytorium `download.docker.com/linux/ubuntu`). Inna dystrybucja → pokaż
użytkownikowi https://docs.docker.com/engine/install/ i nie zgaduj.

`ADDED_TO_DOCKER_GROUP` → grupa działa dopiero w **nowej** sesji SSH. Każde kolejne `ssh` to nowa
sesja, więc po prostu powtórz 1b.

**Test zaliczenia:** ponowne `check.sh --before` bez FAIL w sekcjach 1-4.

---

## Faza 2 - Kod Noda w wybranej wersji

Nie ma publicznego gotowego obrazu serwera Noda (wydania na GitHubie to aplikacje desktopowe),
więc budujemy ze źródeł. Klon płytki (`--depth 1`) z jednym tagiem:

```bash
cat > /tmp/f2.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
TAG="nod-vX.Y.Z"   # podstaw TAG z Fazy 0, np. nod-v0.8.0
if [ -e "$HOME/nod" ]; then
  echo "NOD_DIR_EXISTS"
  git -C "$HOME/nod" describe --tags --exact-match 2>/dev/null || echo "(nie stoi na tagu)"
  exit 0
fi
git clone --quiet --branch "$TAG" --depth 1 https://github.com/n8n-io/nod.git "$HOME/nod"
echo "CLONE_OK"
git -C "$HOME/nod" describe --tags --exact-match
git -C "$HOME/nod" rev-parse --short HEAD
EOS
scp -P PORT /tmp/f2.sh USER@HOST:/tmp/f2.sh
ssh -p PORT USER@HOST "bash /tmp/f2.sh; rm -f /tmp/f2.sh"
```

Oczekiwany wynik: `CLONE_OK`, wybrany tag i krótki hash commita.

**Test zaliczenia:** `git describe --tags --exact-match` = `TAG`.

**FAIL - co zrobić:**
- `NOD_DIR_EXISTS` → na serwerze już jest Nod. **Nie kasuj go.** Zapytaj użytkownika: to stara
  instalacja do aktualizacji (INSTRUKCJA.md, "Aktualizacja") czy porzucony katalog? Decyzja należy
  do niego.
- `Remote branch ... not found` → literówka w tagu. Pokaż listę z Fazy 0.

---

## Faza 3 - Konfiguracja (`.env`)

Adres Noda budujemy z nazwy serwera w tailnecie - bez przepisywania ręcznie:

```bash
cat > /tmp/f3.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
cd ~/nod/deployment/self-host
if [ -f .env ]; then
  echo "ENV_EXISTS - nie uruchamiam setup.sh (zachowuję NOD_VAULT_KEY)"
else
  COMPOSE_PROJECT_NAME=nod sh setup.sh
  echo "SETUP_DONE"
fi
DNS=$(tailscale status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')
URL="https://$DNS:4310"
set_kv() {
  if grep -q "^$1=" .env; then sed -i "s#^$1=.*#$1=$2#" .env; else echo "$1=$2" >> .env; fi
}
set_kv NOD_PUBLIC_URL "$URL"
set_kv NOD_ANALYTICS_ENABLED false
# odkomentuj, jeśli użytkownik w Fazie 0 chciał ukryć przycisk "Send feedback":
# set_kv NOD_FEEDBACK_ENABLED false
chmod 600 .env
echo "--- kontrola (bez sekretów) ---"
stat -c 'ENV_PERM=%a ENV_OWNER=%U' .env
for k in NOD_AUTH_TOKEN NOD_VAULT_KEY NOD_POSTGRES_PASSWORD; do
  printf '%s_LEN=%s\n' "$k" "$(grep "^$k=" .env | tail -1 | cut -d= -f2- | tr -d '\n' | wc -c)"
done
grep -E '^(COMPOSE_PROJECT_NAME|PORT|NOD_BIND_ADDRESS|NOD_PUBLIC_URL|NOD_ANALYTICS_ENABLED|NOD_FEEDBACK_ENABLED)=' .env
EOS
scp -P PORT /tmp/f3.sh USER@HOST:/tmp/f3.sh
ssh -p PORT USER@HOST "bash /tmp/f3.sh; rm -f /tmp/f3.sh"
```

Oczekiwany wynik: `SETUP_DONE`, `ENV_PERM=600`, trzy długości sekretów większe od zera (wartości nie
są wypisywane), `COMPOSE_PROJECT_NAME=nod`, `NOD_BIND_ADDRESS=127.0.0.1`,
`NOD_PUBLIC_URL=https://<serwer>.<tailnet>.ts.net:4310`, `NOD_ANALYTICS_ENABLED=false`.

**Zapisz `NOD_URL`** (wartość `NOD_PUBLIC_URL`) - to adres, który użytkownik otworzy w przeglądarce.

Powiedz użytkownikowi jednym zdaniem: `.env` to trzy sekrety - token wejścia (kto go ma, ma pełny
dostęp do agenta), klucz sejfu (bez niego zapisane dostępy są nie do odczytania) i hasło bazy.

**Test zaliczenia:** prawa 600, trzy długości > 0, `NOD_PUBLIC_URL` to sam origin (bez ścieżki,
bez parametrów) zakończony `.ts.net:4310`.

**FAIL - co zrobić:**
- `setup.sh` kończy się błędem `openssl: not found` → wróć do 1c (doinstaluje openssl).
- `KeyError: 'DNSName'` albo pusta nazwa → Tailscale na serwerze niezalogowany. STOP, `tailscale-vps`.
- `COMPOSE_PROJECT_NAME` brak w wyniku → nowsza wersja `setup.sh` mogła zmienić format. Nie dopisuj
  w ciemno; pokaż użytkownikowi listę kluczy: `grep -oE '^[A-Z_]+=' .env`.

---

## Faza 4 - Build i start

Powiedz użytkownikowi **przed** startem: "To jest ten długi moment. Build ze źródeł trwa ok. 7 minut
na 4 vCPU (na 2 vCPU dłużej), trzy obrazy ważą razem ok. 5 GB. Nic nie klikaj, sprawdzam co minutę."

Build idzie w tle na serwerze, żeby zerwana sesja SSH albo limit czasu komendy agenta go nie przerwały:

```bash
cat > /tmp/f4.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
cd ~/nod/deployment/self-host
rm -f ~/nod-vps/build.log
nohup bash -c 'docker compose --file compose.yaml --env-file .env up -d --build --wait > ~/nod-vps/build.log 2>&1; echo "BUILD_EXIT=$?" >> ~/nod-vps/build.log' >/dev/null 2>&1 &
echo "BUILD_STARTED $(date +%T)"
EOS
scp -P PORT /tmp/f4.sh USER@HOST:/tmp/f4.sh
ssh -p PORT USER@HOST "bash /tmp/f4.sh; rm -f /tmp/f4.sh"
```

Sprawdzaj co ok. 60 s (max 25 minut):

```bash
ssh -p PORT USER@HOST "tail -3 ~/nod-vps/build.log; grep -h '^BUILD_EXIT=' ~/nod-vps/build.log || echo STILL_BUILDING"
```

Gdy pojawi się `BUILD_EXIT=0`, sprawdź kontenery:

```bash
ssh -p PORT USER@HOST "cd ~/nod/deployment/self-host && docker compose --file compose.yaml --env-file .env ps --format '{{.Service}} {{.State}} {{.Health}}'"
```

Oczekiwany wynik: 6 usług `running` - `server`, `postgres`, `runtime`, `browser`, `workspace`,
`workspace-network`; `server`, `browser`, `postgres` i `workspace-network` z `healthy`.

**Test zaliczenia:** `BUILD_EXIT=0`, 6 kontenerów działa, cztery wymienione `healthy`.

**FAIL - co zrobić:**
- `the --chmod option requires BuildKit` → brak Buildx. Wróć do 1c.
- `no space left on device` → za mało dysku. Pokaż `df -h`; `docker builder prune` zwalnia cache,
  ale to decyzja użytkownika (może dotyczyć innych projektów).
- `BUILD_EXIT` różny od 0 bez jasnej przyczyny → pokaż użytkownikowi ostatnie 40 linii
  (`tail -40 ~/nod-vps/build.log`). Nie restartuj w kółko.
- usługa `unhealthy` albo w pętli restartów → `docker logs --tail 50 nod-server-1` (albo nazwa z `ps`).
  Najczęściej brak pamięci - porównaj z RAM z Fazy 1.

---

## Faza 5 - Dostęp przez Tailscale Serve

### 5a. Wystawienie w tailnecie

`sudo` działa zawsze (bez `sudo` tylko, gdy użytkownik jest operatorem Tailscale), więc heredoc:

```bash
cat > /tmp/f5a.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
sudo tailscale serve --bg --https=4310 http://127.0.0.1:4310
echo "SERVE_SET"
sudo tailscale serve status
EOS
scp -P PORT /tmp/f5a.sh USER@HOST:/tmp/f5a.sh
ssh -p PORT USER@HOST "bash /tmp/f5a.sh; rm -f /tmp/f5a.sh"
```

Oczekiwany wynik: `SERVE_SET` i w statusie `https://<serwer>.<tailnet>.ts.net:4310 (tailnet only)`
z `|-- / proxy http://127.0.0.1:4310`.

**FAIL - co zrobić:** komenda wypisuje link do włączenia HTTPS → w tailnecie wyłączone są certyfikaty.
Klik użytkownika: konsola Tailscale → **DNS** → MagicDNS włączone i **HTTPS Certificates → Enable**.
Potem powtórz 5a. W statusie widać `Funnel on` → natychmiast `sudo tailscale funnel reset`
(zasada 2) i powtórz.

### 5b. Cztery testy z komputera użytkownika

Pierwsze wejście potrafi trwać kilka sekund dłużej (Tailscale wystawia certyfikat):

```bash
curl -sS -o /dev/null -w 'strona: %{http_code}\n' NOD_URL/
curl -sS -o /dev/null -w 'bez tokenu: %{http_code}\n' NOD_URL/api/session
curl -sS -o /dev/null -w 'zly token: %{http_code}\n' -H 'Authorization: Bearer to-nie-jest-token' NOD_URL/api/session
curl -sS -m 5 -o /dev/null -w 'publiczny IP: %{http_code}\n' http://PUB_IP:4310/ ; echo "EXIT=$?"
```

Oczekiwany wynik:

| Test | Wynik |
|---|---|
| strona przez tailnet | `200` (bez `-k`, więc certyfikat jest ważny) |
| `/api/session` bez tokenu | `401` |
| `/api/session` ze złym tokenem | `401` |
| publiczny IP, port 4310 | `000` i `EXIT` różny od 0 (timeout albo odmowa) |

Powiedz użytkownikowi, co widzi: Nod odpowiada tylko w Twojej prywatnej sieci, a z internetu
port 4310 nie istnieje.

**Test zaliczenia:** cztery wyniki jak w tabeli.

**FAIL - co zrobić:**
- `403` na stronie → `NOD_PUBLIC_URL` nie zgadza się z adresem, którego używasz (Nod wpuszcza tylko
  nagłówek Host z `NOD_PUBLIC_URL`). Porównaj z `tailscale serve status`. Po poprawce `.env`:
  `docker compose --file compose.yaml --env-file .env up -d --wait`.
- `curl: (6) Could not resolve host` → komputer użytkownika nie ma MagicDNS albo nie jest w tailnecie.
- `curl: (60) SSL certificate problem` → certyfikat jeszcze się wystawia; odczekaj 30 s i powtórz.
- publiczny IP odpowiada (`200`/`403`/`401`) → coś wystawia 4310 publicznie. **STOP.** Sprawdź
  `NOD_BIND_ADDRESS` w `.env` i `ss -tln | grep 4310` na serwerze. Nie idź dalej, dopóki nie zniknie.

### 5c. Token do schowka (nie do czatu)

Token wypisany w czacie zostaje w historii rozmowy. Kopiujesz go od razu do schowka użytkownika:

```bash
# macOS:
ssh -p PORT USER@HOST 'grep ^NOD_AUTH_TOKEN= ~/nod/deployment/self-host/.env | cut -d= -f2-' | tr -d '\n' | pbcopy && echo TOKEN_W_SCHOWKU
# Linux (X11 / Wayland): zamień "pbcopy" na "xclip -selection clipboard" albo "wl-copy"
# Windows (PowerShell): ssh -p PORT USER@HOST "grep ^NOD_AUTH_TOKEN= ~/nod/deployment/self-host/.env | cut -d= -f2-" | Set-Clipboard
```

Oczekiwany wynik: tylko `TOKEN_W_SCHOWKU`. Nic więcej nie wypisuj.

Powiedz: "Token jest w schowku. Wkleisz go za chwilę w Nodzie. Jeśli używasz menedżera haseł - zapisz
go tam. Kto ma ten token, ma pełny dostęp do agenta i wszystkiego, co do niego podłączysz."

---

## Faza 6 - Onboarding i model (w PRZEGLĄDARCE)

Przypomnij złotą zasadę: **teraz przeglądarka, aplikacja desktopowa dopiero w Fazie 7.**

### 6a. Onboarding (klik użytkownika)

1. Otwórz `NOD_URL` w przeglądarce na komputerze w tailnecie, wklej token ze schowka.
2. W onboardingu: **Share usage data - wyłącz** (bywa domyślnie włączone), **Share conversation
   traces - wyłącz**, pole **e-mail zostaw puste**.
3. Dojdź do rozmowy.

### 6b. Podłączenie modelu (klik użytkownika)

**ChatGPT (Plus/Pro)** - instrukcja krok po kroku, powiedz ją w całości PRZED kliknięciem:

1. Settings → Models → Add connection → OpenAI → **Sign in with ChatGPT**.
2. Zaloguj się w OpenAI i zatwierdź dostęp.
3. Przeglądarka wyląduje na stronie z błędem typu "Ta witryna jest nieosiągalna" / `127.0.0.1`
   odrzucił połączenie. **To normalne** - OpenAI odsyła na Twój komputer, a Nod siedzi na serwerze.
4. Skopiuj **cały adres z paska** (zaczyna się od `http://127.0.0.1:1455/auth/callback?code=...`).
5. Wróć do karty z Nodem, rozwiń **zwiniętą** linię "Browser didn't return to Nod?", wklej adres
   w pole "Callback URL", kliknij **Complete sign-in**.

Haczyki: masz na to **10 minut**; każde kliknięcie "Sign in with ChatGPT" tworzy nową próbę, więc adres
ze starej karty nie zadziała; w tym czasie nie uruchamiaj `codex login` na tym samym komputerze
(ten sam port 1455).

**Klucz API** - użytkownik wkleja klucz **sam** w Settings → Models → Add connection → dostawca → klucz.
Nie przez czat, nie do `.env`.

### 6c. Ręczne przełączenie modelu (klik użytkownika)

Podłączenie nowego połączenia **nie przełącza** wybranego modelu - zostaje ten, który był pierwszy.
Settings → Models: ustaw model rozmów na ten, za który chcesz płacić. Od `nod-v0.8.0` jest też
**osobny model do harmonogramów i pracy własnej Noda** ("The light model") - ustaw oba świadomie.

### 6d. Sprawdzenie w bazie (nie na ekranie)

```bash
ssh -p PORT USER@HOST "bash ~/nod-vps/nod-state.sh --model chatgpt"   # albo --model apikey
```

Oczekiwany wynik:
- `STATE_ONBOARDING_COMPLETED=t`,
- `STATE_USAGE_DATA=f`,
- `STATE_SELECTED_CONNECTION=openai/subscription/connected` przy ChatGPT albo
  `<dostawca>/api_key/connected` przy kluczu API - to metoda **dokładnie tego połączenia**, które
  wskazuje wybrany model (`model_settings.selection.connectionId`), a nie zgadywanie po nazwie modelu,
- `[OK] Rozmowy idą z subskrypcji ChatGPT` albo `[OK] Rozmowy idą z klucza API`,
- trasy harmonogramów i pracy w tle (`Trasa schedule/background`) - informacyjnie; WARN, jeśli przy
  ChatGPT idą przez klucz API.

**Test zaliczenia:** `STATE_ONBOARDING_COMPLETED=t`, `STATE_USAGE_DATA=f`, `STATE_SELECTED_CONNECTION`
zgodne z decyzją z Fazy 0 i linia `[OK] Rozmowy idą z ...`. **WARN "Nie mogę potwierdzić ..." to NIE jest
zaliczenie** - skrypt nie odczytał połączenia (inny schemat bazy niż w `nod-v0.8.0`); wtedy STOP, pokaż
output i poproś użytkownika o sprawdzenie w Settings -> Models, przez które połączenie idzie model rozmów.
Dodatkowo użytkownik wysyła w przeglądarce jedną krótką wiadomość ("Cześć, z jakiego modelu
odpowiadasz?") i dostaje odpowiedź.

**FAIL - co zrobić:**
- `STATE_USAGE_DATA=t` → Settings → Privacy & data → Share usage data → wyłącz. Powtórz 6d.
- `[UWAGA] Deklarujesz ChatGPT, a wybrany model ... idzie przez openai / api_key` → 6c nie zrobione
  (dwa połączenia OpenAI, wybrany model z tego z kluczem). Płacisz z klucza API.
- `[UWAGA] ... wskazuje połączenie, którego nie ma` → połączenie usunięto; wybierz model ponownie (6c).
- brak `connected` przy ChatGPT, w logu serwera `model_sign_in_failed` → próba wygasła albo wklejony
  adres był ze starej próby. Nowa próba od kroku 1 z 6b. Logi serwera prawie nic więcej nie powiedzą.
- ekran Noda pokazuje błąd, a `nod-state.sh` pokazuje `connected` → wierz bazie. Wyślij wiadomość testową.

---

## Faza 7 - Aplikacja desktopowa i podłączenia (opcjonalnie)

### 7a. Aplikacja desktopowa (tylko jeśli użytkownik chciał w Fazie 0)

Warunek: Faza 6 zaliczona (onboarding zapisany na serwerze).

1. Pobierz aplikację z wydania odpowiadającego `TAG`: `https://github.com/n8n-io/nod/releases/tag/TAG`
   (Mac: `.dmg`, Windows: `.exe`, Linux: flatpak). Sprawdź sumę SHA-256 z tej samej strony.
2. Przy pierwszym uruchomieniu aplikacja **startuje jako lokalny asystent na komputerze** i nie pyta
   o serwer - łatwo pomyśleć, że "sama się połączyła". Nie podłączaj w tym trybie modelu ani aplikacji.
3. Wybierz **Connect to a server**: adres `NOD_URL`, token ze schowka (5c). Jeśli aplikacja już działa
   lokalnie: menu Nod → Replay onboarding… → Connect to a server (tylko do przełączenia na serwer).
4. Przy ukończonym onboardingu na serwerze aplikacja wchodzi prosto do rozmowy.

Jak sprawdzić, że naprawdę gada z serwerem (Mac, sprawdzone na wersji 0.7.3):

```bash
grep -c serverUrl ~/Library/"Application Support"/nod/profiles/local/settings.json
lsof -nP -iTCP 2>/dev/null | grep -i nod | grep -c 4310
```

Oczekiwany wynik: obie liczby > 0. `0` w pierwszej = aplikacja działa lokalnie.

**FAIL - co zrobić:** ekran "Setup needs another try. These settings are not supported." → **serwer jest
w porządku** (sprawdź w przeglądarce i `nod-state.sh`). To błąd aplikacji przy zdalnym połączeniu.
Co zadziałało u autora poradnika: odinstalowanie aplikacji (zeruje jej ustawienia), instalacja od nowa
i "Connect to a server" - przy ukończonym onboardingu wchodzi prosto do rozmowy. Nie klikaj w kółko
"Try again". Nie używaj "Replay onboarding…", gdy aplikacja jest już połączona z serwerem.

### 7b. n8n przez MCP (jeśli użytkownik ma n8n)

Nod to osobny program, n8n nie jest mu potrzebny. Może się jednak podłączyć do n8n i budować tam
workflowy:

1. W n8n: Settings → **Instance-level MCP** (włącz).
2. W Nodzie: Apps → n8n → Connect, adres n8n po **HTTPS**.
3. **Odrzuć** adres z `localhost` albo `127.0.0.1` - w Nodzie oznacza on kontener Noda, nie serwer
   ani komputer użytkownika. Wymagaj adresu HTTPS osiągalnego z serwera.
4. Zaproponuj regułę w czacie Noda: "Always ask before publishing, executing or archiving n8n workflows".

### 7c. Aplikacje przez Composio (Gmail, Kalendarz...) - uczciwe ostrzeżenie

Powiedz wprost, zanim użytkownik spróbuje: **na self-hoście to może nie działać.** Połączenia idą przez
pośrednika hostowanego przez n8n, a własnego klucza Composio nie da się podać. Zgłoszenie z błędem
`429 public_budget_exceeded` (issue #819) zamknięto 16.11.2026 poprawą komunikatu błędu - czy sam limit
zniknął, ten poradnik nie sprawdził. Jeden test: podłącz jedną aplikację. Błąd → to nie jest Twoja
konfiguracja. Bez Composio działają: przeglądarka i workspace Noda, Telegram, n8n, Notion i Linear
(własne serwery MCP). Obejść (własne konto Composio jako serwer MCP, zalogowana sesja w przeglądarce
Noda) nie testowaliśmy - nie obiecuj ich.

**Test zaliczenia Fazy 7:** to, co użytkownik wybrał, działa albo jest świadomie odłożone (zapisz w czacie).

---

## Faza 8 - Backup i audyt PO

### 8a. Backup

Robisz go teraz, bo w bazie są już połączenia modeli. Powiedz przed: "Na kilkanaście sekund Nod się
zatrzyma." Ścieżka **bezwzględna**, katalog **nie może istnieć** (opakowanie to sprawdza):

```bash
ssh -p PORT USER@HOST 'bash ~/nod-vps/backup.sh "$HOME/backups/nod/$(date +%Y-%m-%d)_po-konfiguracji"'
```

Oczekiwany wynik: `[PASS] Kopia gotowa ... (plik complete jest)`, rozmiar, lista plików (nazwy,
nie zawartość), `[PASS] Serwer Noda znowu działa` i ostrzeżenie o sekretach.

Powiedz użytkownikowi: kopia zawiera `.env` z tokenem i kluczem sejfu. Baza bez `NOD_VAULT_KEY`
nie odtworzy zapisanych dostępów. Trzymaj kopię poza repozytorium, poza czatem i poza niezaszyfrowaną
chmurą. Chce mieć ją też poza serwerem? `scp -r -P PORT USER@HOST:<katalog> <gdzie-u-siebie>` - na
dysk, który kontroluje.

**Test zaliczenia:** plik `complete` jest, katalog ma prawa 700, serwer wstał.

### 8b. Audyt PO

```bash
scp -P PORT ./scripts/check.sh ./scripts/versions.env USER@HOST:~/nod-vps/
ssh -p PORT USER@HOST "bash ~/nod-vps/check.sh --after 2>&1 | tee ~/nod-vps/check-after.txt"
```

Skrypt kopiujesz jeszcze raz - wersja w repo mogła być nowsza niż ta z 1b.

Oczekiwane WARN-y, które nie są błędem:
- "Jest nowsza wersja ..." - Nod wychodzi często; aktualizacja ręcznie z backupem (INSTRUKCJA.md).
- "Zainstalowany ... różni się od przetestowanego" - tylko przy `--latest`.
- "Serwer nie dosięga własnego adresu tailnetu" - wtedy dowodem są testy z 5b.

**Test zaliczenia:** zero FAIL.

### 8c. Zestawienie przed/po

| | PRZED (Faza 1) | PO (Faza 8) |
|---|---|---|
| Nod | brak | `TAG`, 6 kontenerów, healthy |
| Adres | - | `NOD_URL`, tylko z tailnetu, ważny certyfikat |
| Port 4310 z internetu | - | nie odpowiada |
| Wejście bez tokenu | - | 401 |
| `.env` | - | prawa 600, 3 sekrety, nic nie trafiło do czatu |
| Dane użycia | bywają domyślnie włączone | wyłączone (z bazy) |
| Wybrany model | - | zgodny z decyzją z Fazy 0 (z bazy) |
| Backup | brak | jest, z plikiem `complete`, prawa 700 |
| Wersja | - | `TAG` vs przetestowany `NOD_TESTED_TAG` vs najnowszy |

Podsumowanie na koniec:

- Nod: `TAG` w `~/nod`, adres `NOD_URL`
- Model: [ChatGPT / klucz API: dostawca], model rozmów: [...], model do harmonogramów: [...]
- Aplikacja desktopowa: połączona z serwerem / nie używana
- Backup: [ścieżka] (+ kopia poza serwerem: tak / nie)
- Ryzyka, które zostają (powiedz je wprost): research preview z częstymi wydaniami; jeden token =
  pełny dostęp, bez kont i 2FA; kontener `runtime` ma dostęp do socketu Dockera (przez filtrujący
  pośrednik); utrata `NOD_VAULT_KEY` = utrata zapisanych dostępów; Composio na self-hoście niepewne;
  zgłoszenie #803 mówi o padającym workspace przy większych zadaniach na VPS (nie sprawdzaliśmy).
- Następny krok: drugi backup przed każdą aktualizacją; `bash ~/nod-vps/check.sh` raz na jakiś czas
  pokaże, czy jest nowa wersja.

---

## Czego wizard NIE robi (i celowo)

- nie robi hardeningu i nie instaluje Tailscale (to `vps-security` i `tailscale-vps`),
- nie zmienia `sshd_config`, reguł firewalla ani paneli dostawcy, nie otwiera portów,
- nie konfiguruje własnej domeny, reverse proxy (Traefik/Caddy/nginx), profilu `https` z Caddy ani tunelu
  SSH - jeszcze nie obsługiwane,
- nie używa `tailscale funnel`,
- nie wypisuje sekretów do czatu i nie prosi o klucze API,
- nie uruchamia `setup.sh` ponownie, gdy `.env` istnieje,
- nie aktualizuje Noda automatycznie - ścieżka ręczna z backupem jest w INSTRUKCJA.md,
- nie obiecuje, że Composio zadziała, ani że Nod jest bezpieczny.
