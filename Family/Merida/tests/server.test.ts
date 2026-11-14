import { afterEach, describe, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CRITICAL_AT,
  FREE_DB_MB,
  FREE_FILES_MB,
  MB,
  RENOTIFY_MS,
  WARN_AT,
  formatBytes,
  levelOf,
  loadServerStats,
  loadWarned,
  overQuota,
  parseStats,
  percent,
  quotas,
  saveWarned,
  shouldRenotify,
  warningText,
  type ServerStats,
} from "../src/data/server";
import { cloudSection } from "../src/sections/cloud";
import { Shell } from "../src/ui/shell";
import { Store } from "../src/store";
import { Status } from "../src/status";
import { DEFAULT_PREFS, PrefsStore, loadPrefs, validMb } from "../src/prefs";
import { Backdrop } from "../src/backdrop";
import { Library } from "../src/data/library";
import type { Player } from "../src/player";
import type { Ctx } from "../src/sections/context";

const stats = (dbMb: number, filesMb: number, extra: Partial<ServerStats> = {}): ServerStats => ({
  db_bytes: dbMb * MB, storage_bytes: filesMb * MB, storage_objects: 3, buckets: [], tables: [], at: new Date().toISOString(), ...extra,
});
const limits = { db: FREE_DB_MB, files: FREE_FILES_MB };

describe("estadísticas del servidor: los límites y el 80 %", () => {
  it("los límites del plan gratuito son 500 MB de base de datos y 1 GB de archivos, y el aviso es al 80 %", () => {
    expect([FREE_DB_MB, FREE_FILES_MB, WARN_AT, CRITICAL_AT]).toEqual([500, 1024, 0.8, 0.95]);
    expect(DEFAULT_PREFS.quotaDbMb).toBe(500);
    expect(DEFAULT_PREFS.quotaFilesMb).toBe(1024);
  });

  it("el nivel cambia justo en el 80 % y en el 95 %", () => {
    expect(levelOf(0.79)).toBe("ok");
    expect(levelOf(0.8)).toBe("warn");
    expect(levelOf(0.949)).toBe("warn");
    expect(levelOf(0.95)).toBe("critical");
    expect(levelOf(1.2)).toBe("critical");
  });

  it("400 MB de 500 es el 80 %: avisa; 399 MB no", () => {
    expect(overQuota(stats(399, 10), limits)).toEqual([]);
    const over = overQuota(stats(400, 10), limits);
    expect(over.map((q) => q.id)).toEqual(["db"]);
    expect(over[0]).toMatchObject({ level: "warn", ratio: 0.8 });
  });

  it("avisa de cada límite por separado (base de datos y archivos)", () => {
    const over = overQuota(stats(450, 900), limits);
    expect(over.map((q) => q.id)).toEqual(["db", "files"]);
    expect(over.map((q) => q.level)).toEqual(["warn", "warn"]);
    expect(overQuota(stats(10, 1000), limits).map((q) => q.id)).toEqual(["files"]);
  });

  it("respeta los límites que cambies (otro plan)", () => {
    expect(overQuota(stats(450, 10), { db: 8192, files: 102400 })).toEqual([]);
    expect(overQuota(stats(450, 10), { db: 500, files: 1 }).map((q) => q.id)).toEqual(["db", "files"]);
  });

  it("el porcentaje se redondea hacia abajo (no dice 80 % sin haber llegado) y puede pasar de 100", () => {
    expect(percent(0.7999)).toBe("79 %");
    expect(percent(0.8)).toBe("80 %");
    expect(percent(1.234)).toBe("123 %");
  });

  it("da el tamaño en B, KB, MB y GB", () => {
    expect(formatBytes(512)).toBe("512 B");
    expect(formatBytes(2048)).toBe("2 KB");
    expect(formatBytes(412.3 * MB)).toBe("412,3 MB");
    expect(formatBytes(1.5 * 1024 * MB)).toBe("1,50 GB");
  });

  it("el texto de la advertencia dice cuánto llevas y cuánto queda; y si te pasaste, lo dice", () => {
    const [db] = quotas(stats(420, 0), limits);
    expect(warningText(db)).toBe("Base de datos: llevas 84 % del plan gratuito (420,0 MB de 500,0 MB; quedan 80,0 MB).");
    const [over] = quotas(stats(520, 0), limits);
    expect(warningText(over)).toMatch(/superaste el límite/);
  });

  it("solo se vuelve a notificar pasado un día", () => {
    const t = 1_000_000_000_000;
    expect(shouldRenotify(null, t)).toBe(true);
    expect(shouldRenotify(t, t + RENOTIFY_MS - 1)).toBe(false);
    expect(shouldRenotify(t, t + RENOTIFY_MS)).toBe(true);
  });

  it("lo último notificado se guarda y se lee, y un valor corrupto no rompe", () => {
    const mem: Record<string, string> = {};
    const store = { getItem: (k: string) => mem[k] ?? null, setItem: (k: string, v: string) => void (mem[k] = v) };
    saveWarned(store, { db: 123 });
    expect(loadWarned(store)).toEqual({ db: 123 });
    mem["merida-quota-warned"] = "{no es json";
    expect(loadWarned(store)).toEqual({});
    mem["merida-quota-warned"] = JSON.stringify({ db: "ayer", files: 5 });
    expect(loadWarned(store)).toEqual({ files: 5 });
    expect(loadWarned(null)).toEqual({});
  });

  it("limpia lo que devuelve la función (los bigint llegan como texto)", () => {
    const s = parseStats({ db_bytes: "441450496", storage_bytes: 5, storage_objects: "2", buckets: [{ bucket: "chat-files", objects: "2", bytes: "5" }], tables: [{ name: "tasks", bytes: "8192", rows: "3" }], at: "2026-11-13T10:00:00Z" });
    expect(s).toMatchObject({ db_bytes: 441450496, storage_bytes: 5, storage_objects: 2, buckets: [{ bucket: "chat-files", objects: 2, bytes: 5 }], tables: [{ name: "tasks", bytes: 8192, rows: 3 }] });
    expect(parseStats(null)).toMatchObject({ db_bytes: 0, buckets: [], tables: [] });
  });

  it("los límites de las preferencias solo aceptan enteros entre 1 y 10 millones", () => {
    expect(validMb(500, 1)).toBe(500);
    expect(validMb(0, 7)).toBe(7);
    expect(validMb(1.5, 7)).toBe(7);
    expect(validMb("500", 7)).toBe(7);
    expect(validMb(10_000_001, 7)).toBe(7);
    const mem = (raw: unknown) => ({ getItem: () => JSON.stringify(raw), setItem: () => {} });
    expect(loadPrefs(mem({ quotaDbMb: 8192, quotaFilesMb: -3 }))).toMatchObject({ quotaDbMb: 8192, quotaFilesMb: 1024 });
  });
});

