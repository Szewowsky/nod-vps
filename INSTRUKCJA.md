# Nod na własnym VPS - krok po kroku

Nie musisz być programistą. Potrzebujesz:
- VPS z Linuksem AMD64 albo ARM64 (testowane na Ubuntu): 2 rdzenie, 8 GB RAM, najlepiej 50 GB dysku
- serwera po poradnikach `vps-security` i `tailscale-vps` (o tym niżej)
- Tailscale na komputerze, zalogowanego tym samym kontem co serwer
- subskrypcji ChatGPT Plus/Pro albo klucza API do modelu (Claude i Gemini tylko kluczem API)
- terminala na komputerze (Terminal na Macu, PowerShell na Windows)
- ok. 40 minut, z czego ok. 7-15 to czekanie na build

Ten poradnik wystawia Noda **tylko przez Tailscale Serve**. Własna domena z reverse proxy i tunel SSH -
jeszcze nie obsługiwane.

## Krok zero: zabezpiecz i schowaj serwer

```
vps-security  ->  tailscale-vps  ->  nod-vps
```

Ten poradnik **nie robi hardeningu** i **nie instaluje Tailscale**. Najpierw:

1. **https://szewowsky.github.io/vps-security/** - użytkownik nie-root, klucze SSH, firewall
2. **https://szewowsky.github.io/tailscale-vps/** - serwer i komputer w jednej prywatnej sieci

