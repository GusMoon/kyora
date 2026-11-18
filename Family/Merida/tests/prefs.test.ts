import { describe, expect, it } from "vitest";
import { ACCENTS, DEFAULT_PREFS, PrefsStore, applyAccent, loadPrefs, onAccent, savePrefs } from "../src/prefs";

function memory(initial: Record<string, string> = {}) {
  const data = { ...initial };
  return {
    data,
    getItem: (k: string) => (k in data ? data[k] : null),
    setItem: (k: string, v: string) => {
      data[k] = v;
    },
  };
}

describe("preferencias", () => {
  it("sin nada guardado (o sin almacenamiento) usa las de siempre", () => {
    expect(loadPrefs(memory())).toEqual(DEFAULT_PREFS);
    expect(loadPrefs(null)).toEqual(DEFAULT_PREFS);
    expect(DEFAULT_PREFS).toEqual({
      hack: true,
      holo: true,
      start: "inicio",
      accent: "lima",
      tint: true,
      cover: true,
      keys: { inicio: "I", tareas: "T", calendario: "K", musica: "M", nube: "N", chat: "C", contrasenas: "P", finanzas: "F", mejoras: "J", configuracion: "A" },
      notify: false,
      sound: true,
      preview: true,
      currency: "MXN",
      calendarView: "week",
      quotaDbMb: 500,
      quotaFilesMb: 1024,
    });
  });

  it("lo guardado vuelve tal cual, y lo que no vale vuelve a su valor de siempre", () => {
    const store = memory();
    const custom = { ...DEFAULT_PREFS, hack: false, start: "chat" as const, accent: "cian" as const, tint: false, notify: true, sound: false, preview: false, currency: "USD", keys: { ...DEFAULT_PREFS.keys, tareas: "X" } };
    savePrefs(custom, store);
    expect(loadPrefs(store)).toEqual(custom);
    const broken = memory({ "merida-prefs": JSON.stringify({ hack: "sí", start: "nada", accent: "rojo", holo: false, tint: 1, currency: "pesos", notify: "sí", keys: { tareas: "T", musica: "T" } }) });
    expect(loadPrefs(broken)).toEqual({ ...DEFAULT_PREFS, holo: false });
    expect(loadPrefs(memory({ "merida-prefs": "{no es json" }))).toEqual(DEFAULT_PREFS);
  });

  it("unas teclas repetidas o inválidas vuelven todas a las de siempre (nunca queda un atajo a medias)", () => {
    const dup = memory({ "merida-prefs": JSON.stringify({ keys: { ...DEFAULT_PREFS.keys, chat: "T" } }) });
    expect(loadPrefs(dup).keys).toEqual(DEFAULT_PREFS.keys);
    const bad = memory({ "merida-prefs": JSON.stringify({ keys: { ...DEFAULT_PREFS.keys, chat: "ñ" } }) });
    expect(loadPrefs(bad).keys).toEqual(DEFAULT_PREFS.keys);
  });

  it("si el navegador no deja guardar, no se rompe", () => {
    const failing = { getItem: () => null, setItem: () => { throw new Error("bloqueado"); } };
    expect(() => savePrefs(DEFAULT_PREFS, failing)).not.toThrow();
  });

  it("el texto sobre el acento es casi negro en los claros (todas las paletas de Kyra lo son)", () => {
    for (const a of ACCENTS) expect(onAccent(a.color)).toBe("#0a0b0d");
    expect(onAccent("#101010")).toBe("#ffffff");
  });

  it("aplicar un acento cambia las variables de toda la página", () => {
    const root = document.createElement("div");
    applyAccent("magenta", root);
    expect(root.style.getPropertyValue("--accent")).toBe("#ff4fd8");
    expect(root.style.getPropertyValue("--on-accent")).toBe("#0a0b0d");
    expect(root.style.getPropertyValue("--accent-soft")).toBe("rgba(255, 79, 216, 0.14)");
  });

  it("al cambiar una preferencia avisa a quien escucha", () => {
    const prefs = new PrefsStore({ ...DEFAULT_PREFS });
    const seen: string[] = [];
    prefs.on((p) => seen.push(p.accent));
    prefs.set({ accent: "naranja" });
    expect(seen).toEqual(["naranja"]);
    expect(prefs.value.accent).toBe("naranja");
  });
});
