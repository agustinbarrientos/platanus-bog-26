import { ArrowLeftIcon } from "lucide-react";
import Link from "next/link";

import { buttonVariants } from "@/components/ui/button";

export default function NotFound() {
  return (
    <main className="grid min-h-svh place-items-center px-6">
      <section
        aria-labelledby="not-found-heading"
        className="w-full max-w-md space-y-6 text-center"
      >
        <p className="text-sm font-medium text-muted-foreground">404</p>
        <div className="space-y-2">
          <h1 id="not-found-heading" className="text-2xl font-semibold">
            Page not found
          </h1>
          <p className="text-sm leading-6 text-muted-foreground">
            The page you requested does not exist.
          </p>
        </div>
        <Link href="/" className={buttonVariants({ variant: "outline" })}>
          <ArrowLeftIcon aria-hidden="true" data-icon="inline-start" />
          Back home
        </Link>
      </section>
    </main>
  );
}
