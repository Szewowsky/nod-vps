# AGENTS.md - instrukcja dla agenta (Codex, Claude Code i inne)

To repo to wizard instalacji Noda (open-source'owy agent AI od n8n) na VPS, z dostępem wyłącznie
przez Tailscale Serve. Jedyne źródło prawdy dla agenta: **`.claude/commands/nod-setup.md`** -
przeczytaj go w całości i prowadź użytkownika fazami F0 -> F8 dokładnie w tej kolejności, z testem
zaliczenia po każdej fazie.

Zasady, których nie wolno złamać (pełna lista w wizardzie, sekcja "ZASADY (NIGDY NIE ŁAMAĆ)"):

1. Nie dotykaj konfiguracji SSH ani firewalla i nie otwieraj portów. Nigdy `tailscale funnel`.
2. Nie wklejaj do czatu zawartości `.env` ani `NOD_AUTH_TOKEN` - token idzie do schowka użytkownika
   (Faza 5c). Klucze API modeli użytkownik wkleja sam w interfejsie Noda.
3. Nie uruchamiaj `setup.sh` ponownie, gdy `.env` istnieje (nowy `NOD_VAULT_KEY` = utrata dostępów).
4. Najpierw onboarding w przeglądarce (Faza 6), dopiero potem aplikacja desktopowa (Faza 7).
5. Stan sprawdzaj w bazie (`scripts/nod-state.sh`), nie na ekranie Noda.
6. Czekaj na wynik każdej komendy. Test fazy nie przeszedł -> STOP, pokaż output, zapytaj.

Wersja: `scripts/versions.env` (`NOD_TESTED_TAG`). Inny tag tylko na wyraźne życzenie użytkownika
(`--latest`), z ostrzeżeniem, że nie był testowany.

Audyt: `scripts/check.sh --before` przed instalacją, `scripts/check.sh --after` po. Audyt PO ma być
bez FAIL. Backup: `scripts/backup.sh` (ścieżka bezwzględna, nowy katalog). Aktualizacja i problemy:
`INSTRUKCJA.md`.

Komendy z `sudo` na serwerze: zapisz skrypt do pliku lokalnie heredokiem, `scp` na serwer, wykonaj przez
`ssh USER@HOST "bash /tmp/plik.sh"`. Nie łącz faz w jedną komendę.
