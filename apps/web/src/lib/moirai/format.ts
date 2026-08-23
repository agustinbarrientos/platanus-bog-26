/**
 * es-CO number formatting done by hand.
 *
 * `toLocaleString` depends on the runtime's ICU data, which can differ between
 * the server render and the browser; these counters animate on screen, so the
 * separators have to be identical either way.
 */
export function formatEsCO(n: number): string {
  const [int, frac] = Math.abs(n).toFixed(Number.isInteger(n) ? 0 : 1).split(".");
  const grouped = int.replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  return (n < 0 ? "-" : "") + grouped + (frac ? "," + frac : "");
}

/**
 * Always one decimal, es-CO. `formatEsCO` drops the decimal on whole numbers,
 * which reads as a different precision when a 55 sits in the same sentence as
 * a 51,4 — and makes a counting number jump a character wide mid-count. Use
 * this for every biological age and every delta in years.
 */
export function formatEsCO1(n: number): string {
  const [int, frac] = Math.abs(n).toFixed(1).split(".");
  const grouped = int.replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  return (n < 0 ? "-" : "") + grouped + "," + frac;
}
