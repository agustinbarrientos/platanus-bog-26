import type { Metadata } from "next";

import { DeckLoader } from "@/components/slides/deck-loader";

import "@/components/landing/landing.css";
import "@/components/slides/slides.css";

export const metadata: Metadata = {
  title: "Moirai · Presentación",
  robots: { index: false, follow: false },
};

export default function SlidesPage() {
  return <DeckLoader />;
}
