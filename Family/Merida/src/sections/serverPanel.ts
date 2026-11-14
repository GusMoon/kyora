import { h } from "../ui/dom";
import { icon } from "../ui/icons";
import { WARN_AT, formatBytes, percent, quotas, warningText, type Quota } from "../data/server";
import { agoLabel } from "../data/cloud";
import type { Ctx } from "./context";

/** El panel «Servidor» de la Nube: cuánto ocupa tu proyecto de Supabase frente al plan gratuito, con una advertencia al llegar al
 * 80 %. Lee la función `server_stats()` (schema.sql §15) y se actualiza al abrir la Nube, con el botón y cada media hora. */
export function serverPanel(ctx: Ctx): { el: HTMLElement; off: () => void } {
  const { store, prefs, reload } = ctx;
  const el = h("section", { class: "srv", "aria-label": "Estadísticas del servidor" });
  let busy = false;

  async function measure() {
    busy = true;
    render();
    await reload("server");
    busy = false;
    render();
  }

  function meter(q: Quota): HTMLElement {
    const fill = Math.min(1, q.ratio);
    const left = Math.max(0, q.limit - q.used);
    return h("div", { class: `srv-meter is-${q.level}`, "data-quota": q.id },
      h("div", { class: "srv-meter-head" },
        h("span", { class: "label" }, q.label),
        h("span", { class: "srv-pct readout", "aria-label": `${percent(q.ratio)} ocupado` }, percent(q.ratio)),
      ),
      h("div", { class: "srv-bar", role: "progressbar", "aria-label": q.label, "aria-valuemin": "0", "aria-valuemax": "100", "aria-valuenow": String(Math.min(100, Math.floor(q.ratio * 100))) },
        h("div", { class: "srv-fill", style: `--p:${fill}` }),
        h("span", { class: "srv-mark", style: `--at:${WARN_AT}`, title: "Aviso al 80 %" }),
      ),
      h("p", { class: "srv-sub readout" }, `${formatBytes(q.used)} de ${formatBytes(q.limit)} · ${q.ratio >= 1 ? "sin espacio libre" : `quedan ${formatBytes(left)}`}`),
    );
  }

  function render() {
    const stats = store.serverStats;
    const error = store.errors.server;
    const refresh = h("button", { class: "btn-quiet", type: "button", disabled: busy, onClick: () => void measure() }, icon("refresh", "icon"), busy ? "Midiendo…" : "Medir ahora");
    const head = h("div", { class: "srv-head" },
      h("h3", { class: "cfg-title" }, "Servidor · Supabase"),
      stats ? h("span", { class: "srv-when readout" }, `medido ${agoLabel(stats.at)}`) : null,
      refresh,
    );
    if (!stats) {
      el.replaceChildren(head, error ? h("p", { class: "form-error", role: "alert" }, error) : h("p", { class: "cfg-help", role: "status" }, "Midiendo el servidor…"));
      return;
    }
    const qs = quotas(stats, { db: prefs.value.quotaDbMb, files: prefs.value.quotaFilesMb });
    const over = qs.filter((q) => q.level !== "ok");
    const maxTable = Math.max(1, ...stats.tables.map((t) => t.bytes));
    const maxBucket = Math.max(1, ...stats.buckets.map((b) => b.bytes));
    el.replaceChildren(
      h("div", { class: "srv-inner" },
      head,
      over.length
        ? h("div", { class: `srv-warn${over.some((q) => q.level === "critical") ? " is-critical" : ""}`, role: "alert" },
            h("strong", {}, over.some((q) => q.ratio >= 1) ? "Superaste un límite del plan gratuito." : `Estás al ${percent(Math.max(...over.map((q) => q.ratio)))} del plan gratuito.`),
            h("ul", {}, over.map((q) => h("li", {}, warningText(q)))),
            h("p", {}, "Libera espacio (elimina archivos de esta página) o pasa a un plan de pago antes de que Supabase restrinja el proyecto."),
          )
        : null,
      error ? h("p", { class: "form-error", role: "alert" }, error) : null,
      h("div", { class: "srv-meters" }, qs.map(meter)),
      h("details", { class: "srv-more" },
        h("summary", { class: "label" }, "Desglose"),
        h("div", { class: "srv-cols" },
          h("div", {},
            h("p", { class: "label" }, `Archivos · ${stats.storage_objects} en total`),
            stats.buckets.length
              ? h("ul", { class: "srv-list" }, stats.buckets.map((b) => h("li", { style: `--p:${b.bytes / maxBucket}` }, h("span", { class: "srv-name" }, b.bucket), h("span", { class: "srv-val readout" }, `${formatBytes(b.bytes)} · ${b.objects}`))))
              : h("p", { class: "cfg-help" }, "Sin archivos."),
          ),
          h("div", {},
            h("p", { class: "label" }, "Tablas más grandes"),
            h("ul", { class: "srv-list" }, stats.tables.slice(0, 8).map((t) => h("li", { style: `--p:${t.bytes / maxTable}` }, h("span", { class: "srv-name" }, t.name), h("span", { class: "srv-val readout" }, `${formatBytes(t.bytes)} · ${t.rows} filas`)))),
          ),
        ),
      ),
      h("p", { class: "cfg-help srv-note" }, `Límites del plan gratuito: base de datos ${formatBytes(prefs.value.quotaDbMb * 1024 * 1024)} y archivos ${formatBytes(prefs.value.quotaFilesMb * 1024 * 1024)} (se cambian en Configuración → Servidor). La base de datos incluye lo del sistema de Supabase. El tráfico del mes y los usuarios activos no se pueden medir desde aquí: míralos en Supabase → Settings → Usage.`),
      ),
    );
  }

  render();
  void measure();
  const offStore = store.on((area) => area === "server" && render());
  const offPrefs = prefs.on(() => render());
  return {
    el,
    off: () => {
      offStore();
      offPrefs();
    },
  };
}
