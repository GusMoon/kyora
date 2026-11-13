import { describe, expect, it, vi } from "vitest";
import { Library, SERVICE_DOWN, applyEvent, emptyLibrary, needsCookies } from "../src/data/library";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

describe("cliente del servicio de música", () => {
  it("pide a Vite dónde está el servicio y manda el token en cada petición", async () => {
    const calls: [string, RequestInit | undefined][] = [];
    const fetchImpl = vi.fn(async (url: string | URL | Request, init?: RequestInit) => {
      calls.push([String(url), init]);
      if (String(url) === "/__music") return json({ url: "http://127.0.0.1:5190", token: "abc" });
      return json({ ok: true, data: null });
    }) as unknown as typeof fetch;
    const lib = new Library(fetchImpl);
    expect(await lib.connect()).toBe(true);
    await lib.act("music.songs", { playlist: "PL1" });
    const [url, init] = calls.at(-1)!;
    expect(url).toBe("http://127.0.0.1:5190/api/action/music.songs");
    expect(init?.method).toBe("POST");
    expect((init?.headers as Record<string, string>)["X-Merida-Token"]).toBe("abc");
    expect(JSON.parse(String(init?.body))).toEqual({ playlist: "PL1" });
    expect(lib.fileUrl("v 1")).toBe("http://127.0.0.1:5190/api/file?id=v%201&token=abc");
  });

  it("si el servicio no está abierto lo dice, sin romperse", async () => {
    const down = new Library((async () => json({ error: "no" }, 503)) as unknown as typeof fetch);
    expect(await down.connect()).toBe(false);
    const res = await down.act("music.playlists");
    expect(res).toEqual({ ok: false, error: { code: "offline", message: SERVICE_DOWN } });

    const crashing = new Library((async () => {
      throw new TypeError("Failed to fetch");
    }) as unknown as typeof fetch);
    expect(await crashing.connect()).toBe(false);
  });
});

describe("estado de Mis listas", () => {
  it("guarda listas, canciones y progreso por canción", () => {
    let s = emptyLibrary();
    s = applyEvent(s, { kind: "playlists", playlists: [{ id: "LL", title: "Videos que me gustan", count: null }] });
    s = applyEvent(s, { kind: "songs", playlist: "LL", songs: [{ id: "a", title: "A", duration: 200, state: "pending" }, { id: "b", title: "B", duration: 100, state: "done" }] });
    expect(s.playlists).toHaveLength(1);
    expect(s.songs.LL.map((x) => x.id)).toEqual(["a", "b"]);
    expect(s.progress.b).toEqual({ state: "done", percent: 100 });
    s = applyEvent(s, { kind: "progress", playlist: "LL", id: "a", state: "doing", percent: 42 });
    expect(s.busy).toBe(true);
    expect(s.progress.a).toEqual({ state: "doing", percent: 42 });
    s = applyEvent(s, { kind: "progress", playlist: "LL", id: "a", state: "error", percent: 0, error: "Video unavailable" });
    expect(s.progress.a.error).toBe("Video unavailable");
    s = applyEvent(s, { kind: "finished", playlist: "LL", done: 1, failed: 1, cancelled: false });
    expect(s.busy).toBe(false);
  });

  it("los destinatarios, lo guardado en la carpeta y lo que se puede escuchar", () => {
    let s = emptyLibrary();
    s = applyEvent(s, { kind: "recipients", recipients: [{ id: null, name: "Yo", me: true }, { id: "folder", name: "Esta PC (carpeta)", me: false }] });
    expect(s.recipients?.map((r) => r.name)).toEqual(["Yo", "Esta PC (carpeta)"]);
    s = applyEvent(s, { kind: "saved", id: "a", path: "C:\\Music\\A.mp3" });
    expect(s.lastSaved).toBe("C:\\Music\\A.mp3");
    s = applyEvent(s, { kind: "stream", id: "a", source: "http://127.0.0.1:6000/s/a", local: false });
    expect(s.stream).toEqual({ id: "a", source: "http://127.0.0.1:6000/s/a", local: false });
    expect(applyEvent(s, { kind: "otra-cosa" })).toBe(s);
  });

  it("un error de cookies ofrece pegar el cookies.txt; otros errores no", () => {
    let s = applyEvent(emptyLibrary(), { kind: "error", where: "playlists", error: "YouTube necesita cookies nuevas: vuelve a iniciar sesión" });
    expect(needsCookies(s.error)).toBe(true);
    s = applyEvent(emptyLibrary(), { kind: "error", where: "songs", error: "Sin conexión" });
    expect(needsCookies(s.error)).toBe(false);
    s = applyEvent(s, { kind: "songs", playlist: "x", songs: [] });
    expect(s.error).toBeNull();
  });
});
