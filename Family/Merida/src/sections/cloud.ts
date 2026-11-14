import { h } from "../ui/dom";
import { icon, type IconName } from "../ui/icons";
import { BUCKET, formatSize } from "../data/music";
import { explainError } from "../supabase";
import { KIND_LABEL, KIND_ORDER, agoLabel, cloudStatement, cloudUrl, deleteCloudFile, type CloudFile, type CloudKind } from "../data/cloud";
import { serverPanel } from "./serverPanel";
import type { Ctx, Section } from "./context";

export { cloudStatement };

type Filter = "all" | CloudKind;
let lastFilter: Filter = "all"; // se recuerda mientras dure la sesión

const KIND_ICON: Record<CloudKind, IconName> = { image: "file", audio: "music", video: "play", doc: "file", other: "file" };
const THUMB_MAX = 2 * 1024 * 1024; // solo se muestran de miniatura las fotos de hasta 2 MB
const THUMB_COUNT = 48;

export function extOf(name: string): string {
  const m = /\.([a-z0-9]{1,5})$/i.exec(name);
  return m ? m[1].toUpperCase() : "";
}

/** La nube: los archivos que se han compartido por Supabase y siguen en el servidor. Se miran, se abren, se bajan y se
 * **eliminan de verdad** (del almacenamiento y de la base, con confirmación). Merida nunca confirma «Recibido». */
