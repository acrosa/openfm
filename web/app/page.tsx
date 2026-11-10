import Link from "next/link";
import { Footer, GitHubButton, Nav } from "@/components/Chrome";
import { Showcase } from "@/components/Showcase";

const features = [
  ["Play first", "Opens on a sound, a keyboard and eight controls. Pick, shape, play. Nothing to learn before the first note."],
  ["Drag everything", "Operators, envelopes and effects are things you move. Whatever you touch lights up, along with everything it changes."],
  ["Six operators, 32 algorithms", "The classic FM voice in full: 16 voices, LFO, feedback, velocity, keyboard scaling, chorus, delay and reverb."],
  ["Bring your patches", "Import DX7 SysEx banks and single voices. Share any sound as a small, readable file."],
  ["Standalone and AUv3", "Plug into speakers or a mixer and play from any MIDI keyboard, or load it in your iPad DAW with full automation."],
  ["Open all the way down", "Apache 2.0. The interface is its own module on a small API, so you can build a different one."],
];

const spec = [
  ["Runs on", "iPhone and iPad"],
  ["Works as", "Standalone app, AUv3 instrument"],
  ["Voice", "6 operators · 32 algorithms · 16 notes"],
  ["Reads", "DX7 SysEx, OpenFM patches"],
  ["Price", "Free. No ads, no subscriptions"],
  ["License", "Apache 2.0"],
];

export default function Home() {
  return (
    <div className="frame home">
      <Nav />
      <main>
        <section className="grid12 block" style={{ paddingTop: "clamp(48px, 8vw, 104px)" }}>
          <div className="side">
            <p className="label">
              <b>OpenFM</b> FM synthesizer
            </p>
          </div>
          <div className="main">
            <h1 className="display">
              FM synthesis
              <br />
              you can <em>touch.</em>
            </h1>
            <div className="intro">
              <div className="lede-wrap">
                <p className="lede">A six-operator synth that starts simple and goes as deep as you want.</p>
                <div className="actions">
                  <GitHubButton primary />
                  <Link className="button" href="/guide">
                    Read the guide →
                  </Link>
                </div>
              </div>
              <dl className="spec">
                {spec.map(([term, value]) => (
                  <div key={term}>
                    <dt>{term}</dt>
                    <dd>{value}</dd>
                  </div>
                ))}
              </dl>
            </div>
          </div>
        </section>

        <section className="grid12 block" aria-label="OpenFM on iPad and iPhone">
          <div className="side">
            <p className="label">
              <b>The instrument</b> Two modes
            </p>
          </div>
          <div className="main">
            <Showcase />
          </div>
        </section>

        <section className="grid12 block">
          <div className="side">
            <p className="label">
              <b>What it does</b> Six things
            </p>
          </div>
          <ol className="main index">
            {features.map(([title, body], i) => (
              <li key={title}>
                <span className="n">{String(i + 1).padStart(2, "0")}</span>
                <h3>{title}</h3>
                <p>{body}</p>
              </li>
            ))}
          </ol>
        </section>

        <section className="grid12 block closing">
          <div className="side">
            <p className="label">
              <b>New to FM?</b> Start here
            </p>
          </div>
          <div className="main">
            <h2>Zero to a bass line in ten minutes.</h2>
            <p className="prose">
              The guide explains every control with pictures you can poke, lets you hear FM in your browser, and builds
              an industrial bass and lead from a single sine wave.
            </p>
            <div className="actions">
              <Link className="button primary" href="/guide">
                Open the guide →
              </Link>
              <GitHubButton />
            </div>
          </div>
        </section>
      </main>
      <Footer />
    </div>
  );
}
