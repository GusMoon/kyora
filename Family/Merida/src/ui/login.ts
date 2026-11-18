import type { SupabaseClient } from "@supabase/supabase-js";
import { h } from "./dom";
import { explainError } from "../supabase";
import { DEVICE } from "../config";
import { hackText } from "./fx";
import { claimAccount, loginEmail } from "../data/users";

type LineKind = "dim" | "err" | "ok" | "";

/** La consola: un marco con una cabecera, las líneas que van quedando y, abajo, el renglón donde se escribe.
 * Es lo único que se ve en el acceso y en el aviso de configuración. */
class Console {
  readonly root: HTMLElement;
  private readonly log = h("div", { class: "console-log", "aria-live": "polite" });
  private readonly slot = h("div", { class: "console-slot" });
  private readonly hint = h("span", {});
  private readonly foot: HTMLElement;
  private readonly frame: HTMLElement;

  constructor(title: string, tag: string) {
    const body = h("div", { class: "console-body" }, this.log, this.slot);
    // tocar la consola lleva el cursor al renglón, como en una terminal
    body.addEventListener("click", () => {
      if (!window.getSelection()?.toString()) this.slot.querySelector("input")?.focus();
    });
    this.foot = h("footer", { class: "console-foot" }, h("span", {}, `dispositivo ${DEVICE}`), this.hint);
    // el mismo marco de Merida: logo en el acento, /00 ACCESO en mono, caja cuadrada con marcas de esquina
    this.frame = h(
      "section",
      { class: "console", "aria-label": `${title}: ${tag}` },
      h("span", { class: "console-corner", "data-at": "tl", "aria-hidden": "true" }),
      h("span", { class: "console-corner", "data-at": "br", "aria-hidden": "true" }),
      h(
        "header",
        { class: "console-head" },
        h("span", { class: "console-logo", "aria-hidden": "true" }, "MERIDA_"),
        h("h1", { class: "console-title" }, h("span", {}, tag)),
        h("span", { class: "console-tag" }, title),
      ),
      body,
      this.foot,
    );
    this.root = h("main", { class: "console-screen", id: "main" }, this.frame);
  }

  /** Una línea en la consola. Las informativas se escriben con el efecto hacking; lo que tecleas queda tal cual. */
  line(text: string, kind: LineKind = "", hack = kind !== "" && kind !== "err") {
    const el = h("p", { class: `console-line${kind ? ` is-${kind}` : ""}` }, text);
    this.log.append(el);
    if (hack && text.trim()) void hackText(el, text);
  }

  /** Entraste: el pie se vuelve la franja de aviso de Merida con «> acceso concedido_». */
  granted() {
    this.frame.classList.add("is-granted");
    this.foot.replaceChildren(h("span", { class: "console-granted" }, "> acceso concedido_"));
  }

  setHint(text: string) {
    this.hint.textContent = text;
  }

  /** Pide un dato en un renglón (`usuario>`). Resuelve con lo escrito al pulsar Enter, o con null si se pulsa Esc
   * (solo si `escape` es true). Un renglón vacío no se acepta: avisa y sigue esperando. */
  ask(label: string, type: "text" | "password", opts: { initial?: string; escape?: boolean; empty?: string; hint?: string } = {}): Promise<string | null> {
    return new Promise((resolve) => {
      const id = `console-${type}`;
      const input = h("input", {
        id,
        type,
        autocomplete: type === "text" ? "username" : "current-password",
        inputmode: type === "text" && label === "código" ? "numeric" : null,
        spellcheck: "false",
        autocapitalize: "off",
        autocorrect: "off",
        "aria-describedby": "console-hint",
      });
      input.value = opts.initial ?? "";
      const row = h("form", { class: "prompt-row", novalidate: true }, h("label", { for: id }, `${label}>`), input);
      this.hint.id = "console-hint";
      this.setHint(opts.hint ?? (opts.escape ? "enter envía, esc vuelve al usuario" : "enter envía"));

      const finish = (value: string | null, echo: string) => {
        this.slot.replaceChildren();
        this.line(`${label}> ${echo}`);
        resolve(value);
      };
      row.addEventListener("submit", (event) => {
        event.preventDefault();
        const value = type === "text" ? input.value.trim() : input.value;
        if (!value) {
          this.line(opts.empty ?? (type === "text" ? "escribe tu usuario (o el correo del administrador)" : "escribe la contraseña"), "err");
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

/** La pantalla de acceso: una consola en el centro que pide el usuario y luego la contraseña (el administrador, su correo): la misma
 * cuenta de Supabase que en la PC y el móvil. Las cuentas las crea el administrador, no se crean aquí. La contraseña no se guarda en
 * ningún archivo. Si entra, main.ts se entera por onAuthStateChange y monta la app (o pide el código de 6 dígitos, si falta). */
export function loginScreen(client: SupabaseClient): HTMLElement {
  const term = new Console("sesión sin abrir", "acceso");

  async function run() {
    term.line("consola de acceso, versión web", "dim");
    term.line("servidor ........ listo", "dim");
    term.line(`dispositivo ..... ${DEVICE}`, "dim");
    term.line("sesión .......... sin abrir", "dim");
    term.line("");
    term.line("Entra con tu usuario y contraseña (el administrador, con su correo).", "", true);

    let email = "";
    for (;;) {
      email = (await term.ask("usuario", "text", { initial: email })) ?? email;
      const password = await term.ask("contraseña", "password", { escape: true });
      if (password === null) continue; // Esc: otra vez el correo
      term.line("verificando…", "dim");
      try {
        const { error } = await client.auth.signInWithPassword({ email: loginEmail(email), password });
        if (!error) {
          term.line("acceso concedido", "ok");
          term.granted();
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

/** El código de 6 dígitos: una cuenta recién creada por el administrador lo canjea una sola vez; después entra solo con su contraseña.
 * `done` se llama cuando el servidor lo aceptó; `cancel`, si la persona prefiere salir. */
export function verifyScreen(client: SupabaseClient, done: () => void, cancel: () => void): HTMLElement {
  const term = new Console("cuenta sin verificar", "verificar");
  async function run() {
    term.line("tu cuenta es nueva: falta confirmar que eres tú.", "dim");
    term.line("escribe el código de 6 dígitos que te dio el administrador.", "", true);
    term.line("");
    for (;;) {
      const code = await term.ask("código", "text", { escape: true, empty: "escribe el código de 6 dígitos", hint: "enter envía, esc sale" });
      if (code === null) {
        cancel();
        return;
      }
      if (!/^\d{6}$/.test(code)) {
        term.line("el código tiene 6 dígitos", "err");
        continue;
      }
      term.line("verificando…", "dim");
      try {
        await claimAccount(client, code);
        term.line("cuenta verificada", "ok");
        term.granted();
        done();
        return;
      } catch (err) {
        term.line(err instanceof Error ? err.message : "no se pudo comprobar el código", "err");
        term.line("");
      }
    }
  }
  void run();
  return term.root;
}

/** Lo que se ve si falta la configuración del servidor: la misma consola, con el error. */
export function missingConfigScreen(missing: string[]): HTMLElement {
  const term = new Console("sin configurar", "servidor");
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
