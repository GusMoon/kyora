import { afterEach, describe, expect, it } from "vitest";
import { Shell } from "../src/ui/shell";
import { Store } from "../src/store";

function setup() {
  const store = new Store();
  const shell = new Shell({ store });
  document.body.append(shell.root);
  return { shell, store };
}

const tile = (shell: Shell, route: string) => shell.root.querySelector<HTMLElement>(`.tile-${route}`)!;

afterEach(() => {
  location.hash = "";
  document.body.replaceChildren();
});

describe("tablero", () => {
  it("en Inicio hay cinco teselas, sin Sistema ni Salir, y Configuración va en el centro del orden", () => {
    const { shell } = setup();
    shell.setSection("inicio", "");
    expect(shell.root.dataset.mode).toBe("home");
    const tiles = [...shell.root.querySelectorAll(".tile")];
    expect(tiles).toHaveLength(5);
    expect(shell.root.querySelector(".tile-system, .tile-exit")).toBeNull();
    // en el documento: Tareas, Música, Configuración (centro), Nube y Chat
    expect(tiles.map((t) => t.className.match(/tile-(\w+)/)![1])).toEqual(["tareas", "musica", "configuracion", "nube", "chat"]);
    // sin números al lado de los nombres
    expect(shell.root.querySelector(".tile-num")).toBeNull();
    expect(shell.root.textContent).not.toMatch(/\/0\d/);
  });

  it("Configuración, en el centro, es solo un cuadrado con su icono: sin cuenta, medidores ni insignia", () => {
    const { shell } = setup();
    const cfg = tile(shell, "configuracion");
    expect(cfg.querySelector(".tile-glyph .icon")).not.toBeNull();
    expect(cfg.querySelector(".sys, .sys-badge, .tile-foot, .tile-note")).toBeNull();
    expect(cfg.querySelector(".tile-link")?.getAttribute("href")).toBe("#/configuracion");
  });

  it("cada tesela lleva su icono y Configuración abre su sección con la tecla A", () => {
    const { shell } = setup();
    for (const route of ["tareas", "musica", "chat", "configuracion", "nube"]) {
      expect(tile(shell, route).querySelector(".tile-icon")).not.toBeNull();
    }
    expect(tile(shell, "configuracion").querySelector(".tile-link")?.getAttribute("href")).toBe("#/configuracion");
    expect(tile(shell, "configuracion").querySelector(".tile-key")?.textContent).toBe("A");
  });

  it("al abrir una sección su tesela queda activa y las demás pasan al dock, con su puesto", () => {
    const { shell } = setup();
    shell.setSection("tareas", "5 abiertas; 2 vencen hoy.");
    expect(shell.root.dataset.mode).toBe("focus");
    expect(tile(shell, "tareas").classList.contains("is-active")).toBe(true);
    expect(tile(shell, "tareas").querySelector(".tile-statement")?.textContent).toBe("5 abiertas; 2 vencen hoy.");
    expect(shell.root.style.getPropertyValue("--dock-n")).toBe("4");
    const docked = ["musica", "configuracion", "nube", "chat"].map((r) => tile(shell, r).style.getPropertyValue("--dock-i"));
    expect(docked).toEqual(["0", "1", "2", "3"]);
    expect(shell.root.querySelector(".edge")).not.toBeNull();
  });

  it("en el dock cada cuadrado lleva solo su icono y su nombre, y enlaza a su sección", () => {
    const { shell } = setup();
    shell.setSection("chat", "");
    const face = tile(shell, "musica").querySelector<HTMLAnchorElement>(".dock-face")!;
    expect(face.getAttribute("href")).toBe("#/musica");
    expect(face.getAttribute("aria-label")).toBe("Música (tecla M)");
    expect(face.querySelector(".dock-icon")).not.toBeNull();
    expect(face.querySelector(".dock-label")?.textContent).toBe("Música");
  });

  it("la Nube ocupa el lugar del reproductor: sin reproductor en el inicio, abre su sección con la tecla N y dice cuántos archivos hay", () => {
    const { shell, store } = setup();
    const nube = tile(shell, "nube");
    expect(shell.root.querySelector(".tile-play, .play-deck, .btn-play")).toBeNull();
    expect(nube.querySelector(".tile-link")?.getAttribute("href")).toBe("#/nube");
    expect(nube.querySelector(".tile-key")?.textContent).toBe("N");
    expect(nube.querySelector(".tile-note")?.textContent).toBe("Leyendo el servidor…");
    store.files = [{ id: "chat:1", source: "chat", path: "p", name: "a.jpg", mime: "image/jpeg", size: 2 * 1024 * 1024, at: "2026-11-12T10:00:00Z", from: "pc", kind: "image" }];
    store.loaded.files = true;
    store.emit("files");
    expect(nube.querySelector(".tile-note")?.textContent).toBe("1 archivo en el servidor (2.0 MB).");
    shell.setSection("tareas", "");
    expect(nube.querySelector(".dock-face")?.getAttribute("aria-label")).toBe("Nube (tecla N)");
  });

  it("la sección se monta dentro de su tesela, y al cambiar se vacía la anterior", () => {
    const { shell } = setup();
    shell.setSection("tareas", "");
    shell.body.append(document.createElement("form"));
    expect(tile(shell, "tareas").querySelector(".tile-panel form")).not.toBeNull();
    shell.setSection("configuracion", "");
    expect(tile(shell, "tareas").querySelector(".tile-panel")?.children).toHaveLength(0);
    expect(shell.body).toBe(tile(shell, "configuracion").querySelector(".tile-panel"));
    expect(document.title).toBe("Configuración | Merida");
  });

  it("los efectos saben qué bloques y textos animar en cada sección", () => {
    const { shell } = setup();
    shell.setSection("tareas", "x");
    const p = document.createElement("p");
    p.setAttribute("data-hack", "");
    shell.body.append(p);
    const { blocks, texts } = shell.fxTargets();
    expect(blocks[0].classList.contains("tile-head")).toBe(true);
    expect(texts).toContain(p);
    expect(texts.some((t) => t.classList.contains("tile-link"))).toBe(true);
    const home = shell.fxTargets("inicio");
    expect(home.blocks).toHaveLength(5);
  });

  it("el botón de cerrar vuelve al inicio y el foco regresa a la tesela que estaba abierta", () => {
    const { shell } = setup();
    shell.setSection("chat", "");
    const close = tile(shell, "chat").querySelector<HTMLButtonElement>(".tile-close")!;
    close.focus();
    close.click();
    expect(location.hash).toBe("#/inicio");
    shell.setSection("inicio", "");
    expect(document.activeElement).toBe(tile(shell, "chat").querySelector(".tile-link"));
  });
});
