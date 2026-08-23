"use client";

import dynamic from "next/dynamic";

/** The deck reads the URL hash and drives Lottie; it only makes sense in a browser. */
const Deck = dynamic(() => import("./deck").then((m) => m.Deck), {
  ssr: false,
  loading: () => <div className="sl-viewport" />,
});

export function DeckLoader() {
  return <Deck />;
}
