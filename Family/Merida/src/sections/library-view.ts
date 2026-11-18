import { h } from "../ui/dom";
import { icon } from "../ui/icons";
import { formatTime } from "../data/music";
import {
  COOKIE_HINT,
  FOLDER,
  SERVICE_DOWN,
  applyEvent,
  emptyLibrary,
  needsCookies,
  type LibraryState,
  type MusicEvent,
  type Playlist,
  type Recipient,
  type Song,
} from "../data/library";
import type { Ctx } from "./context";

const STATE_TEXT: Record<string, string> = {
  pending: "",
  queued: "en cola",
  doing: "bajando",
  sending: "enviando",
  done: "hecha",
  error: "error",
};

/** «Mis listas»: tus listas de YouTube (con tus cookies) por el servicio local; bajar y decidir a dónde va cada canción. */
export function libraryView(ctx: Ctx): { el: HTMLElement; destroy: () => void } {
  const { library, player } = ctx;
  let state: LibraryState = emptyLibrary();
  let selectedList: string | null = null;
  const picked = new Set<string>();
  let defaultRecipient: string | null = null; // de los ajustes del servicio ("me", un id o "folder")
  let choosing = false; // el panel de destino está abierto
  let alive = true;
  let stopEvents: () => void = () => {};
  let pendingStream: { id: string; title: string } | null = null;

  const notice = h("div", { class: "lib-notice", role: "status" });
  const lists = h("nav", { class: "lib-lists", "aria-label": "Tus listas de YouTube" });
  const songs = h("section", { class: "lib-songs", "aria-label": "Canciones de la lista" });
  const el = h("div", { class: "lib" }, notice, h("div", { class: "lib-grid" }, lists, songs));

  const act = async (name: string, payload: Record<string, unknown> = {}) => {
    const res = await library.act(name, payload);
    if (!res.ok && alive) {
      state = { ...state, error: { where: "action", message: res.error?.message ?? "El servicio no pudo hacerlo" } };
      renderNotice();
    }
    return res;
  };

  // ----------------------------------------------------------- avisos (servicio, FFmpeg, cookies, errores)

  let lastNoticeKey = "";
  function renderNotice(force = false) {
    const key = JSON.stringify([state.ffmpeg, state.error, state.lastSaved]);
    if (key === lastNoticeKey && !force) return; // no rehacer: el panel de cookies puede tener texto escrito
    lastNoticeKey = key;
    const parts: Node[] = [];
    if (state.ffmpeg && !state.ffmpeg.available) {
      parts.push(
        h(
          "div",
          { class: "lib-warn" },
          h("p", {}, state.ffmpeg.message || "Falta FFmpeg para convertir a MP3. Escuchar sí funciona sin él."),
          h("button", { class: "btn-edge", type: "button", onClick: () => void act("music.install_ffmpeg") }, "Instalar FFmpeg"),
        ),
      );
    }
    if (needsCookies(state.error)) {
      const text = h("textarea", { rows: 5, "aria-label": "Contenido del cookies.txt", spellcheck: "false", placeholder: "# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\t…" });
      const form = h("form", { class: "lib-cookies" }, h("p", { class: "msg-error" }, state.error!.message), h("p", { class: "cfg-help" }, COOKIE_HINT, " También puedes cambiar el navegador en Configuración."), text, h("button", { class: "btn-solid", type: "submit" }, "Guardar cookies"));
      form.addEventListener("submit", (e) => {
        e.preventDefault();
        if (!text.value.trim()) return;
        state = { ...state, error: null, playlists: null };
        renderAll();
        void act("music.save_cookies", { text: text.value });
      });
      parts.push(form);
    } else if (state.error) {
      parts.push(h("p", { class: "msg-error" }, state.error.message));
    }
    if (state.lastSaved) parts.push(h("p", { class: "cfg-saved" }, `Guardado en ${state.lastSaved}`));
    notice.replaceChildren(...parts);
  }

  // ----------------------------------------------------------- listas

  function renderLists() {
    if (state.playlists === null) {
      const failed = state.error?.where === "playlists";
      lists.replaceChildren(h("p", { class: "chat-empty" }, failed ? "> no se pudieron leer tus listas" : "> leyendo tus listas…"));
      if (failed) lists.append(h("button", { class: "btn-quiet", type: "button", onClick: () => refreshLists() }, "Volver a intentar"));
      if (failed && !selectedList) songs.replaceChildren();
      return;
    }
    if (!state.playlists.length) {
      lists.replaceChildren(h("p", { class: "chat-empty" }, "> no hay listas en tu cuenta de YouTube"));
      return;
    }
    lists.replaceChildren(
      h("p", { class: "label lib-head" }, "Tus listas"),
      h(
        "ul",
        {},
        state.playlists.map((p: Playlist) =>
          h(
            "li",
            {},
            h(
              "button",
              { class: `lib-list${p.id === selectedList ? " is-current" : ""}`, type: "button", "aria-pressed": String(p.id === selectedList), onClick: () => openList(p.id) },
              h("span", { class: "lib-list-name" }, p.title),
              p.count !== null ? h("span", { class: "readout" }, String(p.count)) : null,
            ),
          ),
        ),
      ),
      h("button", { class: "btn-quiet", type: "button", onClick: () => refreshLists() }, "Actualizar"),
    );
  }

  function openList(id: string) {
    selectedList = id;
    picked.clear();
    choosing = false;
    renderLists();
    renderSongs();
    void act("music.songs", { playlist: id });
  }

  function refreshLists() {
    state = { ...state, playlists: null, error: state.error?.where === "playlists" ? null : state.error };
    renderLists();
    void act("music.playlists");
  }

  // ----------------------------------------------------------- canciones

  function stateCell(song: Song): HTMLElement {
    const p = state.progress[song.id] ?? { state: song.state, percent: 0 };
    if (p.state === "error") return h("span", { class: "msg-error" }, p.error ?? "error");
    if (p.state === "doing") {
      return h("span", { class: "lib-progress" }, h("span", { class: "meter", "aria-hidden": "true" }, h("span", { class: "meter-fill", style: `inline-size:${p.percent}%` })), h("span", { class: "readout" }, `${Math.round(p.percent)}%`));
    }
    if (p.state === "done") return h("span", { class: "lib-done" }, icon("check"), "hecha");
    return h("span", { class: "readout lib-state" }, STATE_TEXT[p.state] ?? "");
  }

  function renderSongs() {
    const focusedId = (document.activeElement as HTMLElement | null)?.id;
    if (!selectedList) {
      songs.replaceChildren(h("p", { class: "chat-empty" }, "> elige una lista a la izquierda"));
      return;
    }
    const list = state.playlists?.find((p) => p.id === selectedList);
    const rows = state.songs[selectedList];
    if (!rows) {
      songs.replaceChildren(h("p", { class: "chat-empty" }, "> leyendo canciones…"));
      return;
    }
    const pending = rows.filter((s) => (state.progress[s.id]?.state ?? s.state) !== "done");
    for (const id of [...picked]) if (!rows.some((s) => s.id === id)) picked.delete(id);
    const all = h("input", { type: "checkbox", id: "lib-all", checked: pending.length > 0 && pending.every((s) => picked.has(s.id)) });
    all.addEventListener("change", () => {
      if (all.checked) pending.forEach((s) => picked.add(s.id));
      else picked.clear();
      renderSongs();
    });
    const download = h("button", { class: "btn-solid", type: "button", disabled: !picked.size, onClick: () => ((choosing = true), renderSongs()) }, `Descargar (${picked.size})`);
    const cancel = state.busy ? h("button", { class: "btn-edge", type: "button", onClick: () => void act("music.cancel") }, "Detener") : null;

    songs.replaceChildren(
      h(
        "header",
        { class: "lib-songs-head" },
        h("h3", { class: "lib-title", "data-hack": "" }, list?.title ?? "Lista"),
        h("label", { class: "lib-all", for: "lib-all" }, all, h("span", {}, "Todas las que faltan")),
        download,
        cancel,
      ),
      ...(choosing ? [destination()] : []),
      h(
        "ul",
        { class: "lib-rows" },
        rows.map((song) => {
          const st = state.progress[song.id]?.state ?? song.state;
          const box = h("input", { type: "checkbox", id: `lib-${song.id}`, checked: picked.has(song.id), disabled: st === "done" || st === "queued" || st === "doing" || st === "sending", "aria-label": `Elegir ${song.title}` });
          box.addEventListener("change", () => {
            if (box.checked) picked.add(song.id);
            else picked.delete(song.id);
            renderSongs();
          });
          return h(
            "li",
            { class: `lib-row is-${st}` },
            box,
            h("span", { class: "lib-song" }, song.title),
            h("span", { class: "readout lib-dur" }, song.duration ? formatTime(song.duration) : ""),
            stateCell(song),
            h("button", { class: "lib-listen", type: "button", "aria-label": `Escuchar ${song.title}`, title: "Escuchar", onClick: () => listen(song) }, icon("play")),
          );
        }),
      ),
    );
    if (focusedId) document.getElementById(focusedId)?.focus();
  }

  /** El panel de «¿a dónde va?»: Yo, cada pasante y esta PC, con el destino por defecto marcado. */
  function destination(): HTMLElement {
    const people: Recipient[] = state.recipients ?? [];
    const options = people.length ? people : [{ id: FOLDER, name: "Esta PC (carpeta)", me: false }];
    const valueOf = (p: Recipient) => (p.id === null ? "me" : String(p.id));
    const current = options.some((p) => valueOf(p) === defaultRecipient) ? defaultRecipient : valueOf(options[0]);
    const set = h("fieldset", { class: "choice" }, h("legend", { class: "label" }, `¿A dónde van ${picked.size === 1 ? "esta canción" : `estas ${picked.size} canciones`}?`));
    for (const p of options) {
      const input = h("input", { type: "radio", name: "lib-dest", value: valueOf(p), checked: valueOf(p) === current, class: "choice-input" });
      set.append(h("label", { class: "choice-item" }, input, icon(p.id === FOLDER ? "pc" : p.me ? "web" : "phone"), h("span", {}, p.id === FOLDER ? "Esta PC (carpeta)" : p.name), icon("check", "icon choice-check")));
    }
    const form = h("form", { class: "lib-dest" }, set, h("div", { class: "lib-dest-actions" }, h("button", { class: "btn-solid", type: "submit" }, "Descargar aquí"), h("button", { class: "btn-quiet", type: "button", onClick: () => ((choosing = false), renderSongs()) }, "Cancelar")));
    form.addEventListener("submit", (e) => {
      e.preventDefault();
      const value = (form.querySelector<HTMLInputElement>("input[name=lib-dest]:checked")?.value) ?? "me";
      const person = options.find((p) => valueOf(p) === value);
      const ids = [...picked];
      choosing = false;
      picked.clear();
      renderSongs();
      void act("music.download", { playlist: selectedList, ids, recipient: value === "me" ? null : value, recipient_name: person?.name ?? "Yo" });
    });
    return form;
  }

  function listen(song: Song) {
    pendingStream = { id: song.id, title: song.title };
    void act("music.stream", { id: song.id });
  }

  // ----------------------------------------------------------- eventos

  function onEvent(ev: MusicEvent) {
    if (!alive) return;
    state = applyEvent(state, ev);
    if (ev.kind === "stream" && pendingStream && state.stream?.id === pendingStream.id) {
      const url = state.stream.local ? library.fileUrl(state.stream.id) : state.stream.source;
      const list = state.playlists?.find((p) => p.id === selectedList)?.title ?? null;
      void player.playUrl({ id: pendingStream.id, title: pendingStream.title, playlist: list }, url);
      pendingStream = null;
    }
    if (ev.kind === "playlists" && !selectedList && state.playlists?.length) {
      openList(state.playlists[0].id);
      return;
    }
    renderAll();
  }

  function renderAll() {
    renderNotice();
    renderLists();
    renderSongs();
  }

  async function start() {
    notice.replaceChildren(h("p", { class: "chat-empty" }, "> conectando con el servicio de música…"));
    lists.replaceChildren();
    songs.replaceChildren();
    const ok = await library.connect();
    if (!alive) return;
    if (!ok) {
      notice.replaceChildren(h("div", { class: "lib-warn" }, h("p", {}, SERVICE_DOWN), h("button", { class: "btn-edge", type: "button", onClick: () => void start() }, "Reintentar")));
      return;
    }
    stopEvents();
    // Los resultados llegan por el canal de eventos y el servicio no los repite: hay que estar escuchando antes de pedirlos.
    const listening = new Promise<void>((done) => {
      const wait = setTimeout(done, 4000); // si el canal tarda, se pide igual
      stopEvents = library.events(onEvent, (live) => {
        if (live) {
          clearTimeout(wait);
          done();
        }
      });
    });
    await listening;
    if (!alive) return;
    const cfg = await library.settings();
    if (cfg.ok) defaultRecipient = ((cfg.data as { default_recipient: string | null }).default_recipient ?? "me") || "me";
    lastNoticeKey = "";
    renderAll();
    void act("music.playlists");
    void act("music.recipients");
  }
  void start();

  return {
    el,
    destroy() {
      alive = false;
      stopEvents();
    },
  };
}
