import { ArrowUpRightIcon, AtSignIcon, UsersRoundIcon } from "lucide-react";

import { ThemeToggle } from "@/components/theme-toggle";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import type { TeamMember } from "@/types";

const teamMembers = [
  { name: "Leandro Agustin Barrientos", githubUsername: "agustinbarrientos" },
  { name: "Felipe Rueda Rivera", githubUsername: "feru34" },
  { name: "Kalia González", githubUsername: "kaliagonzalez" },
  { name: "Juan Montealegre", githubUsername: "montejs3" },
  { name: "Laura Zuluaga Pineda", githubUsername: "lauzulu" },
] as const satisfies readonly TeamMember[];

export default function Home() {
  return (
    <main className="min-h-svh bg-background text-foreground">
      <div className="mx-auto flex min-h-svh w-full max-w-5xl flex-col px-6 py-6 sm:px-8 lg:px-12">
        <header className="flex items-center justify-between border-b pb-5">
          <div className="flex items-center gap-3">
            <div className="flex size-9 items-center justify-center rounded-lg border bg-card">
              <UsersRoundIcon aria-hidden="true" className="size-4" />
            </div>
            <div>
              <p className="text-sm font-medium">Platanus Hack 26</p>
              <p className="text-xs text-muted-foreground">Bogotá · Simulations</p>
            </div>
          </div>
          <ThemeToggle />
        </header>

        <section aria-labelledby="team-heading" className="flex flex-1 flex-col justify-center py-16 sm:py-24">
          <div className="max-w-3xl">
            <Badge variant="secondary" className="mb-5">Simulations challenge</Badge>
            <h1 id="team-heading" className="text-balance text-4xl font-semibold tracking-tight sm:text-6xl">Team 37</h1>
            <p className="mt-5 max-w-2xl text-pretty text-base leading-7 text-muted-foreground sm:text-lg">Five builders working together for the simulations track at Platanus Hack 26 Bogotá.</p>
          </div>

          <ul className="mt-12 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {teamMembers.map(({ name, githubUsername }) => (
              <li key={githubUsername}>
                <a href={`https://github.com/${githubUsername}`} target="_blank" rel="noreferrer" aria-label={`${name}, @${githubUsername} on GitHub, opens in a new tab`} className="block rounded-xl outline-none focus-visible:ring-3 focus-visible:ring-ring/50">
                  <Card className="h-full transition-colors hover:bg-muted/50">
                    <CardContent className="flex items-center justify-between gap-4">
                      <div className="min-w-0">
                        <p className="font-medium">{name}</p>
                        <p className="mt-1 flex items-center gap-1.5 text-sm text-muted-foreground">
                          <AtSignIcon aria-hidden="true" className="size-4" />
                          @{githubUsername}
                        </p>
                      </div>
                      <ArrowUpRightIcon aria-hidden="true" className="size-4 shrink-0 text-muted-foreground" />
                    </CardContent>
                  </Card>
                </a>
              </li>
            ))}
          </ul>
        </section>

        <footer className="border-t pt-5 text-sm text-muted-foreground">Team 37 · Platanus Hack 26</footer>
      </div>
    </main>
  );
}
