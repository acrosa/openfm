# Notes for AI coding assistants (and people in a hurry)

OpenFM is a six-operator FM synth for iOS. The code is split into three
modules in the `OpenFMKit` Swift package, and the split is the most important
thing to respect.

| Module | Language | Owns | May import |
| --- | --- | --- | --- |
| `OpenFMEngine` | C++, Objective-C++ | DSP, voices, effects, `OpenFMAudioUnit` | system frameworks |
| `OpenFMCore` | Swift | `Param`, `Patch`, `Algorithm`, `Macro`, `SynthModel`, `PresetStore`, patch formats, audio/MIDI hosting | `OpenFMEngine` |
| `OpenFMInterface`, `OpenFMMinimalInterface`, any new interface | SwiftUI | views only | `OpenFMCore` |

`App/` and `AUv3/` are thin shells that pick an interface.

## If asked to change or create an interface

- Work only inside an interface module. Read `docs/INTERFACES.md` first; it
  lists the whole API an interface uses.
- Start a new interface by copying `OpenFMMinimalInterface`. Do not edit
  `OpenFMCore` or `OpenFMEngine` to make a view easier to write.
- Read values with `synth.value(_:)`, write with `synth.set(_:to:)`, wrap
  drags in `beginEditing` / `endEditing`.
- In `OpenFMInterface`, use the tokens in `Theme.swift` (colours, three type
  styles, 4 pt grid) and give every control an accessibility label and value.

## If asked to change behaviour or sound

- Logic shared by interfaces goes in `OpenFMCore`, with a test in
  `OpenFMKit/Tests/OpenFMCoreTests`.
- Anything reachable from `Engine::render` must not allocate, lock, log or
  call Swift/Objective-C.
- Never renumber parameter addresses; hosts store automation against them.
- No GPL code (that includes Dexed), no firmware, no commercial patches.

## Commands

```sh
xcodegen generate            # after editing project.yml or adding files to App/, AUv3/, UITests/
Tools/build.sh               # build, errors only
Tools/build.sh test          # unit tests + gesture UI tests
Tools/shot.sh "iPad Pro 11-inch (M5)" out.png -openfm.mode edit -openfm.page effects
```

Launch arguments: `-openfm.mode play|edit`, `-openfm.page algorithm|operator|motion|effects`,
`-openfm.preset "<name>"`, `-openfm.interface minimal`, `-openfm.landscape 1`.

`OpenFM.xcodeproj` is generated; edit `project.yml` instead.
