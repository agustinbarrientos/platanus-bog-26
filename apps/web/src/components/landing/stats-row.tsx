"use client";

import { useMoiraiScroll } from "@/lib/moirai/scroll-store";

import { AskIcon, LockSmallIcon, ReadIcon } from "./icons";
import { reveal } from "./reveal";

const STATS = [
  { Icon: LockSmallIcon, lines: ["Tus datos", "no se guardan"] },
  { Icon: ReadIcon, lines: ["Leo tu examen", "con una foto"] },
  { Icon: AskIcon, lines: ["Pregúntame", "lo que quieras"] },
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
