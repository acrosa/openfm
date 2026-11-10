import type { Metadata } from "next";
import { Annotated, type Spot } from "@/components/Annotated";
import { Footer, GitHubButton, Nav } from "@/components/Chrome";
import { Playground } from "@/components/Playground";
import { Song } from "@/components/Song";

export const metadata: Metadata = {
  title: "Guide",
  description: "Every OpenFM control explained, FM synthesis in plain words, and a tutorial that builds an industrial bass and lead.",
};

// Positions were measured on a 1600 × 1103 capture whose left 44 px and right
// 27 px were cropped away for the published image.
const at = (x: number, y: number) => ({ x: ((x - 44) / 1529) * 100, y: (y / 1103) * 100 });

const playSpots: Spot[] = [
  { ...at(150, 62), title: "The sound", body: "The name of what you are playing. Tap it to open the full browser. EDITED appears in lime once you change anything." },
  { ...at(410, 50), title: "Previous · next", body: "Step through every sound without leaving the keyboard." },
  { ...at(760, 62), title: "Readout", body: "Names the control under your finger, shows its value, and says in plain words what it does. Tap any control once to read about it without changing it." },
  { ...at(1480, 50), title: "Play · Edit", body: "Play is this screen. Edit opens the whole synthesizer. Your choice is remembered." },
  { ...at(540, 270), title: "Output", body: "The sound's waveform. It is live while you play, and when silent it previews the shape, so you can see a control working before you press a key." },
  { ...at(960, 139), title: "Operator marks", body: "Six squares, one per operator. Filled ones are heard; outlined ones shape the tone. They light up to show which operators a control reaches." },
  { ...at(300, 485), title: "Shape", body: "Four macros. Tone is darker ↔ brighter; Attack, Decay and Release change how a note starts, settles and ends. Zero means “as the sound was designed”. Double-tap to go back." },
  { ...at(300, 627), title: "Space", body: "Chorus thickens, Echo repeats, Reverb puts it in a room. Each is how much of that effect you hear. Volume is the master level." },
  { ...at(1295, 420), title: "Sounds", body: "The library, always there on iPad. Tap a name and it is loaded. Your own and imported sounds sit above the factory ones." },
  { ...at(1295, 700), title: "Import · Save", body: "Import reads DX7 .syx banks and OpenFM patch files. Save keeps your version; its menu also has Revert to Original." },
  { ...at(155, 787), title: "Octave dial", body: "Swipe sideways to roll the keyboard up or down an octave. Tapping either side steps once." },
  { ...at(1503, 787), title: "Hold", body: "Keeps notes ringing after you let go, like a piano's sustain pedal." },
  { ...at(800, 960), title: "Keyboard", body: "Touch lower on a key to play louder. Slide to glide between notes. With a hardware keyboard, A S D F… are the white keys and Z / X change octave." },
];

const editSpots: Spot[] = [
  { ...at(100, 175), title: "Algorithm", body: "Which operator feeds which: one of 32 wirings. Drag the number sideways to scrub through them and watch the diagram rearrange; tap it to see all 32." },
  { ...at(492, 167), title: "Feedback", body: "Lets one operator modulate itself. A little adds edge, a lot adds noise. The loop it applies to is drawn on the diagram." },
  { ...at(255, 410), title: "Routing diagram", body: "Bottom row: carriers, the operators you hear. Above them: modulators, which change the tone of whatever they point at. The fill inside each box is its level." },
  { ...at(445, 330), title: "Dragging an operator", body: "Up/down sets level, sideways sets ratio, double-tap switches it off. Here OP 6 is being dragged: it, the operator it modulates and the path between them light up." },
  { ...at(318, 755), title: "Wave", body: "One cycle of the result, redrawn as you edit." },
  { ...at(690, 62), title: "Readout", body: "“Modulator · brightness of OP 5”. The hint changes with the algorithm, so it always describes this operator in this sound." },
  { ...at(1083, 131), title: "Pages", body: "Operator: one operator in detail. Motion: LFO, pitch envelope, tuning. Effects: chorus, delay and reverb as pads you move a dot around in." },
  { ...at(1083, 218), title: "Operator tabs", body: "Pick an operator to edit. C or M marks carrier or modulator; the bar is its level." },
  { ...at(1083, 415), title: "Envelope", body: "How this operator's level moves over a note. Drag handle 1–4: sideways for how fast that stage is reached, up/down for its level. KEY OFF is where you let go." },
  { ...at(1083, 570), title: "Value cells", body: "The same envelope as numbers. Every cell works the same way: drag sideways to change, tap to read about it, double-tap to reset." },
  { ...at(846, 712), title: "Frequency", body: "Ratio mode follows the keyboard (×2.00 is an octave up). Fixed mode stays at one pitch regardless of the key, which is good for clicks and drones." },
  { ...at(1320, 712), title: "Level", body: "Output level, plus how much playing harder (Velocity) and the LFO (Amp Mod) affect it." },
  { ...at(700, 815), title: "More", body: "Rarely needed settings stay folded until you open them." },
];

