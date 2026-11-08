# Third-party dependency: GNU Parted

`package/tools/parted` is the existing static ARM executable used in html6405's
smdk4412 device builds, reporting version `1.8.8.1.179-aef3`.
It was originally added as `prebuilt/parted` to
`html6405/android_device_samsung_smdk4412-common` in commit
`912d98efc4daf43db8b02081827b1ed0d1c39f09`.

SHA-256 of the bundled executable:
`e7c06fd959c3c259f5bce9829406207bf6990b486a79b7f2ee935314099cc126`

The executable's GPLv3 license text is included in `package/tools/COPYING.parted`.
Its original build environment and matching complete source have not yet been
verified. This project does not claim a reproducible source build of this legacy
dependency. The repository's MIT license does not relicense GNU Parted.

The separate `read-range` helper is built from the included `read-range.c`,
has no libc dependency, and is covered by `LICENSE.read-range`.
