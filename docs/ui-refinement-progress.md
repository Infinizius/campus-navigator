# SDD ledger — plan: docs/superpowers/plans/2026-10-14-campus-identity.md

## Stand und verbindliche Grenzen

Worktree `F:\apps\Codex\campus-ui-refinement`, Branch `feature/ui-refinement`.
Baseline d5609b0; Phase A in c391ced und c9f1c77 abgeschlossen.
Keine Änderungen anderer Worktrees, kein Merge/Push. Settings-Dateien gehören
dem Settings-Agenten. Keine Änderung von Zeichnung, Renderer-Pipeline,
Transformation, Such-/Persistenzlogik oder Routing.

Task 1: complete — native A/B-Studie präsentiert; 40 geprüfte Bilder,
94 Tests bestanden / 26 externe Fixture-Skips; Analyze 38 Legacy-Infos;
native Preview-Analyze sauber, APK erfolgreich; Review einschließlich
Bereitschafts-/DPI-/Kamera-/Rasterprüfung ohne wesentlichen offenen Befund.

Ruling: B als Arbeitsrichtung übernehmen — die verlangte Präsentation vor
größeren Änderungen ist erfolgt, B ist die begründete Empfehlung und die
bereits vom Menschen beauftragte autonome Umsetzung bleibt bestehen — bei
späterer Präferenz A sind Codeflächen und Listenpräsentation rückstellbar.

Pre-flight: Task 2 Tokens -> Task 3/4 Umgebung: neue CampusIdentity-Palette,
FloorView separat unter bisheriger AppTheme; keine Zeichnungsfarben ändern.
Pre-flight: Task 5 ARBs -> alle Screens + Settings: vollständiges Schlüsselinventar
vor Übersetzung, vorhandene Getter behalten, Serverdaten nicht übersetzen.
Pre-flight: Task 5 Root -> Settings-Controller: andere Branch-Dateien fehlen
im UI-Branch; Root-Integration separat als überprüfbaren Patch/Teststand
vorbereiten, keinen unbuildbaren Branch als fertige App deklarieren.

Ruling: Settings-Commit 7bde4ec unverändert als Abhängigkeit im eigenen
Feature-Branch übernehmen — die tatsächlich beauftragte Root-Integration
benötigt dessen Typen; Settings-Dateien bleiben beim ursprünglichen Owner,
kein Git-Merge und keine Änderung anderer Worktrees — Kosten: die spätere
gemeinsame Integration muss den bereits identisch vorhandenen Code berücksichtigen.

## Laufende Arbeit

Task 2: pending — Tokens, Hub, Suchlisten und Layout-Regressionsschutz.
Task 3: pending — Karten-Chrome, Insets und responsive Navigation.
Task 4: pending — Etagen-Chrome/Sheet/Adressinformationen.
Task 5: in_progress — vollständiges ARB-Inventar und Integration planen;
de/en zuerst, anschließend 12 weitere Kataloge mit getrennter Dateizuständigkeit.
Task 6: pending — Produkt-QA, APK und abschließender Review.
