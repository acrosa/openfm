"use client";

import Image from "next/image";
import { useState } from "react";

type Mode = "play" | "edit";

const captions: Record<Mode, [string, string]> = {
  play: ["Play, on iPad. A sound, eight controls, the library and a keyboard.", "Play, on iPhone."],
  edit: ["Edit, on iPad. Dragging operator 6 lights everything it changes.", "Edit, on iPhone."],
};

const alts: Record<Mode, [string, string]> = {
  play: [
    "OpenFM on iPad in Play mode: a waveform, Shape and Space controls, a list of sounds and a keyboard. The Tone control is being dragged.",
    "OpenFM on iPhone in Play mode with the Tone control being dragged.",
  ],
  edit: [
    "OpenFM on iPad in Edit mode: operator 6 is being dragged, and it, the operator it modulates and the path between them are lit up.",
    "OpenFM on iPhone in Edit mode showing the routing diagram with operator 6 being dragged.",
  ],
};

/**
 * The app's own Play / Edit switch, on the page: flip it and both devices
 * change screens, the way the real ones do.
 */
export function Showcase() {
  const [mode, setMode] = useState<Mode>("play");
  return (
    <div>
      <div className="mode" role="group" aria-label="Show the app in">
        {(["play", "edit"] as Mode[]).map((m) => (
          <button key={m} type="button" aria-pressed={mode === m} className={mode === m ? "on" : ""} onClick={() => setMode(m)}>
            {m}
          </button>
        ))}
        <span className="mode-hint">{mode === "play" ? "Simple: pick a sound and play." : "Deep: the whole synthesizer."}</span>
      </div>
      <div className="figures">
        <figure>
          <div className="device ipad swap">
            {(["play", "edit"] as Mode[]).map((m) => (
              <Image key={m} src={`/screens/ipad-${m}-2.jpg`} width={1800} height={1298} priority={m === "play"}
                sizes="(max-width: 860px) 100vw, 720px" alt={mode === m ? alts[m][0] : ""} aria-hidden={mode !== m}
                className={mode === m ? "show" : ""} />
            ))}
          </div>
          <figcaption>
            <b>Fig. 1</b> {captions[mode][0]}
          </figcaption>
        </figure>
        <figure className="phone">
          <div className="device iphone swap">
            {(["play", "edit"] as Mode[]).map((m) => (
              <Image key={m} src={`/screens/iphone-${m}-2.jpg`} width={644} height={1400} sizes="240px"
                alt={mode === m ? alts[m][1] : ""} aria-hidden={mode !== m} className={mode === m ? "show" : ""} />
            ))}
          </div>
          <figcaption>
            <b>Fig. 2</b> {captions[mode][1]}
          </figcaption>
        </figure>
      </div>
    </div>
  );
}
