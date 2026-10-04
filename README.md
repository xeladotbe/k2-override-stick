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
- [Manual installation (without stick or SSH)](#manual-installation-without-stick-or-ssh)
- [Slicer setup](#slicer-setup)
- [Configuration](#configuration)
- [Per-print overrides](#per-print-overrides)
- [Per-filament Z-offset](#per-filament-z-offset)
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
3. Optionally create your own settings (see [Configuration](#configuration)).
   You can also do that later; without them the defaults apply.

The stick then looks like this (`00_user_config.cfg` appears after the first
bootstrap if you didn't create it yourself):

```
<stick>/
└── k2-overrides/
    ├── scripts/
    │   ├── bootstrap.sh
    │   ├── teardown.sh
    │   ├── uninstall.sh
    │   ├── common.sh
    │   └── printer/            ← trigger scripts, installed on the printer by bootstrap.sh
    ├── 00_defaults.cfg         ← all settings with their defaults, don't edit
    ├── 00_state.cfg
    ├── 00_user_config.cfg      ← your settings
    ├── 00_user_config.cfg.example  ← every setting explained, template for the above
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

While a print runs, the bootstrap changes nothing (its Klipper restart would
end the print). A Klipper that has shut down doesn't count as printing. To run
it anyway, add `-f`: `sh /mnt/exUDISK/k2-overrides/scripts/bootstrap.sh -f`.

### 3. Set up the slicer

See the next section. Without it, everything still works, but without material-
and plate-specific values.

## Manual installation (without stick or SSH)

Everything the bootstrap does can also be done by hand in Fluidd or Mainsail,
without a stick and without SSH. The catch: **nothing repairs itself.** A
firmware update that resets Creality's files leaves the printer unable to
start a print until you redo step 3 (see below). These steps do exactly what the
bootstrap does on the printer, but haven't been walked through by hand yet;
feedback is welcome.

1. **Download** this repository as a ZIP (**Code → Download ZIP**) and unpack
   it on your computer.
2. **Upload the files.** In Fluidd/Mainsail open the configuration files, create
   a folder `custom` and upload into it every `.cfg` file from the
   `k2-overrides` folder (`00_defaults.cfg`, `00_state.cfg`,
   `10_print_plan.cfg`, `20_bed_mesh.cfg`, `30_print_flow.cfg`,
   `40_print_hooks.cfg`). Also upload `00_user_config.cfg.example` and rename
   it to `00_user_config.cfg`; it explains every setting. The `scripts` folder
   isn't needed.
3. **Rename six stock macros.** Download `gcode_macro.cfg` once as a backup,
   then open it and change only these six section headers:

   | Before | After |
   |---|---|
   | `[gcode_macro START_PRINT]` | `[gcode_macro START_PRINT_STOCK]` |
   | `[gcode_macro PRINT_PREPARE_CLEAR]` | `[gcode_macro PRINT_PREPARE_CLEAR_STOCK]` |
   | `[gcode_macro BED_MESH_CALIBRATE_START_PRINT]` | `[gcode_macro BED_MESH_CALIBRATE_START_PRINT_STOCK]` |
   | `[gcode_macro END_PRINT]` | `[gcode_macro END_PRINT_STOCK]` |
   | `[gcode_macro RESUME_EXTERNAL_PROCESS]` | `[gcode_macro RESUME_EXTERNAL_PROCESS_STOCK]` |
   | `[gcode_macro PRINT_TEMP_SET]` | `[gcode_macro PRINT_TEMP_SET_STOCK]` |

   Don't rename anything else, in particular not `CANCEL_PRINT` or `RESUME`.
4. **Include the files.** Open `printer.cfg` and add these lines, in this
   order, right above the `#*# <---------------------- SAVE_CONFIG ---------------------->`
   line (or at the end of the file if there is none):

   ```
   [include custom/00_defaults.cfg]
   [include custom/00_state.cfg]
   [include custom/00_user_config.cfg]
   [include custom/10_print_plan.cfg]
   [include custom/20_bed_mesh.cfg]
   [include custom/30_print_flow.cfg]
   [include custom/40_print_hooks.cfg]
   ```

   The order matters: `00_user_config.cfg` must come after `00_defaults.cfg`.
5. **Switch on.** Create the file `custom/.variables.cfg` with this content
   (without it, the printer behaves like stock):

   ```
   [Variables]
   override_active = 1
   ```

   Fluidd/Mainsail may hide files starting with a dot; they show up with
   "show hidden files". Instead of creating the file you can also run
   `SET_OVERRIDE_ACTIVE VALUE=1` in the console after step 6, which writes it.
6. **Restart.** Save and run `FIRMWARE_RESTART` in the console. The next print
   starts with a `[K2_OVERRIDES] Plan:` line in the console.

Then set up the slicer as below.

**Changing settings:** edit `custom/00_user_config.cfg` in Fluidd/Mainsail and
run `FIRMWARE_RESTART`.

**New version:** upload the new `.cfg` files over the old ones (not your
`00_user_config.cfg`), add includes for new files in the same order, and run
`FIRMWARE_RESTART`. Check the release notes for renamed macros.

**After every firmware update:** before the next print, open `gcode_macro.cfg`
and check that the six `_STOCK` names from step 3 are still there, and
`printer.cfg` for the includes from step 4. If the update restored Creality's
files, redo those steps. Otherwise the print stops with
`Unknown command "START_PRINT_STOCK"`.

**Uninstalling:** run `K2_CLEAR_MESH_CACHE` in the console, remove the
includes from `printer.cfg`, rename the six sections back (or restore your
backup of `gcode_macro.cfg`), delete the `custom` folder's files from this
project (and `custom/.variables.cfg`), then `FIRMWARE_RESTART`.

Don't mix both ways: once a stick with `k2-overrides` is plugged in, the
bootstrap takes over and overwrites the files in `custom/` with the stick's.

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

Your settings go into `k2-overrides/00_user_config.cfg` on the stick. List only
what you want to change, everything else keeps its default from
`00_defaults.cfg`. The bootstrap creates the file from
`00_user_config.cfg.example` if it is missing; that file explains every
setting and how to write it. To write it yourself, start it with the section
header and end it with an empty `gcode:`:

```
[gcode_macro USER_CONFIG]
variable_z_offset: {
    'default': 0.05,
    'PETG': 0.03,
    }

gcode:
```

The file isn't part of the download, so a new version never overwrites it.

A setting you list replaces its default **completely**: with
`variable_soak_minutes: {'PETG': 8}` every other material gets no soak, since
the `'default': 5` is gone as well. Copy the whole setting from
`00_defaults.cfg` and change what you need.

Each setting can be

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

A plate that isn't listed uses the material's `'default'`, otherwise the outer
`'default'`. If the outer `'default'` is itself per plate, give it its own
`'default'` too, or plates it doesn't list get `0`.

### Settings

| Setting | Default | Meaning |
|---|---|---|
| `z_offset` | `0` | Z-offset in mm, applied at the end of the start sequence. Larger = nozzle farther from the bed. |
| `min_z_offset` | `-0.05` | Lowest Z-offset ever applied: `K2_FILAMENT_Z_OFFSET` clamps to it, and the mesh check measures again instead of shifting the Z-offset below it. |
| `soak_minutes` | `5` (ABS `10`) | Minutes to wait once the bed has reached its temperature. `0` = no soak. |
| `small_print_coverage_pct` | `0` (PLA `15`, PETG `10`) | A print is "small" if its objects cover less than this percentage of the bed. `0` = never small. Small prints skip the soak. |
| `small_print_adaptive_mesh` | `1` | For small prints: `1` = probe only around the print (no cache); `0` = use the cached full-bed mesh (the soak is only skipped if that mesh already exists). |
| `mesh_check_tolerance` | `0.025` | Before a cached mesh is used, up to 9 of its points over the print area (3x3) are probed. If they differ by more than this many mm on average, or one point by more than `mesh_check_point_factor` times that, the mesh is not used as it is (see the next two). `0` = load without checking. |
| `mesh_check_point_factor` | `1` | How far a single probed point may be off, as a multiple of `mesh_check_tolerance`. `1` = no point beyond the tolerance; `1.5` or `2` = more lenient. |
| `mesh_check_shape_tolerance` | `0.015` | If the probed points are all shifted by about the same amount (each within this many mm of their mean), the bed only moved: the cached mesh is used and the shift added to the Z-offset for this print. Never if the Z-offset would end up below `min_z_offset`, and not for shifts over 4x `mesh_check_tolerance`: then the bed is measured again and the cache replaced. `0` = always measure again. |
| `mesh_max_uses` | `20` | After a cached mesh was used in this many prints, it is measured again (the check only probes a few points). `0` = never. |

After editing, copy the file to the stick and apply it (see
[Updating](#updating-and-firmware-updates)).

### Bed mesh cache

For each combination of bed temperature and plate, the first print measures the
bed and saves the mesh as a profile, e.g. `bed_mesh_70c_0c_textured_pei_plate`
(bed 70 °C, chamber 0 °C). Later prints with the same combination load it
instead of probing the whole bed. First they probe up to 5 of its points over the
print area (about 15 seconds). If the bed has moved since, it gets measured again
and the cache is replaced. This happens, for example, right after a long print,
when the whole machine is warm (seen: 0.04–0.05 mm lower than after a short
warm-up). Small prints skip this check. Clear the cache after a nozzle change, a Z calibration or
when a plate looks different: see `K2_CLEAR_MESH_CACHE` under
[Console commands](#console-commands). A manual bed calibration (`G29`, or from
the display) always measures fresh and is not cached, and doesn't replace the
cache for the next print. When the app measures while preparing a print ("Print
Calibration"), that print uses the app's fresh mesh instead, without a soak.

### Changing settings later

The copy on the stick is the one that counts. Change it, then let the bootstrap
apply it. It restarts Klipper, so during a print it does nothing; apply the
change after the print.

- **Stick out:** pull the stick, edit `k2-overrides/00_user_config.cfg` on your
  computer and plug it back in. Plugging in runs the bootstrap automatically.
- **Stick in, over SSH:** edit the file on the stick and run the bootstrap:

  ```sh
  ssh root@<printer-ip>
  vi /mnt/exUDISK/k2-overrides/00_user_config.cfg
  sh /mnt/exUDISK/k2-overrides/scripts/bootstrap.sh
  ```

- **Stick in, edited on your computer:** copy the file over and run the bootstrap:

  ```sh
  scp -O k2-overrides/00_user_config.cfg root@<printer-ip>:/mnt/exUDISK/k2-overrides/
  ssh root@<printer-ip> "sh /mnt/exUDISK/k2-overrides/scripts/bootstrap.sh"
  ```

With a stick installation, don't edit `custom/00_user_config.cfg` in Fluidd or in the printer's config
folder: that is only a copy, and the next bootstrap overwrites it with the one
from the stick. To try a value for a single print, use a
[per-print override](#per-print-overrides) instead.

### Other Klipper settings

`00_user_config.cfg` is included after Creality's `printer.cfg`, so a Klipper
section in it overrides single options of the stock one. For example, a
tighter `Z_TILT_ADJUST` (it runs after every Klipper restart and in G29; stock
accepts up to 0.1 mm difference between left and right):

```
[z_tilt]
retry_tolerance: 0.05
```

Put it after the `gcode:` line of `[gcode_macro USER_CONFIG]`. Not below about
0.04: the probe scatters by about ±0.02 mm, and after 10 failed retries
`Z_TILT_ADJUST` stops with an error, and G29 or the print start with it.

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

## Per-filament Z-offset

The slicer only passes the material type (`PETG`), so all PETGs share one
Z-offset in `00_user_config.cfg`. Brands and variants (e.g. Hyper PETG vs. a
standard PETG) can still need different values, mostly because of different
print temperatures and flow. Calibrate the filament's flow ratio first; then
set the filament's own Z-offset in the **filament profile's start G-code** in
the slicer:

```
K2_FILAMENT_Z_OFFSET Z=0.045
```

It runs after the start sequence, right before the first layer, and replaces
the material's Z-offset for this print. A shift found by the mesh check is
added on top (a plain `SET_GCODE_OFFSET Z=` would drop it). Small negative
values are fine (e.g. `Z=-0.005`); if the result would be below `min_z_offset`
(default -0.05), it is set to that instead. Profiles without
the line use the material's value. Find the value with a Z-offset test print
of that filament.

Only the first call of a print counts, and only before the first layer. The
slicer repeats the filament start G-code at every filament change (CFS
multi-color prints); a new Z-offset there would shift all following layers, so
those calls are ignored (with a console note if the value differs). A
multi-filament print uses the Z-offset of the filament it starts with.

The value lives in the slicer profile, so keep your slicer profiles in sync on
every computer you print from (e.g. by exporting and importing them); the same
goes for the printer profile's `START_PRINT` line.

## Console commands

Type these in the Fluidd/Mainsail console:

| Command | What it does |
|---|---|
| `SET_OVERRIDE_ACTIVE VALUE=0` | Switch the overrides off without pulling the stick (`VALUE=1` switches them on again). |
| `APPLY_MATERIAL_Z_OFFSET MATERIAL=PETG BED_TYPE="High Temp Plate"` | Shows and applies the Z-offset for that combination (only outside a print). |
| `K2_STATUS` | Shows whether the overrides are active, the cached meshes with how many prints used them, and the last 10 mesh checks. |
| `K2_STATUS MATERIAL=PETG BED_TYPE="High Temp Plate" BED_TEMP=70` | The same, plus every setting as it resolves for that combination (outside a print). |
| `K2_CLEAR_MESH_CACHE` | Deletes all cached meshes (never the `default` profile). |
| `K2_CLEAR_MESH_CACHE FILTER=70c` | Deletes only the cached meshes whose name contains `70c`. |
| `K2_FILAMENT_Z_OFFSET Z=0.045` | Sets this print's Z-offset, keeping a mesh-check shift (meant for the filament profile's start G-code, see [Per-filament Z-offset](#per-filament-z-offset)). |

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

**Changed a setting:** see [Changing settings later](#changing-settings-later).

**Got a new version of this project:** download the ZIP again as in
[installation step 1](#1-prepare-the-usb-stick), pull the stick, copy the new
`k2-overrides` folder onto it and plug it back in. Your `00_user_config.cfg`
isn't in the download, so it stays as it is. The
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
| Nothing happens when plugging in the stick | Is the folder called exactly `k2-overrides` and on the root of the stick? Is the stick mounted (`ssh root@<printer-ip> "mount \| grep exUDISK"`)? Was the bootstrap run once by hand ([installation step 2](#2-plug-it-in-and-run-the-bootstrap-once)), and again after the last firmware update? |
| Klipper shows an error after plugging in | The log shows `Klipper not ready after restart: ...` with the reason; `klippy.log` (Fluidd → logs) has the details. To get back to stock quickly, see [Uninstalling](#uninstalling). |
| `Unknown command ..._STOCK` | A stock macro wasn't renamed, e.g. a firmware update restored Creality's `gcode_macro.cfg`. Stick installation: run `ssh root@<printer-ip> "rm /mnt/UDISK/.k2-overrides/version"` and the bootstrap again. Manual installation: redo [step 3](#manual-installation-without-stick-or-ssh). |
| Z-offset or soak ignore the material/plate | Does the `Plan:` line show your material and plate? If not, check the [slicer setup](#slicer-setup). Plate names must match exactly, including upper/lower case. |
| A setting shows `0` unexpectedly | Your `00_user_config.cfg` lists the setting without a `'default'` (it replaces the default completely), or an outer `'default'` per plate lacks its own `'default'`. See [Configuration](#configuration). |
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
