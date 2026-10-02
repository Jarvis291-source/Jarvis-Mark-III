# Jarvis Update Security

Jarvis installiert Updates nicht unbeaufsichtigt.

## Regeln

- feste Update-Quelle: Jarvis291-source/Jarvis-Mark-III
- Installation nur nach ausdrücklicher Bestätigung
- SHA-256-Prüfung vor Installation
- Backup der aktuell installierten App
- Rollback bei fehlgeschlagener Installation
- keine eingebetteten GitHub-Zugangstoken
- keine automatische Ausführung fremder Update-Quellen

Später kann zusätzlich eine kryptografische Signatur des Manifests ergänzt werden.
