# Changelog

Nod wychodzi czasem kilka razy dziennie, więc ten poradnik przypina **ostatni przetestowany tag**.
Stała jest w jednym miejscu: `scripts/versions.env` (`NOD_TESTED_TAG`). Wizard bierze ją domyślnie,
`/nod-setup --latest` bierze najnowszy tag z GitHuba, a `scripts/check.sh` ostrzega (WARN), gdy
zainstalowana wersja różni się od przetestowanej albo od najnowszej.

Oznaczenia: **sprawdzone** = zrobione na żywym serwerze; **nietestowane** = wynika z dokumentacji,
kodu albo wcześniejszej wersji.

## 2026-11-16 - `nod-v0.8.0` (ostatni przetestowany tag)

Serwer testowy: VPS Hostinger KVM2, Ubuntu, Docker 29, Compose v5, Buildx 0.31. Dostęp przez
Tailscale Serve, inne usługi na tym samym serwerze (n8n, reverse proxy) bez zmian.

Sprawdzone:
- aktualizacja `nod-v0.7.6` -> `nod-v0.8.0` ścieżką z INSTRUKCJA.md: backup, `docker compose stop`,
  `git fetch --depth 1 origin tag nod-v0.8.0`, `git checkout`, `up -d --build --wait`;
  przerwa ok. 2 min 40 s, 6 kontenerów działa, `server` healthy bez restartów, adres w tailnecie 200,
- dane po aktualizacji nienaruszone: tury rozmów, połączenia modeli (connected), wybrany model,
  ukończony onboarding,
- zapytania z `scripts/nod-state.sh` (account_settings, model_connections, model_settings, turns)
  działają na schemacie 0.8.0.

Nowe w 0.8.0 (z notatek wydania): osobny model do harmonogramów i pracy własnej Noda
(Settings -> Models), poprawka sprawdzania `NOD_PUBLIC_URL` dla portów domyślnych (#893 - port 4310
z tego poradnika nie jest domyślny, więc bez zmian), obsługa serwerów zgodnych z OpenAI.

Nietestowane (uczciwie):
- **cała ścieżka wizarda na czystym VPS** - instalacja od zera była robiona na 0.7.3 na serwerze
  autora, nie na świeżej maszynie, i nie tym wizardem,
- `tailscale serve` z `sudo` (wizard) - u autora działało bez `sudo`,
- czas buildu i stabilność na 2 vCPU / 8 GB,
- `scripts/check.sh`, `scripts/backup.sh` i Faza 4 w tle (`nohup`) na żywym serwerze,
- ekran "Setup needs another try" na 0.8.0 - kod aplikacji w tym miejscu bez zmian, na żywo nie sprawdzone,
- aplikacja desktopowa 0.8.0 z serwerem 0.8.0,
- Composio na 0.8.0 (issue #819 zamknięte 16.11 poprawą komunikatu, nie wiadomo, czy limit zniknął),
- odtworzenie z backupu (`restore.sh` Noda).

## Wcześniej (historia testów na serwerze autora)

- `nod-v0.7.6` (2026-11-15) - aktualizacja z 0.7.3 tą samą ścieżką, przerwa ok. 2 min 45 s, dane nienaruszone.
- `nod-v0.7.3` (2026-11-12/13) - instalacja od zera ze źródeł: `git clone --depth 1`, `setup.sh`, build
  ok. 7 min na 4 vCPU, obrazy razem ok. 5 GB, `tailscale serve`, testy 200/401/401/brak odpowiedzi
  z publicznego IP, onboarding, ChatGPT przez wklejenie callbacku, pierwszy backup. Tu wyszły
  pułapki opisane w wizardzie.

## Jak dodać nowy przetestowany tag

1. Na serwerze testowym: backup, aktualizacja ścieżką z INSTRUKCJA.md, `bash ~/nod-vps/check.sh --after`
   bez FAIL, `bash ~/nod-vps/nod-state.sh` bez błędów schematu, jedna rozmowa testowa.
2. Zmień `NOD_TESTED_TAG` i `NOD_TESTED_DATE` w `scripts/versions.env`.
3. Dopisz sekcję na górze tego pliku: co sprawdzone, co nie, co się zmieniło w Nodzie.
