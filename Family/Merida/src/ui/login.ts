import type { SupabaseClient } from "@supabase/supabase-js";
import { h } from "./dom";
import { explainError } from "../supabase";
import { DEVICE } from "../config";

type LineKind = "dim" | "err" | "ok" | "";

/** La consola: un marco con una cabecera, las líneas que van quedando y, abajo, el renglón donde se escribe.
 * Es lo único que se ve en el acceso y en el aviso de configuración. */
class Console {
  readonly root: HTMLElement;
  private readonly log = h("div", { class: "console-log", "aria-live": "polite" });
  private readonly slot = h("div", { class: "console-slot" });
  private readonly hint = h("span", {});

  constructor(title: string, tag: string) {
    const body = h("div", { class: "console-body" }, this.log, this.slot);
    // tocar la consola lleva el cursor al renglón, como en una terminal
    body.addEventListener("click", () => {
      if (!window.getSelection()?.toString()) this.slot.querySelector("input")?.focus();
    });
    this.root = h(
      "main",
      { class: "console-screen", id: "main" },
      h(
        "section",
        { class: "console", "aria-label": title },
        h("span", { class: "console-corner", "data-at": "tl", "aria-hidden": "true" }),
        h("span", { class: "console-corner", "data-at": "tr", "aria-hidden": "true" }),
        h("span", { class: "console-corner", "data-at": "bl", "aria-hidden": "true" }),
        h("span", { class: "console-corner", "data-at": "br", "aria-hidden": "true" }),
        h("header", { class: "console-head" }, h("h1", { class: "console-title" }, title), h("span", { class: "console-tag" }, tag)),
        body,
        h("footer", { class: "console-foot" }, h("span", {}, `dispositivo ${DEVICE}`), this.hint),
      ),
    );
  }

  line(text: string, kind: LineKind = "") {
    this.log.append(h("p", { class: `console-line${kind ? ` is-${kind}` : ""}` }, text));
  }

  setHint(text: string) {
    this.hint.textContent = text;
  }

  /** Pide un dato en un renglón (`correo>`). Resuelve con lo escrito al pulsar Enter, o con null si se pulsa Esc
   * (solo si `escape` es true). Un renglón vacío no se acepta: avisa y sigue esperando. */
  ask(label: string, type: "email" | "password", opts: { initial?: string; escape?: boolean } = {}): Promise<string | null> {
    return new Promise((resolve) => {
      const id = `console-${type}`;
      const input = h("input", {
        id,
        type,
        autocomplete: type === "email" ? "username" : "current-password",
        spellcheck: "false",
        autocapitalize: "off",
        autocorrect: "off",
        "aria-describedby": "console-hint",
      });
      input.value = opts.initial ?? "";
      const row = h("form", { class: "prompt-row", novalidate: true }, h("label", { for: id }, `${label}>`), input);
      this.hint.id = "console-hint";
      this.setHint(opts.escape ? "enter envía, esc vuelve al correo" : "enter envía");

      const finish = (value: string | null, echo: string) => {
        this.slot.replaceChildren();
        this.line(`${label}> ${echo}`);
        resolve(value);
      };
      row.addEventListener("submit", (event) => {
        event.preventDefault();
        const value = type === "email" ? input.value.trim() : input.value;
        if (!value) {
          this.line(type === "email" ? "escribe el correo de tu cuenta" : "escribe la contraseña", "err");
          return;
        }
        finish(value, type === "password" ? "********" : value);
      });
      if (opts.escape) {
        input.addEventListener("keydown", (event) => {
          if (event.key === "Escape") finish(null, "(cancelado)");
        });
      }
      this.slot.replaceChildren(row);
      queueMicrotask(() => input.focus());
    });
  }
}

/** La pantalla de acceso: una consola en el centro que pide el correo y luego la contraseña, la misma cuenta de Supabase
 * que en la PC y el móvil. La contraseña no se guarda en ningún archivo. Si entra, main.ts se entera por
 * onAuthStateChange y monta la app. */
export function loginScreen(client: SupabaseClient): HTMLElement {
  const term = new Console("merida", "acceso");

  async function run() {
    term.line("consola de acceso, versión web", "dim");
    term.line("servidor ........ listo", "dim");
    term.line(`dispositivo ..... ${DEVICE}`, "dim");
    term.line("sesión .......... sin abrir", "dim");
    term.line("");
    term.line("Usa la misma cuenta que en la PC y en el móvil.");

    let email = "";
    for (;;) {
      email = (await term.ask("correo", "email", { initial: email })) ?? email;
      const password = await term.ask("contraseña", "password", { escape: true });
      if (password === null) continue; // Esc: otra vez el correo
      term.line("verificando…", "dim");
      try {
        const { error } = await client.auth.signInWithPassword({ email, password });
        if (!error) {
          term.line("acceso concedido", "ok");
          term.setHint("abriendo");
          return;
        }
        term.line(explainError(error), "err");
      } catch (err) {
        term.line(explainError(err), "err");
      }
      term.line("");
    }
  }
  void run();
  return term.root;
}

/** Lo que se ve si falta la configuración del servidor: la misma consola, con el error. */
export function missingConfigScreen(missing: string[]): HTMLElement {
  const term = new Console("merida", "sin configurar");
  term.line("consola de acceso, versión web", "dim");
  term.line("servidor ........ sin configurar", "dim");
  term.line("");
  term.line(`error: no encuentro ${missing.join(" ni ")}.`, "err");
  term.line("");
  term.line("Rellena Server/supabase/.env (o %APPDATA%\\Kyora\\chat.env) con la URL y la clave pública de tu proyecto, como explica Server/supabase/README.md.");
  term.line("");
  term.line("Después cierra Merida y vuelve a abrirla con Scripts\\Merida\\iniciar_merida.bat.");
  term.setHint("sin sesión");
  return term.root;
}
