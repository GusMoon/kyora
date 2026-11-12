import { afterEach, describe, expect, it } from "vitest";
import { Shell } from "../src/ui/shell";
import { Store } from "../src/store";
import { Status } from "../src/status";
import type { Player, PlayerState } from "../src/player";

function fakePlayer(): Player {
  const state: PlayerState = { track: null, playing: false, loading: false, time: 0, duration: 0, error: null };
  return {
    state,
    on(fn: (s: PlayerState) => void) {
      fn(state);
      return () => {};
    },
    play() {},
    toggle() {},
    next() {},
    previous() {},
    seek() {},
    stop() {},
  } as unknown as Player;
}

function setup() {
  let signedOut = false;
  const shell = new Shell({ store: new Store(), player: fakePlayer(), status: new Status(), signOut: () => (signedOut = true) });
  document.body.append(shell.root);
  return { shell, wasSignedOut: () => signedOut };
}

const tile = (shell: Shell, route: string) => shell.root.querySelector<HTMLElement>(`.tile-${route}`)!;

afterEach(() => {
  location.hash = "";
  document.body.replaceChildren();
});

describe("tablero", () => {
  it("en Inicio es un mosaico con las seis teselas, todas cuadradas y en orden", () => {
    const { shell } = setup();
    shell.setSection("inicio", "");
    expect(shell.root.dataset.mode).toBe("home");
    expect(shell.root.querySelectorAll(".tile")).toHaveLength(6);
    const nums = [...shell.root.querySelectorAll(".tile-num")].map((n) => n.textContent);
    expect(nums.sort()).toEqual(["/01", "/02", "/03", "/04", "/05", "/06"]);
    expect(shell.root.querySelector(".is-active")).toBeNull();
  });

  it("al abrir una sección su tesela queda activa y las demás pasan a la columna", () => {
    const { shell } = setup();
    shell.setSection("tareas", "5 abiertas; 2 vencen hoy.");
    expect(shell.root.dataset.mode).toBe("focus");
    expect(shell.root.dataset.active).toBe("tareas");
    expect(tile(shell, "tareas").classList.contains("is-active")).toBe(true);
    expect(tile(shell, "musica").classList.contains("is-active")).toBe(false);
    expect(tile(shell, "tareas").querySelector(".tile-statement")?.textContent).toBe("5 abiertas; 2 vencen hoy.");
    expect(tile(shell, "tareas").querySelector(".tile-link")?.getAttribute("aria-current")).toBe("page");
    expect(document.title).toBe("Tareas | Merida");
  });

  it("la sección se monta dentro de su tesela, y al cambiar se vacía la anterior", () => {
    const { shell } = setup();
    shell.setSection("tareas", "");
    shell.body.append(document.createElement("form"));
    expect(tile(shell, "tareas").querySelector(".tile-panel form")).not.toBeNull();
    shell.setSection("chat", "");
    expect(tile(shell, "tareas").querySelector(".tile-panel")?.children).toHaveLength(0);
    expect(shell.body).toBe(tile(shell, "chat").querySelector(".tile-panel"));
    shell.setStatement("Conversación General.");
    expect(tile(shell, "chat").querySelector(".tile-statement")?.textContent).toBe("Conversación General.");
  });

  it("las teselas que tienen contenido no son enlaces: el enlace es el título (para no meter botones dentro de un <a>)", () => {
    const { shell } = setup();
    for (const route of ["tareas", "musica", "chat"]) {
      expect(tile(shell, route).tagName).toBe("SECTION");
      expect(tile(shell, route).querySelector(".tile-title a")?.getAttribute("href")).toBe(`#/${route}`);
    }
  });

  it("el botón de cerrar vuelve al inicio y Salir cierra la sesión", () => {
    const { shell, wasSignedOut } = setup();
    shell.setSection("musica", "");
    tile(shell, "musica").querySelector<HTMLButtonElement>(".tile-close")!.click();
    expect(location.hash).toBe("#/inicio");
    tile(shell, "exit").click();
    expect(wasSignedOut()).toBe(true);
  });

  it("al volver al inicio el foco regresa a la tesela que estaba abierta", () => {
    const { shell } = setup();
    shell.setSection("chat", "");
    tile(shell, "chat").querySelector<HTMLButtonElement>(".tile-close")!.focus();
    shell.setSection("inicio", "");
    expect(document.activeElement).toBe(tile(shell, "chat").querySelector(".tile-link"));
  });
});