W konsoli Tailscale (https://login.tailscale.com/admin/dns) włącz **MagicDNS** i **HTTPS Certificates** -
bez tego Nod nie dostanie certyfikatu.

## Złota zasada

**Najpierw onboarding w przeglądarce, dopiero potem aplikacja na komputer.** Aplikacja desktopowa
połączona ze zdalnym serwerem potrafi pokazać "Setup needs another try. These settings are not
supported." - serwer działa, zepsuty jest tylko ostatni ekran aplikacji.

## Zanim zaczniesz

Po `tailscale-vps` publiczne SSH jest zamknięte, więc wchodzisz po adresie z tailnetu:

```
ssh <user>@<serwer>
```

`<serwer>` to nazwa serwera w tailnecie albo jego adres `100.x.y.z`. Inny port SSH: `ssh -p 2222 ...`.
Komunikat `Tailscale SSH requires an additional check` z linkiem = otwórz link, potwierdź, komenda ruszy.

## Sprawdź, jak jest teraz (audyt PRZED)

Ze swojego komputera, z katalogu tego repo:

```
ssh <user>@<serwer> "mkdir -p ~/nod-vps"
scp ./scripts/check.sh ./scripts/nod-state.sh ./scripts/backup.sh ./scripts/versions.env <user>@<serwer>:~/nod-vps/
ssh <user>@<serwer> "bash ~/nod-vps/check.sh --before"
```

Sekcje 5-8 (Nod, dostęp, stan, backup) będą na żółto - to normalne, jeszcze go nie ma. W sekcjach 1-4
nie może być FAIL. Zapisz sobie linię "Publiczny IPv4 serwera" - przyda się w Kroku 4.

Brak Dockera, za stary albo bez Buildx (Ubuntu)? Na serwerze:

```
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg git openssl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker "$(id -un)"
```

Wyloguj się i zaloguj ponownie (grupa `docker` działa od nowej sesji), potem znowu `check.sh --before`.

---

## Krok 1: Kod Noda w przetestowanej wersji

**Po co?** Nie ma publicznego gotowego obrazu serwera Noda - budujesz go ze źródeł. Wersję przypinasz,
bo Nod wychodzi czasem kilka razy dziennie.

Przetestowany tag jest w `scripts/versions.env` (teraz: `nod-v0.8.0`). Najnowszy sprawdzisz na komputerze:

```
git ls-remote --tags --refs https://github.com/n8n-io/nod.git 'nod-v*' | awk '{sub("refs/tags/","",$2); print $2}' | grep -E '^nod-v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1
```

Na serwerze:

```
git clone --branch nod-v0.8.0 --depth 1 https://github.com/n8n-io/nod.git ~/nod
git -C ~/nod describe --tags --exact-match
```

Ma się wypisać `nod-v0.8.0`. Katalog `~/nod` już istnieje? Nie kasuj go - to może być działająca
instalacja. Zobacz "Aktualizacja" niżej.

---

## Krok 2: Konfiguracja (`.env`)

**Po co?** `setup.sh` Noda generuje trzy sekrety: token wejścia, klucz sejfu (`NOD_VAULT_KEY`) i hasło
bazy. Ty zmieniasz jedną linię: adres, pod którym będziesz wchodzić.

Na serwerze:

```
cd ~/nod/deployment/self-host
COMPOSE_PROJECT_NAME=nod sh setup.sh
tailscale status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))'
```

Ostatnia komenda wypisze nazwę serwera w tailnecie, np. `<serwer>.<tailnet>.ts.net`. Otwórz `.env`
(`nano .env`) i ustaw dokładnie:

```
NOD_PUBLIC_URL=https://<serwer>.<tailnet>.ts.net:4310
NOD_ANALYTICS_ENABLED=false
```

Bez ukośnika na końcu, bez ścieżki. Opcjonalnie `NOD_FEEDBACK_ENABLED=false` ukrywa przycisk
"Send feedback". Reszty nie ruszaj. Potem:

```
chmod 600 .env
```

**Nie uruchamiaj `setup.sh` drugi raz**, gdy `.env` już istnieje - nowy klucz sejfu = utrata zapisanych
dostępów. **Nie wklejaj `.env` nikomu**, także do czatu z AI.

---

## Krok 3: Build i start

**Po co?** Trzy obrazy (serwer, przeglądarka, workspace) budują się z kodu. Ok. 7 minut na 4 vCPU,
na 2 dłużej. Razem ok. 5 GB.

```
cd ~/nod/deployment/self-host
docker compose --file compose.yaml --env-file .env up -d --build --wait
docker compose --file compose.yaml --env-file .env ps
```

Masz widzieć 6 usług (`server`, `postgres`, `runtime`, `browser`, `workspace`, `workspace-network`),
przy `server`, `browser`, `postgres` i `workspace-network` napis `healthy`.

Boisz się, że zerwie Ci się SSH w trakcie? Uruchom w tle i podglądaj:

```
nohup docker compose --file compose.yaml --env-file .env up -d --build --wait > ~/nod-vps/build.log 2>&1 &
tail -f ~/nod-vps/build.log
```

Błąd `the --chmod option requires BuildKit` = brak Buildx (wróć do "Zanim zaczniesz").

---

## Krok 4: Dostęp przez Tailscale Serve

**Po co?** Nod słucha tylko na `127.0.0.1:4310`. Tailscale wystawia go w Twojej prywatnej sieci pod
adresem z prawdziwym certyfikatem. Internet go nie widzi.

Na serwerze:

```
sudo tailscale serve --bg --https=4310 http://127.0.0.1:4310
sudo tailscale serve status
```

Status ma pokazać `https://<serwer>.<tailnet>.ts.net:4310 (tailnet only)` i `proxy http://127.0.0.1:4310`.
Komenda wypisała link do włączenia HTTPS? Kliknij go (albo włącz HTTPS Certificates w konsoli) i powtórz.

**Nigdy `tailscale funnel`** - wygląda podobnie, ale publikuje usługę w całym internecie.

Cztery testy z **Twojego komputera**:

```
curl -sS -o /dev/null -w '%{http_code}\n' https://<serwer>.<tailnet>.ts.net:4310/
curl -sS -o /dev/null -w '%{http_code}\n' https://<serwer>.<tailnet>.ts.net:4310/api/session
curl -sS -o /dev/null -w '%{http_code}\n' -H 'Authorization: Bearer to-nie-jest-token' https://<serwer>.<tailnet>.ts.net:4310/api/session
curl -sS -m 5 -o /dev/null -w '%{http_code}\n' http://<publiczny-ip>:4310/
```

Oczekiwane: `200`, `401`, `401`, a ostatni `000` z błędem połączenia (port nie istnieje z internetu).

Token do schowka, bez wyświetlania (Mac):

```
ssh <user>@<serwer> 'grep ^NOD_AUTH_TOKEN= ~/nod/deployment/self-host/.env | cut -d= -f2-' | tr -d '\n' | pbcopy
```

Linux: zamiast `pbcopy` - `xclip -selection clipboard` albo `wl-copy`. Windows (PowerShell): `| Set-Clipboard`.
Kto ma ten token, ma pełny dostęp do agenta. Najlepiej zapisz go w menedżerze haseł.

---

## Krok 5: Onboarding i model (w przeglądarce)

1. Otwórz `https://<serwer>.<tailnet>.ts.net:4310`, wklej token.
2. Onboarding: **Share usage data - wyłącz**, **Share conversation traces - wyłącz**, **e-mail - puste**.
3. Model:
   - **ChatGPT Plus/Pro:** Settings → Models → Add connection → OpenAI → Sign in with ChatGPT. Po
     zalogowaniu przeglądarka pokaże błąd, że `127.0.0.1` odrzucił połączenie - **to normalne**. Skopiuj
     cały adres z paska (`http://127.0.0.1:1455/auth/callback?code=...`), wróć do Noda, rozwiń zwiniętą
     linię "Browser didn't return to Nod?", wklej w "Callback URL", kliknij "Complete sign-in".
     Masz 10 minut. Każde "Sign in with ChatGPT" to nowa próba - stary adres nie zadziała. Nie odpalaj
     w tym czasie `codex login` na tym samym komputerze.
   - **Klucz API:** Settings → Models → Add connection → dostawca → wklej klucz. Tylko tutaj.
4. **Przełącz model ręcznie** (Settings → Models). Nowe połączenie nie zmienia wybranego modelu. Od 0.8.0
   jest też osobny model do harmonogramów i pracy własnej Noda - ustaw oba.

Sprawdź stan w bazie (ekranowi Noda nie zawsze można wierzyć):

```
ssh <user>@<serwer> "bash ~/nod-vps/nod-state.sh --model chatgpt"
```

(albo `--model apikey`). Ma być: onboarding `t`, dane użycia `f`, połączenie `connected`, a przy
ChatGPT wybrany model z rodziny OpenAI. Komunikat "Deklarujesz ChatGPT, a wybrany model to ..." = nadal
płacisz z klucza API.

---

## Krok 6: Aplikacja desktopowa i podłączenia (opcjonalnie)

**Aplikacja** (dopiero po Kroku 5!): pobierz z https://github.com/n8n-io/nod/releases dla swojej wersji.
Przy pierwszym starcie aplikacja działa jako **lokalny asystent na komputerze** i nie pyta o serwer.
Wybierz **Connect to a server**, adres `https://<serwer>.<tailnet>.ts.net:4310`, token. Już działa
lokalnie? Menu Nod → Replay onboarding… → Connect to a server.

Czy na pewno gada z serwerem (Mac):

```
grep -c serverUrl ~/Library/"Application Support"/nod/profiles/local/settings.json
```

`0` = działa lokalnie.

**n8n:** w n8n Settings → Instance-level MCP (włącz). W Nodzie Apps → n8n → Connect, adres **HTTPS**
Twojego n8n. Nie `localhost` - w Nodzie to kontener Noda. Dobra reguła w czacie: "Always ask before
publishing, executing or archiving n8n workflows".

**Composio (Gmail, Kalendarz...):** na self-hoście może nie działać - połączenia idą przez pośrednika
n8n, własnego klucza nie podasz. Spróbuj jednej aplikacji; błąd `public_budget_exceeded` = to nie Twoja
konfiguracja.

---

## Krok 7: Backup i audyt PO

```
ssh <user>@<serwer> 'bash ~/nod-vps/backup.sh "$HOME/backups/nod/$(date +%Y-%m-%d)_po-konfiguracji"'
ssh <user>@<serwer> "bash ~/nod-vps/check.sh --after"
```

Backup na kilkanaście sekund zatrzymuje Noda. Kopia zawiera `.env` z tokenem i kluczem sejfu - trzymaj
ją poza repo, poza czatem, poza niezaszyfrowaną chmurą. Kopia tylko na serwerze nie chroni przed utratą
serwera: `scp -r <user>@<serwer>:<katalog-kopii> <dysk-u-siebie>`.

Audyt PO ma być bez FAIL. WARN "Jest nowsza wersja" jest normalny.

---

## Obsługa na co dzień

Wszystkie komendy z `~/nod/deployment/self-host` na serwerze:

- Stan: `docker compose --file compose.yaml --env-file .env ps`
- Logi: `docker logs --tail 50 nod-server-1` (serwer loguje mało - stan czytaj przez `nod-state.sh`)
- Restart serwera Noda: `docker compose --file compose.yaml --env-file .env restart server`
- Stan z bazy: `bash ~/nod-vps/nod-state.sh`
- Audyt i nowa wersja: `bash ~/nod-vps/check.sh`
- Wyłączenie dostępu z tailnetu: `sudo tailscale serve --https=4310 off`
- Całkowite zatrzymanie: `docker compose --file compose.yaml --env-file .env down` (dane zostają w wolumenach)

## Aktualizacja (ręcznie, zawsze z backupem)

Nod nie aktualizuje się sam na serwerze (aplikacja desktopowa ma własny mechanizm). Migracje bazy idą
**tylko do przodu** - powrót do starszej wersji = odtworzenie kopii. Dlatego zawsze w tej kolejności:

1. Sprawdź, co wchodzi: notatki wydania na https://github.com/n8n-io/nod/releases i `CHANGELOG.md`
   tego repo (czy tag był testowany).
2. Backup (nowy katalog):

```
bash ~/nod-vps/backup.sh "$HOME/backups/nod/$(date +%Y-%m-%d)_przed-NOWY_TAG"
```

3. Stop, pobranie **jednego** tagu (klon jest płytki, więc nie `git fetch --tags`), checkout, build:

```
cd ~/nod/deployment/self-host
docker compose --file compose.yaml --env-file .env stop
git -C ~/nod fetch --depth 1 origin tag NOWY_TAG
git -C ~/nod checkout NOWY_TAG
docker compose --file compose.yaml --env-file .env up -d --build --wait
```

4. Sprawdzenie:

```
bash ~/nod-vps/check.sh --after
bash ~/nod-vps/nod-state.sh
```

Na serwerze testowym przerwa trwała ok. 2 min 40 s (build ok. 2,5 min, bo część warstw była w cache).
Każda aktualizacja dokłada kilka GB obrazów i cache - pilnuj dysku (`df -h`, `docker system df`).

Nowy tag nie był testowany w tym poradniku? Działa na Twoje ryzyko - backup z punktu 2 jest Twoją drogą
powrotu. Odtwarzanie: Nod ma w `deployment/self-host` skrypt `restore.sh` (ten poradnik go nie testował -
przeczytaj go przed użyciem).

---

## Coś poszło nie tak?

1. **"Setup needs another try. These settings are not supported."** w aplikacji - serwer jest OK
   (sprawdź w przeglądarce i `nod-state.sh`). Odinstaluj aplikację (zeruje jej ustawienia), zainstaluj,
   "Connect to a server" - przy ukończonym onboardingu wejdzie prosto do rozmowy.
2. **Po zalogowaniu ChatGPT strona z błędem 127.0.0.1** - normalne, patrz Krok 5 (adres z paska do
   zwiniętego pola).
3. **Podłączyłem ChatGPT, a rachunek z klucza API rośnie** - wybrany model się nie przełączył. Settings → Models.
4. **Aplikacja "sama się połączyła"** - działa lokalnie. `settings.json` bez `serverUrl`. Krok 6.
5. **403 "This host is not permitted"** - wchodzisz innym adresem niż `NOD_PUBLIC_URL` (np. tunelem SSH
   na `localhost:4310`). Jeden sposób wejścia naraz.
6. **Ekran mówi błąd, a model działa** - wierz bazie (`nod-state.sh`), nie komunikatowi.
7. **`usage_data` włączone mimo `NOD_ANALYTICS_ENABLED=false`** - to dwie różne rzeczy. Settings → Privacy
   & data → Share usage data.
8. **Composio: `429 public_budget_exceeded`** - ograniczenie pośrednika n8n na self-hoście, nie Twój błąd.
9. **n8n nie łączy się z `localhost`** - podaj adres HTTPS osiągalny z serwera.
10. **Brak gotowego obrazu / "prebuilt bundle" z dokumentacji nie do pobrania** - paczki serwera są
    w prywatnych wydaniach. Build ze źródeł (Krok 3).
11. **`the --chmod option requires BuildKit`** - doinstaluj `docker-buildx-plugin`.
12. **Komenda `ssh` wisi z linkiem Tailscale** - Tailscale SSH prosi o potwierdzenie. Kliknij link.
13. **Backup: "już istnieje" / "musi być bezwzględna"** - Nod wymaga nowego katalogu i pełnej ścieżki.
    `scripts/backup.sh` to pilnuje.
14. **Wersje aplikacji i serwera się rozjechały** - aplikacja aktualizuje się sama, serwer nie. Zgodność
    różnych wersji nie była testowana; trzymaj je blisko siebie.
