import type { SVGProps } from "react";

/** Line icons shared across the page. All inherit `currentColor`. */

const stroke = {
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 2,
  strokeLinecap: "round",
  strokeLinejoin: "round",
} as const;

export const PulseIcon = (p: SVGProps<SVGSVGElement>) => (
  <svg viewBox="0 0 24 24" {...stroke} {...p}>
    <path d="M3 13h4l2.4-7 3.2 13L15 13h6" />
  </svg>
);

export const LeversIcon = (p: SVGProps<SVGSVGElement>) => (
  <svg viewBox="0 0 24 24" {...stroke} {...p}>
    <path d="M4 7h5M15 7h5M4 17h9M19 17h1" />
    <circle cx="12" cy="7" r="2.4" />
    <circle cx="16" cy="17" r="2.4" />
  </svg>
);

export const ShieldIcon = (p: SVGProps<SVGSVGElement>) => (
  <svg viewBox="0 0 24 24" {...stroke} strokeWidth={2.2} {...p}>
    <path d="M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6z" />
  </svg>
);

export const CheckIcon = (p: SVGProps<SVGSVGElement>) => (
  <svg viewBox="0 0 24 24" {...stroke} {...p}>
    <path d="M20 6L9 17l-5-5" />
  </svg>
);

export const RangeIcon = (p: SVGProps<SVGSVGElement>) => (
  <svg viewBox="0 0 24 24" {...stroke} {...p}>
    <path d="M3 16c4-8 14-8 18 0" />
    <path d="M3 11h18" />
  </svg>
);

export const ArrowRightIcon = (p: SVGProps<SVGSVGElement>) => (
  <svg viewBox="0 0 24 24" {...stroke} strokeWidth={2.2} {...p}>
    <path d="M5 12h13M12 5l7 7-7 7" />
  </svg>
);

export const NudgeArrowIcon = (p: SVGProps<SVGSVGElement>) => (
  <svg viewBox="0 0 24 24" {...stroke} strokeWidth={2.2} {...p}>
    <path d="M5 12h13M13 6l6 6-6 6" />
  </svg>
);

export const ChevronLeftIcon = (p: SVGProps<SVGSVGElement>) => (
  <svg viewBox="0 0 24 24" {...stroke} strokeWidth={2.3} {...p}>
    <path d="M15 5l-7 7 7 7" />
  </svg>
);

export const ChevronRightIcon = (p: SVGProps<SVGSVGElement>) => (
  <svg viewBox="0 0 24 24" {...stroke} strokeWidth={2.3} {...p}>
    <path d="M9 5l7 7-7 7" />
  </svg>
);

export const BurgerIcon = (p: SVGProps<SVGSVGElement>) => (
  <svg viewBox="0 0 24 24" {...stroke} {...p}>
    <path d="M4 7h16M4 12h16M4 17h16" />
  </svg>
);

export const LockIcon = ({
  shackleStyle,
  ...p
}: SVGProps<SVGSVGElement> & { shackleStyle?: SVGProps<SVGPathElement>["style"] }) => (
  <svg viewBox="0 0 24 24" {...stroke} strokeWidth={1.8} {...p}>
    <rect x="4" y="10.5" width="16" height="10" rx="3" />
    <path d="M8 10.5V7.6a4 4 0 018 0v2.9" style={shackleStyle} />
  </svg>
);

export const LockSmallIcon = (p: SVGProps<SVGSVGElement>) => (
  <svg viewBox="0 0 24 24" {...stroke} strokeWidth={1.9} {...p}>
    <rect x="4" y="10" width="16" height="10" rx="3" />
    <path d="M8 10V7.5a4 4 0 018 0V10" />
  </svg>
);

export const ReadIcon = (p: SVGProps<SVGSVGElement>) => (
  <svg viewBox="0 0 24 24" {...stroke} strokeWidth={1.9} {...p}>
    <path d="M4 7h9M4 12h12M4 17h6" />
    <path d="M17.5 15.5l2.5 2.5-4 1z" />
  </svg>
);

export const AskIcon = (p: SVGProps<SVGSVGElement>) => (
  <svg viewBox="0 0 24 24" {...stroke} strokeWidth={1.9} {...p}>
    <path d="M20 11.5a8 8 0 11-3.2-6.4" />
    <path d="M9 12l2.5 2.5L20 6" />
  </svg>
);

export const TickIcon = (p: SVGProps<SVGSVGElement>) => (
  <svg viewBox="0 0 24 24" {...stroke} strokeWidth={2.6} {...p}>
    <path d="M20 6L9 17l-5-5" />
  </svg>
);

