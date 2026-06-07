# G1Poc — Even Realities G1 Workout HUD for Garmin Smart Watches

A Garmin Connect IQ data field that streams live workout metrics to
[Even Realities G1](https://www.evenrealities.com/) smart glasses over BLE.
Displays heart rate, pace, cadence, elevation, and more — directly in your
field of view during a run, walk, or hike.

**License:** GPL-3.0, non-commercial use only. See `LICENSE`.

// SPDX-AI-Disclosure: ai-generated
// SPDX-AI-Model: claude-opus-4-7
// SPDX-AI-Provider: Anthropic
// SPDX-AI-Scope: Generated boilerplate; reviewed manually.

---

## Requirements

- **Garmin fenix 7** (tested device; other devices may work)
- Even Realities G1 glasses (G1 only — G2 uses a different protocol)
- Connect IQ SDK 8.4.0+ to build from source

---

## First-Time Pairing

**Step 1 — Disconnect the glasses from your phone.**
The G1 arms can only maintain one BLE connection at a time. While paired
to the Even Realities app, the arms will not advertise and the watch will
never find them. Disable Bluetooth on your phone or unpair in the app.

**Step 2 — Place both arms in the charging cradle.**
The cradle puts the arms into advertising mode. They will not advertise
while being worn.

**Step 3 — Start the data field on the watch.**
It scans, finds both arms, and pairs automatically. Watch the indicator:

| Colour | State |
|---|---|
| Grey L / R | Scanning |
| White L / R | Connected, initialising |
| Green L / R | Streaming |
| Red L / R | Arm bypassed after repeated failures |

**Step 4 — Put the glasses on.** Connection is maintained while worn.

On subsequent workouts the watch reconnects automatically — the cradle
is only needed for the very first pair.

> **If the glasses stop connecting:** place them in the cradle for 10
> seconds, then start a fresh activity. The watch clears stale bonds on
> startup and re-pairs cleanly.

When glasses battery is known, the lowest arm percentage is shown below
the L/R indicator in small text.

---

## HUD Modes

The data field detects your activity type automatically.

---

### Walk / Hike — Glance Mode

The glasses stay **off by default**. It only appears when you need it.

**Triggers:**
- Look up (head-up gesture)
- Press the lap button

**Sequence on trigger:**
1. Look up, Dahsboard appears breifly then fades
2. HUD appears for **12 seconds**
3. Screen blanks
4. **10-second lockout** before the dashboard re-enables (prevents
   accidental double-triggers)

The HUD refreshes each second while visible so stats stay live.

**Glance HUD:**
```
HR: 142 Z3
9:45 /mi
312 ft ^
4.21mi  1:02:15
```

| Line | Content |
|---|---|
| 1 | Heart rate + HR zone |
| 2 | Current pace |
| 3 | Total ascent |
| 4 | Total distance + elapsed time |

---

### Run — Continuous Streaming

The HUD streams continuously. Line 3 rotates every 10 seconds through
five metrics:

| Slot | Example | Notes |
|---|---|---|
| HR % of max | `87 HR%` | Uses your HR zone config |
| Cadence | `172 spm` | Steps per minute |
| Running power | `245w` | |
| Calories | `387 cal` | |
| Elevation gain | `89 ft ^` | |

**Run HUD:**
```
HR: 158 Z4
6:12 /mi
172 spm
3.50mi  21:44
```

---

### Structured Workout — Workout HUD

When a structured workout step is active, the HUD shows step-specific
targets and remaining time/distance.

**HR-targeted step:**
```
HR 158 [145-165]
6:30 /mi
3:12 left
2.10mi  14:22
```

**Pace-targeted step:**
```
HR 162 Z4
6:12 [5:45-6:30]
1:48 left
2.10mi  14:22
```

**Final 10 seconds of a step** — line 4 switches to next-step preview:
```
HR 161 Z4
6:08 /mi
0:09 left
--- Next: Run 2:00 ---
```

| Line | Content |
|---|---|
| 1 | HR with target range `[lo-hi]` if HR-targeted, else HR + zone |
| 2 | Pace with target range if pace-targeted |
| 3 | Time or distance remaining in this step |
| 4 | Distance + elapsed time; "Next: [step]" in final 10s |

> Remaining time is displayed ~2 seconds early to compensate for BLE
> transmission lag. It should align with the watch transition cue.

---

### End of Workout

Stopping the activity shows a summary for 8 seconds:

```
8.30mi  52:14
7:18 /mi avg
HR 154 avg
420 ft ^
```

Then the screen blanks and the dashboard re-enables.

---

## Battery Warnings

Battery is polled every ~5 minutes (`0x2C 0x01` query). When an arm
drops below 20% or 10% for the first time, the HUD is temporarily
replaced:

```
LOW BATTERY
L 18%   R 94%
```

Shows for ~6 seconds, then normal HUD resumes.

---

## Time Sync

On connection the watch sends local time to the glasses so the dashboard
clock stays accurate.

---

## Known Limitations

### 20-byte BLE write cap : the fundamental constraint

Garmin Connect IQ data fields are **hard-capped at 20 bytes per BLE
write** with no MTU negotiation API. This is enforced at the SDK level
and applies regardless of device type (watch app vs data field makes no
difference).

Consequences:
- Text frames split into **11-byte chunks** (9-byte protocol header + 11
  bytes of text = 20 bytes)
- A typical 4-line HUD requires 6–8 chunks
- Each `WRITE_TYPE_WITH_RESPONSE` write costs ~175ms (one BLE connection
  interval for the ACK round-trip)
- A full HUD frame takes **roughly 1–1.5 seconds to appear** on the
  glasses from the moment it is sent

This lag is fundamental. Phone apps and Python scripts using
`requestMtu(251)` can send an entire frame in one write and feel
instantaneous by comparison. There is nothing to be done on the Garmin
side.

Fire-and-forget commands (disable dashboard, etc.) use
`WRITE_TYPE_DEFAULT` (no ACK wait) to avoid stalling the queue
unnecessarily.

### No head-nod gesture events on Connect IQ

The G1 can push gesture events (nods, taps, worn/off) to phone apps,
but **these events never arrive in a Connect IQ data field**. Hundreds
of test combinations ruled out every configuration variable — encryption,
characteristic subscription, init sequence, display mode, feature
activation. The cause is the 20-byte MTU: G1 firmware
appears to withhold unsolicited push events from a default-MTU central
while still answering writes.

Head-up events **do** arrive on the dashboard channel (`0x22 0x0a`)
while the glasses are in dashboard mode. This is the signal used to
trigger the glance HUD. Do not chase gesture events - they will
not come.

### One BLE central at a time

The G1 arms accept only one BLE central connection. If your phone is
connected, the watch cannot connect. Disconnect from the phone before
starting an activity.

### Both arms must be driven independently

The glasses do not relay content between arms internally. Each arm
receives its own copy of every frame, interleaved chunk by chunk
(chunk 0 → left, chunk 0 → right, chunk 1 → left, …). This per-chunk
barrier keeps both lenses in lockstep. If only one arm is available,
the field falls back to single-arm display after ~8 seconds.

### Passive scan only

The fenix 7 performs passive BLE scans — active scan and scan filters
are not available in Connect IQ. Device names and the 128-bit NUS
service UUID are only visible in active scan responses, so the arms are
identified by **manufacturer-specific advertisement data**: 
ID `0x53xx`, low byte `0x01` = left, `0x02` = right.


### No `Toybox.Timer` in data fields

Data fields cannot use `Toybox.Timer` — it requires a permission not
granted to this app type. All periodic work (heartbeat, battery poll,
time sync, HUD refresh) is driven by `compute(info)`, which fires
approximately once per second.

### Structured workout step timing

Step start time is snapped when `onWorkoutStarted` or
`onWorkoutStepComplete` fires. If the watch and glasses are out of sync
at a transition, the remaining-time display can drift by a second
mid-step. The 2-second fudge factor helps but does not eliminate this.

---

## Building from Source

```bash
export PATH="$HOME/.Garmin/ConnectIQ/Sdks/<sdk-version>/bin:$PATH"
bash build.sh
# output: bin/G1Poc.prg
```

Requires a `developer_key.der` in the project root (generated once via
the Connect IQ SDK tools).

## Files

```
manifest.xml        app manifest (fenix7, BLE + UserProfile permissions)
build.sh            single-command build
source/PocBle.mc    all BLE logic, protocol, HUD construction
source/PocView.mc   data field view, timer callbacks
source/Metrics.mc   pure metric formatters (pace, distance, HR zone, elev)
source/Log.mc       on-screen + console logger
LICENSE             GPL-3.0 with non-commercial restriction
```
