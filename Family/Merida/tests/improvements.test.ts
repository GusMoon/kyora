import { afterEach, describe, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  buildImprovementsPrompt,
  finishImprovement,
  functionLines,
  improvementsStatement,
  loadImprovements,
  newImprovement,
  saveImprovement,
  sortImprovements,
  validateImprovement,
  withImprovement,
  withoutImprovement,
  type Improvement,
} from "../src/data/improvements";
import { improvementsSection } from "../src/sections/improvements";
import { Shell } from "../src/ui/shell";
import { Store } from "../src/store";
import { Status } from "../src/status";
import { DEFAULT_PREFS, PrefsStore } from "../src/prefs";
import { Backdrop } from "../src/backdrop";
import { Library } from "../src/data/library";
import { buildPaletteItems } from "../src/paletteItems";
import { routeForKey } from "../src/hotkeys";
import type { Player } from "../src/player";
import type { Ctx } from "../src/sections/context";

const T0 = new Date("2026-11-14T10:00:00Z");
const item = (id: string, section: string, extra: Partial<Improvement> = {}): Improvement => ({ id, section, functions: "", description: "", created_at: T0.toISOString(), ...extra });

type Row = Record<string, unknown>;

/** Un Supabase de mentira con la tabla `feature_requests`: guarda, borra y anota cada llamada. */
function fakeClient(opts: { failDelete?: boolean; failUpsert?: boolean } = {}) {
  const rows: Row[] = [];
  const calls: { op: string; payload?: unknown; id?: unknown }[] = [];
  const from = (table: string) => {
    expect(table).toBe("feature_requests");
    let op = "select";
    let payload: unknown;
    let id: unknown;
    const b: Record<string, unknown> = {
      select: () => b,
      order: () => b,
      limit: () => b,
      upsert: (p: unknown) => ((op = "upsert"), (payload = p), b),
      delete: () => ((op = "delete"), b),
      eq: (_col: string, v: unknown) => ((id = v), b),
      then: (res: (v: unknown) => unknown) => {
        if (op === "upsert") {
          calls.push({ op, payload });
          if (opts.failUpsert) return Promise.resolve({ data: null, error: { message: "sin red" } }).then(res);
          rows.push(payload as Row);
        }
        if (op === "delete") {
          calls.push({ op, id });
          if (opts.failDelete) return Promise.resolve({ data: null, error: { message: "sin red" } }).then(res);
          const at = rows.findIndex((r) => r.id === id);
          if (at >= 0) rows.splice(at, 1);
        }
        return Promise.resolve({ data: op === "select" ? rows : null, error: null }).then(res);
      },
    };
    return b;
  };
  return { client: { from } as unknown as SupabaseClient, rows, calls };
}

const flush = async (n = 6) => {
  for (let i = 0; i < n; i++) await new Promise((r) => setTimeout(r, 0));
};

function mount(setup: (store: Store) => void = () => {}, opts: Parameters<typeof fakeClient>[0] = {}) {
  const fake = fakeClient(opts);
  const store = new Store();
  setup(store);
  const prefs = new PrefsStore({ ...DEFAULT_PREFS, keys: { ...DEFAULT_PREFS.keys } });
  const shell = new Shell({ store, prefs });
  document.body.append(shell.root);
  shell.setSection("mejoras", "");
  const reload = vi.fn(async () => {});
  const ctx: Ctx = {
    client: fake.client, shell, store, player: {} as Player, status: new Status(), prefs, backdrop: new Backdrop({ storage: null }), library: new Library(),
    vault: {} as never, userId: "user-1", signOut() {}, reload,
  };
  const unmount = improvementsSection(ctx);
  return { shell, store, unmount, reload, ...fake };
}

const typeInto = (el: HTMLInputElement | HTMLTextAreaElement, value: string) => {
  el.value = value;
  el.dispatchEvent(new Event("input", { bubbles: true }));
};
const submit = (form: HTMLFormElement) => form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));

