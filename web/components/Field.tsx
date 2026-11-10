"use client";

import { useRef, useState } from "react";

/**
 * The same value cell the app uses: drag sideways to change it, double-click
 * to reset. Arrow keys work too.
 */
export function Field({
  caption, value, min, max, step = 1, reset, format, onChange, onActive,
}: {
  caption: string; value: number; min: number; max: number; step?: number; reset: number;
  format: (v: number) => string; onChange: (v: number) => void; onActive?: (on: boolean) => void;
}) {
  const [on, setOn] = useState(false);
  const start = useRef<{ x: number; value: number } | null>(null);
  const clamp = (v: number) => Math.min(max, Math.max(min, Math.round(v / step) * step));

  return (
    <div
      className={`field${on ? " on" : ""}`}
      role="slider"
      tabIndex={0}
      aria-label={caption}
      aria-valuemin={min}
      aria-valuemax={max}
      aria-valuenow={value}
      aria-valuetext={format(value)}
      onPointerDown={(e) => {
        e.currentTarget.setPointerCapture(e.pointerId);
        start.current = { x: e.clientX, value };
        setOn(true);
        onActive?.(true);
      }}
      onPointerMove={(e) => {
        if (!start.current) return;
        onChange(clamp(start.current.value + ((e.clientX - start.current.x) / 220) * (max - min)));
      }}
      onPointerUp={() => { start.current = null; setOn(false); onActive?.(false); }}
      onPointerCancel={() => { start.current = null; setOn(false); onActive?.(false); }}
      onDoubleClick={() => onChange(reset)}
      onKeyDown={(e) => {
        if (e.key === "ArrowRight" || e.key === "ArrowUp") { e.preventDefault(); onChange(clamp(value + step)); }
        if (e.key === "ArrowLeft" || e.key === "ArrowDown") { e.preventDefault(); onChange(clamp(value - step)); }
      }}
    >
      <span className="cap">{caption}</span>
      <span className="val">{format(value)}</span>
      <span className="bar"><i style={{ width: `${((value - min) / (max - min)) * 100}%` }} /></span>
    </div>
  );
}
