import { h } from "../ui/dom";
import { icon } from "../ui/icons";
import {
  createAccount, lastSeenText, listPresence, passwordProblem, regenerateCode, removeAccount, roleLabel, setRole, usernameProblem,
  type IssuedCode, type PresenceEntry, type Role,
} from "../data/users";
import { explainError } from "../supabase";
import type { Ctx } from "./context";

/** El panel «Usuarios» del administrador: todas las cuentas con un punto si están en línea (o hace cuánto se vieron), su rol y si ya
 * verificaron el código. Aquí se **crea** una cuenta (nombre y contraseña, sin correo) y se le entrega su código de 6 dígitos, y se cambia
 * el rol, se pide otro código o se quita el acceso. Se vuelve a leer solo cada 30 s mientras esté abierto. */
export function usersPanel(ctx: Ctx, opts: { every?: number; now?: () => number } = {}): { el: HTMLElement; off: () => void; refresh: () => Promise<void> } {
  const { client } = ctx;
  const every = opts.every ?? 30000;
  const now = opts.now ?? Date.now;
  const el = h("section", { class: "usr", "aria-label": "Usuarios y quién está en línea" });
  let entries: PresenceEntry[] = [];
  let loaded = false;
  let busy = false;
  let error = "";
  let issued: { code: IssuedCode; created: boolean } | null = null;
  let alive = true;

  const fail = (err: unknown) => {
    error = err instanceof Error && !("code" in err) ? err.message : explainError(err);
  };

  async function refresh() {
    try {
      entries = await listPresence(client);
      error = "";
    } catch (err) {
      fail(err);
    }
    loaded = true;
    if (alive) render();
  }

  /** Corre una acción del administrador y vuelve a leer la lista. */
  async function act<T>(run: () => Promise<T>): Promise<T | null> {
    if (busy) return null;
    busy = true;
    error = "";
    render();
    try {
      const result = await run();
      busy = false;
      await refresh();
      return result;
    } catch (err) {
      fail(err);
      return null;
    } finally {
      busy = false;
      if (alive) render();
    }
  }

  const name = h("input", { type: "text", class: "field", autocomplete: "off", spellcheck: "false", placeholder: "nombre de usuario", "aria-label": "Nombre de usuario de la cuenta nueva", "data-usr": "name" });
  const password = h("input", { type: "password", class: "field", autocomplete: "new-password", placeholder: "contraseña", "aria-label": "Contraseña de la cuenta nueva", "data-usr": "password" });
  const roleSel = h("select", { class: "field", "aria-label": "Rol de la cuenta nueva", "data-usr": "role" },
    h("option", { value: "intern" }, "Visitante"),
    h("option", { value: "admin" }, "Administrador"),
  );
  const formError = h("p", { class: "form-error", role: "alert", hidden: true });

  async function submit(event: Event) {
    event.preventDefault();
    const problem = usernameProblem(name.value) ?? passwordProblem(password.value);
    formError.hidden = !problem;
    formError.textContent = problem ?? "";
    if (problem) return;
    const code = await act(() => createAccount(client, { username: name.value, password: password.value, role: roleSel.value as Role }));
    if (code) {
      issued = { code, created: true };
      name.value = "";
      password.value = "";
      render();
    }
  }
  const form = h("form", { class: "usr-form", onSubmit: submit },
    h("p", { class: "label" }, "Crear cuenta"),
    h("div", { class: "usr-fields" }, name, password, roleSel,
      h("button", { class: "btn-solid", type: "submit", "data-usr": "create" }, icon("check"), "Crear")),
    formError,
    h("p", { class: "cfg-help" }, "Las cuentas no llevan correo. Al crearla se te da un código de 6 dígitos: entrégaselo a la persona; lo escribe una sola vez al entrar (caduca a las 72 horas)."),
  );

  function codeBox(): HTMLElement | null {
    if (!issued) return null;
    const { code, created } = issued;
    return h("div", { class: "usr-code", role: "status", "data-usr": "issued" },
      h("p", { class: "label" }, created ? `Cuenta creada: ${code.username}` : `Código nuevo para ${code.username}`),
      h("p", { class: "usr-code-value readout", "data-usr": "code" }, code.code),
      h("p", { class: "cfg-help" }, "Entrégaselo a la persona. No se vuelve a mostrar: si se pierde, pide uno nuevo."),
      h("button", { class: "btn-quiet", type: "button", onClick: () => { issued = null; render(); } }, "Listo"),
    );
  }

  function row(e: PresenceEntry): HTMLElement {
    const actions = e.me
      ? [h("span", { class: "usr-me readout" }, "tú")]
      : [
          h("button", { class: "btn-quiet", type: "button", disabled: busy, "data-usr": "role", onClick: () => void act(() => setRole(client, e.id, e.role === "admin" ? "intern" : "admin")) },
            e.role === "admin" ? "Pasar a visitante" : "Pasar a admin"),
          h("button", { class: "btn-quiet", type: "button", disabled: busy, "data-usr": "code", onClick: async () => {
            const code = await act(() => regenerateCode(client, e.id, e.username));
            if (code) { issued = { code, created: false }; render(); }
          } }, "Código nuevo"),
          h("button", { class: "btn-quiet usr-remove", type: "button", disabled: busy, "data-usr": "remove", onClick: () => {
            if (window.confirm(`¿Quitar a ${e.username}? Pierde el acceso y su cuenta se borra.`)) void act(() => removeAccount(client, e.id));
          } }, "Quitar"),
        ];
    const state = [roleLabel(e.role), !e.verified ? (e.code_pending ? "código pendiente" : "sin verificar") : null, lastSeenText(e, now())].filter(Boolean).join(" · ");
    return h("li", { class: `usr-row${e.online ? " is-online" : ""}`, "data-user": e.username },
      h("span", { class: "usr-dot", role: "img", "aria-label": e.online ? "en línea" : "desconectado" }),
      h("span", { class: "usr-name" }, e.username),
      h("span", { class: "usr-state readout" }, state),
      h("span", { class: "usr-actions" }, ...actions),
    );
  }

  function render() {
    const online = entries.filter((e) => e.online).length;
    const refreshBtn = h("button", { class: "btn-quiet", type: "button", disabled: busy, "data-usr": "refresh", onClick: () => void refresh() }, icon("refresh", "icon"), "Actualizar");
    const parts: (Node | null)[] = [
      h("div", { class: "usr-head" },
        h("p", { class: "usr-count readout", "data-usr": "count" }, loaded ? `${online} en línea de ${entries.length}` : "Leyendo las cuentas…"),
        refreshBtn,
      ),
      error ? h("p", { class: "form-error", role: "alert", "data-usr": "error" }, error) : null,
      codeBox(),
      loaded && entries.length ? h("ul", { class: "usr-list" }, entries.map(row)) : null,
      form,
    ];
    el.replaceChildren(...parts.filter((n): n is Node => n !== null));
  }

  render();
  void refresh();
  const timer = window.setInterval(() => void refresh(), every);
  return {
    el,
    refresh,
    off: () => {
      alive = false;
      window.clearInterval(timer);
    },
  };
}