afterEach(() => {
  document.body.replaceChildren();
  location.hash = "";
  vi.restoreAllMocks();
});

describe("mejoras: los datos", () => {
  it("una mejora nueva lleva los textos recortados, la hora y un id del dispositivo", () => {
    const n = newImprovement({ section: "  Calendario ", functions: " - Vista de agenda ", description: " Que se vea mejor " }, T0, "x");
    expect(n).toEqual({ id: "x", section: "Calendario", functions: "- Vista de agenda", description: "Que se vea mejor", created_at: T0.toISOString() });
    expect(newImprovement({ section: "A" }).id).toMatch(/^[0-9a-f-]{36}$/);
  });

  it("pide la sección y al menos una función o una descripción", () => {
    expect(validateImprovement({ section: "  " })).toMatch(/sección/);
    expect(validateImprovement({ section: "Música" })).toMatch(/función o una descripción/);
    expect(validateImprovement({ section: "Música", functions: "Cola" })).toBeNull();
    expect(validateImprovement({ section: "Música", description: "Más bonita" })).toBeNull();
    expect(validateImprovement({ section: "x".repeat(81), functions: "a" })).toMatch(/80/);
    expect(validateImprovement({ section: "Música", functions: "a".repeat(4001) })).toMatch(/4000/);
  });

  it("las funciones se leen una por línea, sin viñetas ni números", () => {
    expect(functionLines("- Vista de agenda\n* Arrastrar eventos\n• Colores\n1. Uno\n2) Dos\n\n   \nSin viñeta")).toEqual(["Vista de agenda", "Arrastrar eventos", "Colores", "Uno", "Dos", "Sin viñeta"]);
    expect(functionLines("")).toEqual([]);
  });

  it("se ordenan de la más nueva a la más antigua, sin repetir, y se quitan por id", () => {
    const old = item("a", "Vieja", { created_at: "2026-11-01T00:00:00Z" });
    const fresh = item("b", "Nueva", { created_at: "2026-11-13T00:00:00Z" });
    expect(sortImprovements([old, fresh]).map((i) => i.id)).toEqual(["b", "a"]);
    expect(withImprovement([old], fresh).map((i) => i.id)).toEqual(["b", "a"]);
    expect(withImprovement([old, fresh], { ...old, section: "Editada" }).filter((i) => i.id === "a")).toHaveLength(1);
    expect(withoutImprovement([old, fresh], "a").map((i) => i.id)).toEqual(["b"]);
  });

  it("el enunciado cuenta lo pendiente", () => {
    expect(improvementsStatement([], false)).toBe("Cargando tus mejoras pendientes.");
    expect(improvementsStatement([], true)).toMatch(/No hay mejoras pendientes/);
    expect(improvementsStatement([item("a", "A")], true)).toBe("1 mejora pendiente.");
    expect(improvementsStatement([item("a", "A"), item("b", "B")], true)).toBe("2 mejoras pendientes.");
    expect(improvementsStatement([], true, "Sin conexión")).toBe("Sin conexión");
  });

  it("guarda, lee y borra de verdad en `feature_requests`", async () => {
    const { client, rows, calls } = fakeClient();
    await saveImprovement(client, item("a", "Música"));
    expect(rows).toHaveLength(1);
    expect(await loadImprovements(client)).toHaveLength(1);
    await finishImprovement(client, "a");
    expect(rows).toHaveLength(0); // se borró de la base de datos, no se marcó
    expect(calls.map((c) => c.op)).toEqual(["upsert", "delete"]);
    expect(calls[1].id).toBe("a");
  });

  it("un error del servidor se lanza para poder avisarlo", async () => {
    const { client } = fakeClient({ failDelete: true });
    await expect(finishImprovement(client, "a")).rejects.toBeTruthy();
  });
});

