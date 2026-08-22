import type { LucideIcon } from "lucide-react";
import type { ThemeProvider as NextThemesProvider } from "next-themes";
import type { ComponentProps, ReactNode } from "react";

export type RootLayoutProps = Readonly<{
  children: ReactNode;
}>;

export type ThemeProviderProps = ComponentProps<typeof NextThemesProvider>;

export type ThemeOption = {
  label: string;
  value: "light" | "dark" | "system";
  icon: LucideIcon;
};

export type Highlight = {
  title: string;
  description: string;
  icon: LucideIcon;
};

export type ErrorPageProps = {
  error: Error & { digest?: string };
  reset: () => void;
};
