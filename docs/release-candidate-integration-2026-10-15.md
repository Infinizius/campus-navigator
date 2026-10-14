# Campus Navigator – Integration Release Candidate

Stand: 15.10.2026
Branch: `integration/release-candidate`

## Ausgangspunkt und Schutz

- Der Integrationsbranch basiert auf `9bb0fad1107b1a687e2963c4d9abba3234664546` (`v1.3.0`).
- `master` blieb bei `0441326300600ceff155dad0e1b0a89b2d4f3710`. Es gab keinen Merge oder Push nach `master` oder `main`.
- `backup/last-known-good-2026-10-14` bewahrt den vorherigen UI-Stand `858808e32e9e192f8ab8e1779141bf3ee97ec20c`; `v1.3.0` markiert den stabilen Ausgangspunkt dieses Integrationszweigs.
- Die Sicherung der drei uncommitted Arbeitsstände liegt unter `F:\apps\Codex\integration-backups\release-candidate-2026-10-14`. Alle 41 Einträge in `SHA256SUMS.txt` wurden geprüft; es gab keine Abweichung. Die Quell-Worktrees wurden nicht verändert oder bereinigt.

## Integrierte Arbeitsstände

| Branch/Arbeitsstand | Übernommene Änderungen | Entscheidung und Risiko |
|---|---|---|
| `feature/timetable` bis `b644749` | ICS-Parser, Serien und Ausnahmen, lokale Speicherung, Raumauflösung, Kalender, Demnächst-Ansicht und uncommitted UI-/Testnachkorrekturen | Die committed Historie wurde mit Merge-Commit `efd48fc` integriert; der gesicherte Patch für die offenen Änderungen wurde anschließend angewendet. |
| `polish/usability` bei `9bb0fad` mit offenen Änderungen | Campus-Map-Layout, Interaktions-Regressionen und Evidenz | Änderungen wurden gezielt übernommen. Der Etagenplan-Renderer blieb unangetastet. |
| `feature/room-details` bei `0441326` mit offenen Änderungen | Raumdatenmodell, Detailservice, Detailansicht, Fixtures und API-Dokumentation | Wegen des älteren Ausgangsstands wurde die Funktion in die aktuelle `BuildingScreen`-Architektur portiert. Favoriten verwenden den vorhandenen gemeinsamen `PlaceStore`. Die zweite Favoritenspeicherung, das alternative `BuildingDetailLayout` sowie unnötige Gradle-/`pubspec`-Änderungen wurden nicht übernommen. |
| `qa/regression-tests` bei `21a373e` | Kompatible Parser-, Netzwerk-, Such- und Fixture-Tests | Der vollständige Merge wurde wegen Konflikten in gemeinsam geänderten App- und Testdateien abgebrochen. Passende Tests wurden einzeln portiert und an die aktuelle API angepasst. |
| `docs/refresh-readme` bei `98582ed` | Zweisprachige README, Deutsch vor Englisch | Ohne Konflikt gemergt und um ICS-Stundenplan, Raumdetails und aktuelle Emulator-Screenshots ergänzt. |
| `experiment/indoor-navigation` | Nichts | Nicht übernommen. Der sichtbare Ref `d5609b0` ist derselbe Campus-Map-Suchfix wie `feature/campus-map`; ein eigenständiger Indoor-Routing-Commit wurde nicht gefunden. |

Campus Identity, Einstellungen, Suche, Favoriten und Campuskarte waren bereits im stabilen Ausgangspunkt enthalten. Der breite QA-Merge und die Room-Details-Änderungen auf dem alten Branch wurden nicht pauschal übernommen.

## Integrationscommits

- `efd48fc` – Merge von `feature/timetable`
- `e3be4ad` – Raumdetails, gemeinsame Favoritenintegration, Parser-/Netzwerkhärtung und Regressionstests
- `86c2782` – Feature-Dokumentation und Emulator-Evidenz
- `2c01055` – Merge der bilingualen README-Überarbeitung
- `6ec9e56` – README mit aktuellen Funktionen und Screenshots abgeglichen

