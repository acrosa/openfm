"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Field } from "./Field";
import { levelToIndex, midiToHz, noteName } from "@/lib/fm";

const KEYS = [48, 50, 52, 53, 55, 57, 59, 60];
const RATIOS = [0.5, 1, 2, 3, 3.5, 4, 5, 7, 9, 14];

/**
 * One carrier and one modulator, live in the browser: the smallest FM synth
 * there is. Drag LEVEL and RATIO and watch and hear the wave change.
 */
export function Playground() {
  const [level, setLevel] = useState(0);
  const [ratioIndex, setRatioIndex] = useState(1);
  const [decay, setDecay] = useState(0);
  const [note, setNote] = useState<number | null>(null);
  const [active, setActive] = useState<string | null>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const audio = useRef<{ ctx: AudioContext; carrier: OscillatorNode; mod: OscillatorNode; depth: GainNode; amp: GainNode } | null>(null);

  const ratio = RATIOS[ratioIndex];
  const index = levelToIndex(level);

  // Draw two cycles of sin(θ + I·sin(ratio·θ)).
  useEffect(() => {
    const el = canvas.current;
    if (!el) return;
    const dpr = window.devicePixelRatio || 1;
    const w = el.clientWidth, h = el.clientHeight;
    el.width = w * dpr;
    el.height = h * dpr;
    const g = el.getContext("2d");
    if (!g) return;
    g.scale(dpr, dpr);
    g.clearRect(0, 0, w, h);
    g.strokeStyle = "#1f1f22";
    g.beginPath(); g.moveTo(0, h / 2); g.lineTo(w, h / 2); g.stroke();
    g.strokeStyle = active || note !== null ? "#ccff00" : "#f4f3ef";
    g.lineWidth = 1.5;
    g.lineJoin = "round";
    g.beginPath();
    for (let x = 0; x <= w; x++) {
      const t = (x / w) * 2 * 2 * Math.PI;
      const y = Math.sin(t + index * Math.sin(ratio * t));
      const py = h / 2 - y * (h / 2 - 18);
      if (x === 0) g.moveTo(x, py); else g.lineTo(x, py);
    }
    g.stroke();
  }, [index, ratio, active, note]);

  const ensure = useCallback(() => {
    if (audio.current) return audio.current;
    const ctx = new AudioContext();
    const carrier = ctx.createOscillator();
    const mod = ctx.createOscillator();
    const depth = ctx.createGain();
    const amp = ctx.createGain();
    amp.gain.value = 0;
    depth.gain.value = 0;
    mod.connect(depth).connect(carrier.frequency);
    carrier.connect(amp).connect(ctx.destination);
    carrier.start();
    mod.start();
    audio.current = { ctx, carrier, mod, depth, amp };
    return audio.current;
  }, []);

  // Keep the sounding note in step with the controls.
  useEffect(() => {
    const a = audio.current;
    if (!a || note === null) return;
    const f = midiToHz(note);
    const now = a.ctx.currentTime;
    a.carrier.frequency.setTargetAtTime(f, now, 0.005);
    a.mod.frequency.setTargetAtTime(f * ratio, now, 0.005);
    if (decay === 0) a.depth.gain.setTargetAtTime(index * f * ratio, now, 0.02);
  }, [note, ratio, index, decay]);

  const press = (n: number) => {
    const a = ensure();
    void a.ctx.resume();
    const f = midiToHz(n);
    const now = a.ctx.currentTime;
    a.carrier.frequency.setValueAtTime(f, now);
    a.mod.frequency.setValueAtTime(f * ratio, now);
    a.depth.gain.cancelScheduledValues(now);
    a.depth.gain.setValueAtTime(index * f * ratio, now);
    // A modulator envelope: bright at the strike, then settling.
    if (decay > 0) a.depth.gain.setTargetAtTime(index * f * ratio * 0.12, now, decay / 300);
    a.amp.gain.cancelScheduledValues(now);
    a.amp.gain.setTargetAtTime(0.22, now, 0.008);
    setNote(n);
  };

  const release = () => {
    const a = audio.current;
    if (a) a.amp.gain.setTargetAtTime(0, a.ctx.currentTime, 0.08);
    setNote(null);
  };

  useEffect(() => () => { void audio.current?.ctx.close(); }, []);

  const message =
    active === "LEVEL" ? "Modulator level is brightness. At 0 the carrier is a pure sine; turn it up and harmonics pile on."
    : active === "RATIO" ? "Ratio decides which harmonics appear. Whole numbers sound musical; 3.5 turns it into metal."
    : active === "DECAY" ? "Give the modulator its own envelope: bright when the key goes down, mellow a moment later. That is a pluck."
    : level === 0 ? "Hold a key, then drag LEVEL to the right."
    : "Now try RATIO. Double-click a control to reset it.";

  return (
    <div className="panel">
      <canvas ref={canvas} aria-label="Waveform of the carrier being modulated" role="img" />
      <div className="fields">
        <Field caption="Level" value={level} min={0} max={99} reset={0} format={(v) => String(v)}
          onChange={setLevel} onActive={(on) => setActive(on ? "LEVEL" : null)} />
        <Field caption="Ratio" value={ratioIndex} min={0} max={RATIOS.length - 1} reset={1}
          format={(v) => `×${RATIOS[v].toFixed(2)}`} onChange={setRatioIndex} onActive={(on) => setActive(on ? "RATIO" : null)} />
        <Field caption="Decay" value={decay} min={0} max={99} reset={0} format={(v) => (v === 0 ? "OFF" : String(v))}
          onChange={setDecay} onActive={(on) => setActive(on ? "DECAY" : null)} />
        <div className="field" aria-hidden="true">
          <span className="cap">Index</span>
          <span className="val">{index.toFixed(1)}</span>
          <span className="bar"><i style={{ width: `${Math.min(100, (index / 13) * 100)}%` }} /></span>
        </div>
      </div>
      <div className="panel-note" aria-live="polite">{message}</div>
      <div className="keys" role="group" aria-label="Keyboard">
        {KEYS.map((n) => (
          <button key={n} type="button" className={note === n ? "down" : ""} aria-label={`Play ${noteName(n)}`}
            onPointerDown={(e) => { e.currentTarget.setPointerCapture(e.pointerId); press(n); }}
            onPointerUp={release} onPointerCancel={release}
            onKeyDown={(e) => { if ((e.key === " " || e.key === "Enter") && !e.repeat) { e.preventDefault(); press(n); } }}
            onKeyUp={(e) => { if (e.key === " " || e.key === "Enter") release(); }}>
            {noteName(n)}
          </button>
        ))}
      </div>
    </div>
  );
}
