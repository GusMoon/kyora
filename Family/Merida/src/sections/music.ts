import { h, shortWhen } from "../ui/dom";
import { formatSize, formatTime, playlists, type Track } from "../data/music";
import type { PlayerState } from "../player";
import type { Ctx, Section } from "./context";

export function musicStatement(tracks: Track[], loaded: boolean, error?: string): string {
  if (error) return error;
  if (!loaded) return "Cargando tus canciones.";
  if (!tracks.length) return "Aún no hay canciones. Mándalas desde la PC con Descargar.";
  const lists = playlists(tracks).length;
  const head = tracks.length === 1 ? "1 canción" : `${tracks.length} canciones`;
  return lists ? `${head} en ${lists === 1 ? "1 lista" : `${lists} listas`}.` : `${head}.`;
}

export const musicSection: Section = (ctx: Ctx) => {
  const { store, shell, player } = ctx;

  const rows = h("tbody");
  const table = h(
    "table",
    { class: "tracks" },
    h("caption", { class: "sr-only" }, "Canciones recibidas"),
    h("thead", {}, h("tr", {}, h("th", { scope: "col" }, "Título"), h("th", { scope: "col", class: "col-list" }, "Lista"), h("th", { scope: "col", class: "num" }, "Tamaño"), h("th", { scope: "col", class: "num" }, "Llegó"))),
    rows,
  );

  // El bloque «sonando»
  const cover = h("div", { class: "deck-cover", "aria-hidden": "true" });
  const title = h("p", { class: "deck-title" });
  const sub = h("p", { class: "deck-sub" });
  const error = h("p", { class: "form-error", role: "alert" });
  const elapsed = h("span", { class: "readout" }, "0:00");
  const total = h("span", { class: "readout" }, "0:00");
  const fill = h("div", { class: "bar-fill" });
  const bar = h("div", { class: "bar", role: "slider", tabindex: 0, "aria-label": "Avance de la canción", "aria-valuemin": 0, "aria-valuemax": 100, "aria-valuenow": 0 }, fill);
  bar.addEventListener("click", (e) => {
    const r = bar.getBoundingClientRect();
    player.seek((e.clientX - r.left) / r.width);
  });
  bar.addEventListener("keydown", (e) => {
    const s = player.state;
    if (!s.duration) return;
    if (e.key === "ArrowRight") player.seek((s.time + 5) / s.duration);
    else if (e.key === "ArrowLeft") player.seek((s.time - 5) / s.duration);
    else return;
    e.preventDefault();
  });
  const prev = h("button", { class: "btn-step", type: "button", "aria-label": "Anterior", onClick: () => player.previous() }, "⏮");
  const toggle = h("button", { class: "btn-solid btn-play", type: "button", onClick: () => player.toggle() }, "Reproducir");
  const next = h("button", { class: "btn-step", type: "button", "aria-label": "Siguiente", onClick: () => player.next() }, "⏭");

  const deck = h(
    "section",
    { class: "deck", "aria-label": "Sonando" },
    cover,
    h("div", { class: "deck-info" }, title, sub),
    bar,
    h("div", { class: "deck-times" }, elapsed, total),
    h("div", { class: "deck-controls" }, prev, toggle, next),
    error,
  );

  function renderDeck(s: PlayerState) {
    const t = s.track;
    deck.dataset.empty = String(!t);
    title.textContent = t ? t.title : "Nada sonando";
    sub.textContent = t ? t.playlist ?? "Sin lista" : "Elige una canción de la tabla.";
    cover.replaceChildren(t?.cover_url ? h("img", { src: t.cover_url, alt: "", referrerpolicy: "no-referrer" }) : h("span", {}, (t?.title ?? "M").trim().charAt(0).toUpperCase()));
    toggle.textContent = s.loading ? "Cargando" : s.playing ? "Pausar" : "Reproducir";
    toggle.disabled = !t || s.loading;
    prev.disabled = next.disabled = !t;
    const pct = s.duration ? (s.time / s.duration) * 100 : 0;
    fill.style.width = `${pct}%`;
    bar.setAttribute("aria-valuenow", String(Math.round(pct)));
    bar.setAttribute("aria-valuetext", `${formatTime(s.time)} de ${formatTime(s.duration)}`);
    elapsed.textContent = formatTime(s.time);
    total.textContent = formatTime(s.duration);
    error.textContent = s.error ?? "";
    for (const row of rows.querySelectorAll<HTMLTableRowElement>("tr")) {
      if (row.dataset.id === t?.id) row.setAttribute("aria-current", "true");
      else row.removeAttribute("aria-current");
    }
  }

  function renderList() {
    shell.setStatement(musicStatement(store.tracks, store.loaded.tracks, store.errors.tracks));
    const current = player.state.track?.id;
    rows.replaceChildren(
      ...store.tracks.map((t) =>
        h(
          "tr",
          { "data-id": t.id, "aria-current": t.id === current ? "true" : null },
          h("td", {}, h("button", { class: "track-play", type: "button", onClick: () => void player.play(t, store.tracks) }, t.title)),
          h("td", { class: "col-list" }, t.playlist ?? ""),
          h("td", { class: "num readout" }, formatSize(t.size_bytes)),
          h("td", { class: "num readout" }, shortWhen(t.created_at)),
        ),
      ),
    );
  }

  shell.body.append(h("div", { class: "music" }, h("div", { class: "tracks-wrap" }, table), deck));
  renderList();
  const offStore = store.on((area) => area === "tracks" && renderList());
  const offPlayer = player.on(renderDeck);
  return () => {
    offStore();
    offPlayer();
  };
};