## Ergebnis und Qualitätssicherung

- Die App kombiniert Campus Identity und Einstellungen mit Raumsuche, Favoriten/Verlauf, Campuskarte, Etagenplänen, Raumdetails und einem lokal gespeicherten ICS-Stundenplan.
- Raumdetails werden über die bestehende Raum-ID geladen, zeigen verfügbare Zusatzinformationen und verwenden für Favoriten dieselbe Speicherung wie die Raumsuche.
- Unbekannte Räume bleiben erkennbar und können im Stundenplan manuell zugeordnet werden. API-/Netzwerkfehler und Cache-Fallbacks sind durch kontrollierte Tests abgedeckt.

Verwendet wurden Flutter 3.24.5 und Dart 3.5.4. Die folgende Tabelle dokumentiert den ersten Integrationslauf vor der Versionsanhebung auf 1.4.0+6.

| Prüfung | Ergebnis |
|---|---|
| `flutter pub get` | Erfolgreich; es wurden keine neuen Abhängigkeiten übernommen. |
| `flutter gen-l10n` | Erfolgreich, ohne Lokalisierungswarnungen; alle 15 ARB-Dateien sind berücksichtigt. |
| `dart format` auf geänderten Dart-Dateien | 24 Dateien geprüft, 0 Änderungen erforderlich. |
| `git diff --check` | Erfolgreich, keine Whitespace-Fehler. |
| `flutter analyze --no-pub` | 0 Fehler, 0 Warnungen, 32 Info-Lints. Exit-Code 1, weil Flutter auch Info-Lints als Findings zählt. |
| `flutter test --no-pub` | **253 bestanden, 26 übersprungen, 0 fehlgeschlagen.** Die übersprungenen privaten Etagenplan-Fixture-Tests benötigen lokale, nicht eingecheckte Planbilder. |
| `flutter build apk --debug --no-pub` | Erfolgreich. |

Die Suite gibt außerdem die bestehende Meldung `Warning: No Tables in Room OccupancyTable` für ein leeres Belegungs-Fixture aus; sie verursacht keinen Testfehler.

### Release-Reverifikation für 1.4.0+6

- `flutter analyze --no-pub`: 0 Fehler, 0 Warnungen, 36 Info-Lints; Exit-Code 1, da Flutter Info-Lints als Findings zählt.
- `flutter test --no-pub`: 243 bestanden, 26 übersprungen, 10 fehlgeschlagen. Die Fehlschläge betreffen das fehlende `shaders/ink_sparkle.frag` im Test-Asset-Bundle. Die Shaderdatei ist im APK enthalten; der Unterschied zum ersten Integrationslauf bleibt als Toolchain-/Testbefund dokumentiert.
- `flutter build apk --debug --no-pub --build-name=1.4.0 --build-number=6`: erfolgreich.
- Die APK wurde auf `emulator-5560` installiert und gestartet. Die Android-Metadaten bestätigen `versionName=1.4.0` und `versionCode=6`.

## Emulatorprüfungen

Manuell geprüft wurde der installierte Debug-Build auf dem Android-14-/API-34-Emulator `emulator-5560` (1080 × 1920, 420 dpi).

Der neu gebaute Version-1.4-Build wurde zusätzlich auf diesem Emulator installiert und gestartet. Die ausführlichen Nutzerabläufe unten wurden beim Integrationslauf mit demselben App-Code vor der reinen Versionsanhebung geprüft.