export const TinyCheckIcon = (p: SVGProps<SVGSVGElement>) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth={3} strokeLinecap="round" {...p}>
    <path d="M5 13l4 4 10-10" />
  </svg>
);

export const StarIcon = (p: SVGProps<SVGSVGElement>) => (
  <svg viewBox="0 0 24 24" fill="#F2AE2E" {...p}>
    <path d="M12 2.8l2.8 5.9 6.4.8-4.7 4.4 1.2 6.3L12 17.1l-5.7 3.1 1.2-6.3-4.7-4.4 6.4-.8z" />
  </svg>
);

export const GooglePlayIcon = (p: SVGProps<SVGSVGElement>) => (
  <svg viewBox="0 0 24 24" {...p}>
    <path
      d="M3.9 1.9C3.35 2.2 3 2.78 3 3.55v16.9c0 .77.35 1.35.9 1.65L13.6 12 3.9 1.9z"
      fill="#2BD4FF"
    />
    <path d="M17.3 8.2 5.05 1.35C4.6 1.1 4.2 1.6 3.9 1.9L13.6 12l3.7-3.8z" fill="#00E17B" />
    <path
      d="M20.85 10.55 17.3 8.2 13.6 12l3.7 3.8 3.55-2.35c.75-.55.75-1.5 0-2.9z"
      fill="#FFC800"
    />
    <path d="M3.9 22.1c.3.3.7.8 1.15.55L17.3 15.8 13.6 12 3.9 22.1z" fill="#FF3A44" />
  </svg>
);

export const AppleIcon = (p: SVGProps<SVGSVGElement>) => (
  <svg viewBox="4.2 2.6 15.6 19" fill="#B5C2CC" {...p}>
    <path d="M17.05 12.53c.02-2.06 1.68-3.05 1.75-3.1-.96-1.4-2.44-1.56-2.97-1.58-1.26-.1-2.47.74-3.11.74-.65 0-1.64-.72-2.7-.7-1.39.02-2.67.81-3.38 2.05-1.44 2.5-.37 6.2 1.03 8.23.69.99 1.5 2.1 2.57 2.06 1.03-.04 1.42-.67 2.66-.67 1.24 0 1.59.66 2.67.64 1.11-.02 1.82-1.01 2.5-2 .78-1.14 1.1-2.24 1.12-2.3-.02-.01-2.15-.83-2.14-3.37z" />
    <path d="M14.9 6.36c.55-.66.92-1.58.82-2.5-.81.03-1.79.54-2.36 1.2-.51.58-.95 1.52-.83 2.42.9.07 1.82-.46 2.37-1.12z" />
  </svg>
);

export const LinkedInIcon = (p: SVGProps<SVGSVGElement>) => (
  <svg viewBox="0 0 24 24" fill="#0A66C2" {...p}>
    <path d="M4.98 3.5a2.5 2.5 0 11-.02 5 2.5 2.5 0 01.02-5zM3 9h4v12H3zM10 9h3.8v1.7h.06c.53-.95 1.83-1.95 3.77-1.95 4.03 0 4.77 2.5 4.77 5.75V21h-4v-5.6c0-1.34-.02-3.06-1.9-3.06-1.9 0-2.2 1.45-2.2 2.96V21h-4z" />
  </svg>
);

export const GitHubIcon = (p: SVGProps<SVGSVGElement>) => (
  <svg viewBox="0 0 512 512" fill="currentColor" {...p}>
    <path d="M216.5 362.5c-66-8-112.5-55.5-112.5-117 0-25 9-52 24-70-6.5-16.5-5.5-51.5 2-66 20-2.5 47 8 63 22.5 19-6 39-9 63.5-9s44.5 3 62.5 8.5c15.5-14 43-24.5 63-22 7 13.5 8 48.5 1.5 65.5 16 19 24.5 44.5 24.5 70.5 0 61.5-46.5 108-113.5 116.5 17 11 28.5 35 28.5 62.5l0 52C323 491.5 335.5 500 350.5 494 441 459.5 512 369 512 257 512 115.5 397 0 255.5 0S0 115.5 0 257c0 111 70.5 203 165.5 237.5 13.5 5 26.5-4 26.5-17.5l0-40c-7 3-16 5-24 5-33 0-52.5-18-66.5-51.5-5.5-13.5-11.5-21.5-23-23-6-.5-8-3-8-6 0-6 10-10.5 20-10.5 14.5 0 27 9 40 27.5 10 14.5 20.5 21 33 21s20.5-4.5 32-16c8.5-8.5 15-16 21-21z" />
  </svg>
);

