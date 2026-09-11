# Changelog

## 1.8.0
- **OpenTag3D 2.001 support**, and it is now the default for new tags. 2.001 is 2.000 with one
  correction: `mfi_value` loses its scaling of 10 and reads as plain `g/min` rather than
  `g/10min`. The stored byte is unchanged - a raw `63` is `630 g/10min` under 2.000 and
  `63 g/min` under 2.001, the same rate written sensibly - so the 2.001 table is derived from
  the 2.000 one rather than duplicated, and converting between the two leaves the bytes alone.
  Checked field by field against opentag3d.info/spec.json on 2026-09-11
- **Writing refuses to change a spool's spec version.** `Write-OpenTag3DTag` reads the version
  off the tag first; if it differs from the image's, nothing is written - not even the
  capability container - and the error names both versions. A blank tag, or one holding
  something that is not an OpenTag3D record, has nothing to disagree with and writes normally.
  `-Force` overrides, with a warning
- Version lookup now prefers an exact table and otherwise takes the closest one below it in the
  same major, so a future 2.002 tag is read with the 2.001 table rather than the 2.000 one
- The NTAG213 refusal, the GUI's tag-type list and the Mode control now key on the major
  version rather than testing for 2.000 specifically
- Fixed **Read tag** showing only the colour swatch and title for a 2.x tag. The results table
  had the 1.003 group headings hard-coded, so every row of a payload grouped Display /
  Inventory / Operational was filtered out. Group headings now come from the tag's own spec
  version, any section the page was not told about is still shown rather than dropped, the
  spec version appears beside the title, and the field count is stated underneath

## 1.7.0
- **OpenTag3D 2.000 support, alongside 1.003.** The two layouts share only three addresses,
  so they are separate field tables behind a spec registry rather than one table with edits.
  2.000 is one flat 216-byte block against 1.003's Core-plus-Extended, adds `sku`, `barcode`,
  `nozzle_diameter` and `chamber_temp`, moves `tolerance` from micrometres to hundredths of a
  millimetre, and narrows `td` from two bytes to one. Verified field by field against
  opentag3d.info/spec.json and against a live pfil.us lookup
- **Reading needs no version.** A payload declares its own at `0x00`, so the field table is
  chosen from the bytes. This matters now rather than later: the Polar lookup service already
  serves 2.000, which 1.6.0 refused
- **A spec version selector** on both GUI screens, and `-SpecVersion` on
  `Export-OpenTag3DPayload`. **New tags default to 2.000** - the published spec, and what the
  lookup service serves; 1.003 stays a first-class choice. The lookup path keeps whatever the
  service returns unless a version is named, which is the lossless choice
- Saved images from the editor name the spec version they hold, both versions being in
  routine use. A profile with no recorded version is read as 1.003, since that is what its
  values were entered under
- **Conversion between versions**, matching fields by id and carrying values in real-world
  units, so `tolerance` converts rather than copies. Fields the target lacks, and values too
  wide for a narrower field, are dropped with a warning rather than mangled
- **NTAG213 is refused for 2.000** - 216 bytes plus framing against 144 bytes of user memory.
  The GUI removes the chip from the list while 2.000 is selected; the cmdlets explain why
- The editor groups 2.000's fields by the spec's own `usage` attribute (Display, Inventory,
  Operational), since 2.000 has no Core/Extended split
- Missing required fields are reported on save and write. 2.000 marks ten; 1.003 marks none
- Integer handling widened to 64-bit throughout - 2.000's `barcode` is 6 bytes and overflowed
  `Int32` in both directions
- Added `-PassThru` to `Export-OpenTag3DPayload`, returning the image bytes instead of writing
  a file. The GUI now uses it rather than saving to a temp file and rebuilding the name
- Profiles record the spec version they were saved from, and load into either

## 1.6.0
- Tags can be built by hand for any vendor, with no spool lookup: **New tag** on the
  View & edit screen opens a blank form covering every spec field, which then saves as an
  image or writes straight to a tag like any other payload. The serial is editable here -
  on a looked-up payload it stays locked, being the key the data came from - while the tag
  version stays fixed either way
