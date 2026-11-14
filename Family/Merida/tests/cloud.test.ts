import { afterEach, describe, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import { agoLabel, cloudStatement, cloudTotals, cloudUrl, kindOf, listCloud, mergeCloud } from "../src/data/cloud";
import { cloudSection, extOf } from "../src/sections/cloud";
import { Shell } from "../src/ui/shell";
import { Store } from "../src/store";
import { Status } from "../src/status";
import { DEFAULT_PREFS, PrefsStore } from "../src/prefs";
import { Backdrop } from "../src/backdrop";
import { Library } from "../src/data/library";
import type { Player } from "../src/player";
import type { Ctx } from "../src/sections/context";

const att = (id: string, path: string, name: string, mime: string, size: number, at: string, device: string | null = "pc", deleted: string | null = null) => ({
  id,
  storage_path: path,
  file_name: name,
  mime_type: mime,
  size_bytes: size,
  created_at: at,
  message: device ? { sender_device: device, deleted_at: deleted } : null,
});
const trk = (id: string, path: string, at: string, recipient: string, size = 5_000_000) => ({
  id,
  title: `Canción ${id}`,
  file_name: `${id}.mp3`,
  storage_path: path,
  mime_type: "audio/mpeg",
  size_bytes: size,
  created_at: at,
  owner_id: "me",
  recipient_id: recipient,
});

const flush = () => new Promise((r) => setTimeout(r, 0));

afterEach(() => {
  document.body.replaceChildren();
});

describe("tipos de archivo", () => {
  it("separa fotos, música, vídeos, documentos y otros", () => {
    expect(kindOf("image/png")).toBe("image");
    expect(kindOf("audio/mpeg")).toBe("audio");
    expect(kindOf("video/mp4")).toBe("video");
    expect(kindOf("application/pdf")).toBe("doc");
    expect(kindOf("application/octet-stream", "notas.docx")).toBe("doc");
    expect(kindOf("application/octet-stream", "cosa.bin")).toBe("other");
    expect(extOf("foto.final.JPG")).toBe("JPG");
    expect(extOf("sin-extension")).toBe("");
  });
});

describe("la nube (lo que hay en el servidor)", () => {
  it("junta los adjuntos del chat y las canciones, lo más nuevo primero, sin repetir un mismo MP3", () => {
    const files = mergeCloud(
      [att("a1", "u/c/m/foto.jpg", "foto.jpg", "image/jpeg", 480_000, "2026-11-12T11:00:00Z", "movil"), att("a2", "u/c/n/doc.pdf", "doc.pdf", "application/pdf", 1_000_000, "2026-11-10T09:00:00Z", "pc")],
      [trk("t1", "u/music/x.mp3", "2026-11-12T12:00:00Z", "me"), trk("t2", "u/music/x.mp3", "2026-11-12T12:00:00Z", "ana"), trk("t3", "u/music/y.mp3", "2026-11-08T12:00:00Z", "ana")],
      "me",
      { ana: "ana" },
    );
    expect(files.map((f) => f.path)).toEqual(["u/music/x.mp3", "u/c/m/foto.jpg", "u/c/n/doc.pdf", "u/music/y.mp3"]);
    expect(files[0]).toMatchObject({ source: "music", kind: "audio", from: "para ti, para ana" });
    expect(files[1]).toMatchObject({ source: "chat", kind: "image", from: "móvil" });
    expect(files[3].from).toBe("para ana");
  });

  it("ignora los mensajes borrados y dice «un pasante» si no se sabe el nombre", () => {
    const files = mergeCloud([att("a1", "p1", "x.png", "image/png", 10, "2026-11-12T10:00:00Z", "pc", "2026-11-12T10:05:00Z")], [trk("t1", "p2", "2026-11-12T10:00:00Z", "otro")], "me");
    expect(files).toHaveLength(1);
    expect(files[0].from).toBe("para un pasante");
  });

  it("cuenta archivos y tamaño, y lo dice en una frase", () => {
    const files = mergeCloud([att("a1", "p1", "a.jpg", "image/jpeg", 1024 * 1024, "2026-11-12T10:00:00Z")], [trk("t1", "p2", "2026-11-12T10:00:00Z", "me", 3 * 1024 * 1024)], "me");
    expect(cloudTotals(files)).toEqual({ count: 2, bytes: 4 * 1024 * 1024, byKind: { image: 1, audio: 1, video: 0, doc: 0, other: 0 } });
    expect(cloudStatement(files, true)).toBe("2 archivos en el servidor (4.0 MB).");
    expect(cloudStatement([], true)).toBe("No hay archivos en el servidor.");
    expect(cloudStatement([], false)).toBe("Leyendo el servidor…");
    expect(cloudStatement([], true, "Sin conexión")).toBe("Sin conexión");
  });

  it("dice cuánto hace que llegó", () => {
    const now = new Date("2026-11-12T12:00:00Z");
    expect(agoLabel("2026-11-12T11:59:40Z", now)).toBe("ahora");
    expect(agoLabel("2026-11-12T11:30:00Z", now)).toBe("hace 30 min");
    expect(agoLabel("2026-11-12T09:00:00Z", now)).toBe("hace 3 h");
    expect(agoLabel("2026-11-11T09:00:00Z", now)).toBe("ayer");
    expect(agoLabel("nada", now)).toBe("");
  });

  it("solo lee: pide las dos tablas y los pasantes, y no llama a nada que cambie el servidor", async () => {
    const calls: string[] = [];
    const query = (rows: unknown[]) => {
      const q: Record<string, unknown> = {};
      q.select = () => q;
      q.order = () => q;
      q.limit = async () => ({ data: rows, error: null });
      return q;
    };
    const client = {
      from: (table: string) => {
        calls.push(`from:${table}`);
        return query(table === "attachments" ? [att("a1", "p1", "a.jpg", "image/jpeg", 10, "2026-11-12T10:00:00Z")] : [trk("t1", "p2", "2026-11-12T09:00:00Z", "me")]);
      },
      rpc: async (name: string) => {
        calls.push(`rpc:${name}`);
        return { data: [{ id: "ana", username: "ana" }], error: null };
      },
    } as unknown as SupabaseClient;
    const files = await listCloud(client, "me");
    expect(files).toHaveLength(2);
    expect(calls.sort()).toEqual(["from:attachments", "from:music_tracks", "rpc:list_recipients"]);
    expect(calls.join()).not.toMatch(/confirm/);
  });

  it("una URL temporal para abrir, y otra para descargar con el nombre del archivo", async () => {
    const createSignedUrl = vi.fn(async (_p: string, _s: number, opts?: { download: string }) => ({ data: { signedUrl: `https://x/y${opts ? "?download" : ""}` }, error: null }));
    const client = { storage: { from: () => ({ createSignedUrl }) } } as unknown as SupabaseClient;
    expect(await cloudUrl(client, "a/b.jpg")).toBe("https://x/y");
    expect(await cloudUrl(client, "a/b.jpg", "b.jpg")).toBe("https://x/y?download");
    expect(createSignedUrl).toHaveBeenLastCalledWith("a/b.jpg", 3600, { download: "b.jpg" });
  });
});

describe("sección Nube", () => {
  function mount(files = mergeCloud([att("a1", "p/a.jpg", "a.jpg", "image/jpeg", 100, "2026-11-12T10:00:00Z", "pc"), att("a2", "p/b.pdf", "b.pdf", "application/pdf", 200, "2026-11-12T09:00:00Z", "movil")], [trk("t1", "p/c.mp3", "2026-11-12T08:00:00Z", "me")], "me")) {
    const store = new Store();
    store.files = files;
    store.loaded.files = true;
    const reload = vi.fn(async () => {});
    const shell = new Shell({ store });
    document.body.append(shell.root);
    shell.setSection("nube", "");
    const createSignedUrls = vi.fn(async (paths: string[]) => ({ data: paths.map((path) => ({ path, signedUrl: `https://x/${path}`, error: null })), error: null }));
    const client = { storage: { from: () => ({ createSignedUrls, createSignedUrl: async () => ({ data: { signedUrl: "https://x/open" }, error: null }) }) } } as unknown as SupabaseClient;
    const ctx: Ctx = {
      client,
      shell,
      store,
      player: {} as Player,
      status: new Status(),
      prefs: new PrefsStore({ ...DEFAULT_PREFS }),
      backdrop: new Backdrop({ storage: null }),
      library: new Library(),
      vault: {} as never,
      userId: "u",
      signOut() {},
      reload,
    };
    const unmount = cloudSection(ctx);
    return { shell, store, reload, createSignedUrls, unmount };
  }

  it("lista los archivos como tarjetas, pide la lista fresca y cuenta por tipo", async () => {
    const { shell, reload } = mount();
    await flush();
    expect(reload).toHaveBeenCalledWith("files");
    const names = [...shell.body.querySelectorAll(".cloud-name")].map((n) => n.textContent);
    expect(names).toEqual(["a.jpg", "b.pdf", "t1.mp3"]);
    const tabs = [...shell.body.querySelectorAll(".cloud-filters .tab")].map((t) => t.textContent?.replace(/\s+/g, " ").trim());
    expect(tabs).toEqual(["Todo 3", "Fotos 1", "Música 1", "Documentos 1"]);
    expect(shell.body.textContent).toContain("pc ·");
    expect(shell.body.textContent).toContain("para ti");
  });

  it("el filtro deja solo un tipo, y cada tarjeta tiene Abrir, Descargar y Eliminar", async () => {
    const { shell } = mount();
    await flush();
    [...shell.body.querySelectorAll<HTMLButtonElement>(".cloud-filters .tab")].find((b) => b.textContent?.startsWith("Música"))!.click();
    const names = [...shell.body.querySelectorAll(".cloud-name")].map((n) => n.textContent);
    const buttons = [...shell.body.querySelectorAll(".cloud-actions button")].map((b) => b.textContent);
    [...shell.body.querySelectorAll<HTMLButtonElement>(".cloud-filters .tab")][0].click(); // el filtro se recuerda: se deja como estaba
    expect(names).toEqual(["t1.mp3"]);
    expect(buttons).toEqual(["Abrir", "Descargar", "Eliminar"]);
  });

  it("las fotos pequeñas llevan miniatura (una sola llamada de URLs firmadas)", async () => {
    const { shell, createSignedUrls } = mount();
    await flush();
    await flush();
    expect(createSignedUrls).toHaveBeenCalledTimes(1);
    expect(createSignedUrls).toHaveBeenCalledWith(["p/a.jpg"], 3600);
    expect(shell.body.querySelector<HTMLImageElement>(".cloud-card img")?.getAttribute("src")).toBe("https://x/p/a.jpg");
  });

  it("sin archivos lo dice, y un error del servidor se ve en el enunciado", async () => {
    const { shell, store } = mount([]);
    await flush();
    expect(shell.body.querySelector(".cloud-empty")?.textContent).toBe("No hay archivos de este tipo en el servidor.");
    store.errors.files = "No se pudo leer el servidor.";
    store.emit("files");
    expect(shell.root.querySelector(".tile-nube .tile-statement")?.textContent).toBe("No se pudo leer el servidor.");
  });
});
