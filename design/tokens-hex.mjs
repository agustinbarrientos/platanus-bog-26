// oklch -> sRGB hex, so the Flutter side can use the exact same palette.
const T = {
  bg:'0.982 0.008 215', surface:'1 0.002 215', surface2:'0.966 0.012 212',
  ink:'0.30 0.028 245', ink2:'0.53 0.022 245', ink3:'0.67 0.018 245',
  line:'0.915 0.012 220',
  blue:'0.72 0.085 232', blueSoft:'0.935 0.032 232', blueInk:'0.46 0.075 240',
  green:'0.72 0.085 158', greenSoft:'0.935 0.032 158', greenInk:'0.44 0.070 160',
  amber:'0.76 0.085 78', amberSoft:'0.948 0.032 78', amberInk:'0.48 0.070 70',
};
const g = (x) => x <= 0.0031308 ? 12.92*x : 1.055*Math.pow(x, 1/2.4) - 0.055;
function hex(str) {
  const [L, C, H] = str.split(' ').map(Number);
  const h = H * Math.PI / 180, a = C * Math.cos(h), b = C * Math.sin(h);
  const l_ = L + 0.3963377774*a + 0.2158037573*b;
  const m_ = L - 0.1055613458*a - 0.0638541728*b;
  const s_ = L - 0.0894841775*a - 1.2914855480*b;
  const l = l_**3, m = m_**3, s = s_**3;
  const rgb = [
     4.0767416621*l - 3.3077115913*m + 0.2309699292*s,
    -1.2684380046*l + 2.6097574011*m - 0.3413193965*s,
    -0.0041960863*l - 0.7034186147*m + 1.7076147010*s,
  ].map((v) => Math.round(Math.min(1, Math.max(0, g(v))) * 255));
  return '#' + rgb.map((v) => v.toString(16).padStart(2, '0').toUpperCase()).join('');
}
const rows = Object.entries(T).map(([k, v]) => [k, v, hex(v)]);
console.log(rows.map(([k, v, h]) => `${k.padEnd(10)} oklch(${v})`.padEnd(38) + h).join('\n'));
console.log('\n--- Flutter ---');
console.log(rows.map(([k, , h]) => `  static const ${k} = Color(0xFF${h.slice(1)});`).join('\n'));