describe("mejoras: la sección", () => {
  it("lista las pendientes con su sección, sus funciones como viñetas y su descripción", () => {
    const { shell } = mount((s) => {
      s.improvements = [item("a", "Calendario", { functions: "- Vista de agenda\nArrastrar eventos", description: "Que se vea mejor" })];
      s.loaded.improvements = true;
    });
    const card = shell.body.querySelector(".imp-card")!;
    expect(card.querySelector(".imp-section")?.textContent).toBe("Calendario");
    expect([...card.querySelectorAll(".imp-functions li")].map((l) => l.textContent)).toEqual(["Vista de agenda", "Arrastrar eventos"]);
    expect(card.querySelector(".imp-desc")?.textContent).toBe("Que se vea mejor");
    expect(card.querySelector(".imp-done")?.textContent).toContain("Hecho");
    expect(shell.body.closest(".tile")?.querySelector(".tile-statement")?.textContent).toBe("1 mejora pendiente.");
  });

  it("registrar pide lo mínimo; con lo escrito aparece al instante, se sube y se vacía el formulario", async () => {
    const { shell, store, rows } = mount((s) => {
      s.loaded.improvements = true;
    });
    const form = shell.body.querySelector<HTMLFormElement>(".imp-form")!;
    submit(form);
    expect(form.querySelector(".form-error")?.textContent).toMatch(/sección/);
    const [section] = form.querySelectorAll("input");
    const [functions, description] = form.querySelectorAll("textarea");
    typeInto(section, "Finanzas");
    submit(form);
    expect(form.querySelector(".form-error")?.textContent).toMatch(/función o una descripción/);
    typeInto(functions, "Presupuestos por categoría");
    typeInto(description, "Avisar al pasarse");
    submit(form);
    await flush();
    expect(store.improvements).toHaveLength(1);
    expect(store.improvements[0]).toMatchObject({ section: "Finanzas", functions: "Presupuestos por categoría", description: "Avisar al pasarse" });
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ section: "Finanzas" });
    expect(shell.body.querySelectorAll(".imp-card")).toHaveLength(1);
    expect(section.value).toBe("");
    expect(functions.value).toBe("");
    expect(form.querySelector(".form-error")?.textContent).toBe("");
  });

  it("si no se puede guardar, lo dice y vuelve a leer lo del servidor", async () => {
    const { shell, reload } = mount(() => {}, { failUpsert: true });
    const form = shell.body.querySelector<HTMLFormElement>(".imp-form")!;
    typeInto(form.querySelector("input")!, "Música");
    typeInto(form.querySelector("textarea")!, "Cola");
    submit(form);
    await flush();
    expect(shell.body.querySelector(".notice")?.textContent).toMatch(/No se guardó la mejora/);
    expect(reload).toHaveBeenCalledWith("improvements");
  });

  it("«Hecho» pide confirmación; al confirmar sale de la lista y se borra de la base de datos", async () => {
    const { shell, store, rows, calls } = mount((s) => {
      s.improvements = [item("a", "Calendario"), item("b", "Música", { created_at: "2026-11-01T00:00:00Z" })];
      s.loaded.improvements = true;
    });
    rows.push({ id: "a" }, { id: "b" });
    const confirmSpy = vi.spyOn(window, "confirm").mockReturnValue(false);
    (shell.body.querySelector(".imp-done") as HTMLElement).click();
    await flush();
    expect(confirmSpy).toHaveBeenCalledOnce();
    expect(store.improvements).toHaveLength(2); // cancelar no borra nada
    expect(calls).toHaveLength(0);
    confirmSpy.mockReturnValue(true);
    (shell.body.querySelector(".imp-done") as HTMLElement).click();
    await flush();
    expect(store.improvements.map((i) => i.id)).toEqual(["b"]);
    expect(shell.body.querySelectorAll(".imp-card")).toHaveLength(1);
    expect(shell.body.textContent).not.toContain("Calendario");
    expect(calls).toEqual([{ op: "delete", id: "a" }]);
    expect(rows.map((r) => r.id)).toEqual(["b"]);
  });

  it("si no se puede borrar, la mejora vuelve a la lista y se avisa", async () => {
    const { shell, store } = mount(
      (s) => {
        s.improvements = [item("a", "Calendario")];
        s.loaded.improvements = true;
      },
      { failDelete: true },
    );
    vi.spyOn(window, "confirm").mockReturnValue(true);
    (shell.body.querySelector(".imp-done") as HTMLElement).click();
    await flush();
    expect(store.improvements.map((i) => i.id)).toEqual(["a"]);
    expect(shell.body.querySelector(".notice")?.textContent).toMatch(/No se pudo borrar la mejora/);
    expect(shell.body.querySelectorAll(".imp-card")).toHaveLength(1);
  });

  it("sin pendientes lo dice, y lo que llega del servidor se pinta solo", () => {
    const { shell, store } = mount((s) => {
      s.loaded.improvements = true;
    });
    expect(shell.body.querySelector(".imp-list .cfg-help")?.textContent).toBe("No hay mejoras pendientes.");
    store.improvements = [item("z", "Chat")];
    store.emit("improvements");
    expect(shell.body.querySelectorAll(".imp-card")).toHaveLength(1);
  });

  describe("copiar el prompt", () => {
    const seed = (s: Store) => {
      s.improvements = [
        item("a", "Calendario", { functions: "- Vista de agenda\nArrastrar eventos", description: "Que se vea mejor\n\n# no es un título", created_at: "2026-11-13T00:00:00Z" }),
        item("b", "Música", { functions: "Cola", created_at: "2026-11-12T00:00:00Z" }),
        item("c", "Chat", { description: "Más rápido", created_at: "2026-11-01T00:00:00Z" }),
      ];
      s.loaded.improvements = true;
    };
    const stubClipboard = (writeText: (t: string) => Promise<void>) => Object.defineProperty(navigator, "clipboard", { value: { writeText }, configurable: true });
    const checks = (shell: Shell) => [...shell.body.querySelectorAll<HTMLInputElement>(".imp-check")];
    const click = (el: HTMLElement) => el.click();

    it("el prompt en Markdown lleva contexto, una tarea por mejora, funciones como casillas y la descripción citada", () => {
      const md = buildImprovementsPrompt([
        item("a", "Calendario", { functions: "- Vista de agenda\nArrastrar eventos", description: "Que se vea mejor\n\n# no es un título" }),
        item("c", "  Chat \n nuevo ", { description: "Más rápido" }),
      ]);
      expect(md).toMatch(/^# Mejoras para Merida/);
      expect(md).toContain("## Tareas (2)");
      expect(md).toContain("### 1. Calendario\n\n**Funciones que se quieren:**\n- [ ] Vista de agenda\n- [ ] Arrastrar eventos\n\n**Descripción:**\n> Que se vea mejor\n>\n> # no es un título");
      expect(md).toContain("### 2. Chat nuevo\n\n**Descripción:**\n> Más rápido");
      expect(md).not.toMatch(/^# no es un título/m); // la descripción nunca crea títulos
      expect(md).toContain("las 2 mejoras");
      expect(md).toContain("npm run typecheck");
      expect(buildImprovementsPrompt([item("b", "Música", { functions: "Cola" })])).toContain("la mejora en el orden");
    });

    it("hay una casilla por mejora y el botón de copiar empieza desactivado", () => {
      const { shell } = mount(seed);
      expect(checks(shell)).toHaveLength(3);
      expect(shell.body.querySelector<HTMLButtonElement>(".imp-copy")!.disabled).toBe(true);
      expect(shell.body.querySelector(".imp-count")?.textContent).toMatch(/Escoge/);
    });

    it("copia solo lo escogido, en el orden de la lista, y avisa", async () => {
      const writeText = vi.fn(async (_text: string) => {});
      stubClipboard(writeText);
      const { shell } = mount(seed);
      const [a, , c] = checks(shell);
      click(c);
      click(a);
      expect(shell.body.querySelector(".imp-count")?.textContent).toBe("2 de 3 seleccionadas");
      expect(shell.body.querySelector(".imp-card.is-picked")).not.toBeNull();
      click(shell.body.querySelector(".imp-copy") as HTMLElement);
      await flush();
      expect(writeText).toHaveBeenCalledOnce();
      const md = writeText.mock.calls[0][0];
      expect(md).toContain("## Tareas (2)");
      expect(md.indexOf("Calendario")).toBeLessThan(md.indexOf("Chat"));
      expect(md).not.toContain("Música");
      expect(shell.body.querySelector(".notice")?.textContent).toMatch(/Prompt copiado con 2 mejoras/);
    });

    it("«Todas» marca y desmarca todas, y queda a medias con una parte", () => {
      const { shell } = mount(seed);
      const all = shell.body.querySelector<HTMLInputElement>(".imp-all input")!;
      click(all);
      expect(checks(shell).every((c) => c.checked)).toBe(true);
      expect(shell.body.querySelector<HTMLButtonElement>(".imp-copy")!.disabled).toBe(false);
      click(checks(shell)[0]);
      expect(all.indeterminate).toBe(true);
      click(all); // a medias → pasa a todas marcadas
      click(all);
      expect(checks(shell).some((c) => c.checked)).toBe(false);
      expect(shell.body.querySelector<HTMLButtonElement>(".imp-copy")!.disabled).toBe(true);
    });

    it("la selección sobrevive a que llegue algo nuevo y se olvida de lo que ya no existe", () => {
      const { shell, store } = mount(seed);
      click(checks(shell)[1]); // Música
      store.improvements = [...store.improvements, item("d", "Nube", { functions: "x", created_at: "2026-11-14T00:00:00Z" })];
      store.emit("improvements");
      expect(checks(shell).filter((c) => c.checked)).toHaveLength(1);
      expect(shell.body.querySelector(".imp-count")?.textContent).toBe("1 de 4 seleccionadas");
      store.improvements = store.improvements.filter((i) => i.id !== "b");
      store.emit("improvements");
      expect(shell.body.querySelector(".imp-count")?.textContent).toMatch(/Escoge/);
    });

    it("si el navegador no deja copiar, lo dice", async () => {
      stubClipboard(async () => {
        throw new Error("denegado");
      });
      const { shell } = mount(seed);
      click(checks(shell)[0]);
      click(shell.body.querySelector(".imp-copy") as HTMLElement);
      await flush();
      expect(shell.body.querySelector(".notice")?.textContent).toMatch(/No se pudo copiar/);
    });
  });

  it("la tesela del mosaico y su atajo existen", () => {
    const store = new Store();
    const shell = new Shell({ store });
    expect(shell.root.querySelector(".tile-mejoras")).not.toBeNull();
    expect(shell.root.querySelector(".tile-mejoras .tile-link")?.textContent).toBe("Mejoras");
    expect(routeForKey({ ...DEFAULT_PREFS.keys }, "j")).toBe("mejoras");
  });

  it("la paleta ofrece «Nueva mejora pendiente»", async () => {
    const store = new Store();
    const go = vi.fn();
    const prefs = new PrefsStore({ ...DEFAULT_PREFS, keys: { ...DEFAULT_PREFS.keys } });
    const { client } = fakeClient();
    const items = await buildPaletteItems({ client, store, prefs, vault: { state: "locked", items: [], lock() {} } as never, go });
    const action = items.find((i) => i.label === "Nueva mejora pendiente")!;
    expect(action).toBeTruthy();
    action.run();
    expect(go).toHaveBeenCalledWith("#/mejoras");
    expect(store.take("new-improvement")).not.toBeNull();
  });
});
