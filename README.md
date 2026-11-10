# OpenFM

An open-source six-operator FM synthesizer for iPhone and iPad.

OpenFM pairs the classic 32-algorithm, six-operator FM voice with a
touch-first interface: you drag the operators in the routing diagram, pull
envelope handles, and move a point around an effect pad. Whatever you touch
lights up together with everything it affects, and a readout says in plain
words what that parameter does in the current patch.

It runs standalone — plug into speakers, a mixer or an audio interface and
play it from the screen or any MIDI keyboard — and as an AUv3 instrument
inside hosts such as GarageBand, AUM, Logic Pro for iPad and Cubasis.

Status: pre-release. Free, no ads, no subscriptions. Apache 2.0.

## Features

- Six operators, 32 algorithms, 16 voices
- Live routing diagram: drag an operator up/down for level, sideways for
  ratio, double-tap to switch it on or off
- Draggable four-stage envelopes for every operator and for pitch
- LFO (six waves, delay, pitch and amplitude depth), feedback, velocity
  sensitivity, keyboard level and rate scaling
- Chorus, ping-pong delay and reverb on XY pads
- One-cycle waveform preview and a live oscilloscope
- Four-layer loop recorder: each layer keeps the sound it was recorded with
- Multi-touch keyboard with velocity by touch position, an octave dial and a latching hold
- CoreMIDI input from every connected source, plus an "OpenFM" virtual
  destination for other apps
- AUv3 instrument with a full parameter tree for host automation and state
  save/restore
- Play mode with four shape macros for people who just want to play; the full editor behind one switch
- Import DX7 SysEx (bulk and single voices) and OpenFM patch files; share any sound as a file
- Presets saved as readable JSON; an original factory bank
- Replaceable interface: the UI is its own module on a small public API

**New to FM?** The [guide](web/app/guide/page.tsx) on the project site explains every control, lets you
hear FM in the browser and walks through building an industrial bass and lead.

## Building

