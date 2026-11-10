"use client";

import Image from "next/image";
import { useState } from "react";

export type Spot = { x: number; y: number; title: string; body: string };

/** A screenshot with numbered marks. Tap a mark or a row to read about it. */
export function Annotated({ src, width, height, alt, spots }: { src: string; width: number; height: number; alt: string; spots: Spot[] }) {
  const [active, setActive] = useState(0);
  return (
    <div className="annotated">
      <div className="shot">
        <Image src={src} width={width} height={height} alt={alt} sizes="(max-width: 860px) 100vw, 600px" />
        {spots.map((spot, i) => (
          <button
            key={spot.title}
            type="button"
            className={`spot${i === active ? " on" : ""}`}
            style={{ left: `${spot.x}%`, top: `${spot.y}%` }}
            aria-label={`${i + 1}: ${spot.title}`}
            aria-pressed={i === active}
            onClick={() => setActive(i)}
            onMouseEnter={() => setActive(i)}
          >
            {i + 1}
          </button>
        ))}
      </div>
      <ol className="notes">
        {spots.map((spot, i) => (
          <li key={spot.title} className={i === active ? "on" : ""}>
            <button type="button" onClick={() => setActive(i)} aria-expanded={i === active}>
              <span className="n">{String(i + 1).padStart(2, "0")}</span>
              <span className="t">{spot.title}</span>
              <span className="b">{spot.body}</span>
            </button>
          </li>
        ))}
      </ol>
    </div>
  );
}
