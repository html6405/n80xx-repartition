Gemeinsames Recovery-ZIP mit expliziten Layoutprofilen.

- N8000 mit passendem Layout: System 2048 MiB, Cache 152 MiB.
- N8000 mit 16 GB praktisch geprüft: frisches System auf ausdrücklichen Wunsch,
  EFS/OTA gegen unabhängige PC-Sicherung verifiziert, GPT und Dateisystemgrößen
  geprüft, Wiederholungstest und Recovery-Neustart erfolgreich.
- ext4 ohne Journal wird trotz der alten parted-Ausgabe `ext2` korrekt erkannt.
- Ursprüngliche GPT, Layoutdaten und Prüfsummen werden gesichert.
- Standardmäßig werden System, Vendor und Cache gesichert. Das Auslassen dieser
  Images ist nur über die in README beschriebenen expliziten Testoptionen aktiv.
- N8010-Profil experimentell, abschließender Gerätetest noch offen.
- N8020 und unbekannte Layouts werden abgewiesen.

Vor einer Umstellung EFS und persönliche Daten unabhängig sichern. Nach einer
Umstellung mit frischem System ist eine ROM-Installation notwendig.
Die GPT-Dateien sind keine automatische Revert-Funktion; Anleitung beachten.
Herkunft und bekannter Stand des alten parted-Binaries: THIRD_PARTY.md.