export const cloudSection: Section = (ctx: Ctx) => {
  const { store, shell, client, reload } = ctx;
  let alive = true;
  let filter: Filter = lastFilter;
  const thumbs = new Map<string, string>();
  let confirming: string | null = null; // el archivo que está pidiendo confirmación para eliminarse
  let deleting: string | null = null; // el que se está eliminando ahora

  const filters = h("div", { class: "tabs cloud-filters", role: "group", "aria-label": "Tipo de archivo" });
  const grid = h("div", { class: "cloud-grid" });
  const note = h("p", { class: "cloud-empty", role: "status" });
  const problem = h("p", { class: "form-error", role: "alert" });
  const refresh = h("button", { class: "btn-quiet cloud-refresh", type: "button", onClick: () => void load() }, icon("refresh", "icon"), "Actualizar");

  async function load() {
    refresh.disabled = true;
    await reload("files");
    refresh.disabled = false;
  }

  function visible(): CloudFile[] {
    return filter === "all" ? store.files : store.files.filter((f) => f.kind === filter);
  }

  function renderFilters() {
    const counts = new Map<Filter, number>([["all", store.files.length]]);
    for (const f of store.files) counts.set(f.kind, (counts.get(f.kind) ?? 0) + 1);
    if (filter !== "all" && !counts.get(filter)) filter = "all";
    const options: { id: Filter; label: string }[] = [{ id: "all", label: "Todo" }, ...KIND_ORDER.filter((k) => counts.get(k)).map((k) => ({ id: k as Filter, label: KIND_LABEL[k] }))];
    filters.replaceChildren(
      ...options.map((o) =>
        h(
          "button",
          {
            class: "tab",
            type: "button",
            "aria-pressed": String(o.id === filter),
            onClick: () => {
              filter = lastFilter = o.id;
              render();
            },
          },
          `${o.label} `,
          h("span", { class: "readout" }, String(counts.get(o.id) ?? 0)),
        ),
      ),
    );
  }

  async function act(file: CloudFile, download: boolean, button: HTMLButtonElement) {
    problem.textContent = "";
    button.disabled = true;
    try {
      const url = await cloudUrl(client, file.path, download ? file.name : undefined);
      const a = h("a", { href: url, target: "_blank", rel: "noopener noreferrer", download: download ? file.name : null });
      document.body.append(a);
      a.click();
      a.remove();
    } catch {
      problem.textContent = "Ese archivo ya no está en el servidor (la limpieza automática lo borró) o no hay conexión.";
    } finally {
      button.disabled = false;
    }
  }

  /** Elimina el archivo del servidor (Storage y base) y lo quita de lo que Merida tiene cargado. */
  async function remove(file: CloudFile) {
    problem.textContent = "";
    deleting = file.id;
    render();
    try {
      const res = await deleteCloudFile(client, file);
      store.files = store.files.filter((f) => f.id !== file.id);
      thumbs.delete(file.path);
      if (file.source === "music") {
        store.tracks = store.tracks.filter((tr) => tr.storage_path !== file.path);
        store.emit("tracks");
      } else if (res.messageDeleted) {
        store.messages = store.messages.filter((m) => m.id !== res.messageDeleted);
        store.emit("messages");
      } else if (res.messageKept) {
        store.messages = store.messages.map((m) => (m.id === res.messageKept ? { ...m, attachments: m.attachments.filter((a) => a.storage_path !== file.path) } : m));
        store.emit("messages");
      }
      confirming = null;
    } catch (err) {
      problem.textContent = `No se pudo eliminar ${file.name}: ${explainError(err)}`;
    } finally {
      deleting = null;
      store.emit("files");
    }
  }

  function actionsFor(file: CloudFile): HTMLElement {
    if (deleting === file.id) return h("div", { class: "cloud-actions" }, h("p", { class: "cloud-confirm", role: "status" }, "Eliminando del servidor…"));
    if (confirming === file.id) {
      const warn = file.source === "music" ? "¿Eliminar del servidor? Se borra la canción para todos los que la tienen. No se puede deshacer." : "¿Eliminar del servidor? No se puede deshacer.";
      return h(
        "div",
        { class: "cloud-actions is-confirming" },
        h("p", { class: "cloud-confirm", role: "alert" }, warn),
        h("button", { class: "btn-edge is-danger", type: "button", onClick: () => void remove(file) }, icon("trash", "icon"), "Sí, eliminar"),
        h(
          "button",
          {
            class: "btn-edge",
            type: "button",
            onClick: () => {
              confirming = null;
              render();
            },
          },
          "Cancelar",
        ),
      );
    }
    const open = h("button", { class: "btn-edge", type: "button", "aria-label": `Abrir ${file.name}` }, icon("arrow", "icon"), "Abrir");
    const save = h("button", { class: "btn-edge", type: "button", "aria-label": `Descargar ${file.name}` }, icon("download", "icon"), "Descargar");
    const del = h("button", { class: "btn-edge is-danger", type: "button", "aria-label": `Eliminar ${file.name}` }, icon("trash", "icon"), "Eliminar");
    open.addEventListener("click", () => void act(file, false, open));
    save.addEventListener("click", () => void act(file, true, save));
    del.addEventListener("click", () => {
      confirming = file.id;
      render();
      grid.querySelector<HTMLButtonElement>(`[data-path="${CSS.escape(file.path)}"] .is-danger`)?.focus();
    });
    return h("div", { class: "cloud-actions" }, open, save, del);
  }

  function card(file: CloudFile): HTMLElement {
    const ext = extOf(file.name);
    const thumb = h("div", { class: "cloud-thumb", "aria-hidden": "true", "data-kind": file.kind }, icon(KIND_ICON[file.kind], "icon cloud-kind"), ext ? h("span", { class: "cloud-ext" }, ext) : null);
    const url = thumbs.get(file.path);
    if (url) thumb.prepend(h("img", { src: url, alt: "", loading: "lazy" }));
    return h(
      "article",
      { class: "cloud-card", "data-path": file.path },
      thumb,
      h("div", { class: "cloud-meta" }, h("p", { class: "cloud-name", title: file.name }, file.name), h("p", { class: "cloud-sub readout" }, `${file.from} · ${formatSize(file.size)} · ${agoLabel(file.at)}`)),
      actionsFor(file),
    );
  }

  /** Pide las URL firmadas de las fotos que se ven (una sola llamada) y las pone de miniatura. */
  async function loadThumbs(files: CloudFile[]) {
    const wanted = files.filter((f) => f.kind === "image" && f.size <= THUMB_MAX && !thumbs.has(f.path)).slice(0, THUMB_COUNT);
    if (!wanted.length) return;
    try {
      const { data } = await client.storage.from(BUCKET).createSignedUrls(
        wanted.map((f) => f.path),
        3600,
      );
      if (!alive) return;
      for (const row of data ?? []) if (row.path && row.signedUrl) thumbs.set(row.path, row.signedUrl);
      for (const el of grid.querySelectorAll<HTMLElement>(".cloud-card")) {
        const url = thumbs.get(el.dataset.path ?? "");
        const holder = el.querySelector(".cloud-thumb");
        if (url && holder && !holder.querySelector("img")) holder.prepend(h("img", { src: url, alt: "", loading: "lazy" }));
      }
    } catch {
      /* sin miniaturas: queda el icono */
    }
  }

  function render() {
    shell.setStatement(cloudStatement(store.files, store.loaded.files, store.errors.files));
    renderFilters();
    const files = visible();
    const error = store.errors.files;
    note.textContent = error ? "" : !store.loaded.files ? "Leyendo el servidor…" : files.length ? "" : "No hay archivos de este tipo en el servidor.";
    note.hidden = !note.textContent;
    grid.replaceChildren(...files.map(card));
    void loadThumbs(files);
  }

  const server = serverPanel(ctx);
  shell.body.append(
    server.el,
    h("div", { class: "cloud-bar" }, filters, refresh),
    h("p", { class: "cfg-note cloud-help" }, "Lo que se ha compartido por Supabase y sigue en el servidor: fotos y archivos del chat, y las canciones que subió la PC. La limpieza automática los borra después de que se confirman como recibidos. Aquí puedes abrirlos, descargarlos o eliminarlos del servidor (se borran de verdad)."),
    problem,
    note,
    grid,
  );
  render();
  void load();
  const off = store.on((area) => area === "files" && render());
  return () => {
    alive = false;
    off();
    server.off();
  };
};
