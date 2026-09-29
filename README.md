# K2 Plus Override Stick

Klipper macro tweaks for the **Creality K2 Plus** that live on a USB stick, so
they can be set up again after a firmware update or factory reset.

- **Z-offset per material and build plate**: e.g. PETG on the textured plate
  gets a different offset than PLA on the smooth one.
- **Heat soak before the print**: the bed heats up, then waits a configurable
  time so it is thermally settled. The print is paused meanwhile, so
  **cancelling works at any time**.
- **Bed mesh cache**: the mesh is measured once per bed temperature and plate and
  reused afterwards, instead of probing before every print.
- **Small prints**: skip the soak and optionally probe only the area around the
  print.
- **Back-to-back prints**: a print that starts right after the previous one gets
  a shorter soak, since the bed is still warm.
- **Firmware updates**: everything lives on the stick, the printer only keeps
  two small trigger scripts. The update from V1.1.6.4 to V1.1.7.0 kept those
  scripts, so re-plugging the stick was enough to redo the changes the update
  had reverted. Whether future updates behave the same is unknown; if the
  scripts are gone, one SSH command sets everything up again.

Everything is configured in one file on the stick. Pull the stick and the
printer behaves exactly like stock again.

> **Status: beta.** Developed and tested on a K2 Plus with firmware
> **V1.1.6.4** and **V1.1.7.0**. Other firmware versions or K2 models may work
> but are untested.

> **Use at your own risk.** This project changes the printer's Klipper
> configuration and renames Creality's stock macros. It comes without any
> warranty (see [LICENSE](LICENSE)); you are responsible for your printer and
> your prints.

---

## Contents

- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Installation](#installation)
- [Slicer setup](#slicer-setup)
- [Configuration](#configuration)
- [Per-print overrides](#per-print-overrides)
- [Console commands](#console-commands)
- [What you see during a print](#what-you-see-during-a-print)
- [Updating and firmware updates](#updating-and-firmware-updates)
- [Troubleshooting](#troubleshooting)
- [Uninstalling](#uninstalling)
- [Known limitations](#known-limitations)

---

## How it works

A firmware update on the K2 Plus can reset the printer configuration, and a
factory reset wipes it completely. This project keeps all of its files on a USB
stick instead. From the stick, `bootstrap.sh` sets the printer up:

1. installs two tiny trigger scripts on the printer: one reacts when the stick
   is plugged in or removed, the other runs at every boot,
2. copies the `.cfg` files into the printer's config (`printer_data/config/custom/`)
   and includes them in `printer.cfg`,
3. renames the stock macros it extends (e.g. `START_PRINT` becomes
   `START_PRINT_STOCK`; a backup of the original `gcode_macro.cfg` is kept),
4. restarts Klipper if anything changed and switches the overrides on.

It runs automatically whenever the stick is plugged in or the printer boots;
only the very first time (and after a factory reset) you start it by hand.
When the stick is removed, the overrides are switched off. The files stay on the
printer but pass everything straight through to the stock macros.

## Requirements

- Creality K2 Plus (tested with firmware V1.1.6.4 and V1.1.7.0)
- Root access to the printer via SSH (enable it in the printer's settings menu;
  Creality's default root password is `creality_2024`)
- A USB stick formatted as FAT32 or exFAT (it can hold your print files too)
- A computer with `ssh` (built into Windows 10/11, macOS and Linux)
- A slicer that lets you edit the machine start G-code (Creality Print, OrcaSlicer)

## Installation

### 1. Prepare the USB stick

1. Download this repository as a ZIP (**Code → Download ZIP** at the top of the
   GitHub page) and unpack it on your computer.
2. Copy the `k2-overrides` folder from inside the unpacked folder to the
   **root** of the stick. Only that folder is needed, and its name must stay
   `k2-overrides`: that is how the printer recognizes the stick.
3. Adjust `k2-overrides/00_user_config.cfg` on the stick to your needs (see
   [Configuration](#configuration)). You can also do that later.

The stick then looks like this:

```
<stick>/
└── k2-overrides/
    ├── scripts/
    │   ├── bootstrap.sh
    │   ├── teardown.sh
    │   ├── uninstall.sh
    │   ├── common.sh
    │   └── printer/            ← trigger scripts, installed on the printer by bootstrap.sh
    ├── 00_state.cfg
    ├── 00_user_config.cfg      ← your settings
    ├── 10_print_plan.cfg
    ├── 20_bed_mesh.cfg
    ├── 30_print_flow.cfg
    └── 40_print_hooks.cfg
```

### 2. Plug it in and run the bootstrap once

Plug the stick into the printer, then run (replace `<printer-ip>` with your
printer's IP address):

```sh
ssh root@<printer-ip> "sh /mnt/exUDISK/k2-overrides/scripts/bootstrap.sh; logread | grep k2-overrides"
```

It takes up to a minute and restarts Klipper once. The log should end with
`Overrides active`, and the Fluidd/Mainsail console shows
`[K2_OVERRIDES] Override active: 1`. From now on, plugging in the stick or
booting the printer does this automatically.

### 3. Set up the slicer

See the next section. Without it, everything still works, but without material-
and plate-specific values.

## Slicer setup

The printer only learns the material and the build plate from the slicer. In
**Printer settings → Machine G-code → Machine start G-code**, extend the
`START_PRINT` line with `MATERIAL=` and `BED_TYPE=`:

```
START_PRINT EXTRUDER_TEMP=[nozzle_temperature_initial_layer] BED_TEMP=[bed_temperature_initial_layer_single] MATERIAL={filament_type[initial_tool]} BED_TYPE="{curr_bed_type}"
```

Keep the quotes around `BED_TYPE`, plate names contain spaces. A printer without
the stick simply ignores the extra parameters.

**"Print Calibration" in the print dialog:** when it is enabled, the printer runs
Creality's own fresh bed calibration before the print, and this project stays
out of the way (no soak, no mesh cache; the Z-offset is still applied). Leave it
off to use the mesh cache.

## Configuration

All settings are in `k2-overrides/00_user_config.cfg`. Each setting can be

- **one number for everything:**

  ```
  variable_soak_minutes: 5
  ```

- **per material** (the material name in upper case, as your slicer's filament
  type), with `'default'` for all other materials:

  ```
  variable_soak_minutes: {
      'default': 5,
      'ABS': 10,
      'ASA': 10,
      }
  ```

- **per material and build plate** (the plate name exactly as the slicer calls
  it, upper/lower case matters):

  ```
  variable_z_offset: {
      'default': 0.05,
      'PETG': {'Textured PEI Plate': 0.02, 'default': 0.03},
      }
  ```

> **Always give a per-plate entry its own `'default'`.** Without it, a plate that
> isn't listed gets `0`, not the value of the outer `'default'`.

### Settings

| Setting | Default | Meaning |
|---|---|---|
| `z_offset` | `0` | Z-offset in mm, applied at the end of the start sequence. Larger = nozzle farther from the bed. |
| `soak_minutes` | `5` (ABS `10`) | Minutes to wait once the bed has reached its temperature. `0` = no soak. |
| `small_print_coverage_pct` | `0` (PLA `15`, PETG `10`) | A print is "small" if its objects cover less than this percentage of the bed. `0` = never small. Small prints skip the soak. |
| `small_print_adaptive_mesh` | `1` | For small prints: `1` = probe only around the print (no cache); `0` = use the cached full-bed mesh (the soak is only skipped if that mesh already exists). |
| `warm_restart_minutes` | `10` | A print starting within this many minutes after the previous one gets a shorter soak, see below. `0` = off. |
| `warm_bed_tolerance` | `10` | The bed may have cooled down by at most this many °C for the shorter soak. |

After editing, copy the file to the stick and apply it (see
[Updating](#updating-and-firmware-updates)).

### Bed mesh cache

For each combination of bed temperature and plate, the first print measures the
bed and saves the mesh as a profile, e.g. `bed_mesh_70c_0c_textured_pei_plate`
(bed 70 °C, chamber 0 °C). Later prints with the same combination load it
instead of probing. Clear the cache after a nozzle change, a Z calibration or
when a plate looks different: see `K2_CLEAR_MESH_CACHE` under
[Console commands](#console-commands). A manual bed calibration (`G29`, or from
the display) always measures fresh and is not cached, and doesn't replace the
cache for the next print. When the app measures while preparing a print ("Print
Calibration"), that print uses the app's fresh mesh instead, without a soak.

### Back-to-back prints

If the previous print ended less than `warm_restart_minutes` ago at the same bed
temperature, the soak is shortened. How much depends on how long the bed was
hot in the previous print and how long ago it ended: right after a long print
most of the soak is skipped, after 5 of 10 minutes about half, after a very short
print hardly anything. Preheating from the display does not count, and neither
does a print that was cancelled during its soak.

## Per-print overrides

Any setting can be overridden for a single print by adding a `K2_` parameter
to the `START_PRINT` line in the slicer, e.g. in the filament's or process's
start G-code:

```
START_PRINT ... MATERIAL=PETG BED_TYPE="High Temp Plate" K2_SOAK_MINUTES=10 K2_Z_OFFSET=0.02
```

Names are `K2_` + the setting in upper case, optionally followed by a material
and a plate (upper case, spaces and `-` become `_`):

| Parameter | Applies to |
|---|---|
| `K2_Z_OFFSET=0.02` | this print |
| `K2_Z_OFFSET_PETG=0.02` | this print, if the material is PETG |
| `K2_Z_OFFSET_PETG_HIGH_TEMP_PLATE=0.02` | this print, if PETG on the High Temp Plate |

The most specific one wins; all of them win over `00_user_config.cfg`. Values
must be plain numbers. Wrong names or values are reported in the console and
ignored.

## Console commands

Type these in the Fluidd/Mainsail console:

| Command | What it does |
|---|---|
| `SET_OVERRIDE_ACTIVE VALUE=0` | Switch the overrides off without pulling the stick (`VALUE=1` switches them on again). |
| `APPLY_MATERIAL_Z_OFFSET MATERIAL=PETG BED_TYPE="High Temp Plate"` | Shows and applies the Z-offset for that combination (only outside a print). |
| `K2_CLEAR_MESH_CACHE` | Deletes all cached meshes (never the `default` profile). |
| `K2_CLEAR_MESH_CACHE FILTER=70c` | Deletes only the cached meshes whose name contains `70c`. |

## What you see during a print

All messages start with `[K2_OVERRIDES]`. A typical start:

```
[K2_OVERRIDES] Plan: PETG on High Temp Plate, bed 70C, mesh load bed_mesh_70c_0c_high_temp_plate, soak 5.0 min, Z-offset 0.007
[K2_OVERRIDES] Heat soak: bed to 70C, then 5.0 min, print paused meanwhile
[K2_OVERRIDES] Bed at 70C, soaking 5.0 min
[K2_OVERRIDES] Heat soak: 4 min left
...
[K2_OVERRIDES] Loading cached mesh: bed_mesh_70c_0c_high_temp_plate
[K2_OVERRIDES] Z-offset for PETG on High Temp Plate: 0.007
```

The `Plan:` line sums up everything decided for this print. During the soak
the printer shows the print as **paused**; that is intended.

- **Cancel** works at any time during the soak and takes effect within about
  a second.
- **Resume** (touchscreen, slicer or Fluidd) during the soak skips the rest of
  it: the printer starts homing and probing right away and continues the print.
  The touchscreen and the slicer show a spinner until the print runs.

## Updating and firmware updates

**Changed a setting or got a new version of this project:** pull the stick,
copy the changed files onto it on your computer and plug it back in. For a new
version, download the ZIP again as in [installation step 1](#1-prepare-the-usb-stick)
and keep your own `00_user_config.cfg`. The
printer applies them automatically and only restarts Klipper if something
actually changed. If a new version renames or removes files, delete the old ones
from the stick as well; the printer-side copies are cleaned up automatically.

With the stick left in the printer, the same works over the network:

```sh
scp -O -r k2-overrides root@<printer-ip>:/mnt/exUDISK/
ssh root@<printer-ip> "sh /mnt/exUDISK/k2-overrides/scripts/bootstrap.sh"
```

(`scp` needs `-O` because the printer has no SFTP server.)

**After a firmware update or factory reset:** before the next print, make sure
the bootstrap ran once:

- **The trigger scripts survived** (the update to V1.1.7.0 kept them, and the
  printer's config too, but replaced Creality's `gcode_macro.cfg`): reboot with
  the stick plugged in, or re-plug it. The bootstrap notices that
  `gcode_macro.cfg` is Creality's original again and reinstalls the overrides
  (`logread | grep k2-overrides` shows `gcode_macro.cfg is stock again`).
- **Everything was wiped** (factory reset): run the bootstrap once by hand, as
  in [installation step 2](#2-plug-it-in-and-run-the-bootstrap-once).

Cached meshes that are gone get measured again on the first prints.

## Troubleshooting

**Check the log first:**

```sh
ssh root@<printer-ip> "logread | grep k2-overrides"
```

| Problem | What to do |
|---|---|
| The stick isn't recognized after pulling and re-plugging it (the display shows it empty) | The previous unplug didn't unmount it cleanly. Restart the printer with the stick plugged in. |
| Nothing happens when plugging in the stick | Is the folder called exactly `k2-overrides` and on the root of the stick? Is the stick mounted (`ssh root@<printer-ip> "mount | grep exUDISK"`)? Was the bootstrap run once by hand ([installation step 2](#2-plug-it-in-and-run-the-bootstrap-once)), and again after the last firmware update? |
| Klipper shows an error after plugging in | The log shows `Klipper not ready after restart: ...` with the reason; `klippy.log` (Fluidd → logs) has the details. To get back to stock quickly, see [Uninstalling](#uninstalling). |
| `Unknown command ..._STOCK` | A stock macro wasn't renamed. Run `ssh root@<printer-ip> "rm /mnt/UDISK/.k2-overrides/version"` and the bootstrap again. |
| Z-offset or soak ignore the material/plate | Does the `Plan:` line show your material and plate? If not, check the [slicer setup](#slicer-setup). Plate names must match exactly, including upper/lower case. |
| A setting shows `0` unexpectedly | A per-plate entry without its own `'default'`, see [Configuration](#configuration). |
| `ERROR: ...` lines at the print start | A `K2_` parameter or `MATERIAL`/`BED_TYPE` value was rejected; the line says why. |

## Uninstalling

**Temporarily:** pull the stick (or `SET_OVERRIDE_ACTIVE VALUE=0`). The printer
behaves like stock.

**Completely:** with the stick plugged in and no print running, run

```sh
ssh root@<printer-ip> "sh /mnt/exUDISK/k2-overrides/scripts/uninstall.sh"
```

It removes the trigger scripts, the cached mesh profiles (`bed_mesh_*`), the
includes and files in the printer's config and gives the stock macros their
names back, then restarts Klipper. Afterwards the stick does nothing anymore,
even when plugged in; delete the `k2-overrides` folder from it whenever you
like. A factory reset removes everything as well.

## Known limitations

- Only tested on the K2 Plus with firmware V1.1.6.4 and V1.1.7.0. The K2 and K2
  Pro use the same Klipper firmware family and might work, but are untested;
  feedback is welcome. If the stock macros differ, the bootstrap stops with a warning in
  the log and the printer stays stock.
- Creality's calibration always overwrites the `default` mesh profile as well;
  that is firmware behavior.
- The chamber temperature is part of the mesh profile name but is currently
  always `0` unless your start G-code sets a chamber target.

---

Background, design decisions and firmware findings: [docs/DESIGN.md](docs/DESIGN.md).

Licensed under the [MIT License](LICENSE). Not affiliated with Creality.
