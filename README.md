# Nod na własnym VPS (dostęp tylko przez Tailscale) 🤖

Postaw sobie Noda - open-source'owego agenta AI od n8n z własnym "komputerem" - na serwerze, który już masz. Widoczny tylko z Twoich urządzeń, z prawdziwym certyfikatem, bez domeny i bez otwierania portów. Gotowy wizard dla Claude Code + przewodnik krok po kroku po polsku.

## Dla kogo?

Masz VPS z Linuksem (np. Hostinger, Hetzner, DigitalOcean), **już zabezpieczony** i **schowany za Tailscale**. Chcesz na nim postawić Noda: agenta, który robi zadania w przeglądarce i we własnym Linuksie, pamięta, ma harmonogramy i przed akcją, o którą nie prosiłeś, pyta o zgodę.

Po tym poradniku:

- Nod działa na Twoim serwerze w przetestowanej wersji (albo najnowszej, jeśli tak wybierzesz),
- wchodzisz na `https://<serwer>.<tailnet>.ts.net:4310` z laptopa i telefonu w tailnecie,
- z internetu port 4310 **nie istnieje**,
- model jest podłączony (ChatGPT Plus/Pro albo klucz API) i sprawdzony w bazie, nie "na oko",
- masz backup i audyt, który mówi, czy jest nowa wersja.

Dostęp przez własną domenę z reverse proxy (Traefik, Caddy, nginx) i przez tunel SSH - jeszcze nie obsługiwane.

### Krok zero: dwa poprzednie poradniki

```
vps-security  ->  tailscale-vps  ->  nod-vps
(hardening)       (SSH za tailnetem)  (Nod + dostęp przez Tailscale Serve)
```

Ten poradnik **nie robi hardeningu** i **nie instaluje Tailscale**. Zacznij tutaj i wróć:

1. **https://szewowsky.github.io/vps-security/** - użytkownik nie-root, klucze SSH, firewall
2. **https://szewowsky.github.io/tailscale-vps/** - serwer i Twój komputer w jednej prywatnej sieci

## Co dostajesz?

- **Wizard dla Claude Code** - 9 faz (F0-F8), każda z komendą, oczekiwanym wynikiem, testem zaliczenia i planem B
- **Skrypt audytu** - `scripts/check.sh` sprawdza serwer PRZED i PO: wymagania, Docker i Buildx, Tailscale, kontenery, `.env`, dostęp, stan z bazy, backup i wersję
- **Stan Noda z bazy** - `scripts/nod-state.sh`: onboarding, dane użycia, połączenia modeli, wybrany model - bez sekretów
- **Backup bez potknięć** - `scripts/backup.sh`: ścieżka bezwzględna, nowy katalog, chmod 700, ostrzeżenie o sekretach
- **Przypięta wersja** - `scripts/versions.env` (ostatni przetestowany tag) i `CHANGELOG.md` (co i kiedy sprawdzone)
- **Instrukcja tekstowa** - `INSTRUKCJA.md` dla tych, którzy wolą kopiować komendy ręcznie (z aktualizacją)

## Wymagania

| Co | Minimum |
|----|---------|
| System | Linux AMD64 albo ARM64 (testowane na Ubuntu) |
| CPU | 2 rdzenie (build ze źródeł ok. 7 min na 4 vCPU, na 2 dłużej) |
| RAM | 8 GB (limity kontenerów to razem ok. 7 GB + Postgres) |
| Dysk | 50 GB zalecane przez dokumentację; obrazy ważą ok. 5 GB, każda aktualizacja dokłada kolejne |
| Narzędzia | Docker Engine 25+, Compose v2, Buildx, Git, OpenSSL (wizard doinstaluje Dockera, jeśli brakuje) |
| Tailscale | serwer i Twój komputer w tym samym tailnecie (po `tailscale-vps`), w konsoli włączone HTTPS Certificates |
| Model | subskrypcja ChatGPT Plus/Pro albo klucz API (Claude i Gemini **tylko** z kluczem API) |

## Quick Start

### Opcja A: Wklej jeden prompt agentowi (zalecane - tak robię to w filmie)

Otwórz Claude Code w nowym, pustym folderze i wklej to w całości:

