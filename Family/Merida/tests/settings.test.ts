import { afterEach, describe, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import { settingsSection, settingsStatement } from "../src/sections/settings";
import { Shell } from "../src/ui/shell";
import { Store } from "../src/store";
import { Status } from "../src/status";
import { DEFAULT_PREFS, PrefsStore } from "../src/prefs";
import { Library } from "../src/data/library";
import { Backdrop } from "../src/backdrop";
import type { Player, PlayerState } from "../src/player";
import type { Ctx } from "../src/sections/context";

const flush = () => new Promise((r) => setTimeout(r, 0));

function player(): Player {
  const state: PlayerState = { track: null, playing: false, loading: false, time: 0, duration: 0, error: null };
  return { state, on: (fn: (s: PlayerState) => void) => (fn(state), () => {}), toggle() {}, play() {}, next() {}, previous() {}, seek() {}, stop() {} } as unknown as Player;
}

function mount(fetchImpl: typeof fetch, opts: { role?: string; client?: unknown } = {}) {
  const store = new Store();
  const status = new Status();
  status.set({ account: "kyora1947, admin", username: "kyora1947", role: opts.role ?? "admin", email: "yo@correo.com", latency: 120, live: "live" });
  const prefs = new PrefsStore({ ...DEFAULT_PREFS, keys: { ...DEFAULT_PREFS.keys } });
  const shell = new Shell({ store, prefs });
  document.body.append(shell.root);
  shell.setSection("configuracion", "");
  const signOut = vi.fn();
  const backdrop = new Backdrop({ storage: null, prepare: async () => ({ url: "data:image/jpeg;base64,AAAA", accent: "#ff5a1f" }) });
  const ctx: Ctx = { client: (opts.client ?? {}) as SupabaseClient, shell, store, player: player(), status, prefs, backdrop, library: new Library(fetchImpl), vault: {} as never, userId: "u", signOut, reload: async () => {} };
  const unmount = settingsSection(ctx);
  return { shell, signOut, prefs, backdrop, unmount, status };
}

const offline = (async () => new Response("{}", { status: 503 })) as unknown as typeof fetch;
const byLabel = (els: HTMLElement[], text: string) => els.find((e) => e.textContent === text)!;

afterEach(() => {
  document.body.replaceChildren();
});

describe("Configuración", () => {
  it("el enunciado dice de quién es la sesión", () => {
    const st = new Status();
    expect(settingsStatement({ ...st.data, username: "kyora1947", role: "admin" })).toBe("Sesión de kyora1947 (admin). Lo que cambies aquí se aplica al momento.");
    expect(settingsStatement({ ...st.data, email: "a@b.c" })).toMatch(/^Sesión de a@b\.c\./);
  });

  it("deja poner un fondo de pantalla temporal y quitarlo, con los ajustes de colores y portada", async () => {
    const { shell, backdrop, prefs } = mount(offline);
    await flush();
    const body = shell.body;
    expect(body.textContent).toContain("Ahora hay el fondo liso de siempre.");
    expect(body.textContent).toContain("dura mientras la sesión esté abierta");
    const input = body.querySelector<HTMLInputElement>("input[type=file]")!;
    expect(input.accept).toBe("image/*");
    await backdrop.setWallpaper(new Blob(["x"], { type: "image/png" }));
    expect(body.textContent).toContain("Hay un fondo puesto.");
    expect(body.querySelector<HTMLElement>(".wall-thumb")?.dataset.empty).toBe("false");
    const block = input.closest(".cfg-block")!;
    const switches = [...block.querySelectorAll<HTMLInputElement>(".switch-input")];
    expect(switches).toHaveLength(2);
    switches[0].click();
    switches[1].click();
    expect(prefs.value.tint).toBe(false);
    expect(prefs.value.cover).toBe(false);
    [...body.querySelectorAll("button")].find((b) => b.textContent === "Quitar fondo")!.click();
    expect(backdrop.active).toBe(false);
    expect(body.textContent).toContain("Ahora hay el fondo liso de siempre.");
  });

  it("enseña la cuenta, las métricas y los ajustes en bloques", async () => {
    const { shell } = mount(offline);
    await flush();
    const titles = [...shell.body.querySelectorAll(".cfg-title")].map((t) => t.textContent);
    // por grupos: Cuenta, Apariencia, Uso, Módulos y (solo el administrador) Administración
    expect(titles).toEqual(["Cuenta", "Métricas", "Efectos", "Color de acento", "Fondo de pantalla", "Al abrir Merida", "Atajos de teclado", "Avisos de mensajes", "Finanzas", "Servidor", "Comandos del chat", "Música", "Usuarios"]);
    expect(shell.body.textContent).toContain("kyora1947");
    expect(shell.body.textContent).toContain("yo@correo.com");
    expect(shell.body.textContent).toContain("120 ms");
  });

  it("los atajos se cambian pulsando una tecla en su casilla, no dejan repetir y se pueden restablecer", async () => {
    const { shell, prefs } = mount(offline);
    await flush();
    const press = (label: string, key: string) =>
      shell.body.querySelector<HTMLInputElement>(`input[aria-label="${label}"]`)!.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true }));
    press("Tecla para Tareas", "x");
    expect(prefs.value.keys.tareas).toBe("X");
    expect(shell.body.querySelector<HTMLInputElement>('input[aria-label="Tecla para Tareas"]')!.value).toBe("X");
    expect(shell.root.querySelector(".tile-tareas .tile-key")?.textContent).toBe("X"); // el tablero lo muestra al momento
    press("Tecla para Chat", "x");
    expect(prefs.value.keys.chat).toBe("C"); // no cambió
    expect(shell.body.textContent).toContain("La tecla X ya abre Tareas.");
    press("Tecla para Chat", "Escape");
    expect(prefs.value.keys.chat).toBe("C");
    shell.body.querySelectorAll<HTMLButtonElement>("button").forEach((b) => b.textContent === "Restablecer atajos" && b.click());
    expect(prefs.value.keys.tareas).toBe("T");
    expect(shell.body.textContent).toContain("Ctrl + K (fija)");
  });

  it("la moneda de Finanzas se guarda en las preferencias", async () => {
    const { shell, prefs } = mount(offline);
    await flush();
    const select = shell.body.querySelector<HTMLSelectElement>('select[aria-label="Moneda de Finanzas"]')!;
    expect(select.value).toBe("MXN");
    select.value = "USD";
    select.dispatchEvent(new Event("change"));
    expect(prefs.value.currency).toBe("USD");
  });

  it("activar los avisos pide permiso; si lo conceden se encienden y si no, el interruptor vuelve a apagarse", async () => {
    for (const [answer, expected] of [["granted", true], ["denied", false]] as const) {
      class N {
        static permission: NotificationPermission = "default";
        static requestPermission = vi.fn(async () => ((N.permission = answer), answer));
      }
      vi.stubGlobal("Notification", N);
      const { shell, prefs } = mount(offline);
      await flush();
      const label = [...shell.body.querySelectorAll("label")].find((l) => l.textContent === "Avisar de mensajes nuevos")!;
      const input = shell.body.querySelector<HTMLInputElement>(`#${label.getAttribute("for")}`)!;
      expect(input.checked).toBe(false);
      input.checked = true;
      input.dispatchEvent(new Event("change"));
      await flush();
      expect(N.requestPermission).toHaveBeenCalledOnce();
      expect(prefs.value.notify).toBe(expected);
      expect(input.checked).toBe(expected);
      document.body.replaceChildren();
      vi.unstubAllGlobals();
    }
  });

  it("hay un índice con los grupos y un salto a cada bloque, que deja el foco en él", async () => {
    const { shell } = mount(offline);
    await flush();
    const groups = [...shell.body.querySelectorAll(".cfg-nav-title")].map((e) => e.textContent);
    expect(groups).toEqual(["Cuenta", "Apariencia", "Uso", "Módulos", "Administración"]);
    const links = [...shell.body.querySelectorAll<HTMLButtonElement>(".cfg-nav-link")];
    expect(links.map((b) => b.textContent)).toEqual(["Cuenta", "Métricas", "Efectos", "Color de acento", "Fondo de pantalla", "Al abrir Merida", "Atajos de teclado", "Avisos de mensajes", "Finanzas", "Servidor", "Comandos del chat", "Música", "Usuarios"]);
    const target = shell.body.querySelector<HTMLElement>("#cfg-atajos-de-teclado")!;
    const scroll = vi.fn();
    target.scrollIntoView = scroll;
    byLabel(links, "Atajos de teclado").click();
    expect(scroll).toHaveBeenCalledOnce();
    expect(document.activeElement).toBe(target);
    expect(byLabel(links, "Atajos de teclado").getAttribute("aria-current")).toBe("true");
    expect(byLabel(links, "Cuenta").hasAttribute("aria-current")).toBe(false);
  });

  it("el buscador deja solo los ajustes que coinciden (sin acentos ni mayúsculas) y esconde los grupos vacíos", async () => {
    const { shell } = mount(offline);
    await flush();
    const search = shell.body.querySelector<HTMLInputElement>('input[aria-label="Buscar un ajuste"]')!;
    const visible = () => [...shell.body.querySelectorAll<HTMLElement>(".cfg-block")].filter((b) => !b.hidden).map((b) => b.querySelector(".cfg-title")!.textContent);
    search.value = "NOTIFICACION";
    search.dispatchEvent(new Event("input"));
    expect(visible()).toEqual(["Avisos de mensajes"]);
    expect([...shell.body.querySelectorAll<HTMLElement>(".cfg-group")].filter((g) => !g.hidden)).toHaveLength(1);
    expect([...shell.body.querySelectorAll<HTMLElement>(".cfg-nav-link")].filter((b) => !b.closest("li")!.hidden).map((b) => b.textContent)).toEqual(["Avisos de mensajes"]);
    expect(shell.body.querySelector<HTMLElement>(".cfg-nomatch")!.hidden).toBe(true);
    search.value = "zzzzqq";
    search.dispatchEvent(new Event("input"));
    expect(visible()).toEqual([]);
    expect(shell.body.querySelector<HTMLElement>(".cfg-nomatch")!.hidden).toBe(false);
    // Esc vacía la búsqueda y muestra todo otra vez, sin salir de Configuración
    const esc = new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true });
    search.dispatchEvent(esc);
    expect(search.value).toBe("");
    expect(visible()).toHaveLength(13);
  });

  describe("Usuarios: solo el administrador", () => {
    const visibleTitles = (shell: { body: HTMLElement }) =>
      [...shell.body.querySelectorAll<HTMLElement>(".cfg-block")].filter((b) => !b.hidden).map((b) => b.querySelector(".cfg-title")!.textContent);
    const client = () => ({ rpc: vi.fn(async () => ({ data: [], error: null })) });

    it("un visitante no ve el bloque ni su grupo, y no se pide la lista de cuentas", async () => {
      const c = client();
      const { shell, unmount } = mount(offline, { role: "visitante", client: c });
      await flush();
      expect(visibleTitles(shell)).not.toContain("Usuarios");
      const groups = [...shell.body.querySelectorAll<HTMLElement>(".cfg-group")].filter((g) => !g.hidden).map((g) => g.getAttribute("aria-label"));
      expect(groups).not.toContain("Administración");
      expect([...shell.body.querySelectorAll<HTMLElement>(".cfg-nav-link")].filter((b) => !b.closest("li")!.hidden).map((b) => b.textContent)).not.toContain("Usuarios");
      expect(c.rpc).not.toHaveBeenCalledWith("list_presence");
      unmount();
    });

    it("el administrador lo ve y se leen las cuentas", async () => {
      const c = client();
      const { shell, unmount } = mount(offline, { role: "admin", client: c });
      await flush();
      expect(visibleTitles(shell)).toContain("Usuarios");
      expect(c.rpc).toHaveBeenCalledWith("list_presence");
      unmount();
    });

    it("si el rol llega después de montar la sección, aparece entonces (y se esconde si deja de serlo)", async () => {
      const c = client();
      const { shell, status, unmount } = mount(offline, { role: "", client: c });
      await flush();
      expect(visibleTitles(shell)).not.toContain("Usuarios");
      status.set({ role: "admin" });
      await flush();
      expect(visibleTitles(shell)).toContain("Usuarios");
      expect(c.rpc).toHaveBeenCalledWith("list_presence");
      status.set({ role: "visitante" });
      expect(visibleTitles(shell)).not.toContain("Usuarios");
      unmount();
    });
  });

  it("Cerrar sesión cierra la sesión", () => {
    const { shell, signOut } = mount(offline);
    shell.body.querySelector<HTMLButtonElement>(".cfg-signout")!.click();
    expect(signOut).toHaveBeenCalledOnce();
  });

  it("cambiar los efectos, la sección al abrir y el acento se guarda al momento", () => {
    const { shell, prefs } = mount(offline);
    const hack = shell.body.querySelector<HTMLInputElement>(".switch-input")!;
    hack.checked = false;
    hack.dispatchEvent(new Event("change"));
    expect(prefs.value.hack).toBe(false);
    const chat = shell.body.querySelector<HTMLInputElement>('input[name="cfg-start"][value="chat"]')!;
    chat.checked = true;
    chat.dispatchEvent(new Event("change"));
    expect(prefs.value.start).toBe("chat");
    const cian = shell.body.querySelector<HTMLInputElement>('input[name="cfg-accent"][value="cian"]')!;
    cian.checked = true;
    cian.dispatchEvent(new Event("change"));
    expect(prefs.value.accent).toBe("cian");
  });

  it("sin el servicio de música lo explica y deja reintentar", async () => {
    const { shell } = mount(offline);
    await flush();
    await flush();
    expect(shell.body.textContent).toContain("El servicio de música no está abierto");
    expect([...shell.body.querySelectorAll("button")].some((b) => b.textContent === "Reintentar")).toBe(true);
  });
});
