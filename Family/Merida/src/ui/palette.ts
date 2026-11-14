import { h } from "./dom";
import { icon } from "./icons";
import { grouped, rank, type PaletteItem } from "../palette";

/** La paleta de comandos: una caja sobre todo lo demás. Se abre con `Ctrl+K` (también escribiendo en un campo), se mueve con
 * las flechas, se ejecuta con Enter y se cierra con Esc. El foco vuelve a donde estaba. */
export class Palette {
  private root: HTMLElement | null = null;
  private input!: HTMLInputElement;
  private list!: HTMLElement;
  private results: PaletteItem[] = [];
  private active = 0;
  private opener: HTMLElement | null = null;

  /** `getItems` se llama cada vez que se abre: así siempre refleja lo que hay ahora (tareas nuevas, bóveda abierta…). */
  constructor(private getItems: () => PaletteItem[] | Promise<PaletteItem[]>) {}

  get isOpen(): boolean {
    return this.root !== null;
  }

  toggle() {
    if (this.isOpen) this.close();
    else void this.open();
  }

  async open() {
    if (this.root) return;
    this.opener = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    this.input = h("input", {
      type: "text",
      class: "palette-input",
      role: "combobox",
      "aria-expanded": "true",
      "aria-controls": "palette-list",
      "aria-autocomplete": "list",
      "aria-label": "Buscar una sección, tarea o acción",
      placeholder: "Escribe para buscar…",
      autocomplete: "off",
      spellcheck: "false",
    });
    this.list = h("ul", { class: "palette-list", id: "palette-list", role: "listbox", "aria-label": "Resultados" });
    const box = h(
      "div",
      { class: "palette-box", role: "dialog", "aria-modal": "true", "aria-label": "Paleta de comandos" },
      h("div", { class: "palette-bar" }, icon("command", "icon"), this.input, h("kbd", { class: "palette-esc" }, "Esc")),
      this.list,
      h("p", { class: "palette-foot label" }, "↑↓ elegir · ⏎ abrir · Esc cerrar"),
    );
    this.root = h("div", { class: "palette", onMouseDown: (e: Event) => e.target === this.root && this.close() }, box);
    document.body.append(this.root);
    this.input.addEventListener("input", () => this.render(true));
    this.input.addEventListener("keydown", (e) => this.onKey(e));
    this.input.focus();
    let items: PaletteItem[] = [];
    try {
      items = await this.getItems();
    } catch {
      items = [];
    }
    if (!this.root) return; // se cerró mientras cargaba
    this.all = items;
    this.render(true);
  }

  private all: PaletteItem[] = [];

  close() {
    if (!this.root) return;
    this.root.remove();
    this.root = null;
    this.all = [];
    this.opener?.isConnected && this.opener.focus({ preventScroll: true });
    this.opener = null;
  }

  private onKey(e: KeyboardEvent) {
    if (e.isComposing) return;
    if (e.key === "Escape") {
      e.preventDefault();
      e.stopPropagation();
      this.close();
    } else if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      if (!this.results.length) return;
      this.active = (this.active + (e.key === "ArrowDown" ? 1 : -1) + this.results.length) % this.results.length;
      this.paintActive();
    } else if (e.key === "Enter") {
      e.preventDefault();
      this.run(this.results[this.active]);
    } else if (e.key === "Tab") {
      e.preventDefault(); // el foco no sale de la caja
    }
  }

  private run(item: PaletteItem | undefined) {
    if (!item) return;
    this.close();
    item.run();
  }

  private render(reset: boolean) {
    this.results = rank(this.all, this.input.value);
    if (reset) this.active = 0;
    this.list.replaceChildren();
    if (!this.results.length) {
      this.list.append(h("li", { class: "palette-empty", role: "presentation" }, this.all.length ? "Nada coincide con lo que escribiste." : "Cargando…"));
      this.input.removeAttribute("aria-activedescendant");
      return;
    }
    let index = 0;
    for (const g of grouped(this.results)) {
      this.list.append(h("li", { class: "palette-group label", role: "presentation" }, g.group));
      for (const item of g.items) {
        const i = index++;
        this.list.append(
          h(
            "li",
            {
              class: "palette-item",
              role: "option",
              id: `palette-opt-${i}`,
              "aria-selected": String(i === this.active),
              // mousedown + preventDefault: elegir con el ratón no le quita el foco al campo
              onMouseDown: (e: Event) => {
                e.preventDefault();
                this.run(item);
              },
              onMouseMove: () => {
                if (this.active !== i) {
                  this.active = i;
                  this.paintActive();
                }
              },
            },
            h("span", { class: "palette-label" }, item.label),
            item.hint ? h("span", { class: "palette-hint" }, item.hint) : null,
          ),
        );
      }
    }
    this.paintActive();
  }

  private paintActive() {
    this.list.querySelectorAll<HTMLElement>(".palette-item").forEach((el, i) => {
      const on = i === this.active;
      el.setAttribute("aria-selected", String(on));
      if (on) {
        this.input.setAttribute("aria-activedescendant", el.id);
        el.scrollIntoView?.({ block: "nearest" });
      }
    });
  }
}