const sections = [
  ["fm", "FM in one minute"],
  ["try", "Hear it"],
  ["play", "The Play screen"],
  ["edit", "The Edit screen"],
  ["tutorial", "Tutorial: industrial loop"],
  ["loops", "Recording loops"],
  ["patches", "Bringing in sounds"],
];

const K = ({ children }: { children: React.ReactNode }) => <span className="kv">{children}</span>;

export default function Guide() {
  return (
    <div className="frame">
      <Nav />
      <div className="guide">
        <aside className="toc">
          <p className="label">Guide</p>
          <ol>
            {sections.map(([id, title]) => (
              <li key={id}><a href={`#${id}`}>{title}</a></li>
            ))}
          </ol>
        </aside>

        <main>
          <section className="section" style={{ paddingTop: 72 }}>
            <p className="label">Guide</p>
            <h1 style={{ fontSize: "clamp(36px, 6vw, 72px)", margin: "12px 0 20px" }}>Learn OpenFM.</h1>
            <p className="prose">
              You don't need to understand FM to enjoy it: pick a sound and play. But ten minutes here will make every
              control make sense. Read top to bottom, or jump to the tutorial.
            </p>
          </section>

          <section className="section" id="fm">
            <p className="label">01 · Concepts</p>
            <h2>FM in one minute</h2>
            <p className="prose">
              Sing one steady note. Now have a friend gently shake your shoulders: your voice wobbles. That wobble is
              vibrato. If they could shake you <strong>hundreds of times a second</strong>, you would stop hearing a
              wobble and start hearing a <strong>different tone</strong>: brighter, buzzier, bell-like.
            </p>
            <p className="prose analogy">
              That is FM synthesis. One simple sound shakes another so fast that the shaking becomes the tone.
            </p>
            <dl className="terms">
              <div>
                <dt>Operator</dt>
                <dd>A singer who can only hum a pure tone, with a volume knob and a script for how loud to be over time. OpenFM has <em>six</em>.</dd>
              </div>
              <div>
                <dt>Carrier</dt>
                <dd>An operator you <em>hear</em>. Its level is loudness.</dd>
              </div>
              <div>
                <dt>Modulator</dt>
                <dd>An operator doing the <em>shaking</em>. You don't hear it directly. Its level is brightness.</dd>
              </div>
              <div>
                <dt>Algorithm</dt>
                <dd>The seating chart: who shakes whom. A tall stack makes complex, noisy tones; several side-by-side pairs make rich, layered ones.</dd>
              </div>
              <div>
                <dt>Ratio</dt>
                <dd>How fast a modulator shakes compared with the note. <em>×1, ×2, ×3</em> sound musical. In-between values like <em>×3.50</em> sound like struck metal.</dd>
              </div>
              <div>
                <dt>Envelope</dt>
                <dd>The script: how an operator's level moves while you hold a key and after you let go. On a modulator it makes a sound start bright and mellow out, like a plucked string.</dd>
              </div>
              <div>
                <dt>Feedback</dt>
                <dd>An operator shaking itself, like a microphone pointed at its own speaker. A little is grit; a lot is noise.</dd>
              </div>
              <div>
                <dt>LFO</dt>
                <dd>A very slow shake, slow enough to hear as movement: vibrato when it moves pitch, tremolo when it moves volume.</dd>
              </div>
            </dl>
          </section>

          <section className="section" id="try">
            <p className="label">02 · Try it</p>
            <h2>Hear it</h2>
            <p className="prose">
              This is the smallest FM synth there is: one carrier, one modulator. Hold a key and drag{" "}
              <strong>Level</strong> sideways, exactly as you would in the app.
            </p>
            <Playground />
            <p className="prose" style={{ marginTop: 20 }}>
              Everything in OpenFM is this, six times over. More operators mean more layers and more ways to wire them.
            </p>
          </section>

          <section className="section" id="play">
            <p className="label">03 · Interface</p>
            <h2>The Play screen</h2>
            <p className="prose">
              Where the app opens. A sound, a keyboard and eight controls. Tap a number to see what it is. In this
              picture <strong>Tone</strong> is being dragged, so it is lit, and so is everything it affects.
            </p>
            <Annotated src="/screens/ipad-play.jpg" width={1800} height={1298} spots={playSpots}
              alt="OpenFM Play screen on iPad with numbered marks on each control." />
            <h3>One gesture for every value</h3>
            <p className="prose">
              <strong>Drag sideways</strong> to change. <strong>Tap</strong> to read what it is.{" "}
              <strong>Double-tap</strong> to put it back. Dragging up and down scrolls the page, so you can't change a
              value by accident while scrolling.
            </p>
          </section>

          <section className="section" id="edit">
            <p className="label">04 · Interface</p>
            <h2>The Edit screen</h2>
            <p className="prose">
              The whole synthesizer. The diagram on the left is the sound's wiring and also its main control: you drag
              the operators themselves.
            </p>
            <Annotated src="/screens/ipad-edit.jpg" width={1800} height={1298} spots={editSpots}
              alt="OpenFM Edit screen on iPad with numbered marks on the routing diagram, envelope and value cells." />
            <h3>Reading the highlight</h3>
            <p className="prose">
              While you drag, the lime highlight marks <strong>cause and effect</strong>: the thing you hold, every operator
              downstream of it, and the paths between them. If a carrier lights up when you move a modulator, that is
              the sound you are about to change.
            </p>
          </section>

          <section className="section" id="tutorial">
            <p className="label">05 · Tutorial</p>
            <h2>Build an industrial loop</h2>
            <p className="prose">
              Two sounds from scratch, a growling bass and a glassy alarm of a lead, and a two-bar riff to play with
              them. Press play to hear where this is going.
            </p>
            <Song />

            <h3>Sound 1 · Rust Bass</h3>
            <p className="prose">A dark growl with a metal clank at the front of every note.</p>
            <ol className="steps">
              <li><div>
                <div className="do">Start from nothing: tap the sound name → <K>+</K> → <K>New Init Voice</K>. Switch to <K>EDIT</K>.</div>
                <div className="why">You hear a plain sine wave: one carrier (OP 1), nothing shaping it. The diagram shows algorithm 01.</div>
              </div></li>
              <li><div>
                <div className="do">In the diagram, drag <K>OP 2</K> up to <K>LEVEL 85</K>.</div>
                <div className="why">OP 2 sits above OP 1, so it modulates it. The sine grows teeth. This is the growl.</div>
              </div></li>
              <li><div>
                <div className="do">Select OP 2. In its envelope set <K>RATE 2 60</K> and <K>LEVEL 2 50</K>.</div>
                <div className="why">The brightness now drops right after the strike: bright bite, darker body. Drag handle 2 down and left to do the same by eye.</div>
              </div></li>
              <li><div>
                <div className="do">Select OP 1. Set <K>RATE 2 50</K> <K>LEVEL 2 75</K> <K>LEVEL 3 60</K> <K>RATE 4 65</K>.</div>
                <div className="why">The carrier's envelope is the volume: a firm hit, a short sag, and a quick stop when you let go, so fast notes stay tight.</div>
              </div></li>
              <li><div>
                <div className="do">Add metal: drag <K>OP 3</K> up to <K>LEVEL 80</K> and <K>OP 4</K> up to <K>LEVEL 82</K>. Then set OP 4 <K>COARSE 3</K> <K>FINE 50</K>, so it reads <K>×3.50</K>.</div>
                <div className="why">OP 3 is a second carrier, a second layer. A modulator at ×3.50 is not a clean harmonic, and that is what makes it clang.</div>
              </div></li>
              <li><div>
                <div className="do">Make the clang short. On OP 4 and OP 3: <K>RATE 2 75</K> <K>LEVEL 2 0</K> <K>LEVEL 3 0</K>.</div>
                <div className="why">The metal layer now only speaks at the start of each note, like a hammer hitting a pipe.</div>
              </div></li>
              <li><div>
                <div className="do">Go to <K>MOTION</K> and set <K>TRANSPOSE −12</K>. In <K>EFFECTS</K>: Delay <K>TIME 270 ms</K> <K>REPEATS 35</K> <K>MIX 15</K>, Reverb <K>MIX 10</K>.</div>
                <div className="why">An octave down for weight; a short echo to make the room feel like concrete.</div>
              </div></li>
              <li><div>
                <div className="do">Back in <K>PLAY</K>: <K>SAVE</K> → Save… → “Rust Bass”.</div>
                <div className="why">Too tame? Push <K>TONE</K> up. Too harsh? Pull it down. That is what the macros are for.</div>
              </div></li>
            </ol>

            <h3>Sound 2 · Siren Lead</h3>
            <p className="prose">A cold, glassy tone that cuts through the bass.</p>
            <ol className="steps">
              <li><div>
                <div className="do">New Init Voice again. Drag <K>OP 2</K> up to <K>LEVEL 78</K>, then sideways until it reads <K>×7.00</K>.</div>
                <div className="why">A high ratio puts the added harmonics far above the note: thin, bright, a little like glass.</div>
              </div></li>
              <li><div>
                <div className="do">OP 2 envelope: <K>RATE 2 55</K> <K>LEVEL 2 60</K>. OP 1 envelope: <K>LEVEL 3 80</K> <K>RATE 4 50</K>.</div>
                <div className="why">A bright ping that settles into a held tone and rings for a moment after release.</div>
              </div></li>
              <li><div>
                <div className="do"><K>MOTION</K> → LFO <K>PITCH 12</K> <K>DELAY 30</K>.</div>
                <div className="why">Vibrato that only arrives once a note has been held: short notes stay straight, long ones start to wail.</div>
              </div></li>
              <li><div>
                <div className="do"><K>EFFECTS</K> → Delay <K>TIME 400 ms</K> <K>MIX 30</K>, Reverb <K>MIX 25</K>. Save as “Siren Lead”.</div>
                <div className="why">The echo answers each phrase, which fills the gaps in a sparse melody.</div>
              </div></li>
            </ol>

            <h3>Play it</h3>
            <p className="prose">
              The riff is in <strong>E</strong>. The one “wrong” note, <strong>F</strong>, a half step above home, is
              what makes it sound menacing. Read each lane left to right; every box is a sixteenth note.
            </p>
            <ol className="steps">
              <li><div>
                <div className="do">Load Rust Bass. Roll the octave dial down to <K>C1</K> and play the Bass lane: mostly <K>E</K>, with <K>G</K>, <K>F</K> and <K>D</K> at the ends of the bars.</div>
                <div className="why">Keep the notes short and even. The gaps matter as much as the notes.</div>
              </div></li>
              <li><div>
                <div className="do">Load Siren Lead, octave dial at <K>C3</K>, and play the Lead lane: <K>E</K> <K>B</K> <K>G</K> … <K>F</K> <K>E</K>, then up to <K>D</K> <K>C</K> <K>B</K> <K>G</K>.</div>
                <div className="why">Hold the long notes and let the delayed vibrato come in.</div>
              </div></li>
              <li><div>
                <div className="do">To hear both at once, or to loop the bass while you play the lead, see <a href="#loops" style={{ textDecoration: "underline" }}>Recording loops</a> below.</div>
                <div className="why">The standalone app plays one sound at a time, like a hardware synth, and does not record.</div>
              </div></li>
            </ol>
            <p className="prose" style={{ marginTop: 20 }}>
              These values are a starting point, not a recipe. Change one number and listen. That is how every FM
              sound has ever been made.
            </p>
          </section>

          <section className="section" id="loops">
            <p className="label">06 · Loops</p>
            <h2>Recording loops</h2>
            <p className="prose">
              OpenFM is an instrument, not a recorder: on its own it plays one sound, live, and keeps nothing. To
              record a riff and have it loop while you play over it, boom-box style, run OpenFM <strong>inside a
              host app</strong>. The host does the recording; OpenFM makes the sound.
            </p>
            <p className="prose analogy">
              Think of OpenFM as a keyboard and the host as a tape deck with several tracks. You can plug the same
              keyboard into every track.
            </p>
            <h3>With GarageBand (free)</h3>
            <ol className="steps">
              <li><div>
                <div className="do">Create a new song and choose <K>Live Loops</K>, then an empty grid.</div>
                <div className="why">Live Loops is a grid of cells. Each cell holds one loop; each row is one instrument.</div>
              </div></li>
              <li><div>
                <div className="do">Add an instrument: in the sound browser go to <K>External</K> → <K>Audio Unit Extensions</K> → <K>OpenFM</K>.</div>
                <div className="why">OpenFM opens inside GarageBand with its full interface. Pick Rust Bass.</div>
              </div></li>
              <li><div>
                <div className="do">Tap an empty cell in that row, choose <K>Record into Cell</K>, and play the bass riff.</div>
                <div className="why">When you stop, the cell loops what you played, in time.</div>
              </div></li>
              <li><div>
                <div className="do">Add a second OpenFM track, load Siren Lead, and record the melody into a cell on its row.</div>
                <div className="why">Each track is its own copy of OpenFM with its own sound, so bass and lead play together.</div>
              </div></li>
              <li><div>
                <div className="do">Tap cells to start and stop them. Record variations into the next column and switch between columns.</div>
                <div className="why">That is the whole trick: a few short loops, switched on and off, are a song.</div>
              </div></li>
            </ol>
            <p className="prose" style={{ marginTop: 20 }}>
              Menu names move around a little between GarageBand versions. Other hosts work the same way:{" "}
              <strong>AUM</strong> or <strong>Loopy Pro</strong> for live looping, <strong>Logic Pro</strong> or{" "}
              <strong>Cubasis</strong> for full songs. Every OpenFM control can be automated from the host. The plug-in
              is new, so if a host misbehaves, please open an issue on GitHub.
            </p>
          </section>

          <section className="section" id="patches">
            <p className="label">07 · Sounds</p>
            <h2>Bringing in sounds</h2>
            <p className="prose">
              OpenFM reads <strong>DX7 SysEx</strong> files (.syx), the format thousands of classic FM sounds are shared
              in, as 32-sound banks or single voices. Tap <strong>Import</strong>, pick the file, and the bank appears
              at the top of your sounds with its first sound loaded. You can also open a .syx file from the Files app
              straight into OpenFM.
            </p>
            <p className="prose">
              Your own sounds are saved as small, readable JSON files. Share one from the browser's <strong>+</strong>{" "}
              menu and anyone with OpenFM can open it.
            </p>
            <div className="actions" style={{ marginTop: 28 }}>
              <GitHubButton primary />
            </div>
          </section>
        </main>
      </div>
      <Footer />
    </div>
  );
}