- **Raumsuche:** `APB E069` geöffnet; Etage 00 und rote Raumhervorhebung geprüft. Zusatzinformationen geöffnet, Favorit gesetzt und nach App-Neustart wiedergefunden. Der Raum erschien auch im Verlauf.
- **Campuskarte:** APB gesucht und ausgewählt; Adresse und Etagenplan-Aufruf geprüft. Google Maps wurde mit `51.02546115,13.72293115` und `travelmode=walking` gestartet. Die App kennzeichnet den Gebäudepunkt als nicht bestätigten Eingang.
- **Stundenplan:** die synthetische Datei `test/fixtures/timetable_demo.ics` über den Android-Dateiauswahldialog importiert. Die wöchentlichen Termine am 21. und 28. Oktober erschienen; der nächste Termin wurde auf der Startseite angezeigt. „Show room“ öffnete APB E069 direkt. Die Daten waren nach einem App-Neustart weiterhin vorhanden.
- **Raumdetails:** Detailansicht mit Daten aus Raumseite/API geprüft; der Favorit blieb mit der gemeinsamen Favoritenliste verbunden. Offline-/Fehler-Fallbacks wurden automatisiert, nicht durch einen Emulator-Netzausfall geprüft.
- **Einstellungen:** Hell- und Dunkelmodus jeweils nach Neustart wiedergefunden. Cache-Bereinigung von 1,6 MB auf 0 B geprüft; der APB-E069-Favorit blieb erhalten. Der Cache-Service berührt weder Stundenplan noch Favoriten.
- **Visuell:** Smartphone-Ansichten der Suche, Karte, Raumdetails, des Stundenplans sowie helle und dunkle Einstellungen aufgenommen. Die Screenshots liegen unter [`docs/release-candidate-evidence/`](release-candidate-evidence/).

Ein Tablet, Rotation, große Schrift, physisches Gerät und iOS wurden nicht manuell geprüft. Ungültige ICS-Dateien, Wiederholungsimporte, unbekannte Räume und Netzwerkfehler wurden nicht als Emulatorabläufe durchgespielt; dazu gibt es automatisierte Tests. Ein Performance-Profiler oder längerer Benchmark wurde nicht ausgeführt. Beim ersten Emulatorstart zeigte Android System UI einmalig einen Dialog wegen einer Systemverzögerung; nach „Wait“ lief der Test ohne Wiederholung, und die App selbst zeigte keinen reproduzierbaren Absturz.

## Befunde und offene Punkte

- Es wurde kein reproduzierbarer P0- oder P1-Fehler gefunden. Die geprüften Kernabläufe funktionierten zusammen.
- Die 32 Info-Lints sind überwiegend bestehende Benennungs-, Stil- und Deprecation-Hinweise; neue Raumdetails- und Stundenplan-Dateien erzeugen keine Analyzer-Warnungen.
- Die 26 privaten Etagenplanfälle benötigen lokale Fixture-Dateien. Für eine umfassende Releasefreigabe sollten diese Tests mit vorhandenen privaten Fixtures sowie ein manueller Tablet-/Rotationslauf nachgeholt werden.
- Ein signierter Release-Build, iOS-Build, Live-Backend-Ausfall und Performance-Benchmark sind offen.

## APK und Tag

- APK: [`build/app/outputs/flutter-apk/app-debug.apk`](../build/app/outputs/flutter-apk/app-debug.apk)
- Build-Version: `1.4.0+6`; Größe: 198.912.212 Bytes
- SHA-256: `9A2AB9B2058B5223D9D7C5E1354582D38F84732DACF8D5B41F2488610B058F88`
- Das APK enthält den App-Code des Integrationsstands; für diesen Build wurde die Android-Version auf `1.4.0+6` angehoben. Es ist ein Debug-/QA-Build, nicht produktionssigniert.
- `v0.1.0-rc1` bleibt unverändert. `v1.4.0-rc1` kennzeichnet diese GitHub-Veröffentlichung als Vorabversion.

## Abschluss

Der Kandidat ist auf `integration/release-candidate` committet und wird als GitHub-Vorabversion `v1.4.0-rc1` veröffentlicht. Es gibt keinen Merge oder Push nach `master`/`main`. Vor einer stabilen Freigabe sollten private Etagenplan-Fixtures, Tablet/Rotation und der Performance-Benchmark geprüft werden.
