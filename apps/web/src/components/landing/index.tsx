"use client";

import { useEffect } from "react";

import { startDriver } from "@/lib/moirai/scroll-store";

import { AndroidBar } from "./android-bar";
import { ChatSection } from "./chat-section";
import { DownloadSection } from "./download-section";
import { EngineSection } from "./engine-section";
import { GallerySection } from "./gallery-section";
import { Hero } from "./hero";
import { PipelineSection } from "./pipeline-section";
import { ProofSection } from "./proof-section";
import { SiteFooter } from "./site-footer";
import { SiteNav } from "./site-nav";
import { StatsRow } from "./stats-row";

/**
 * Moirai's landing page.
 *
 * One scroll driver feeds every section (see lib/moirai/scroll-store), so the
 * pinned scenes, the reveals and the hero carousel all read from a single pass
 * over the layout each frame.
 */
export function LandingPage() {
  useEffect(() => startDriver(), []);

  return (
    <div className="moirai">
      <SiteNav />
      <Hero />
      <StatsRow />
      <EngineSection />
      <ChatSection />
      <PipelineSection />
      <GallerySection />
      <ProofSection />
      <DownloadSection />
      <AndroidBar />
      <SiteFooter />
    </div>
  );
}
