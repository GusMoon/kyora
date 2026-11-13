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

function mount(fetchImpl: typeof fetch) {
  const store = new Store();
  const status = new Status();
  status.set({ account: "kyora1947, admin", username: "kyora1947", role: "admin", email: "yo@correo.com", latency: 120, live: "live" });
  const shell = new Shell({ store });
  document.body.append(shell.root);
  shell.setSection("configuracion", "");
  const signOut = vi.fn();
  const prefs = new PrefsStore({ ...DEFAULT_PREFS });
  const backdrop = new Backdrop({ storage: null, prepare: async () => ({ url: "data:image/jpeg;base64,AAAA", accent: "#ff5a1f" }) });
  const ctx: Ctx = { client: {} as SupabaseClient, shell, store, player: player(), status, prefs, backdrop, library: new Library(fetchImpl), signOut, reload: async () => {} };
  const unmount = settingsSection(ctx);
  return { shell, signOut, prefs, backdrop, unmount };
}

const offline = (async () => new Response("{}", { status: 503 })) as unknown as typeof fetch;

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
    expect(titles).toEqual(["Cuenta", "Métricas", "Efectos", "Al abrir Merida", "Color de acento", "Fondo de pantalla", "Comandos del chat", "Música"]);
    expect(shell.body.textContent).toContain("kyora1947");
    expect(shell.body.textContent).toContain("yo@correo.com");
    expect(shell.body.textContent).toContain("120 ms");
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