Requirements: Xcode 27 or later (iOS 18 or later to run), [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
xcodegen generate          # creates OpenFM.xcodeproj from project.yml
open OpenFM.xcodeproj
```

Pick the **OpenFM** scheme and run. To put it on a device, select your team
under Signing & Capabilities for both the `OpenFM` and `OpenFMAU` targets and
change the `org.openfm` bundle identifier prefix to one you own.

From the command line:

```sh
Tools/build.sh                 # build for the simulator, print errors only
Tools/build.sh test            # unit tests and gesture UI tests
Tools/shot.sh "iPad Pro 11-inch (M5)" out.png -openfm.page effects
```

The engine also builds on its own, which is handy when working on DSP:

```sh
E=OpenFMKit/Sources/OpenFMEngine
clang++ -std=c++20 -O2 -I$E -I$E/msfa Tools/render_check.cpp \
  $E/*.cpp $E/msfa/*.cc -o /tmp/render_check && /tmp/render_check
```

## Layout

OpenFM is three layers, and each one only knows about the layer below it:

```
interface      OpenFMInterface (shipping UI) · OpenFMMinimalInterface (example) · yours
logic          OpenFMCore    — parameters, patches, presets, macros, audio + MIDI hosting
engine         OpenFMEngine  — C++ DSP and the AUAudioUnit
```

| Path | What lives there |
| --- | --- |
| `OpenFMKit/Sources/OpenFMEngine/` | C++ engine, effects, `OpenFMAudioUnit`; `msfa/` is Google's FM core (Apache 2.0) with small marked changes |
| `OpenFMKit/Sources/OpenFMCore/` | The public Swift API every interface is built on |
| `OpenFMKit/Sources/OpenFMInterface/` | The standard SwiftUI interface |
| `OpenFMKit/Sources/OpenFMMinimalInterface/` | A complete interface in one file, meant to be copied |
| `OpenFMKit/Tests/` | XCTest unit tests; engine tests drive the real audio unit offline |
| `App/`, `AUv3/` | Thin shells: start a session, show an interface |
| `UITests/` | Gesture tests that drag real controls in the simulator |
| `web/` | The project website and guide (Next.js) |

The layers are separate modules, so the compiler keeps an interface from
reaching into the engine. **To build your own interface, read
[docs/INTERFACES.md](docs/INTERFACES.md)** — it is one view, one initializer
and one line changed in the app. [AGENTS.md](AGENTS.md) has the same rules in
a form AI coding assistants can follow.

The standalone app has no separate audio path: it runs the same
`OpenFMAudioUnit` in-process and pulls it from the hardware output, so the app
and the plug-in always sound the same.

### Simple and deep

The interface opens in **Play**: the sound's name, a live scope, four shape
macros (Tone, Attack, Decay, Release), chorus/echo/reverb/volume, Sounds and
Import. **Edit** is one tap away and shows everything — routing, operators,
envelopes, LFO, effects — with the rarely used sections folded.

### Importing sounds

Import from the Play page or the browser, or open a file in OpenFM from Files
or AirDrop. Formats are a list (`PatchFormats.all`): DX7 SysEx and OpenFM's
own `.openfmpatch` JSON today; adding another synth's format is one type.

### Realtime rules

`Engine::render` and everything it calls must not allocate, lock or block.
Parameters cross threads through atomics, notes through wait-free
single-producer queues. Memory for effects is allocated in `prepare()`.
Please keep it that way; see [CONTRIBUTING.md](CONTRIBUTING.md).

## Website

`web/` is a Next.js site: a landing page and an interactive guide.

```sh
cd web && npm install && npm run dev
```

To deploy on Vercel, import this repository and set the project's **Root Directory** to `web`.
Screenshots in `web/public/screens` are taken with `Tools/shot.sh`.

## Preset format

User presets are stored in `Application Support/UserPresets.json`. A patch
looks like this (values use DX7 ranges; operators are listed OP1 first):

```json
{
  "format": "openfm.patch", "version": 1,
  "name": "Glass Keys", "category": "Keys",
  "algorithm": 5, "feedback": 5, "keySync": true, "transpose": 0,
  "operators": [ { "on": true, "level": 99, "fixed": false, "coarse": 1, "fine": 0,
                   "detune": 0, "envelope": { "rates": [96, 28, 22, 62], "levels": [99, 80, 0, 0] },
                   "velocity": 2, "ampModSens": 0, "rateScaling": 0, "breakpoint": 39,
                   "leftDepth": 0, "rightDepth": 0, "leftCurve": 0, "rightCurve": 0 } ],
  "pitchEnvelope": { "rates": [99, 99, 99, 99], "levels": [50, 50, 50, 50] },
  "lfo": { "wave": 0, "speed": 35, "delay": 0, "pitchDepth": 0, "ampDepth": 0, "keySync": true, "pitchSens": 3 },
  "effects": { "chorusMix": 0.3, "chorusRate": 0.6, "chorusDepth": 0.5, "delayMix": 0, "delayTime": 0.35,
               "delayFeedback": 0.35, "reverbMix": 0.22, "reverbSize": 0.5, "reverbDamping": 0.4 }
}
```

## Known limitations

- All engines in one process share lookup tables, so several plug-in
  instances in the same host must run at the same sample rate (they normally do).
- Pitch-envelope edits apply from the next note; other edits are heard on
  held notes immediately.
- The AUv3 extension keeps its own user presets; sharing them with the app
  needs an App Group, which requires a developer team.
- Bluetooth MIDI devices must be paired in another app or in Settings first.
- Factory presets are not yet exposed to hosts as AU factory presets.

## Roadmap

MPE, a modulation matrix, custom algorithms, a step sequencer, wavetable
operators, SysEx export and hardware integration.

## License and credits

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).

The FM core is [MSFA](https://github.com/google/music-synthesizer-for-android)
by Google. [Dexed](https://github.com/asb2m10/dexed) was a reference for
behaviour only; no Dexed code (GPL) is included. OpenFM contains no Yamaha or
M-VAVE firmware or factory voices.