/** The mascot silhouette, used flat as a tab-bar glyph. */
export const MoiraiGlyph = (p: SVGProps<SVGSVGElement>) => (
  <svg viewBox="0 0 64 64" {...p}>
    <path
      d="M54.65,47.17c-.09-.02-.18-.05-.27-.06-.07,0-.15-.02-.25-.04-.72-.1-2.37-.33-3.69-2.73,4.22-1.83,9.79-6.72,9.46-17.67-.43-13.89-12.22-21.07-19.12-23.13C36.53,2.26,28.47.63,20.85.1h-.19c-.34,0-.71-.02-1.07-.04-.41-.02-.81-.05-1.16-.05-2.35,0-3.31,1.13-3.71,2.07-.55,1.34-.32,2.78-.21,3.25l.79,3.88c-2.17,2.33-7.28,8.86-7.36,18.99-.07,7.64,3.72,12.06,7.42,14.3-.54.23-1.16.39-1.86.39-.44,0-1.38-.16-1.9-.27-.09-.02-.21-.04-.3-.05,0,0-.26-.03-.68-.03-1.19,0-3.42.24-4.99,1.86-.72.74-1.57,2.07-1.52,4.15.11,3.98,2.89,6.51,7.25,6.6h.46c1.66,0,4.21-.22,6.82-1.28-.36.8-.64,1.77-.61,2.86.03,1.11.42,2.75,2.07,4.23,1.24,1.11,2.69,1.71,4.18,1.71,2.87,0,4.85-2.08,5.43-2.95l.06-.09c.91-1.21,1.68-2.54,2.33-3.95.97,2.84,2.71,5.56,5.73,7.45.06.04.13.08.2.11,1,.52,2.02.78,3.03.78,1.93,0,3.68-.96,4.79-2.63.87-1.3,1.2-2.78,1.01-4.24,1.47.9,3.17,1.59,5.15,1.93.46.09.93.14,1.4.14,3.48,0,6.14-2.41,6.46-5.86.11-1.21.06-5.21-5.19-6.17l-.03-.02ZM57.16,53.09c-.23,2.42-2.07,3.42-3.79,3.42-.31,0-.61-.03-.89-.09-9.91-1.7-11-13.24-11-13.24,0,0-1.08-.06-1.83-.06-.68,8.49,2.51,10.94,3.66,12.43s1.09,3.12.27,4.34c-.55.82-1.43,1.43-2.55,1.43-.55,0-1.15-.14-1.79-.48-8.01-5.03-5.03-17.86-5.03-17.86h-1.56c-1.29,10.86-4.94,14.77-5.21,15.23-.19.32-1.49,1.75-3.19,1.75-.74,0-1.55-.27-2.38-1.02-2.75-2.46.18-5.44.18-5.44,0,0,1.24-1.33,1.97-2.24,3.34-5.67,3.43-8.74,3.43-8.74,0,0-.92,0-1.6-.09-2.75,5.3-4.09,6.12-4.09,6.12-3.42,3.63-8.2,3.91-9.96,3.91h-.4c-1.29-.03-4.52-.33-4.62-3.98-.08-2.96,2.74-3.24,3.82-3.24.25,0,.41.02.41.02,0,0,1.52.33,2.48.33,4.52-.03,6.74-3.97,6.74-3.97,0,0-9.73-1.83-9.63-13.38.1-11.55,7.4-17.93,7.4-17.93.14-.4.05-.91.05-.91l-.93-4.62s-.22-.96.06-1.65c.14-.33.61-.42,1.23-.42s1.44.09,2.23.09c7.67.54,15.49,2.17,19.35,3.33,3.87,1.15,16.77,6.71,17.2,20.63.42,13.91-9.39,15.75-10.34,15.82,1.9,6.86,6.25,7.06,7.06,7.2h-.03c.82.15,3.53.49,3.26,3.33l.02-.02ZM42.07,29.87l-6.2-.36h-.03c-.29,0-.53.23-.53.52,0,1.19.31,3.88,3.43,3.94h.08c3.03,0,3.61-2.45,3.72-3.54.03-.29-.19-.54-.48-.56h0ZM29.83,23.94c-1.64,0-2.97,1.29-2.97,2.88s1.33,2.88,2.97,2.88,2.97-1.29,2.97-2.88-1.33-2.88-2.97-2.88ZM51.41,28.39c0-1.59-1.33-2.88-2.97-2.88s-2.97,1.29-2.97,2.88,1.33,2.88,2.97,2.88,2.97-1.29,2.97-2.88Z"
      fill="currentColor"
    />
  </svg>
);
