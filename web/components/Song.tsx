"use client";

import { useEffect, useRef, useState } from "react";
import { createOutput, noteName, playNote, type WebPatch } from "@/lib/fm";

// Browser approximations of the sounds used in the tutorial.
const RUST_BASS: WebPatch = {
  ratio: 1, index: 5.5, indexEnd: 1.4, indexDecay: 0.18,
  ratio2: 3.5, index2: 3.2, index2Decay: 0.06,
  attack: 0.003, decay: 0.22, sustain: 0.55, release: 0.08, gain: 0.45,
};
const SIREN_LEAD: WebPatch = {
  ratio: 7, index: 2.6, indexEnd: 0.9, indexDecay: 0.25,
  attack: 0.006, decay: 0.3, sustain: 0.6, release: 0.25, gain: 0.18,
};

const BPM = 112;
const _ = null;
// Two bars of sixteenth notes in E, with the flat second (F) that makes it menacing.
export const LEAD: (number | null)[] = [
  64, _, _, 71, _, _, 67, _, _, _, 65, _, 64, _, _, _,
  64, _, _, 71, _, _, 74, _, _, 72, _, 71, _, _, 67, _,
];
export const BASS: (number | null)[] = [
  40, _, 40, _, 40, _, _, 40, _, 40, _, 40, 43, _, 41, _,
  40, _, 40, _, 40, _, _, 40, _, 40, _, 38, _, 41, _, 40,
];
// A hat between every kick, with a pickup at the end of each bar.
const HAT: (number | null)[] = [
  _, _, 1, _, _, _, 1, _, _, _, 1, _, _, _, 1, 1,
  _, _, 1, _, _, _, 1, _, _, _, 1, _, _, 1, 1, 1,
];
// Four on the floor.
const KICK: (number | null)[] = Array.from({ length: 32 }, (_v, i) => (i % 4 === 0 ? 1 : null));

type Part = "lead" | "bass" | "hat" | "kick";
const PARTS: { id: Part; name: string; steps: (number | null)[]; drum: boolean }[] = [
  { id: "lead", name: "Lead", steps: LEAD, drum: false },
  { id: "bass", name: "Bass", steps: BASS, drum: false },
  { id: "hat", name: "Hat", steps: HAT, drum: true },
  { id: "kick", name: "Kick", steps: KICK, drum: true },
];

/** A sine that falls from a thump to a hum in a tenth of a second. */
function playKick(ctx: AudioContext, out: AudioNode, time: number) {
  const osc = ctx.createOscillator();
  const amp = ctx.createGain();
  osc.frequency.setValueAtTime(170, time);
  osc.frequency.exponentialRampToValueAtTime(46, time + 0.11);
  amp.gain.setValueAtTime(0.9, time);
  amp.gain.exponentialRampToValueAtTime(0.001, time + 0.26);
  osc.connect(amp).connect(out);
  osc.start(time);
  osc.stop(time + 0.3);
}

/** A few milliseconds of bright noise. */
function playHat(ctx: AudioContext, out: AudioNode, noise: AudioBuffer, time: number) {
  const src = ctx.createBufferSource();
  src.buffer = noise;
  const filter = ctx.createBiquadFilter();
  filter.type = "highpass";
  filter.frequency.value = 7500;
  const amp = ctx.createGain();
  amp.gain.setValueAtTime(0.22, time);
  amp.gain.exponentialRampToValueAtTime(0.001, time + 0.045);
  src.connect(filter).connect(amp).connect(out);
  src.start(time);
  src.stop(time + 0.06);
}

function Lane({ name, steps, now, drum }: { name: string; steps: (number | null)[]; now: number; drum: boolean }) {
  const spoken = steps.map((s) => (s === null ? "rest" : drum ? "hit" : noteName(s))).join(", ");
  return (
    <div className="lane">
      <div className="name">{name}</div>
      <div className="scroll-x">
        <div className="grid32" role="img" aria-label={`${name} pattern: ${spoken}`}>
          {steps.map((s, i) => (
            <span key={i} className={`${s !== null ? "note" : ""}${i === now ? " now" : ""}${i % 16 === 0 ? " bar-start" : ""}`}>
              {s === null ? "" : drum ? "●" : noteName(s)}
            </span>
          ))}
        </div>
      </div>
    </div>
  );
}

/** Plays the tutorial's two-bar track and shows which step is sounding. */
export function Song() {
  const [playing, setPlaying] = useState(false);
  const [now, setNow] = useState(-1);
  const [on, setOn] = useState<Record<Part, boolean>>({ lead: true, bass: true, hat: true, kick: true });
  const mix = useRef(on);
  mix.current = on;
  const ctxRef = useRef<AudioContext | null>(null);

  useEffect(() => {
    if (!playing) return;
    const ctx = ctxRef.current ?? new AudioContext();
    ctxRef.current = ctx;
    void ctx.resume();
    const stepTime = 60 / BPM / 4;
    const out = createOutput(ctx, stepTime * 3, 0.2);
    const dry = ctx.createGain();
    dry.connect(ctx.destination);
    const noise = ctx.createBuffer(1, Math.floor(ctx.sampleRate * 0.1), ctx.sampleRate);
    const data = noise.getChannelData(0);
    for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;

    let step = 0;
    let next = ctx.currentTime + 0.08;
    const pending: number[] = [];

    // Schedule a little ahead of the clock so timing stays tight.
    const timer = window.setInterval(() => {
      while (next < ctx.currentTime + 0.12) {
        const i = step % 32;
        const m = mix.current;
        const bass = BASS[i], lead = LEAD[i];
        if (KICK[i] !== null && m.kick) playKick(ctx, dry, next);
        if (HAT[i] !== null && m.hat) playHat(ctx, dry, noise, next);
        if (bass !== null && m.bass) playNote(ctx, out, RUST_BASS, bass, next, stepTime * 0.9);
        if (lead !== null && m.lead) playNote(ctx, out, SIREN_LEAD, lead, next, stepTime * 1.8);
        pending.push(window.setTimeout(() => setNow(i), Math.max(0, (next - ctx.currentTime) * 1000)));
        next += stepTime;
        step++;
      }
    }, 25);

    return () => {
      window.clearInterval(timer);
      pending.forEach(window.clearTimeout);
      out.disconnect();
      dry.disconnect();
      setNow(-1);
    };
  }, [playing]);

  useEffect(() => () => { void ctxRef.current?.close(); }, []);

  return (
    <div className="panel">
      <div className="transport">
        <button type="button" className={`button${playing ? " live" : " primary"}`} onClick={() => setPlaying((p) => !p)} aria-pressed={playing}>
          {playing ? "■ Stop" : "▶ Play the track"}
        </button>
        {PARTS.map((part) => (
          <button key={part.id} type="button" className="button" aria-pressed={on[part.id]}
            onClick={() => setOn((v) => ({ ...v, [part.id]: !v[part.id] }))} style={{ opacity: on[part.id] ? 1 : 0.4 }}>
            {part.name}
          </button>
        ))}
        <span className="label">{BPM} BPM · 2 bars · E</span>
      </div>
      {PARTS.map((part) => (
        <Lane key={part.id} name={part.name} steps={part.steps} now={now} drum={part.drum} />
      ))}
      <div className="panel-note">
        Tap a part to mute it, the way you would mute a layer in the app. This is a browser sketch of the track so
        you know what you are aiming for; the app sounds fuller.
      </div>
    </div>
  );
}