```text
Sklonuj repozytorium https://github.com/Szewowsky/nod-vps.git do bieżącego katalogu,
przeczytaj plik .claude/commands/nod-setup.md i przeprowadź mnie przez opisany tam wizard
instalacji Noda (agenta AI od n8n) na moim VPS - dokładnie według jego zasad i kolejności
faz od F0 do F8. Idź krok po kroku: czekaj na wynik każdej komendy i nie przechodź dalej,
jeśli test fazy nie przeszedł. Zacznij od zebrania danych (Faza 0), potem audyt PRZED przez
scripts/check.sh --before, kod Noda w przetestowanej wersji z scripts/versions.env, build,
dostęp wyłącznie przez Tailscale Serve, onboarding w przeglądarce, a na końcu backup przez
scripts/backup.sh, audyt PO i zestawienie: co było na czerwono, a co jest teraz na zielono.
Złota zasada: najpierw onboarding w przeglądarce, dopiero potem aplikacja na komputer.
Mój serwer przeszedł już vps-security i tailscale-vps, więc NIE zmieniaj konfiguracji SSH
ani firewalla, nie otwieraj żadnych publicznych portów i nigdy nie używaj tailscale funnel.
Komendy z sudo buduj heredokiem zapisywanym do pliku i uruchamianym przez ssh. Nigdy nie
wklejaj do czatu zawartości pliku .env ani tokenu - token skopiuj mi do schowka. Logowania
(onboarding, ChatGPT, klucz API) robię sam w przeglądarce - Ty mi mówisz, gdzie kliknąć.
```

Chcesz najnowszą wersję Noda zamiast przetestowanej? Dopisz na końcu: `Użyj najnowszego tagu (--latest).`

