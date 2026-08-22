import {
  BlocksIcon,
  CloudUploadIcon,
  Code2Icon,
  ZapIcon,
} from "lucide-react";

import { ThemeToggle } from "@/components/theme-toggle";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import type { Highlight } from "@/types";

const stack = ["Next.js", "Tailwind CSS", "shadcn/ui", "Vercel"] as const;

const highlights = [
  {
    title: "Fast local iteration",
    description: "Start with npm run dev. Use npm run check before the demo.",
    icon: ZapIcon,
  },
  {
    title: "Deliberately unopinionated",
    description:
      "Add authentication, data, and integrations only when the product needs them.",
    icon: BlocksIcon,
  },
  {
    title: "Deploy on push",
    description:
      "Vercel creates previews for branches and production builds from main.",
    icon: CloudUploadIcon,
  },
] as const satisfies readonly Highlight[];

export default function Home() {
  return (
    <main className="min-h-svh bg-background text-foreground">
      <div className="mx-auto flex min-h-svh w-full max-w-6xl flex-col px-6 py-6 sm:px-8 lg:px-12">
        <header className="flex items-center justify-between border-b pb-5">
          <div className="flex items-center gap-3">
            <div className="flex size-9 items-center justify-center rounded-lg border bg-card">
              <Code2Icon aria-hidden="true" className="size-4" />
            </div>
            <div>
              <p className="text-sm font-medium">Hackathon Starter</p>
              <p className="text-xs text-muted-foreground">
                Next.js on Vercel
              </p>
            </div>
          </div>
          <ThemeToggle />
        </header>

        <section
          aria-labelledby="starter-heading"
          className="flex flex-1 flex-col justify-center py-16 sm:py-24"
        >
          <div className="max-w-3xl">
            <Badge variant="secondary" className="mb-5 gap-2">
              <span
                aria-hidden="true"
                className="size-1.5 rounded-full bg-emerald-500"
              />
              Ready to build
            </Badge>
            <h1
              id="starter-heading"
              className="text-balance text-4xl font-semibold tracking-tight sm:text-6xl"
            >
              Build the idea, not the setup.
            </h1>
            <p className="mt-5 max-w-2xl text-pretty text-base leading-7 text-muted-foreground sm:text-lg">
              A focused foundation for moving from a blank repository to a
              working product without choosing the product too early.
            </p>
            <div className="mt-6 flex flex-wrap gap-2">
              {stack.map((item) => (
                <Badge key={item} variant="outline">
                  {item}
                </Badge>
              ))}
            </div>
          </div>

          <div className="mt-12 grid gap-4 md:grid-cols-3">
            {highlights.map(({ title, description, icon: Icon }) => (
              <Card key={title} className="bg-card/70 shadow-none">
                <CardHeader className="gap-4">
                  <div className="flex size-10 items-center justify-center rounded-lg bg-muted">
                    <Icon
                      aria-hidden="true"
                      className="size-5 text-muted-foreground"
                    />
                  </div>
                  <div className="space-y-2">
                    <CardTitle>{title}</CardTitle>
                    <CardDescription className="leading-6">
                      {description}
                    </CardDescription>
                  </div>
                </CardHeader>
              </Card>
            ))}
          </div>
        </section>

        <footer className="border-t pt-5 text-sm text-muted-foreground">
          Replace{" "}
          <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs text-foreground">
            src/app/page.tsx
          </code>{" "}
          when the product takes shape.
        </footer>
      </div>
    </main>
  );
}
