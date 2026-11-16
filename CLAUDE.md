# nod-vps

Wizard instalacji Noda (agent AI od n8n) na VPS, dostęp tylko przez Tailscale Serve. Źródło prawdy:
`.claude/commands/nod-setup.md` (komenda `/nod-setup`). Zasady agenta: `AGENTS.md`.

- Język: polski, znaki Unicode, NIGDY długa pauza (em-dash), zawsze krótki łącznik (-).
- Nie pisz, że Nod jest "bezpieczny" - mów, co zrobione i jakie ryzyka zostają.
- Przetestowany tag Noda zmieniasz tylko w `scripts/versions.env` + wpis w `CHANGELOG.md`.
- Nie commituj danych serwera użytkownika, tokenów, `.env`, backupów ani wyników audytu (`.gitignore`).
- Skrypty w `scripts/` niczego nie zmieniają na serwerze poza `backup.sh` (tworzy kopię, na chwilę
  zatrzymuje Noda).
