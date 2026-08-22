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
