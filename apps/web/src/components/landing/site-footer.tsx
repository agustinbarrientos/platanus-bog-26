import { MoiraiLogo, PlatanusIcon } from "./brand";
import { GitHubIcon, LinkedInIcon } from "./icons";

const TEAM = [
  { name: "Agustín Barrientos", url: "https://www.linkedin.com/in/barrientosagustin/" },
  { name: "Felipe Rueda Rivera", url: "https://www.linkedin.com/in/feliperuedarivera/" },
  { name: "Juan Montealegre", url: "https://www.linkedin.com/in/jsmontealegre/" },
  { name: "Laura Zuluaga Pineda", url: "https://www.linkedin.com/in/laura-zuluaga-pineda/" },
];

export function SiteFooter() {
  return (
    <div className="mo-footer">
      <div className="mo-footer__row">
        <MoiraiLogo aria-label="Moirai" style={{ height: 22, width: "auto", display: "block" }} />
        <span style={{ fontWeight: 600, fontSize: 12.5, color: "#4F5D69" }}>
          Cuánto puedes frenar el reloj de tu cuerpo.
        </span>
        <a
          className="mo-footer__repo"
          href="https://github.com/platanus-hack/platanus-hack-26-co-team-37"
          target="_blank"
          rel="noopener noreferrer"
          aria-label="Código en GitHub"
        >
          <GitHubIcon width={16} height={16} style={{ display: "block" }} />
        </a>
        <div style={{ flex: 1 }} />
        <a className="mo-footer__link" href="#motor">
          Cómo funciona
        </a>
        <a className="mo-footer__link" href="#respaldo">
          Respaldo
        </a>
      </div>
      <div style={{ borderTop: "1px solid #E9EFF3" }}>
        <div className="mo-footer__row" style={{ padding: "14px 28px", gap: "8px 14px" }}>
          <span className="mo-footer__credit">
            <PlatanusIcon width={17} height={17} style={{ display: "block" }} />
            Hecho en 36 horas en{" "}
            <a href="https://hack.platan.us/26-co" target="_blank" rel="noopener noreferrer">
              Platanus Hack 26
            </a>{" "}
            · Bogotá
          </span>
          {TEAM.map((p) => (
            <a
              key={p.url}
              className="mo-footer__person"
              href={p.url}
              target="_blank"
              rel="noopener noreferrer"
            >
              <LinkedInIcon width={13} height={13} style={{ flex: "none" }} />
              {p.name}
            </a>
          ))}
        </div>
      </div>
    </div>
  );
}
