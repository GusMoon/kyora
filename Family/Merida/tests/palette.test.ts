import { describe, expect, it, vi } from "vitest";
import { grouped, normalize, rank, score, type PaletteItem } from "../src/palette";
import { Palette } from "../src/ui/palette";

const item = (label: string, patch: Partial<PaletteItem> = {}): PaletteItem => ({ id: label, label, group: "Ir a", run: () => {}, ...patch });

describe("paleta de comandos: búsqueda", () => {
  it("ignora acentos y mayúsculas", () => {
    expect(normalize("  MÚSICA ")).toBe("musica");
    expect(score("musica", item("Ir a Música"))).toBeGreaterThan(0);
  });

  it("ordena: igual > empieza > palabra > contiene > palabras clave > letras en orden", () => {
    const items = [
      item("Nueva tarea"),
      item("Tarea nueva", { id: "b" }),
      item("Revisar tareas pendientes", { id: "c" }),
      item("Otra cosa", { id: "d", keywords: "tarea" }),
    ];
    // «Tarea nueva» empieza igual (100); «Nueva tarea» y «Revisar tareas…» tienen una palabra que empieza igual (80, gana la más corta); «Otra cosa» solo por su palabra clave (40)
    expect(rank(items, "tarea").map((i) => i.id)).toEqual(["b", "Nueva tarea", "c", "d"]);
    expect(score("tarea", item("tarea"))).toBe(120);
    expect(score("tar", item("tarea"))).toBe(100);
    expect(score("tar", item("nueva tarea"))).toBe(80);
    expect(score("ar", item("tarea"))).toBe(60);
  });

  it("encuentra por letras en orden (búsqueda difusa) y descarta lo que no está", () => {
    expect(score("ntar", item("Nueva tarea"))).toBe(20);
    expect(score("zzz", item("Nueva tarea"))).toBe(0);
    expect(rank([item("a"), item("b")], "zzz")).toEqual([]);
  });

  it("sin búsqueda devuelve todo en su orden, y respeta el límite", () => {
    const items = Array.from({ length: 60 }, (_, i) => item(`x${i}`));
    expect(rank(items, "")).toHaveLength(40);
    expect(rank(items, "", 5).map((i) => i.label)).toEqual(["x0", "x1", "x2", "x3", "x4"]);
  });

  it("también busca en la pista (el correo, el estado…)", () => {
    expect(rank([item("Netflix", { hint: "ana@correo.com" })], "ana@").map((i) => i.label)).toEqual(["Netflix"]);
  });

  it("agrupa los resultados seguidos del mismo grupo", () => {
    const g = grouped([item("a", { group: "X" }), item("b", { group: "X" }), item("c", { group: "Y" })]);
    expect(g.map((x) => [x.group, x.items.length])).toEqual([["X", 2], ["Y", 1]]);
  });
});

describe("paleta de comandos: la caja", () => {
  const flush = () => new Promise((r) => setTimeout(r, 0));
  const key = (el: Element, k: string) => el.dispatchEvent(new KeyboardEvent("keydown", { key: k, bubbles: true, cancelable: true }));

  it("se abre con el foco en el campo, filtra, y Enter ejecuta lo elegido y la cierra", async () => {
    const go = vi.fn();
    const other = vi.fn();
    const p = new Palette(() => [item("Ir a Tareas", { run: go }), item("Ir a Chat", { run: other })]);
    await p.open();
    await flush();
    const input = document.querySelector<HTMLInputElement>(".palette-input")!;
    expect(p.isOpen).toBe(true);
    expect(document.activeElement).toBe(input);
    expect(document.querySelectorAll(".palette-item")).toHaveLength(2);
    input.value = "tare";
    input.dispatchEvent(new Event("input"));
    expect(document.querySelectorAll(".palette-item")).toHaveLength(1);
    key(input, "Enter");
    expect(go).toHaveBeenCalledOnce();
    expect(other).not.toHaveBeenCalled();
    expect(p.isOpen).toBe(false);
    expect(document.querySelector(".palette")).toBeNull();
  });

  it("las flechas mueven la selección y Esc la cierra devolviendo el foco", async () => {
    const opener = document.createElement("button");
    document.body.append(opener);
    opener.focus();
    const second = vi.fn();
    const p = new Palette(() => [item("Uno"), item("Dos", { run: second })]);
    await p.open();
    await flush();
    const input = document.querySelector<HTMLInputElement>(".palette-input")!;
    key(input, "ArrowDown");
    expect(document.querySelectorAll(".palette-item")[1].getAttribute("aria-selected")).toBe("true");
    key(input, "Enter");
    expect(second).toHaveBeenCalledOnce();
    await p.open();
    await flush();
    key(document.querySelector(".palette-input")!, "Escape");
    expect(p.isOpen).toBe(false);
    expect(document.activeElement).toBe(opener);
    opener.remove();
  });

  it("es un diálogo modal accesible", async () => {
    const p = new Palette(() => []);
    await p.open();
    expect(document.querySelector('.palette-box')?.getAttribute("aria-modal")).toBe("true");
    expect(document.querySelector(".palette-input")?.getAttribute("role")).toBe("combobox");
    p.close();
  });
});