Agent zapyta Cię o dane serwera, model i prywatność, a potem poprowadzi przez całość.
Dokładna instrukcja krok po kroku (z testami "czy zadziałało"): **[poradnik](https://szewowsky.github.io/nod-vps/)**.

Masz **Codex** zamiast Claude Code? Ten sam prompt działa - Codex czyta `AGENTS.md` z repo,
który wskazuje na ten sam wizard. Nie używaj `/nod-setup` (to komenda Claude Code), po prostu
wklej prompt.

### Opcja B: Z Claude Code, ręcznie przez slash command

```bash
git clone https://github.com/Szewowsky/nod-vps.git
cd nod-vps
claude
# wpisz: /nod-setup            (przetestowany tag)
# albo:  /nod-setup --latest   (najnowszy tag, nieprzetestowany)
```

### Opcja C: Ręcznie, bez agenta

Wszystkie komendy w tej samej kolejności znajdziesz w **[INSTRUKCJA.md](INSTRUKCJA.md)**.
Audyt serwera przed startem:

```bash
ssh <user>@<serwer> "mkdir -p ~/nod-vps"
scp ./scripts/check.sh ./scripts/versions.env <user>@<serwer>:~/nod-vps/
ssh <user>@<serwer> "bash ~/nod-vps/check.sh --before"
```

## 9 faz wizarda

| # | Faza | Test zaliczenia |
|---|------|-----------------|
| F0 | Dane i decyzje: serwer, łańcuch poradników, model, aplikacja, prywatność, backup, wersja | wszystkie odpowiedzi zebrane, nic nie zgadywane |
| F1 | Połączenie, skrypty na serwer, audyt PRZED (+ Docker z oficjalnego repo, jeśli brakuje) | `check.sh --before` bez FAIL w wymaganiach |
| F2 | Kod Noda w wybranej wersji (`git clone --branch <tag> --depth 1`) | `git describe --tags` = wybrany tag |
| F3 | `.env` przez `setup.sh` Noda + adres tailnetu w `NOD_PUBLIC_URL` | prawa 600, trzy sekrety niepuste (bez wypisywania), sam origin |
| F4 | Build ze źródeł i start (w tle, ok. 7 min) | 6 kontenerów, `server`/`browser`/`postgres` healthy |
| F5 | Tailscale Serve + token do schowka | strona 200, bez tokenu 401, zły token 401, publiczny IP:4310 milczy |
| F6 | Onboarding i model **w przeglądarce** | z bazy: onboarding zapisany, dane użycia wyłączone, model zgodny z decyzją |
| F7 | Aplikacja desktopowa, n8n, Composio (opcjonalnie) | wybrane działa albo świadomie odłożone |
| F8 | Backup + audyt PO + zestawienie | kopia z plikiem `complete`, `check.sh` bez FAIL |

## Audyt

Nie wiesz, czy serwer jest gotowy albo czy instalacja wyszła? Uruchom na serwerze:

```bash
bash check.sh --before                 # przed: brak Noda to WARN, nie FAIL
bash check.sh                          # po: wszystko ma być zielone
bash nod-state.sh --model chatgpt      # stan z bazy (albo --model apikey)
```

Dostaniesz raport PASS/WARN/FAIL. `check.sh` ostrzega też, gdy zainstalowana wersja różni się od przetestowanej albo od najnowszej. Skrypty audytu **niczego nie zmieniają** i nie wypisują sekretów - można je puszczać ile razy chcesz.

## Ważne

- **Najpierw onboarding w przeglądarce, potem aplikacja.** Aplikacja desktopowa połączona z serwerem potrafi pokazać "Setup needs another try. These settings are not supported." - serwer działa, zepsuty jest tylko ostatni ekran aplikacji (stan na `nod-v0.8.0`)
- **Po zalogowaniu ChatGPT zobaczysz stronę z błędem `127.0.0.1`.** To normalne - kopiujesz adres z paska do zwiniętego pola "Browser didn't return to Nod?" (10 minut na to)
- **Podłączenie ChatGPT nie przełącza modelu.** Bez ręcznej zmiany dalej płacisz z klucza API, jeśli był pierwszy. Wizard sprawdza to w bazie
- **"Share usage data" bywa domyślnie włączone** - wyłącz; pole e-mail w onboardingu zostaw puste
- **Jeden sposób wejścia naraz.** Nod wpuszcza tylko adres z `NOD_PUBLIC_URL`; po ustawieniu adresu tailnetu tunel SSH na `localhost:4310` daje 403
- **Jeden token = pełny dostęp** do agenta i wszystkiego, co do niego podłączysz. Brak kont i 2FA. Token trafia do schowka, nie do czatu
- **Backup zatrzymuje Noda na kilkanaście sekund i zawiera sekrety** (`NOD_AUTH_TOKEN`, `NOD_VAULT_KEY`). Bez klucza sejfu kopia bazy nie odtworzy zapisanych dostępów
- **Composio (Gmail, Kalendarz...) na self-hoście może nie działać** - połączenia idą przez pośrednika n8n, własnego klucza nie podasz. Bez Composio działają przeglądarka, workspace, Telegram, n8n, Notion, Linear
- **n8n podłączasz adresem HTTPS**, nie `localhost` - w Nodzie `localhost` to kontener Noda
- **Nod wychodzi czasem kilka razy dziennie.** Dlatego wersja jest przypięta (`scripts/versions.env`), a aktualizacja to świadoma, ręczna ścieżka z backupem (INSTRUKCJA.md)
- Testuj na świeżym VPS, zanim ruszysz produkcję

## Ryzyka, które zostają

To nie jest lista na wyrost - to rzeczy, których ten poradnik nie usuwa:

- Nod to **research preview**: wydania co kilka dni (czasem kilka dziennie), dokumentacja miejscami nie nadąża
- kontener `runtime` montuje socket Dockera (z filtrującym pośrednikiem) - błąd w tym pośredniku to potencjalnie root na serwerze
- dokumentacja Noda ostrzega, że metadane maszyny w chmurze mogą dać poleceniom z workspace dostęp do poświadczeń dostawcy; czy dotyczy to Twojego VPS - sprawdź u dostawcy
- zgłoszenie #803 w repo Noda mówi o padającym workspace przy większych zadaniach na VPS - nie sprawdzaliśmy
- kontrola zaufania przed akcjami to osąd modelu; autorzy zalecają mocny model

## Czym jest Nod

[Nod](https://github.com/n8n-io/nod) to open-source'owy osobisty agent AI od n8n Labs. To **osobny program, nie część n8n** i nie dodatek do niego - n8n nie jest potrzebne (Nod może się do niego opcjonalnie podłączyć przez MCP). Jego "własny komputer" to **kontenery Docker** na Twoim serwerze (Linux do pracy + przeglądarka Chromium), nie maszyna wirtualna. Dostęp: przeglądarka, aplikacja desktopowa, Telegram, WhatsApp. To repo **nie jest** częścią projektu Nod ani nie jest przez n8n firmowane - to nieoficjalny poradnik instalacji po polsku, oparty na dokumentacji `deployment/self-host` i na instalacji przetestowanej na VPS (szczegóły w `CHANGELOG.md`).

## Licencja

MIT - patrz [LICENSE](LICENSE). Sam Nod jest na licencji Apache 2.0 i pozostaje własnością swoich autorów.

---

Materiał towarzyszący do filmu na YouTube. Kanał: [Robert Szewczyk](https://youtube.com/@robert_szewczyk)
