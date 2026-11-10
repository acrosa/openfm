# Contributing to OpenFM

Thanks for helping. Bug reports, patches, sounds and documentation are all
welcome.

## Getting set up

1. Install Xcode 27+ and XcodeGen (`brew install xcodegen`).
2. `xcodegen generate`, then open `OpenFM.xcodeproj`.
3. `Tools/build.sh test` should pass before you start and before you open a
   pull request.

`OpenFM.xcodeproj` is generated — change `project.yml`, not the project file.

## Ground rules

**Layers.** Engine, logic and interface are separate modules (see the
README). Interfaces import `OpenFMCore` only; shared behaviour goes in
`OpenFMCore` with a test, never in a view. New interfaces are welcome as new
targets — see [docs/INTERFACES.md](docs/INTERFACES.md).

**Licensing.** Everything you contribute is licensed under Apache 2.0.
Do not copy code from GPL projects (Dexed included), and do not add firmware,
ROM dumps or commercial factory voices. New third-party code needs a
compatible license and an entry in `NOTICE`. If you change a file under
`OpenFMEngine/msfa`, add a `// Modified for OpenFM` comment saying what changed.

**The render thread.** Code reachable from `Engine::render` must not
allocate, take locks, call Objective-C or Swift, log, or touch files. Pass
data in through atomics or the existing wait-free queues, and allocate in
`prepare()`.

**Parameters.** A new parameter needs an address in `OpenFMAudioUnit`, a
`Param` in `OpenFMCore/Param.swift`, and handling in `applyParameter` /
`readParameter`. Never renumber existing addresses: hosts store automation
against them.

**Interface.** Use the tokens in `OpenFMInterface/Theme.swift` — colours, the
three type styles, the 4 pt grid. Every control needs an accessibility label
and value, and anything draggable needs an adjustable action. A gesture
should call `beginEditing` / `endEditing` on the model so the readout and the
diagram highlight what it changes.

**Factory sounds.** Patches in `FactoryPresets.swift` must be your own work.
The test suite checks that each one is audible and does not clip.

## Tests

- `OpenFMKit/Tests/` — XCTest unit tests. Engine tests drive the real audio unit offline.
- `UITests/` — gesture tests that drag real controls in the simulator.

Add a test with any behaviour change. For DSP work, `Tools/render_check.cpp`
gives a fast loop without Xcode.

## Pull requests

Keep them focused, describe what you changed and how you tested it, and
include a screenshot for interface changes (`Tools/shot.sh` can take one).
