import type { Metadata, Viewport } from "next";
import { Fredoka, Nunito } from "next/font/google";

import { ThemeProvider } from "@/components/theme-provider";
import type { RootLayoutProps } from "@/types";

import "./globals.css";

// Fredoka carries the display numbers, Nunito the prose.
const fredoka = Fredoka({
  variable: "--font-fredoka",
  subsets: ["latin"],
  weight: ["400", "500", "600"],
});

const nunito = Nunito({
  variable: "--font-nunito",
  subsets: ["latin"],
  weight: ["400", "600", "700"],
  style: ["normal", "italic"],
});

export const metadata: Metadata = {
  title: "Moirai · Cuánto puedes frenar el reloj de tu cuerpo",
  description:
    "Sube tu examen y contesta unas preguntas. Simulo diez mil futuros tuyos y te digo qué decisión le quita más años a tu cuerpo.",
  icons: { icon: "/moirai/moirai-icon.svg" },
  openGraph: {
    title: "Moirai · Cuánto puedes frenar el reloj de tu cuerpo",
    description:
      "Simulo diez mil futuros tuyos, luego los repito cambiando una sola cosa. Esa diferencia es lo que ganas.",
    locale: "es_CO",
    type: "website",
  },
};

export const viewport: Viewport = {
  themeColor: "#EFF8FE",
};

export default function RootLayout({ children }: RootLayoutProps) {
  return (
    <html
      lang="es"
      className={`${fredoka.variable} ${nunito.variable}`}
      suppressHydrationWarning
    >
      <body className="min-h-screen bg-background font-sans antialiased">
        {/* The design system is light-only: no dark palette was ever drawn. */}
        <ThemeProvider
          attribute="class"
          defaultTheme="light"
          enableSystem={false}
          disableTransitionOnChange
        >
          {children}
        </ThemeProvider>
      </body>
    </html>
  );
}
