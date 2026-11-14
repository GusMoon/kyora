import { describe, expect, it } from "vitest";
import { applyKeyEdit, normalizeKey, resolveKeys, routeForKey, validateKeys } from "../src/hotkeys";
import { DEFAULT_KEYS } from "../src/routes";

describe("atajos de teclado", () => {
  it("una tecla es una sola letra (sin acento) o número, en mayúscula", () => {
    expect(normalizeKey(" k ")).toBe("K");
    expect(normalizeKey("7")).toBe("7");
    for (const bad of ["", "ab", "ñ", "é", "Esc", " ", "-"]) expect(normalizeKey(bad)).toBe("");
  });

  it("las de siempre son válidas y no se repiten", () => {
    expect(validateKeys(DEFAULT_KEYS)).toBeNull();
    expect(new Set(Object.values(DEFAULT_KEYS)).size).toBe(Object.keys(DEFAULT_KEYS).length);
  });

  it("cambiar una tecla a una libre funciona", () => {
    const res = applyKeyEdit(DEFAULT_KEYS, "tareas", "x");
    expect(res.ok).toBe(true);
    if (res.ok) {
      expect(res.keys.tareas).toBe("X");
      expect(routeForKey(res.keys, "x")).toBe("tareas");
      expect(routeForKey(res.keys, "t")).toBeNull(); // la T ya no abre nada
    }
  });

  it("no deja usar una tecla de otra sección y dice cuál es", () => {
    const res = applyKeyEdit(DEFAULT_KEYS, "tareas", "c");
    expect(res).toEqual({ ok: false, error: "La tecla C ya abre Chat." });
  });

  it("volver a poner la misma tecla de la sección es válido", () => {
    expect(applyKeyEdit(DEFAULT_KEYS, "chat", "C").ok).toBe(true);
  });

  it("rechaza lo que no es una letra o un número", () => {
    expect(applyKeyEdit(DEFAULT_KEYS, "chat", "Escape").ok).toBe(false);
    expect(applyKeyEdit(DEFAULT_KEYS, "chat", "ñ").ok).toBe(false);
  });

  it("encuentra la sección de una tecla, sin importar mayúsculas", () => {
    expect(routeForKey(DEFAULT_KEYS, "k")).toBe("calendario");
    expect(routeForKey(DEFAULT_KEYS, "P")).toBe("contrasenas");
    expect(routeForKey(DEFAULT_KEYS, "i")).toBe("inicio");
    expect(routeForKey(DEFAULT_KEYS, "Enter")).toBeNull();
  });

  it("lo guardado se valida completo: si algo no vale, todo vuelve a las de siempre", () => {
    expect(resolveKeys({ ...DEFAULT_KEYS, tareas: "x" }).tareas).toBe("X");
    expect(resolveKeys({ ...DEFAULT_KEYS, tareas: "C" })).toEqual(DEFAULT_KEYS);
    expect(resolveKeys(null)).toEqual(DEFAULT_KEYS);
    expect(resolveKeys("hola")).toEqual(DEFAULT_KEYS);
    // lo que falte se completa con las de siempre
    expect(resolveKeys({ tareas: "x" }).musica).toBe("M");
  });
});
