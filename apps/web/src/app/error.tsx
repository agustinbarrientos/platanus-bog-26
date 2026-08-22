"use client";

import { RotateCcwIcon, TriangleAlertIcon } from "lucide-react";

import { Button } from "@/components/ui/button";
import type { ErrorPageProps } from "@/types";

export default function ErrorPage({ reset }: ErrorPageProps) {
  return (
    <main className="grid min-h-svh place-items-center px-6">
      <section
        aria-labelledby="error-heading"
        className="w-full max-w-md space-y-6 text-center"
      >
        <div className="mx-auto flex size-12 items-center justify-center rounded-full bg-destructive/10 text-destructive">
          <TriangleAlertIcon aria-hidden="true" className="size-6" />
        </div>
        <div className="space-y-2">
          <h1 id="error-heading" className="text-2xl font-semibold">
            Something went wrong
          </h1>
          <p className="text-sm leading-6 text-muted-foreground">
            The page could not be loaded. Try the request again.
          </p>
        </div>
        <Button onClick={reset}>
          <RotateCcwIcon aria-hidden="true" data-icon="inline-start" />
          Try again
        </Button>
      </section>
    </main>
  );
}
