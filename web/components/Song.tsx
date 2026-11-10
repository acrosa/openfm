"use client";

import { useEffect, useRef, useState } from "react";
import { createOutput, noteName, playNote, type WebPatch } from "@/lib/fm";

// Browser approximations of the two sounds built in the tutorial.
const RUST_BASS: WebPatch = {
  ratio: 1, index: 5.5, indexEnd: 1.4, indexDecay: 0.18,
  ratio2: 3.5, index2: 3.2, index2Decay: 0.06,
  attack: 0.003, decay: 0.22, sustain: 0.55, release: 0.08, gain: 0.5,
};
const SIREN_LEAD: WebPatch = {
  ratio: 7, index: 2.6, indexEnd: 0.9, indexDecay: 0.25,
  attack: 0.006, decay: 0.3, sustain: 0.6, release: 0.25, gain: 0.2,
};

const BPM = 112;
const _ = null;
// Two bars of sixteenth notes in E, with the flat second (F) that makes it menacing.
export const BASS: (number | null)[] = [
  40, _, 40, _, 40, _, _, 40, _, 40, _, 40, 43, _, 41, _,
  40, _, 40, _, 40, _, _, 40, _, 40, _, 38, _, 41, _, 40,
];
export const LEAD: (number | null)[] = [
  64, _, _, 71, _, _, 67, _, _, _, 65, _, 64, _, _, _,
  64, _, _, 71, _, _, 74, _, _, 72, _, 71, _, _, 67, _,
];

function Lane({ name, steps, now }: { name: string; steps: (number | null)[]; now: number }) {
  return (
    <div className="lane">
      <div className="name">{name}</div>
      <div className="scroll-x">
        <div className="grid32" role="img" aria-label={`${name} pattern: ${steps.map((s) => (s === null ? "rest" : noteName(s))).join(", ")}`}>
          {steps.map((s, i) => (
            <span key={i} className={`${s !== null ? "note" : ""}${i === now ? " now" : ""}${i % 16 === 0 ? " bar-start" : ""}`}>
              {s !== null ? noteName(s) : ""}
            </span>
          ))}
        </div>
      </div>
    </div>
  );
}

/** Plays the tutorial's two-bar loop and shows which step is sounding. */
export function Song() {
  const [playing, setPlaying] = useState(false);
  const [now, setNow] = useState(-1);
  const [bass, setBass] = useState(true);
  const [lead, setLead] = useState(true);
  const mix = useRef({ bass: true, lead: true });
  mix.current = { bass, lead };
  const ctxRef = useRef<AudioContext | null>(null);

  useEffect(() => {
    if (!playing) return;
    const ctx = ctxRef.current ?? new AudioContext();
    ctxRef.current = ctx;
    void ctx.resume();
    const stepTime = 60 / BPM / 4;
    const out = createOutput(ctx, stepTime * 3, 0.22);
    let step = 0;
    let next = ctx.currentTime + 0.08;
    const pending: number[] = [];

    // Schedule a little ahead of the clock so timing stays tight.
    const timer = window.setInterval(() => {
      while (next < ctx.currentTime + 0.12) {
        const i = step % 32;
        const b = BASS[i], l = LEAD[i];
        if (b !== null && mix.current.bass) playNote(ctx, out, RUST_BASS, b, next, stepTime * 0.9);
        if (l !== null && mix.current.lead) playNote(ctx, out, SIREN_LEAD, l, next, stepTime * 1.8);
        pending.push(window.setTimeout(() => setNow(i), Math.max(0, (next - ctx.currentTime) * 1000)));
        next += stepTime;
        step++;
      }
    }, 25);

    return () => {
      window.clearInterval(timer);
      pending.forEach(window.clearTimeout);
      out.disconnect();
      setNow(-1);
    };
  }, [playing]);

  useEffect(() => () => { void ctxRef.current?.close(); }, []);

  return (
    <div className="panel">
      <div className="transport">
        <button type="button" className={`button${playing ? " live" : " primary"}`} onClick={() => setPlaying((p) => !p)} aria-pressed={playing}>
          {playing ? "■ Stop" : "▶ Play the loop"}
        </button>
        <button type="button" className="button" aria-pressed={bass} onClick={() => setBass((v) => !v)} style={{ opacity: bass ? 1 : 0.45 }}>
          Bass {bass ? "on" : "off"}
        </button>
        <button type="button" className="button" aria-pressed={lead} onClick={() => setLead((v) => !v)} style={{ opacity: lead ? 1 : 0.45 }}>
          Lead {lead ? "on" : "off"}
        </button>
        <span className="label">{BPM} BPM · 2 bars · E</span>
      </div>
      <Lane name="Lead" steps={LEAD} now={now} />
      <Lane name="Bass" steps={BASS} now={now} />
      <div className="panel-note">
        This is a browser sketch of the two sounds so you know what you are aiming for. The app, with six operators and
        real envelopes, sounds fuller.
      </div>
    </div>
  );
}
