"use client";

import { useMoiraiScroll } from "@/lib/moirai/scroll-store";

import { AskIcon, LockSmallIcon, ReadIcon } from "./icons";
import { reveal } from "./reveal";

const STATS = [
  { Icon: LockSmallIcon, lines: ["Tu examen se lee", "una vez, no se guarda"] },
  { Icon: ReadIcon, lines: ["Leo los biomarcadores", "que tenga tu examen"] },
  { Icon: AskIcon, lines: ["Pregúntale a Moirai", "en tus palabras"] },
];

export function StatsRow() {
  const prog = useMoiraiScroll((s) => s.prog.stats);

  return (
    <div id="stats" className="mo-stats" style={reveal({ stats: prog }, "stats", 0, 24)}>
      {STATS.map(({ Icon, lines }) => (
        <div key={lines[0]} className="mo-stat">
          <Icon width={24} height={24} stroke="#1E6EA9" />
          <span>
            {lines[0]}
            <br />
            {lines[1]}
          </span>
        </div>
      ))}
    </div>
  );
}