describe("cargar las estadísticas", () => {
  const client = (res: { data?: unknown; error?: { message: string; code?: string } | null }) => ({ rpc: async () => ({ data: res.data ?? null, error: res.error ?? null }) }) as unknown as SupabaseClient;

  it("llama a server_stats y devuelve los datos limpios", async () => {
    const out = await loadServerStats(client({ data: { db_bytes: 100, storage_bytes: 200, storage_objects: 1, buckets: [], tables: [], at: "2026-11-13T10:00:00Z" } }));
    expect(out).toMatchObject({ db_bytes: 100, storage_bytes: 200 });
  });

  it("si la función no existe, dice que hay que volver a ejecutar schema.sql", async () => {
    await expect(loadServerStats(client({ error: { message: "Could not find the function public.server_stats", code: "PGRST202" } }))).rejects.toThrow(/schema\.sql/);
  });

  it("otros errores se propagan tal cual", async () => {
    await expect(loadServerStats(client({ error: { message: "sin red" } }))).rejects.toMatchObject({ message: "sin red" });
  });
});

describe("la Nube enseña el servidor", () => {
  afterEach(() => {
    document.body.replaceChildren();
    location.hash = "";
  });

  function mount(setup: (s: Store) => void, reload = vi.fn(async () => {})) {
    const store = new Store();
    setup(store);
    const prefs = new PrefsStore({ ...DEFAULT_PREFS, keys: { ...DEFAULT_PREFS.keys } });
    const shell = new Shell({ store, prefs });
    document.body.append(shell.root);
    shell.setSection("nube", "");
    const client = { storage: { from: () => ({ createSignedUrls: async () => ({ data: [] }) }) } } as unknown as SupabaseClient;
    const ctx: Ctx = { client, shell, store, player: {} as Player, status: new Status(), prefs, backdrop: new Backdrop({ storage: null }), library: new Library(), vault: {} as never, userId: "u", signOut() {}, reload };
    const unmount = cloudSection(ctx);
    return { shell, store, prefs, reload, unmount };
  }

  it("con el 84 % de la base de datos enseña la advertencia, los dos medidores y pide medir al abrir", () => {
    const { shell, reload } = mount((s) => {
      s.serverStats = stats(420, 300, { buckets: [{ bucket: "chat-files", objects: 41, bytes: 244 * MB }], tables: [{ name: "messages", bytes: 38 * MB, rows: 12840 }] });
      s.loaded.server = true;
    });
    expect(reload).toHaveBeenCalledWith("server");
    const warn = shell.body.querySelector(".srv-warn")!;
    expect(warn.getAttribute("role")).toBe("alert");
    expect(warn.textContent).toMatch(/84 % del plan gratuito/);
    expect(warn.textContent).toMatch(/Base de datos: llevas 84 %/);
    const meters = [...shell.body.querySelectorAll<HTMLElement>(".srv-meter")];
    expect(meters.map((m) => m.dataset.quota)).toEqual(["db", "files"]);
    expect(meters[0].classList.contains("is-warn")).toBe(true);
    expect(meters[0].querySelector(".srv-pct")?.textContent).toBe("84 %");
    expect(meters[1].classList.contains("is-ok")).toBe(true);
    expect(meters[1].querySelector(".srv-pct")?.textContent).toBe("29 %");
    expect(shell.body.querySelector(".srv-list")?.textContent).toMatch(/chat-files/);
    expect(shell.body.querySelector(".srv-mark")).not.toBeNull(); // la marca del 80 %
  });

  it("por debajo del 80 % no hay advertencia", () => {
    const { shell } = mount((s) => (s.serverStats = stats(100, 100)));
    expect(shell.body.querySelector(".srv-warn")).toBeNull();
    expect(shell.body.querySelector(".srv-meter.is-ok")).not.toBeNull();
  });

  it("al pasar del 95 % la advertencia es crítica, y al pasar el límite lo dice", () => {
    const { shell } = mount((s) => (s.serverStats = stats(10, 1100)));
    expect(shell.body.querySelector(".srv-warn.is-critical")).not.toBeNull();
    expect(shell.body.querySelector(".srv-warn")?.textContent).toMatch(/Superaste un límite/);
  });

  it("usa los límites de Configuración", () => {
    const { shell, prefs } = mount((s) => (s.serverStats = stats(420, 10)));
    expect(shell.body.querySelector(".srv-warn")).not.toBeNull();
    prefs.set({ quotaDbMb: 8192 }); // otro plan: ya no está cerca
    expect(shell.body.querySelector(".srv-warn")).toBeNull();
  });

  it("si la medición falla enseña el problema (por ejemplo, falta schema.sql)", () => {
    const { shell } = mount((s) => (s.errors.server = "Falta la función server_stats en Supabase."));
    expect(shell.body.querySelector(".srv .form-error")?.textContent).toMatch(/server_stats/);
  });

  it("«Medir ahora» vuelve a pedir las estadísticas", async () => {
    const { shell, reload } = mount((s) => (s.serverStats = stats(10, 10)));
    await new Promise((r) => setTimeout(r, 0)); // la medición de al abrir termina y el botón se libera
    reload.mockClear();
    (shell.body.querySelector(".srv .btn-quiet") as HTMLElement).click();
    expect(reload).toHaveBeenCalledWith("server");
  });
});

describe("la insignia de la tesela de la Nube", () => {
  it("setAlert pone el porcentaje en rojo y lo quita sin texto", () => {
    const store = new Store();
    const shell = new Shell({ store, prefs: new PrefsStore({ ...DEFAULT_PREFS, keys: { ...DEFAULT_PREFS.keys } }) });
    document.body.append(shell.root);
    const badge = () => shell.root.querySelector<HTMLElement>(".tile-nube .tile-badge")!;
    expect(badge().hidden).toBe(true);
    shell.setAlert("nube", "84 %", "Base de datos al 84 %");
    expect(badge().hidden).toBe(false);
    expect(badge().textContent).toBe("84 %");
    expect(badge().classList.contains("is-warn")).toBe(true);
    shell.setAlert("nube", null);
    expect(badge().hidden).toBe(true);
    expect(badge().classList.contains("is-warn")).toBe(false);
    document.body.replaceChildren();
  });
});
