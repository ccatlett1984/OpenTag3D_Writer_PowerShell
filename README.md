# OpenTag3D RFID Writer

A PowerShell module for working with [OpenTag3D](https://opentag3d.info) NFC tags on filament
spools. It looks up spool data by serial (currently only supported by Polar Filament), builds
NTAG21x tag images, reads and decodes existing tags, and writes tags through a PC/SC reader such
as the ACR122U. Tags for any other vendor can be filled in by hand in the browser UI, which is
also there for anyone who would rather not use the console.

Not affiliated with Polar Filament.

I am affiliated with the OpenTag3D project.

## What it does

- **Look up a spool** by serial and fetch its OpenTag3D payload
- **Read and write every published spec version** — 1.003, 2.000 and 2.001 — and convert
  between them
- **Build a complete tag image** — 180 bytes (NTAG213), 540 (NTAG215) or 924 (NTAG216),
  including UID/lock/capability-container header and the configuration pages
- **Read a tag** and decode every spec field — 36 in 1.003, 40 in 2.x — or decode a saved
  `.bin` on any platform
- **Edit tag data** before writing, with per-field validation
- **Build a tag by hand** for any vendor, with no lookup, and save it as a reusable profile
- **Write to a tag** over PC/SC, verifying every page afterwards
- **Browser UI** covering all of the above

## Requirements

| | |
|---|---|
| PowerShell | 7 or later, on Windows, Linux and macOS |
| Reading/writing tags | A PC/SC reader — developed against an ACR122U |
| PC/SC service | Windows: Smart Card service. Linux: `pcscd` + `libpcsclite1` + `libccid`. macOS: built in |

Everything else — lookups, building images, decoding saved `.bin` files, the browser UI —
needs nothing beyond PowerShell. See [Platform support](#platform-support).

## Install

On Windows or Linux, clone the repository first:

```powershell
git clone https://github.com/ccatlett1984/OpenTag3D_Writer_PowerShell.git
cd OpenTag3D_Writer_PowerShell
```

### Windows Setup

Windows ships with Windows PowerShell 5.1, which this module does not support. Install
PowerShell 7 first, then use `pwsh` rather than `powershell`:

```powershell
winget install Microsoft.PowerShell
```

```powershell
# Save the location where PowerShell 7 expects installed modules to live.
# (Windows PowerShell 5.1 keeps its modules elsewhere and is not supported.)
$dest = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules'

# Create that folder if it does not already exist.
New-Item -ItemType Directory -Path $dest -Force | Out-Null

# Copy the project module into that folder, effectively installing it. PowerShell can then
# find commands such as Show-OpenTag3DGui and Read-OpenTag3DTag from any folder.
Copy-Item .\OpenTag3DWriter -Destination $dest -Recurse -Force
Get-ChildItem -Recurse (Join-Path $dest 'OpenTag3DWriter') | Unblock-File
```

### Linux Setup

Reading or writing physical tags on Linux requires a PC/SC service, library, and reader
driver. On Debian, install them with:

```bash
# pcscd runs the smart-card service, libpcsclite1 lets the module communicate with that
# service, and libccid provides the driver used by USB readers such as the ACR122U.
sudo apt update
sudo apt install pcscd libpcsclite1 libccid

# Start the smart-card service now and automatically after future restarts.
sudo systemctl enable --now pcscd

#you may need to disable the native linux NFC driver in your distro, run this line if pcscd says it can't access the reader.
echo -e "blacklist pn533_usb\nblacklist pn533\nblacklist nfc" | sudo tee /etc/modprobe.d/blacklist-nfc.conf
```

On other Linux distributions, use that distribution's package manager to install the
equivalent PC/SC service, pcsc-lite library, and CCID reader-driver packages; package names
and service-management commands may differ.

Start PowerShell by running `pwsh`, then install the module:
```powershell
# Save the location where PowerShell expects installed modules to live.
$dest = Join-Path $HOME '.local/share/powershell/Modules'

# Create that folder if it does not already exist.
New-Item -ItemType Directory -Path $dest -Force | Out-Null

# Copy the project module into that folder, effectively installing it. PowerShell can then
# find commands such as Show-OpenTag3DGui and Read-OpenTag3DTag from any folder.
Copy-Item ./OpenTag3DWriter -Destination $dest -Recurse -Force
```

### MacOS Setup

Install the required dependency from Terminal:

```bash
# PowerShell 7 is the shell and runtime required to load and run this module on macOS.
brew install powershell

git clone https://github.com/ccatlett1984/OpenTag3D_Writer_PowerShell.git
cd OpenTag3D_Writer_PowerShell
```

Start PowerShell by running `pwsh`, then install the module:

```powershell
# Run pwsh in Terminal to start PowerShell before entering the commands below.
# Save the location where PowerShell expects installed modules to live.
$dest = Join-Path $HOME '.local/share/powershell/Modules'

# Create that folder if it does not already exist.
New-Item -ItemType Directory -Path $dest -Force | Out-Null

# Copy the project module into that folder, effectively installing it. PowerShell can then
# find commands such as Show-OpenTag3DGui and Read-OpenTag3DTag from any folder.
Copy-Item ./OpenTag3DWriter -Destination $dest -Recurse -Force
```

## Quick start

```powershell
# Browser UI - also the place to build a tag for a non-Polar vendor by hand
Show-OpenTag3DGui

# Save a tag image (defaults: Extended mode, NDEF format, Downloads or ~)
Export-OpenTag3DPayload -TagType NTAG215 -Serial 50017-FYG5

# Fetch and write to a tag in one step
Export-OpenTag3DPayload -TagType NTAG215 -Serial 50017-FYG5 -WriteToTag

# Force a spec version, converting if the lookup served a different one
Export-OpenTag3DPayload -TagType NTAG215 -Serial 50017-FYG5 -SpecVersion 2.001

# Write a saved image
Write-OpenTag3DTag -Path .\50017-FYG5-NTAG215-Extended-Ndef.bin

# Read the tag on the reader
Read-OpenTag3DTag | Select-Object material, color_name, print_temp, serial

# Decode a saved image (works on Linux and macOS too)
Read-OpenTag3DTag -Path .\tag.bin | Select-Object -ExpandProperty Fields | Format-Table
```

All parameters are name-only; nothing binds positionally.

## Commands

### `Export-OpenTag3DPayload`

Fetches a spool payload and builds a tag image, either to a file or straight to a tag.

| Parameter | Values | Notes |
|---|---|---|
| `-TagType` | `NTAG213` `NTAG215` `NTAG216` | Required |
| `-Serial` | e.g. `50017-FYG5` | Required; normalised to upper case; accepts pipeline input |
| `-Mode` | `Core` `Extended` | Defaults to `Core` for NTAG213, `Extended` otherwise |
| `-Format` | `Ndef` `Raw` | Default `Ndef` |
| `-SpecVersion` | `1.003` `2.000` `2.001` | Omit to keep what the lookup returns; naming one converts. See [Spec versions](#spec-versions) |
| `-OutputDir` | path | Defaults to Downloads (Windows) or `~` |
| `-WriteToTag` | switch | Write to a reader instead of a file |
| `-PassThru` | switch | Return the image bytes instead of saving or writing |
| `-ReaderName` | name fragment | With `-WriteToTag`; defaults to the first reader matching `ACR122`. See [Reader names](#reader-names) |

`-OutputDir` and `-WriteToTag` are mutually exclusive.

### `Write-OpenTag3DTag`

Writes an existing image to a tag.

| Parameter | Values | Notes |
|---|---|---|
| `-Path` | path to `.bin` | Accepts pipeline input from `Get-ChildItem` |
| `-Bytes` | `byte[]` | In-memory image instead of a file |
| `-ReaderName` | name fragment | Defaults to the first reader matching `ACR122`. See [Reader names](#reader-names) |
| `-Force` | switch | Write even if the spool holds a different spec version |

Always performed: the chip is identified (see [Chip identification](#chip-identification))
and checked against the image; the spool's existing spec version is read and must match the
image's (see [Writing over an existing spool](#writing-over-an-existing-spool)) — both before
anything is committed; the capability container on page 3 is written and read back; user
memory is read back and compared page by page.

### `Read-OpenTag3DTag`

Reads a tag, or decodes a saved image, and returns the decoded fields.

| Parameter | Values | Notes |
|---|---|---|
| `-Path` | path to `.bin` | Decode a saved image; works on any platform |
| `-ReaderName` | name fragment | Defaults to the first reader matching `ACR122`. See [Reader names](#reader-names) |
| `-Raw` | switch | Also return the payload bytes |

Every spec field is a property (`material`, `color_name`, `print_temp`, `serial`, …),
plus a `Fields` collection for display and a `SpecVersion` saying which layout was read.

There is no version parameter: a payload declares its own at `0x00`, so the field table is
chosen from the bytes. A tag written to any of the three reads correctly without being told
which.

### `Show-OpenTag3DGui`

Starts a local browser UI on `http://localhost:8787/`.

| Parameter | Values | Notes |
|---|---|---|
| `-Port` | 1024–65535 | Default 8787 |
| `-NoBrowser` | switch | Print the URL instead of launching a browser |
| `-IdleTimeout` | seconds | Default 15; see below |
| `-KeepAlive` | switch | Never stop automatically |

The UI has two screens:

- **Fetch & write** — look up a serial, save an image, write a tag, read a tag. **Read tag**
  shows every field decoded off the tag, grouped as that tag's own spec version groups them
- **View & edit** — load data, change it, then save an image or write a tag

**View & edit** starts from any of four sources:

| Button | Starts from |
|---|---|
| **Load from serial** | A Polar Filament spool lookup |
| **Load from tag** | Whatever is on the reader |
| **New tag** | A blank form — every spec field editable, no lookup involved |
| **Load** (under Saved profile) | Field values you saved earlier |

Whichever source you start from, the editor is the same: fields grouped the way that
payload's spec version groups them — Core and Extended for 1.003, Display / Inventory /
Operational for 2.x — per-field validation on save, a colour picker on each colour field, and
**Save image** / **Write to tag** at the bottom. The last two sources are covered in
[Generic vendor tags](#generic-vendor-tags).

The page sends a heartbeat every three seconds. Once the first one arrives, the server
shuts down if the heartbeat stops for `-IdleTimeout` seconds, so closing the tab stops
the server. A page reload is not treated as a close. The listener binds to localhost
only and has no authentication — fine on a desktop, not on a shared machine.

## Spec versions

The module carries a field table for each published layout and speaks all three.

| | 1.003 | 2.000 | 2.001 |
|---|---|---|---|
| Structure | Core `0x00-0x6F`, Extended to `0xBA` | one block, `0x00-0xD7` | same as 2.000 |
| Payload | 112 or 187 bytes | 216 bytes | 216 bytes |
| Fields | 36 | 40 — adds `sku`, `barcode`, `nozzle_diameter`, `chamber_temp` | 40, unchanged |
| Chips | NTAG213, 215, 216 | **NTAG215 or 216 only** | **NTAG215 or 216 only** |
| `-Mode` | Core / Extended | not applicable | not applicable |
| Required fields | none | ten, warned about but not enforced | same ten |

**2.001 is 2.000 with one correction.** `mfi_value` stops being divided by 10 and is read as
plain **g/min** rather than g/10min. The stored byte does not change — a raw `63` is
`630 g/10min` under 2.000 and `63 g/min` under 2.001, which is the same rate written
sensibly. Every id, address, length, type, scaling and required flag is otherwise identical,
so the module derives the 2.001 table from the 2.000 one rather than duplicating it.

**A payload declares its own version at `0x00`**, so reading never needs to be told which
layout to expect — `Read-OpenTag3DTag` picks the table from the bytes, and the GUI's version
selector follows whatever you load rather than overriding it.

A payload declaring a version with no exact table is read with the closest table below it in
the same major — a hypothetical 2.002 tag uses the 2.001 table — and says so with a warning.
A major version with no table at all is refused rather than guessed at.

Writing is where the selector matters. In the GUI it sits beside the tag type on both
screens; on the command line it is `-SpecVersion`. New tags default to **2.001** — the
current published spec. 1.003 and 2.000 stay first-class choices for tagging alongside
existing stock, and tags already written are unaffected either way, since reading follows
the payload.

Because the default is a 2.x layout, NTAG213 is absent from the tag-type list until you
select 1.003: 216 bytes plus NDEF framing cannot fit 144 bytes of user memory. The cmdlets
refuse the same combination with that explanation.

### Writing over an existing spool

`Write-OpenTag3DTag` reads the version off the tag before it writes anything, and **refuses
to change it** unless told to. Not because the result would be misread — the payload declares
its version at `0x00`, so a version-aware reader handles whichever version it finds. The guard
is against changing a tag's format *by accident*: the module's default version moves over time,
so editing one field on an existing spool should not quietly migrate the tag with it.

Two things do go wrong when a version changes, and both are reasons to make it deliberate:
going up, readers that predate the new version reject the tag rather than reading it; going
down, fields the older layout has no room for are lost. The error names whichever applies. A
mismatch stops the write with both versions named and the tag untouched — the check runs
before even the capability container is written.

```
Spec version mismatch: this image is OpenTag3D 2.001, the spool on the reader holds
OpenTag3D 1.003. Changing a tag's spec version is a deliberate act - readers that predate
2.001 will refuse the tag afterwards. Nothing was written. Rebuild the image as 1.003, or
pass -Force to rewrite the tag as 2.001.
```

A blank tag, or one holding something that is not an OpenTag3D record, has no version to
disagree with and writes normally. `-Force` migrates the tag to the image's version, warning
as it goes.

In the browser UI the same refusal becomes a confirmation rather than a dead end. **Write to
tag** reports what the spool holds and what writing would make it, says which way it goes
wrong, lists the fields a downgrade would drop, and offers **Migrate to 2.001** against
**Cancel** — the same pattern as the NTAG213 truncation prompt. Nothing is written until you
confirm.

![The migration confirmation, writing a 2.001 image at a 1.003 spool](docs/gui-version-migration.png)

Downgrading swaps the reason for the fields that would be lost, and names them.

Every page of user memory is written, including the all-zero ones. Skipping blank pages would
be quicker on a factory-fresh tag, but over a tag that already held a longer payload it leaves
the old bytes sitting past the new terminator.

### Converting between versions

The lookup service decides its own version, so `Export-OpenTag3DPayload` passes its payload
through untouched unless `-SpecVersion` asks for a different one. Conversion matches fields
by id, not address — 1.003 and the 2.x layouts share almost no addresses — and carries values
across in real-world units, so `tolerance` converts properly between 1.003's micrometres and
2.x's hundredths of a millimetre, and `mfi_value` between 2.000's g/10min and 2.001's g/min.

Anything that cannot carry across is dropped with a warning rather than mangled: 2.x's four
new fields have no home in 1.003, and a value too wide for a narrower field (1.003's two-byte
`td` into 2.x's one byte) is reported instead of truncated.

```powershell
# Whatever the service serves, unchanged
Export-OpenTag3DPayload -TagType NTAG215 -Serial 50017-FYG5

# Force a layout, converting if the service served the other one
Export-OpenTag3DPayload -TagType NTAG215 -Serial 50017-FYG5 -SpecVersion 2.001
```

## Generic vendor tags

The spool lookup only knows about Polar Filament. To tag anything else — another brand, a
refill, a spool you wound yourself — open **View & edit** and press **New tag**: every spec
field starts blank and editable, and **Save image** or **Write to tag** finishes the job
exactly as it does for a looked-up spool.

![View & edit, mid-way through a hand-built 2.001 tag](docs/gui-view-edit.png)

Two things differ from an edited Polar payload:

- The **serial** is yours to set. On a lookup it is locked, because it is the key the data
  came from; on a hand-built tag it is just the vendor's batch id.
- The **tag version** stays fixed at the spec version the module targets. It describes the
  format, not the filament.

Anything left blank is stored as zero, which the spec reads as "not supplied", so there is
no need to fill in fields you do not have. Colour fields have a picker beside the hex box;
**clear** returns a colour to unused.

**Spec version** picks the layout — see [Spec versions](#spec-versions). It opens on 2.001.
The form follows it: 2.x shows 40 fields grouped Display / Inventory / Operational, 1.003
shows 36 grouped Core / Extended. Saved images name the version they hold, so
`ACME-0001-NTAG215-Generic-2.001-Ndef.bin` is unambiguous a month later.

**Mode** is a 1.003 concept and greys out for 2.x. Core is `0x00-0x6F` (112 bytes), Extended
adds `0x70-0xBA` (187 bytes). Left on *Default for tag type* it follows the chip — Core for
NTAG213, Extended otherwise. Choosing NTAG213 for an Extended payload asks before dropping the
extended fields, and lists what survives.

### Profiles

**Save profile** stores the current field values under a name, and the dropdown loads them
back into a blank form later — useful when you tag the same filament repeatedly and only the
batch details change. A profile holds field values only; tag type, mode and spec version are
remembered as a starting point, not enforced — a profile saved from a 2.000 form loads into a
1.003 one, keeping the fields the two versions share.

Profiles are one JSON file each, so they can be edited by hand, copied between machines or
kept in version control:

| | |
|---|---|
| Windows | `%APPDATA%\OpenTag3D\Profiles` |
| Linux, macOS | `$XDG_CONFIG_HOME/opentag3d/profiles`, defaulting to `~/.config` |

```json
{
  "name": "acme-pla-matte",
  "tagType": "NTAG215",
  "mode": "Extended",
  "specVersion": "1.003",
  "savedUtc": "2026-08-30T22:31:52Z",
  "values": {
    "material": "PLA",
    "manufacturer": "Acme Filament",
    "color_1": "#C2410C",
    "print_temp": "215 C"
  }
}
```

Keys are OpenTag3D field ids and values take the same display form the parser produces
(`1.75 mm`, `215 C`, `#14ADDB`, `2026-04-03`). Anything that is not a spec field is ignored
on load, and empty values are dropped on save.

There is no cmdlet for building a generic tag yet — the module's field map and payload
builder are in place for one, but for now this is a UI feature.

## Tag layout

Images are complete NTAG21x dumps:

| Region | NTAG213 | NTAG215 | NTAG216 |
|---|---|---|---|
| Header (pages 0–3) | 16 bytes | 16 bytes | 16 bytes |
| User memory (page 4 on) | 144 | 504 | 888 |
| Config pages (last 5) | 20 | 20 | 20 |
| **Total** | **180** | **540** | **924** |

Pages 0–2 hold a placeholder UID with valid BCCs, since real UIDs are factory-programmed
and read-only; they exist so the file is a structurally valid dump. Page 3 holds the
capability container (`E1 10 12/3E/6D 00`). The trailing configuration pages carry factory
defaults with password protection disabled.

By default the payload is wrapped as an NDEF message — an `application/opentag3d` MIME
record inside an NDEF TLV — so readers report the tag as NFC Forum Type 2 with a readable
record. `-Format Raw` writes the bare payload at page 4 instead.

Reading takes **the first record in the message whose type is `application/opentag3d`**, as
the spec requires — not simply the first record. A tag may carry a URI record ahead of it so
a phone opens a product page, and that tag still reads. TLVs before the NDEF one (NULL
padding, lock control, memory control) are stepped over, and a record's ID field is skipped
properly when one is present. Chunked records are reported rather than half-read.

How much of that user memory a payload needs depends on the spec version:

| Payload | Bytes | Fits |
|---|---|---|
| 1.003 Core (`0x00–0x6F`) | 112 | any NTAG21x |
| 1.003 Extended (`0x00–0xBA`) | 187 | NTAG215, NTAG216 |
| 2.000 and 2.001 (`0x00–0xD7`) | 216 | NTAG215, NTAG216 |

Add roughly 27 bytes of NDEF framing to each — record header, the 21-byte
`application/opentag3d` type, the TLV and its terminator.

An NTAG213 holds only the 1.003 Core block, so asking for Extended on one falls back to Core
with a warning, and the edit screen lists exactly which fields survive before writing.
**A 2.x payload cannot go on an NTAG213 at all** — 216 bytes plus framing against 144 bytes
of user memory — which is why the chip disappears from the tag-type list whenever 2.000 or
2.001 is selected.

## Platform support

| Feature | Windows | Linux | macOS |
|---|---|---|---|
| Look up a spool, build images | yes | yes | yes |
| Decode a saved `.bin` | yes | yes | yes |
| Browser UI | yes | yes | yes |
| Read a tag from a reader | yes | yes | yes\* |
| Write a tag | yes | yes | yes\* |

The PC/SC layer binds three separate implementations, because they are not
interface-compatible:

- **Windows** — `winscard.dll`, Unicode entry points, 32-bit `DWORD`
- **Linux** — `libpcsclite.so.1`, ANSI entry points only (there is no `SCardListReadersW`),
  and `DWORD`/`LONG` are C `long`, so 64-bit on LP64. `SCARD_IO_REQUEST` is 16 bytes here
  against 8 on Windows
- **macOS** — the PCSC framework: same ANSI API as Linux, but `DWORD` stays `uint32_t`

\* The macOS declarations follow the framework headers but have not been exercised against
a reader. Linux has been tested against `libpcsclite.so.1`; Windows is the primary target.

### Reader names

Reader names come from the driver, not from the module, so the same ACR122U is
`ACS ACR122U PICC Interface 0` on Windows and `ACS ACR122U 00 00` under pcsc-lite.
`-ReaderName` is a fragment rather than the full name, so use something both platforms
share — `ACR122` — or leave it blank and the first reader matching `ACR122` is used. A
fragment that does not match exactly falls back to a per-word score, so a name copied from
another platform still resolves, with a warning naming the reader actually chosen.

`Get-PcscReader` is not exported; to list what the service can see, use `pcsc_scan` on
Linux or macOS.

### Chip identification

Reading or writing a physical tag starts by working out which NTAG21x is on the reader.
Three methods are tried in order:

1. **`GET_VERSION` (0x60)** through the reader's PN532 pass-through. Byte 6 of the reply is
   the storage size: `0x0F` NTAG213, `0x11` NTAG215, `0x13` NTAG216. Both pseudo-APDU
   wrappers are attempted — `InDataExchange` (`D4 40 01`) and `InCommunicateThru`
   (`D4 42`) — because which one a reader accepts depends on the driver, and the Linux CCID
   driver commonly rejects the first.
2. **The capability container at page 3**, whose third byte is `0x12` / `0x3E` / `0x6D`.
   A plain read of a page every NTAG has, so it works on any reader, but only on a tag that
   has already been NDEF-formatted.
3. **Probing the last user page** of each candidate, smallest chip first, resetting the card
   between attempts. Reading past the end of memory makes the tag NAK, and on pcsc-lite that
   leaves the card in an error state until it is reset — so both the order and the reset
   matter.

`-Verbose` reports which method identified the chip.

## Troubleshooting

**`Failed to listen on prefix ... conflicts with an existing registration`**
Another instance is still holding the port, or an HTTP.sys reservation exists:

```powershell
Get-Process powershell, pwsh | Where-Object { $_.Id -ne $PID }
netsh http show urlacl | Select-String 8787
```

Remove a stale reservation from an elevated prompt with
`netsh http delete urlacl url=http://localhost:8787/`, or just use `-Port 8788`.

**HTTP 429 / "rate limited by the server"**
The lookup service throttles back-to-back requests. Add `Start-Sleep -Seconds 3` between
serials when batching, or fetch to files first and write the tags afterwards.

**`Invalid checksum` / HTTP 403**
The serial has a check digit, so a typo in either half is rejected rather than reported as
"not found". Verify the serial as printed on the spool.

**`Tag on the reader is an NTAG213 but this image is for an NTAG215`**
Exactly what it says — the chip was identified before writing. Rebuild with the right
`-TagType`.

**`No tag on the reader`**
Place the tag and retry.

**`Reader matching '...' not found. Available: ACS ACR122U 00 00`**
Reader names are set by the driver, so the same ACR122U is `ACS ACR122U PICC Interface 0`
on Windows and `ACS ACR122U 00 00` under pcsc-lite. `-ReaderName` is a fragment, not the
full name: use something both platforms share, such as `ACR122`, or leave it blank — the
first reader matching `ACR122` is used automatically.

**`Could not identify the tag as NTAG213, NTAG215 or NTAG216`**
Re-run with `-Verbose` to see what each identification method returned. If every method
reports `SW=6A81` or similar, the reader is passing APDUs through but the tag is not
responding: reseat it, and on Linux confirm the kernel NFC modules are blacklisted (see
[Linux Setup](#linux-setup)) so pcscd owns the reader outright.

**`No readers available` / `The PC/SC service is not running`**
On Windows, start the Smart Card service. On Linux, start `pcscd` and check the reader is
visible with `pcsc_scan`. If the reader is plugged in but invisible, blacklist the kernel
NFC modules — see [Linux Setup](#linux-setup).

**`Access denied by the PC/SC service` (Linux)**
polkit is refusing the client. Add your user to the pcscd policy, or run
`pcscd --disable-polkit` for a quick test.

**`Spec version mismatch: this image is OpenTag3D ..., the spool on the reader holds ...`**
The tag already carries a different layout, and overwriting it would change what other readers
make of it. Nothing was written. Rebuild the image at the spool's version — `-SpecVersion` on
`Export-OpenTag3DPayload`, or the version selector in the GUI — or pass `-Force` to
`Write-OpenTag3DTag` if you really mean to change the tag's format.

**`OpenTag3D 2.x cannot be written to an NTAG213`**
A 2.x layout is 216 bytes; with NDEF framing that is 243 against an NTAG213's 144 bytes of
user memory. The spec dropped the chip. Use an NTAG215 or NTAG216, or build the tag as 1.003.

**`No application/opentag3d record in the tag's NDEF message`**
The tag holds a valid NDEF message, but none of its records carry the OpenTag3D type. The
message's record types are listed in the error. Every record is checked, so this means the
payload genuinely is not there.

**`this module has field tables for ... only`**
The tag declares a major version no table covers. Check what `Read-OpenTag3DTag -Verbose`
reports for the tag version; a newer *minor* release of a major the module knows is read with
the closest table below it, with a warning.

**`Profile name '...' is not usable`**
Profile names become file names, so they are restricted to letters, digits, spaces, dots,
dashes and underscores, up to 64 characters. Nothing that could point outside the profile
directory is accepted.

**The profile dropdown is empty, or a profile has gone missing**
Profiles are per-user files, not part of the module, so they do not travel with a reinstall
and are not shared between accounts. Check the directory for your platform under
[Profiles](#profiles) — copying the `.json` files there is all a move takes.

**The module does not autoload, or `Private/` and `Public/` appear directly in `Modules/`**
`Copy-Item` was given a `$dest` that did not exist yet, so it copied the module's *contents*
there instead of the folder itself. Delete what landed in `Modules/`, create the directory
first, and copy again — see [Install](#install).

**Odd `Â` characters in output**
Fixed in 1.4.0. Windows PowerShell 5.1 reads BOM-less `.ps1` files using the ANSI codepage,
which mangles UTF-8. All files are now pure ASCII with a UTF-8 BOM. If you see this, an old
copy of the module is still on `$env:PSModulePath` — delete it and reinstall.

## Notes

- Field layouts follow the published spec at
  [opentag3d.info/spec.json](https://opentag3d.info/spec.json). The module carries a table
  for 1.003, 2.000 and 2.001, each checked field by field against it. A payload declaring a
  newer *minor* version is read with the closest table below it in the same major, with a
  warning; a major version with no table is refused rather than guessed at.
- The tag version is never editable — it describes the format, not the filament, and the
  module stamps it. The serial is locked on a payload that came from a lookup, since it is
  the key the data came from, and editable on a hand-built tag, where it is the vendor's own
  batch id. Both rules are enforced server-side, not just in the UI.
- Page 3 is one-time programmable. The module only ever writes the capability container for
  the tag type it detected, and reads it back to confirm.
- Reading and writing touch user memory only. The UID and the lock/configuration pages on a
  physical tag are never modified.
- A hand-built tag is a normal OpenTag3D tag: same NDEF record, same field layout, same
  capability container. Nothing marks it as having come from this module rather than a
  vendor, and nothing about it is Polar-specific.

## License

AGPLv3
