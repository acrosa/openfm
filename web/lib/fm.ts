// A tiny two-modulator FM voice for the browser, used by the guide's
// playground and tutorial. It is an illustration of the idea, not the
// OpenFM engine: the app runs a full six-operator voice.

export type WebPatch = {
  /** Modulator frequency as a multiple of the note. */
  ratio: number;
  /** Modulation depth at the start of the note and where it settles. */
  index: number;
  indexEnd: number;
  /** Seconds for the modulation to settle. */
  indexDecay: number;
  /** Optional second modulator: a short metallic strike. */
  ratio2?: number;
  index2?: number;
  index2Decay?: number;
  attack: number;
  decay: number;
  sustain: number;
  release: number;
  gain: number;
};

export const midiToHz = (note: number) => 440 * Math.pow(2, (note - 69) / 12);

const NAMES = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"];
/** C3 = 60, the convention OpenFM uses. */
export const noteName = (note: number) => `${NAMES[note % 12]}${Math.floor(note / 12) - 2}`;

/** DX-style output level (0–99) to modulation index in radians. */
export const levelToIndex = (level: number) => (level <= 0 ? 0 : 13 * Math.pow(2, (level - 99) / 8));

/** Schedules one note. Everything is created and released on its own. */
export function playNote(
  ctx: AudioContext,
  destination: AudioNode,
  patch: WebPatch,
  note: number,
  time: number,
  duration: number
) {
  const freq = midiToHz(note);
  const carrier = ctx.createOscillator();
  carrier.frequency.value = freq;
  const amp = ctx.createGain();
  amp.gain.value = 0;

  const addModulator = (ratio: number, start: number, end: number, decay: number) => {
    const osc = ctx.createOscillator();
    osc.frequency.value = freq * ratio;
    const depth = ctx.createGain();
    // Frequency deviation = index × modulator frequency.
    depth.gain.setValueAtTime(start * freq * ratio, time);
    depth.gain.exponentialRampToValueAtTime(Math.max(end, 0.001) * freq * ratio, time + decay);
    osc.connect(depth).connect(carrier.frequency);
    osc.start(time);
    osc.stop(time + duration + patch.release + 0.05);
  };
  addModulator(patch.ratio, patch.index, patch.indexEnd, patch.indexDecay);
  if (patch.ratio2 && patch.index2) addModulator(patch.ratio2, patch.index2, 0, patch.index2Decay ?? 0.08);

  amp.gain.setValueAtTime(0, time);
  amp.gain.linearRampToValueAtTime(patch.gain, time + patch.attack);
  amp.gain.exponentialRampToValueAtTime(Math.max(patch.gain * patch.sustain, 0.0001), time + patch.attack + patch.decay);
  amp.gain.setValueAtTime(Math.max(patch.gain * patch.sustain, 0.0001), time + duration);
  amp.gain.exponentialRampToValueAtTime(0.0001, time + duration + patch.release);

  carrier.connect(amp).connect(destination);
  carrier.start(time);
  carrier.stop(time + duration + patch.release + 0.05);
}

/** Master output with a soft echo, so the demo sits in a little space. */
export function createOutput(ctx: AudioContext, echoSeconds: number, echoMix: number) {
  const input = ctx.createGain();
  const master = ctx.createGain();
  master.gain.value = 0.8;
  const limiter = ctx.createDynamicsCompressor();
  const delay = ctx.createDelay(1);
  delay.delayTime.value = echoSeconds;
  const feedback = ctx.createGain();
  feedback.gain.value = 0.35;
  const wet = ctx.createGain();
  wet.gain.value = echoMix;
  input.connect(master);
  input.connect(delay);
  delay.connect(feedback).connect(delay);
  delay.connect(wet).connect(master);
  master.connect(limiter).connect(ctx.destination);
  return input;
}
