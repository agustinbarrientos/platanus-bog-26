"use client";

import { MonitorIcon, MoonIcon, SunIcon } from "lucide-react";
import { useTheme } from "next-themes";
import { useState } from "react";

import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import type { ThemeOption } from "@/types";

const themeOptions = [
  { label: "Light", value: "light", icon: SunIcon },
  { label: "Dark", value: "dark", icon: MoonIcon },
  { label: "System", value: "system", icon: MonitorIcon },
] as const satisfies readonly ThemeOption[];

const themeTriggerId = "theme-menu-trigger";

export function ThemeToggle() {
  const { setTheme } = useTheme();
  const [isOpen, setIsOpen] = useState(false);

  return (
    <DropdownMenu
      open={isOpen}
      onOpenChange={setIsOpen}
      triggerId={themeTriggerId}
    >
      <DropdownMenuTrigger
        id={themeTriggerId}
        render={
          <Button
            variant="outline"
            size="icon"
            className="relative"
            aria-label="Select theme"
          />
        }
        onKeyDown={(event) => {
          if (event.key === "Enter" || event.key === " ") {
            event.preventDefault();
            setIsOpen(true);
          }
        }}
      >
        <SunIcon
          aria-hidden="true"
          className="size-4 scale-100 rotate-0 transition-all dark:scale-0 dark:-rotate-90"
        />
        <MoonIcon
          aria-hidden="true"
          className="absolute size-4 scale-0 rotate-90 transition-all dark:scale-100 dark:rotate-0"
        />
        <span className="sr-only">Select theme</span>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        {themeOptions.map(({ label, value, icon: Icon }) => (
          <DropdownMenuItem key={value} onClick={() => setTheme(value)}>
            <Icon aria-hidden="true" />
            {label}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