- Field values can be saved as named **vendor profiles** and loaded back into a blank form,
  one JSON file each under `%APPDATA%\OpenTag3D\Profiles` or
  `$XDG_CONFIG_HOME/opentag3d/profiles`. Profile names are validated, and unknown keys are
  dropped on load, so an edited file cannot reach the encoder
- Colour fields now have a native colour picker beside the hex box, with a clear button to
  return a colour to unused. The hex box stays the value of record and alpha is preserved
- A blank form leaves unset numbers and times empty rather than showing 0 and 00:00:00
- Fields that fall outside the payload are no longer shown in the editor: a Core payload has
  nowhere to store them, and an editable box that silently discards what you type is worse
  than no box
- Saved image names now come from the edited values rather than the loaded ones, and fall
  back to manufacturer, material and colour when there is no serial

## 1.5.1
- Reader names differ between platforms - Windows reports `ACS ACR122U PICC Interface 0`,
  pcsc-lite reports `ACS ACR122U 00 00` - so `-ReaderName` no longer requires a literal
  substring match. A name that does not match exactly falls back to a per-word score, and
  the error now lists the readers seen and suggests a shorter fragment
- Tag identification is more robust on Linux:
  - `GET_VERSION` is tried through both PN532 wrappers, `InDataExchange` and
    `InCommunicateThru`. The Linux CCID driver frequently rejects the first
  - the NDEF capability container at page 3 is used as a second method - a plain read of a
    page every NTAG has
  - the page probe now runs smallest chip first and resets the card between attempts. A
    read past the end of memory makes the tag NAK, which wedges the card on pcsc-lite and
    made every later probe fail as well
  - the failure message lists what was tried and the status word each attempt returned
- Install instructions now cover the Linux and macOS module path
  (`~/.local/share/powershell/Modules`); `Unblock-File` is Windows-only and is skipped
  elsewhere

## 1.5.0
- Tag reading and writing now work on Linux and macOS through pcsc-lite, not Windows only.
  Three native bindings are declared, since the ABIs differ: Unicode entry points and 32-bit
  `DWORD` on Windows, ANSI entry points with LP64 `DWORD`/`LONG` on Linux, ANSI with 32-bit
  `DWORD` on macOS
- Reader availability is now probed rather than inferred from the operating system, so the
  GUI enables tag buttons whenever a reader is reachable
- PC/SC status codes are translated to readable messages (no reader, no tag, service down,
  polkit refusal) instead of bare hex

## 1.4.0
- Added `Read-OpenTag3DTag` — reads a tag or decodes a saved image into all 36 spec fields
- Added a **View & edit** screen to the GUI: load from a serial or a tag, edit any field,
  then save or write. Serial and tag version are display-only, enforced server-side
- NTAG213 truncation now warns and lists the fields that will be kept before writing
- GUI stops automatically when the page is closed (heartbeat, with `-IdleTimeout`/`-KeepAlive`)
- Output defaults to Downloads on Windows (resolved from the registry, so OneDrive
  redirection is respected) and the home directory elsewhere
- Fixed `Â` appearing before degree and micro signs: source files are now pure ASCII with a
  UTF-8 BOM, and JSON responses declare `charset=utf-8`
- Fixed `-shl` on `[byte]` truncating to byte width, which broke the tag version and any
  NDEF message over 254 bytes
- Fixed unit stripping on values whose unit contains digits (`600 g/10min`)

## 1.3.0
- Added the browser UI (`Show-OpenTag3DGui`), cross-platform via `HttpListener`

## 1.2.0
- Added NTAG213 support, forced to Core mode
- `-Mode` became optional with per-tag defaults
- All parameters are name-only

## 1.1.0
- Added `Write-OpenTag3DTag` — writes an image to a tag over PC/SC
- Chip type confirmed with `GET_VERSION` before writing; user memory verified after

## 1.0.0
- Initial module: `Export-OpenTag3DPayload`
