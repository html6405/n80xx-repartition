# N80xx: gemeinsames ZIP für System 2 GiB

`N80xx-System-2GiB.zip` ist der einzige aktuelle Installer. Ein gemeinsamer
Ablauf verwendet explizit geprüfte Modellprofile. Nur bekannte Kombinationen
aus Modell und tatsächlichen Partitionsgrenzen werden akzeptiert.

Download: [GitHub Releases](https://github.com/html6405/n80xx-repartition/releases).
Dort liegt genau ein gemeinsames ZIP je Version samt SHA-256-Datei. Der erste
Stand ist eine Vorabversion; Quellcode und Build-Anleitung liegen im Repository.

N8000: Das ursprüngliche Verfahren wurde auf 32 GB getestet. Das gemeinsame
ZIP wurde am 08.11.2026 auf einem N8000 mit 16 GB im ausdrücklich gewählten
Modus mit frischem System erfolgreich ausgeführt; ext4 ohne Journal wird
korrekt erkannt. EFS und OTA wurden anschließend bytegenau gegen unabhängige
PC-Sicherungen geprüft. Details zum Testumfang stehen in VALIDATION.md.

N8010 ist experimentell: Der erste Flash-Durchlauf wurde begonnen, durch eine
Sitzungsunterbrechung fehlt die abschließende Prüfung. Sein Zustand muss vor
weiteren Schreibzugriffen am Gerät ausgelesen werden. N8020 bleibt gesperrt.

Nur die folgenden tatsächlich ausgelesenen Profile werden akzeptiert:

| Modell / beobachtetes Layout | System-Ziel | Cache-Ziel | Unveränderte Grenzen |
| --- | ---: | ---: | --- |
| N8000, Originalgrenzen wie am 32-GB-Testgerät | 2048 MiB | 152 MiB | Partitionen 1–7 und 10–12 |
| N8010, bereits verändertes 16-GB-Gerät | 2048 MiB | 704,99609375 MiB | Partitionen 1–7 und 10–12 |

Die Gesamtkapazität und das Ende von Userdata dürfen variieren. Daraus folgt
keine allgemeine Freigabe für alle 16-GB-Geräte. Modell und alle festen
Partitionsgrenzen müssen exakt zum jeweiligen Profil passen. N8020 und
unbekannte N8010-Layouts bleiben gesperrt. Das ZIP nimmt keine allgemeine
automatische Neupartitionierung anhand eines Modellnamens vor.

EFS, Vendor/HIDDEN, OTA/misc, Userdata, Boot, Recovery und Bootloader behalten
ihre Grenzen. Cache wird verkleinert, System mit gesichertem Inhalt nach vorne
versetzt und das System-Dateisystem vergrößert. Nur GPT-Einträge 8 und 9 werden
neu angelegt; Mounts müssen Partitionsnamen oder Blockgeräte statt alter
PARTUUIDs dieser beiden Partitionen verwenden. ext-Dateisysteme ohne Journal,
die das alte parted als ext2 ausgibt, werden über tune2fs erkannt. Die bekannte
Blockgröße von 4096 Byte wird verlangt. Data muss unverschlüsseltes ext4 sein.

## Sicherung und Platzbedarf

Vor einer Umstellung ein unabhängiges PC-Backup anlegen, insbesondere EFS und
persönliche Daten. Das ZIP legt zusätzlich vollständige Images von EFS, Vendor,
OTA, Cache, System sowie zwei 4-MiB-GPT-Bereiche an. Datenimages werden per
Größe und SHA-256 gegen die Quelle geprüft. Der freie Platz wird anhand der
tatsächlichen Größen plus 256 MiB Reserve verlangt. Bei Platzmangel wird vor
Backup-Erstellung, Aushängen oder Schreibzugriffen auf Partitionen abgebrochen.

Automatische Auswahl: zuerst ausreichend freies Data unter `/data/media/0`,
bei fehlendem Benutzerverzeichnis unter dem vorhandenen `/data/media`,
sonst eine schreibbar gemountete SD auf `/external_sdcard`. Die SD muss von
mmcblk1 kommen; vfat, exfat und ext4 werden akzeptiert. Alle einzelnen Images
dieser Profile bleiben unter 4 GiB, sodass auch FAT32 passt. Es erfolgt keine
Aufteilung über mehrere Datenträger und keine Löschung vorhandener Dateien.
Für das geprüfte N8010 mindestens 4 GiB freien Platz auf der SD bereitstellen.
Der Sicherungsordner heißt `n80xx-repartition-backup-<Profil>` am gewählten
Ort. Ein bestehender Ordner wird nicht überschrieben. EFS-Daten sind privat;
FAT32 bietet keine Unix-Zugriffsrechte. Sicherungen nicht veröffentlichen.

Das ZIP speichert außerdem `partitions-before.txt`, die rohe primäre GPT,
den GPT-Endbereich, `layout-backup.env` mit Gerätegröße, Ausgangs-/Zielgrenzen
und Sicherungsmodus sowie Prüfsummen in `SHA256SUMS`. Diese Dateien vor einer
weiteren Umstellung zusätzlich auf den PC kopieren. `layout-backup.env` ist
ein Datensatz und darf nicht als Shell-Code ausgeführt werden.

Die Rohkopien sind keine fertige automatische Rücksetzung. Insbesondere kann
der 4-MiB-Endbereich bei manchen Layouts noch Userdata enthalten und darf nicht
blind zurückgeschrieben werden. Für eine GPT-Rücksetzung müssen ausschließlich
die tatsächlichen GPT-Metadatensektoren aus der Sicherung verwendet werden.
Nach dem Verschieben von System muss auch dessen Inhalt an den alten Start
zurückgebracht werden, oder System wird dort neu formatiert und die ROM erneut
installiert. Alte GPT und aktuelles Dateisystem passen sonst nicht zusammen.

### Leere Testgeräte

Standardmäßig sichert das ZIP System und Vendor und stellt System wieder her.
Für ausdrücklich leere Testgeräte kann der Aufrufer vor dem Start des
Installers `N80XX_FRESH_SYSTEM=1` setzen: System wird nicht gesichert und nach
der Umstellung als leeres ext4 mit 2 GiB neu angelegt. Danach ist eine passende
ROM zu flashen. `N80XX_BACKUP_VENDOR=0` lässt zusätzlich die Vendor-Imagesicherung
aus; die Grenzen von HIDDEN bleiben geschützt. `N80XX_BACKUP_CACHE=0` lässt
die Cache-Imagesicherung aus. Cache wird weiterhin geprüft und in-place
verkleinert; bei einem Fehler ohne Cache-Image ist eine Neuformatierung
möglicherweise erforderlich. EFS, OTA und GPT werden immer gesichert.
Die Platzprüfung berücksichtigt die gewählten Optionen.
Ohne diese expliziten Umgebungsvariablen bleibt der erhaltende Standard aktiv.
Für verschiedene Sicherungsmodi werden getrennte Ordnernamen verwendet.

## Prüfung und Installation

Statisches ARM-parted ist enthalten und wird vom ZIP nach /tmp entpackt.
Recovery benötigt /sbin/sh, unzip, e2fsck, resize2fs, tune2fs, sha256sum,
blockdev und die üblichen BusyBox-Werkzeuge.
Ein kleiner statischer ARM-Helfer `read-range` sichert die GPT-Bereiche mit
einem 64-Bit-Kernel-Seek. Das alte Recovery-dd las beim großen skip die gesamte
eMMC vorwärts; der Helfer vermeidet das. Quellcode und MIT-Lizenz liegen im ZIP.

Nur lesender Vorlauf nach Entpacken der tools nach /tmp:

`/sbin/sh /tmp/n80xx-repartition/tools/repartition.sh --check`

Dieser verlangt bereits einen geeigneten Sicherungsort und meldet andernfalls
den fehlenden Platz, ohne etwas auszuhängen oder anzulegen. `--apply` bzw. das
Flashen des ZIPs führt nach bestandenem Vorlauf die Umstellung aus.

Bei bereits vergrößertem Layout werden Dateisystemgrößen und Konsistenz ohne
Schreiben geprüft. Sind Cache/System noch gemountet, kann die Konsistenzprüfung
eine Fehlermeldung liefern; dann in Recovery aushängen und wiederholen.
Eine unterbrochene Umstellung wird nicht automatisch fortgesetzt oder
zurückgerollt. Bei Fehlern Recovery laufen lassen, Protokoll und Sicherungen
erhalten. Nach erfolgter Tabellenänderung darf eine alte GPT nicht blind
zurückgeschrieben werden. Ein noch ausstehendes System-Restore muss manuell
aus der Sicherung an die geprüften neuen Grenzen erfolgen. Nach erfolgreicher
Umstellung Recovery neu starten und danach eine passende ROM installieren.

## Build und Herkunft

`python3 build_zip.py`

Innerhalb des Android-Quellbaums erzeugt der Build `read-range` mit dem
vorhandenen Android-Clang r563880 neu. Ein eigenständiger Checkout verwendet
den beiliegenden ARM-Helfer. Zum Neubauen mit einem ARM-fähigen Clang und LLD:
`python3 build_zip.py --clang /pfad/zu/clang`.

Tests: `python3 -m unittest discover -s tests -p 'test_*.py'`.
Der Builder akzeptiert nur die ausdrücklich erlaubten Paketdateien und lehnt
Symlinks sowie unerwartete Dateien ab. Backups und Archiv bleiben lokal und
sind auch durch eine Git-Allowlist vom Repository ausgeschlossen.

Nur `package/` wird eingepackt, keine PC-Backups, Tests oder Protokolle.
parted 1.8.8.1.179-aef3 entspricht dem vorhandenen statischen Binary in
`device/samsung/smdk4412-common/prebuilt/parted`. GPLv3-Lizenztext liegt bei.
Die zum alten Binary passende vollständige Quellcodebereitstellung ist vor
öffentlicher Weitergabe noch zu klären; alternativ einen nachvollziehbaren
eigenen Build mit entsprechendem Quellcode verwenden.
