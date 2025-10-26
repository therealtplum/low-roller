import React, { useEffect, useState } from "react";

type Props = {
  faces: number[];
  picked: number[];
  onPickToggle: (i: number) => void;
};

const PIPS: Record<number, Array<[number, number]>> = {
  1: [[50, 50]],
  2: [[25, 25], [75, 75]],
  3: [[25, 25], [50, 50], [75, 75]],
  4: [[25, 25], [25, 75], [75, 25], [75, 75]],
  5: [[25, 25], [25, 75], [50, 50], [75, 25], [75, 75]],
  6: [[25, 25], [25, 50], [25, 75], [75, 25], [75, 50], [75, 75]],
};

function Die({ v, picked, onClick, animate }: { v: number; picked: boolean; onClick: () => void; animate: boolean }) {
  return (
    <button
      className={`die svgdie ${picked ? "picked" : ""} ${animate ? "rolling" : ""}`}
      onClick={onClick}
      aria-label={`Die showing ${v}`}
    >
      <svg viewBox="0 0 100 100" width="72" height="72" role="img" aria-hidden="true">
        {/* body */}
        <rect x="4" y="4" width="92" height="92" rx="14" ry="14" className="die-bg" />
        {/* inner bevel */}
        <rect x="8" y="8" width="84" height="84" rx="12" ry="12" className="die-inset" />
        {/* pips */}
        {PIPS[v]?.map(([cx, cy], i) => (
          <circle key={i} cx={cx} cy={cy} r="7.5" className="pip-svg" />
        ))}
      </svg>
    </button>
  );
}

export default function Dice({ faces, picked, onPickToggle }: Props) {
  // toggle animation whenever faces change
  const [animate, setAnimate] = useState(false);
  useEffect(() => {
    if (faces.length) {
      setAnimate(true);
      const t = setTimeout(() => setAnimate(false), 250);
      return () => clearTimeout(t);
    }
  }, [faces.join(",")]);

  return (
    <div className="dice-row">
      {faces.map((v, i) => (
        <Die
          key={i}
          v={v}
          picked={picked.includes(i)}
          onClick={() => onPickToggle(i)}
          animate={animate}
        />
      ))}
      {faces.length === 0 && <div className="hint">Roll to start</div>}
    </div>
  );
}