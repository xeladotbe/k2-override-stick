# Design notes

How the override stick works inside, and the Klipper/firmware facts behind the
decisions. For installation and configuration see the [README](../README.md).

- [Repository layout](#repository-layout)
- [Stick, bootstrap and boot](#stick-bootstrap-and-boot)
- [How a print runs](#how-a-print-runs)
- [Hooks into the stock macros](#hooks-into-the-stock-macros)
- [Settings resolution](#settings-resolution)
- [Warm restart](#warm-restart)
- [Klipper and firmware facts](#klipper-and-firmware-facts)
- [Development](#development)

## Repository layout

```
k2-override-stick/
├── k2-overrides/                 # goes onto the stick root, folder name is the marker
│   ├── scripts/
│   │   ├── bootstrap.sh          # applies the stick (hotplug "add", boot script, manual)
│   │   ├── teardown.sh           # switches the overrides off (cached on the printer)
│   │   ├── uninstall.sh          # undoes everything bootstrap.sh did, mesh cache included (manual)
│   │   ├── common.sh             # Moonraker HTTP helpers over nc (no curl/wget on the printer)
│   │   └── printer/              # installed onto the printer by bootstrap.sh
│   │       ├── hotplug.sh        # → /etc/hotplug.d/block/95-k2-overrides
│   │       └── init.sh           # → /etc/init.d/k2-overrides (procd rc.common, START=99)
│   │   └── user_config_template.cfg  # copied to 00_user_config.cfg on the stick when missing
│   ├── 00_defaults.cfg           # USER_CONFIG with every setting's default
│   ├── 00_state.cfg              # save_variables, SET_OVERRIDE_ACTIVE, per-print state _K2 + helpers
│   ├── 00_user_config.cfg        # the user's USER_CONFIG overrides (not in git, created by bootstrap.sh)
│   ├── 10_print_plan.cfg         # _K2_PLAN
│   ├── 20_bed_mesh.cfg           # BED_MESH_CALIBRATE / BED_MESH_CALIBRATE_START_PRINT hooks, K2_CLEAR_MESH_CACHE
│   ├── 30_print_flow.cfg         # START_PRINT, soak, start sequence, Z-offset
│   └── 40_print_hooks.cfg        # END_PRINT, PRINT_PREPARE_CLEAR, RESUME_EXTERNAL_PROCESS, PRINT_TEMP_SET
├── LICENSE
└── docs/DESIGN.md
```

## Stick, bootstrap and boot

A firmware update can wipe `/mnt/UDISK` (including `printer_data/config`) and
`/etc`; the V1.1.6.4 → V1.1.7.0 update instead kept `/mnt/UDISK` (our copies,
includes, mesh profiles, version file) and only replaced `gcode_macro.cfg`,
which undid our renames. Bootstrap handles both. Everything lives on the stick; the printer keeps only the two trigger
scripts in `/etc` and a cache in `/mnt/UDISK/.k2-overrides`. `bootstrap.sh`
installs the trigger scripts itself, so a new or reset printer needs one manual
bootstrap run and nothing else.

Klipper macros can't be unloaded at runtime, so the copied files stay on the
printer. On/off is the persistent `save_variables` key `override_active`, set
by `SET_OVERRIDE_ACTIVE`; with 0, every override passes straight through to
stock (`START_PRINT` checks it, all other hooks only act inside our own flow).

**Triggers.** The hotplug script reacts to `sd*` add/remove. On add it waits
for the mount at `/mnt/exUDISK` and runs `bootstrap.sh` from the stick in the
background; on remove it runs the cached `teardown.sh`. The boot script covers
what hotplug can't: at power-on the "add" may fire before Klipper/Moonraker are
up (or not at all), and a stick pulled while the printer was off never sends
"remove". At boot it waits for the mount and runs `bootstrap.sh` (stick present)
or `teardown.sh` (no stick).

**`bootstrap.sh`**, in order:

1. Re-runs itself from a private copy in `/tmp/k2-overrides-run.<pid>` (removed
   on exit). A shell keeps its script open, and a stick with open files can't
   be unmounted when pulled: it then stays mounted as a dead `sda1` and the
   next plug-in comes up as `sdb` and isn't mounted at all (seen once on
   hardware 2026-09-29; a reboot clears it). Then the lock
   (`/tmp/k2-overrides.lock`, tmpfs, so a stale lock can't survive a reboot):
   hotplug, boot script and manual runs can overlap.
2. Installs `scripts/printer/hotplug.sh` and `init.sh` into `/etc` if missing or
   different (copy, `chmod`, atomic `mv`) and enables the boot script if
   `/etc/rc.d` has no link yet.
3. Waits until Klipper has left its startup phase, also when it is in `error`
   (so a broken config can still be repaired). Then stops without changing
   anything if a print runs or is paused: the restart in step 10 would kill it.
4. Backup of the pristine `gcode_macro.cfg` as `.k2-overrides/gcode_macro.cfg.orig`
   whenever it has no `_STOCK` section of ours (first run, or after a firmware
   update replaced it); in that case the migrations are replayed from 0 even if
   the version file survived.
5. **Migrations**: numbered, ordered renames of stock macro sections in
   `gcode_macro.cfg` (`[gcode_macro X]` → `[gcode_macro X_STOCK]`), tracked in
   `.k2-overrides/version`. A number, once shipped, is never redefined; a
   correction gets a new number (a stick already at that version would skip a
   redefined one). Each rename is idempotent.

   | # | Renamed |
   |---|---|
   | 1 | `START_PRINT`, `PRINT_PREPARE_CLEAR`, `BED_MESH_CALIBRATE_START_PRINT`, `END_PRINT`, `RESUME_EXTERNAL_PROCESS`, `PRINT_TEMP_SET` |

6. Creates `00_user_config.cfg` on the stick from `user_config_template.cfg`
   if it is missing, then syncs every `*.cfg` from the stick into
   `config/custom/` (only if the content differs).
7. Removes retired files: a manifest (`.k2-overrides/installed.list`) lists
   what bootstrap installed; a file in it that is gone from the stick loses its
   copy and its include. Files someone else put into `custom/` are never
   touched.
8. One literal `[include custom/<name>.cfg]` per file in `printer.cfg`, in
   file name order, as one block **before** the `#*# <---- SAVE_CONFIG ---->`
   trailer (see facts below for both). If any is missing or out of order, the
   block is rewritten: `00_user_config.cfg` must be read after
   `00_defaults.cfg` (see Settings resolution), and a file added later would
   otherwise land at the end.
9. Caches `teardown.sh` + `common.sh` on the printer (the stick is gone when
   they are needed).
10. `FIRMWARE_RESTART` via Moonraker if anything changed, waits for `ready`
   (logs Klipper's `state_message` if it doesn't come back), then
   `SET_OVERRIDE_ACTIVE VALUE=1`.

`uninstall.sh` reverses this (same `/tmp` copy and lock, refuses during a
print): triggers first, so a plugged-in stick can't set things up again, then
`K2_CLEAR_MESH_CACHE` while our macros are still loaded, then every
`[gcode_macro X_STOCK]` back to `X` (rather than restoring the `.orig` backup,
which may predate a firmware update), the manifest's includes and files,
`.variables.cfg`, `.k2-overrides/`, and a `FIRMWARE_RESTART`.

Bootstrap logs through `logger` only: `logread | grep k2-overrides`.

## How a print runs

All per-print state is in one macro, `_K2` (`00_state.cfg`): `plan` (written
once by `_K2_PLAN`, only read afterwards) and `phase`:

```
idle ─(app's Print Calibration)─> app_mesh ─┐
idle ─────────────── START_PRINT ───────────┴─> heating ─> soaking ─> starting ─> printing ─> idle
                                (no soak: straight to starting)      END_PRINT / any abort ─> idle
```

1. **`START_PRINT`** (stock renamed to `START_PRINT_STOCK`): with the stick off
   it runs the stock macro. Otherwise `_K2_PLAN {rawparams}`, then
   `_K2_BEGIN`. Klipper renders each line only when it is dispatched, so the
   second line already sees the plan; that is how "return values" work here.
2. **`_K2_PLAN`** (`10_print_plan.cfg`) decides everything once: validates
   `MATERIAL`/`BED_TYPE` and the `K2_*` params, resolves the settings, the bed
   temperatures, whether the print is small (shoelace area over the
   `exclude_object` polygons against the probed area from `[bed_mesh]`
   `mesh_min`/`mesh_max`; if that can't be read, no print counts as small,
   with a warning, since a guessed bed size would skip soaks on a smaller
   bed; the app emits
   `EXCLUDE_OBJECT_DEFINE` before `START_PRINT`), the mesh profile
   `bed_mesh_<bed>c_<chamber>c_<plate>`, the mesh action and the soak:
   - `stock`: the app measured while preparing this job (`_K2.fresh_mesh`,
     see Firmware behavior), or phase `app_mesh` on older firmware; no
     mesh step, no soak.
   - `adaptive`: small print with `small_print_adaptive_mesh: 1`; calibration
     with `GCODE_FILE=` around the print, no cache, no soak.
   - `load`: the profile exists (a small print then skips the soak).
   - `calibrate`: no profile yet; calibrated with `PROFILE=<name>`.

   It logs one `Plan:` line and one `ERROR:` line per rejected param.
3. **`_K2_BEGIN`**: with a soak it sets the bed target and the nozzle to the
   stock clear temperature (`custom_macro.g28_ext_temp`, 140 °C), raises
   `idle_timeout` if needed, pauses the print (`PAUSE_BASE`) and starts
   `_K2_TICK`. Without a soak it goes straight to `_K2_CONTINUE`.
4. **`_K2_TICK`** (`delayed_gcode`, every second): `heating` until the bed is
   within 1 °C of the target, then `soaking` counts down (one line per minute).
   Then `_K2_FINISH_WAIT` (stops the tick, restores `idle_timeout`, runs
   `_K2_CONTINUE`, re-saves `PAUSE_STATE`) and `RESUME_BASE`. A resume pressed
   during the wait runs `_K2_FINISH_WAIT` early (see hooks). Once the phase is
   past the wait, a tick that was still pending does nothing; if the print was
   resumed behind our back, it resets and stops.
5. **`_K2_CONTINUE`**: phase `starting`, Creality's
   `BED_MESH_CALIBRATE_START_PRINT_STOCK` (homing, nozzle clean, mesh; its
   `BED_MESH_CALIBRATE` call follows the plan), `START_PRINT_STOCK`, then
   `_K2_FINALIZE`: re-loads our mesh profile if another one is active (after a
   calibration it is `default`, since Creality saves the result there too and
   leaves that one active; seen on hardware, a cached load stays active),
   applies the Z-offset,
   phase `printing`. Only `BED_TEMP=`/`EXTRUDER_TEMP=` numbers are forwarded
   to the stock macros, never the original params.
6. **`END_PRINT`** (stock renamed): `_K2_RESET` (stops the tick, restores
   `idle_timeout`, records the warm-restart data, phase `idle`, empty plan),
   then the stock macro.

## Hooks into the stock macros

| Hook | How | Why there |
|---|---|---|
| `START_PRINT` | section renamed (migration 1) | entry point |
| `BED_MESH_CALIBRATE` | `rename_existing` (real built-in) | follows the plan only in phase `starting`; a manual `G29` or the app's calibration always calibrates normally |
| `BED_MESH_CALIBRATE_START_PRINT` | renamed (migration 1) | older firmware's app calls it for "Print Calibration" (before `START_PRINT`); sets phase `app_mesh`, runs stock, so `START_PRINT` skips its mesh step. Current firmware uses `G29` instead, detected via `_K2.fresh_mesh` (see Firmware behavior) |
| `END_PRINT` | renamed (migration 1) | stock `CANCEL_PRINT` calls it first, so it also sees a cancel |
| `PRINT_PREPARE_CLEAR` | renamed (migration 1) | `END_PRINT_STOCK`, `MOTOR_CANCEL_PRINT` (bypasses `END_PRINT`; probably Creality's cancel on motor/collision errors) and `START_PRINT_STOCK` call it; outside phase `starting` it means the print ended or was aborted → `_K2_RESET`. Safety net for every abort path that skips `END_PRINT`: an armed soak timer would otherwise later run the whole start sequence on an idle printer |
| `RESUME_EXTERNAL_PROCESS` | renamed (migration 1) | stock `RESUME` (touchscreen, slicer, Moonraker) runs it before `RESUME_BASE`. During the soak wait it runs `_K2_FINISH_WAIT` (start sequence) instead of the stock part, so `RESUME_BASE` then continues a fully started print: resume = skip the rest of the soak. While our print runs unpaused (resume pressed during the start sequence, queued behind it) it skips the stock part, which would otherwise extrude ~80 mm. Otherwise stock. An earlier version raised an error to block the resume: the touchscreen and the slicer then showed a spinner with no controls until the soak ended, since they wait for `RESUME_BASE`'s confirmation (`key602`) |
| `PRINT_TEMP_SET` | renamed (migration 1) | the app calls it only while preparing a print job, before its own calibration; sets `_K2.job_prepared` so that calibration marks a fresh mesh (see Firmware behavior) |

`CANCEL_PRINT` and `RESUME` can't be hooked themselves: see
[`rename_existing` and renamed sections](#rename_existing-and-renamed-sections).

## Settings resolution

`USER_CONFIG` is defined twice: `00_defaults.cfg` with every setting, then
the user's `00_user_config.cfg`. Klipper merges same-named sections key by key
(later file wins), so the user file overrides whole settings, never parts of
one. It is git-ignored and only created on the stick, so an update can't
overwrite it.

For every setting in `USER_CONFIG`:
`[MATERIAL][BED_TYPE]` → `[MATERIAL]['default']` → top-level `'default'`
(→ `[BED_TYPE]` / `['default']` inside it, if it is a dict).
Known gap: a material's per-plate dict without its own `'default'` falls back
to the top-level `'default'` as a whole; if that is a dict too, the value
becomes `0` (Jinja's `|float` on a dict). The README asks to give a per-plate
top-level `'default'` its own `'default'`.

Then the `K2_*` params from the `START_PRINT` line win, most specific last:
`K2_<NAME>` < `K2_<NAME>_<M>` < `K2_<NAME>_<M>_<B>` (`<M>`/`<B>` upper case,
spaces and `-` → `_`). `..._DEFAULT` names are rejected on purpose (use the
material-wide name). Values: at most one leading `-` and one `.`, digits
otherwise. `MATERIAL`/`BED_TYPE`: letters, digits and ` _.+-` only, since they
end up in G-code lines and the stored plan. The `Plan:`/`Z-offset` lines name
the winning `K2_*` param, so a typo in the material or plate part shows up as a
missing "(K2_...)".

## Warm restart

`_K2_MARK_HOT` records when the bed reached temperature (in the tick when the
soak starts, otherwise at the end of the start sequence). `_K2_RESET`, at the
end of a print that got as far as `printing` (normal end, `CANCEL_PRINT`,
any abort that runs `END_PRINT`), stores the printer clock (`toolhead.estimated_print_time`),
the bed temperature and how long the bed was hot. `_K2_PLAN` then gives

```
credit = min(hot_time / soak, 1) * (1 - minutes_since_end / warm_restart_minutes)
soak   = soak * (1 - credit)
```

if the bed target is the same, the gap is shorter than `warm_restart_minutes`
and the bed is at most `warm_bed_tolerance` °C below the target. The clock is
the MCU clock and restarts with Klipper; the gap is then negative and the full
soak applies. Preheating from the display never counts (no finished print),
a print cancelled during its soak neither (never reached `printing`).

## Klipper and firmware facts

Each of these cost at least one failed attempt on the printer; the sources
checked are Creality's [K2_Series_Klipper](https://github.com/CrealityOfficial/K2_Series_Klipper)
(V1.1.3.13; the installed firmware is newer, some modules are closed source).

### Cancelling needs a paused print, not a waiting macro

Klipper holds one gcode mutex for a whole file line including every nested
macro, and `G4`/`M190`/`TEMPERATURE_WAIT` inside it don't release it
(`gcode.py`, `reactor.py`, `virtual_sdcard.py`). A `CANCEL_PRINT` just queued
behind a blocking soak until it was over. A `delayed_gcode` callback takes the
mutex only while it runs, so a cancel lands between two ticks; heating the bed
inside the ticks makes even the heat-up cancellable. The only true bypass is
`M112`, an emergency stop.

### Where the pause may happen

Creality's `BED_MESH_CALIBRATE_START_PRINT` unconditionally runs `G0 Z10` and
`CXSAVE_CONFIG` right after its `BED_MESH_CALIBRATE` line. Pausing from inside
it would run those against an unfinished mesh, so the pause sits in our
`START_PRINT`, before Creality's macro is called at all.

### `RESUME_BASE` restores the state from before the pause

`PAUSE_BASE` runs `SAVE_GCODE_STATE NAME=PAUSE_STATE`, `RESUME_BASE` runs
`RESTORE_GCODE_STATE NAME=PAUSE_STATE MOVE=1` (`pause_resume.py`): offsets and
position from *before* the start sequence. `_K2_TICK` re-saves `PAUSE_STATE`
right before `RESUME_BASE`; otherwise the Z-offset is dropped and the head
moves back. The app's and Moonraker's resume call the `RESUME` macro
(`run_script("RESUME")`).

### `idle_timeout`

This printer's own config sets it to 99999999 so long pauses never lose the
heaters. The soak only ever raises it (`max()`); an earlier version replaced it
with soak + 120 s and the heaters switched off mid-soak.

### `rename_existing` and renamed sections

- Same-named `[gcode_macro]` sections in different included files are merged
  key by key (the last file's `gcode:` wins), so `rename_existing` can't wrap a
  macro from another file (`Existing command 'START_PRINT' not found in
  gcode_macro rename`). It only works for real built-ins (`BED_MESH_CALIBRATE`,
  `PAUSE`, ...). Hence the physical renames in `gcode_macro.cfg`.
- `rename_existing` always renames the *declaring section's own name*. Stock
  `CANCEL_PRINT` and `RESUME` carry `rename_existing: CANCEL_PRINT_BASE` /
  `RESUME_BASE`; renaming those sections would leave the real built-in
  registered under the old name (`gcode command CANCEL_PRINT already
  registered`, printer halted once). So `END_PRINT` (first step of
  `CANCEL_PRINT`) and `RESUME_EXTERNAL_PROCESS` (first step of `RESUME`) are
  hooked instead.
- Stock `PRINT_PREPARED`/`BED_MESH_CALIBRATE_START_PRINT` read and write
  `START_PRINT.prepare`, so our `START_PRINT` must keep `variable_prepare`.

### `printer.cfg` includes

- A wildcard `[include custom/*.cfg]` loads, but every `SAVE_CONFIG`/
  `CXSAVE_CONFIG` afterwards fails (`Unable to parse existing config`): the
  re-read (`configfile.py _strip_include_duplicates`) doesn't expand the glob.
  Hence one literal include per file.
- Nothing may follow the `#*# <---- SAVE_CONFIG ---->` trailer; a blind append
  broke it (`Option 'z_offset' in section 'prtouch_v3' must be specified`).

### Jinja and G-code parsing on this firmware

- No `do` extension: `{% do x.append(y) %}` halts Klipper at load; use
  `{% set _ = x.append(y) %}`.
- A filter result can't be followed by a method call:
  `(x|join('')).isdigit()`, not `x|join('').isdigit()`.
- `set` inside a `for` doesn't leak out; mutate a dict or list instead.
- A macro can't call itself, not even through another macro (`Macro X called
  recursively`); sequential calls are fine.
- `action_respond_info` fires while the template renders, i.e. before any of
  the macro's commands run; log order can mislead.
- The config parser strips everything after `#` in every line, also inside
  `gcode:`.
- The G-code parser takes the whole first word as the command (names like
  `K2_...` are fine), cuts lines at `;`, and extended arguments end at `#`,
  `*` or `;`. Extended params are split with `shlex`, and `SET_GCODE_VARIABLE`
  additionally runs `ast.literal_eval` on the value. Forwarding the original
  params (`BED_TYPE="High Temp Plate"`) through stored variables needed two
  escaping layers and broke once; the plan now stores only validated strings
  and numbers.
- `[respond]` isn't configured: use `{action_respond_info(...)}`, not
  `RESPOND`.

### Firmware behavior

- Creality's calibration honors `PROFILE=` but also always saves the result as
  `default`.
- How the app prepares a print job (firmware V1.1.6.4, hardware tests
  2026-09-29 with temporary logging macros): it heats and homes, calls
  `PRINT_TEMP_SET EXTRUDER_TEMP=… BED_TEMP=…` (the job's temperatures), measures
  a fresh mesh with its own closed-source routine if "Print Calibration" is on
  (also without it for a PETG job at 70 °C; the reason is unknown), calls
  `PRINT_TEMP_SET … WAIT_TEMP=1`, `PRINT_PREPARED` (`START_PRINT.prepare=1`) and
  then starts the file (`START_PRINT`). Its measurement runs through
  `BED_MESH_CALIBRATE` (our hook) at the job's bed temperature, but it calls
  neither the `G29` nor the `PRINT_CALIBRATION` macro (`[G29_TIME]` in the log
  is Creality's Python code). `PRINT_PREPARED` comes before **every** print, so
  `prepare` can't tell a calibrated job from another (a version relying on it
  skipped the soak and cache on every print). While measuring, no job data is
  visible (`print_stats` standby, no file); Creality's
  `virtual_sdcard.bed_mesh_calibate_state` turns true after a calibration but
  stays true for later jobs without one.
- Manual actions don't call `PRINT_TEMP_SET`: setting a temperature from the
  display, the desktop app, the phone app or Fluidd, and leveling from the
  display (which runs the `G29` macro as `G29 BED_TEMP=0`, i.e. at 50 °C).
- Hence the job mark: our `PRINT_TEMP_SET` sets
  `_K2.job_prepared`; the `BED_MESH_CALIBRATE` hook sets `_K2.fresh_mesh` and
  `fresh_mesh_temp` (bed target) after a calibration outside our flow only while
  it is set. The next print keeps that mesh (no soak, no cache) only if it runs
  at that bed temperature and the bed is at most `warm_bed_tolerance` below it
  (the app's measurement turns the heaters off at its end); otherwise a console
  line says why not. `_K2_BEGIN` consumes both marks, any print end or abort
  (`_K2_RESET`) clears them. A time window after the calibration was tried and
  rejected as a guess.
- The app calls `WAIT_BED_STABLE_END`, which doesn't exist (`Unknown command`
  in the console, seen in a PETG job with Print Calibration); harmless.
- Older firmware's app was seen calling `BED_MESH_CALIBRATE_START_PRINT
  GCODE_FILE=...` (without `BED_TEMP`) for Print Calibration instead; that path
  sets phase `app_mesh`.
- `custom_macro.default_bed_temp` is 50 on this printer; Creality's mesh macro
  uses it unless `BED_TEMP` is passed and higher.
- Moonraker's `gcode_store` keeps only the last 1000 lines.
- The printer's BusyBox has neither `curl` nor `wget` (Moonraker is reached
  with `nc`, with `-w 15` if this `nc` supports it so a silent Moonraker can't
  hang the scripts), and no SFTP server (`scp -O`).
- `set -e` plus `VAR=$(cat missing_file)` ends a script silently; use
  `|| echo 0`.

## Development

Edit in the repo, copy to the stick in the printer, run bootstrap:

```sh
scp -O -r k2-overrides root@<printer-ip>:/mnt/exUDISK/
ssh root@<printer-ip> "sh /mnt/exUDISK/k2-overrides/scripts/bootstrap.sh"
```

(Copy the folder into `/mnt/exUDISK/`, the stick root: with `/mnt/exUDISK/k2-overrides/` as the target, `scp -r` would nest a second `k2-overrides` inside. Works the same on Windows.)

Useful Moonraker queries, e.g. `http://<printer-ip>:7125/printer/objects/query?bed_mesh`,
`...?gcode_macro%20_K2` (current phase and plan), `/server/gcode_store`
(console history) and `/server/files/logs/klippy.log`.

Before deploying macro changes, render them locally with Jinja2
(`jinja2.Environment('{%', '%}', '{', '}')`, no extensions) and check the
generated lines with `shlex` and `ast.literal_eval`; a syntax error in any
macro halts Klipper at load.

Code style: at most four comment lines per macro, blank lines between logical
blocks inside `gcode:`, reasoning goes into this file.
