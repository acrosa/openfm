# Building your own interface

OpenFM is built so the interface can be replaced without touching the
synthesizer. This page is everything you need to write a new one.

## The boundary

```
your interface            SwiftUI — imports OpenFMCore, nothing else
      │
OpenFMCore                Swift — parameters, patches, presets, macros, audio + MIDI hosting
      │
OpenFMEngine              C++ / Objective-C++ — DSP and the AUAudioUnit
```

These are separate modules in the `OpenFMKit` Swift package, so the compiler
enforces the rule: an interface can only see what OpenFMCore marks `public`.
`ClassicInterface` (the shipping UI) and `MinimalInterface` (a 100-line
example) are both written this way.

## The shortest path

1. Copy `OpenFMKit/Sources/OpenFMMinimalInterface` to a new folder and add a
   matching target and product in `OpenFMKit/Package.swift`.
2. Give it one public view with this initializer:

   ```swift
   public struct MyInterface: View {
       public init(synth: SynthModel, presets: PresetStore) { ... }
   }
   ```
3. Show it: change one line in `App/OpenFMApp.swift` (`interface(for:)`) and,
   for the plug-in, one line in `AUv3/AudioUnitViewController.swift`.
4. Add the product to both targets in `project.yml` and run `xcodegen generate`.

Or use OpenFMKit from your own app: add the package, then

```swift
let session = try OpenFMSession()   // engine + model + preset library
session.start()                     // audio out, MIDI in
MyInterface(synth: session.synth, presets: session.presets)
```

## What the core gives you

Everything goes through two objects. Both are `@Observable`, so SwiftUI views
that read them redraw on their own.

### `SynthModel` — the sound being played

| You want to | Call |
| --- | --- |
| Read a parameter | `synth.value(.op(3, .level))`, `synth.string(.feedback)` |
| Change a parameter | `synth.set(.algorithm, to: 4)` |
| Wrap a drag | `synth.beginEditing(param)` … `synth.endEditing()` |
| Use a macro | `synth.value(Macro.tone)`, `synth.set(Macro.tone, to: 0.4)` |
| Play | `synth.noteOn(60, velocity: 100)`, `synth.noteOff(60)`, `synth.setHold(true)` |
| Draw the routing | `synth.algorithm` (`edges`, `carriers`, `positions`, `feedback`) |
| Highlight what a gesture affects | `synth.focus`, `synth.activeParams`, `synth.affectedOps` |
| Explain a parameter | `synth.title(param)`, `synth.hint(param)` |
| Draw the output | `synth.scope(count:)`, `synth.activeVoices`, `Algorithm.previewWave(bytes: synth.bytes)` |
| Load / capture a sound | `synth.load(patch, presetID:)`, `synth.patch` |
| Undo edits | `synth.revert()`, `synth.restore(param)`, `synth.loadedValue(param)`, `synth.isEdited` |
| Explain without changing | `synth.peek(param)`, `synth.peek(macro)`, `synth.post(title:value:)` → read `synth.peek` |
| Hear a sound without a keyboard | `synth.audition()` |

`Param` describes every parameter — range, default, step, captions and how to
format a value — so a control can be generic:

```swift
Slider(value: Binding(get: { synth.value(p) }, set: { synth.set(p, to: $0) }), in: p.range)
```

Parameters: `Param.op(1...6, field)` for the 21 per-operator fields,
`Param.enabled(op)`, the voice parameters (`.algorithm`, `.feedback`,
`.lfoSpeed`, `.transpose`, `.pitchRate(n)`, …) and the effects
(`.chorusMix`, `.delayTime`, `.reverbSize`, `.volume`, …).

Call `beginEditing` / `endEditing` around continuous gestures. It is what lets
a plug-in host record automation, and it drives `focus` and `affectedOps`.

### `PresetStore` — the library

`presets.all`, `presets.sections`, `presets.neighbor(of:offset:)`,
`presets.save(_:)`, `presets.delete(_:)`, `presets.importFile(at:)`.

## Simple first, deep when wanted

The classic interface has two modes, and a new interface can stop at either:

- **Play** uses only macros, three effect mixes, volume, the preset list and
  import. A complete instrument needs nothing more — `MinimalInterface` is
  roughly this.
- **Edit** exposes every parameter, with the rarely used ones folded away.

`Macro` is the bridge. Each macro offsets several real parameters from the
sound as loaded, and returns to exactly that sound at zero. Add one in
`OpenFMCore/Macro.swift` and every interface that iterates `Macro.all` gets it.

## Rules that keep interfaces swappable

- Import `OpenFMCore` only. If you need something from the engine, add a
  public method to `SynthModel` instead of importing `OpenFMEngine`.
- Keep synth behaviour out of views. If two interfaces would both need a
  piece of logic, it belongs in OpenFMCore with a test.
- Never touch audio from the interface: no timers driving sound, no direct
  buffer access. Notes and parameters go through `SynthModel`.
- An AUv3 window can be any size and is created more than once; don't assume
  full screen or a single instance. Avoid `UIApplication.shared` — it is not
  available in extensions.

## Adding a patch format

Importing is a list of formats, not part of any interface. To read another
synth's patches, implement `PatchFormat` (bytes in, `[Patch]` out) and add it
to `PatchFormats.all` in `OpenFMCore/Formats/PatchFormat.swift`. The browser,
the Import button, "Open in OpenFM" and file sharing all pick it up.
If the format needs a new file extension to open from Files, also declare it
in `App/Info.plist`.
