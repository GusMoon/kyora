import { h } from "../ui/dom";
import { icon } from "../ui/icons";
import { explainError } from "../supabase";
import { normalizeUrl } from "../data/commands";
import { searchItems, type VaultItem } from "../data/vault";
import { generatePassword, strength } from "../vault/crypto";
import { CLIPBOARD_MS, copySecret, type VaultSession } from "../vault/session";
import type { Ctx, Section } from "./context";

export const MIN_MASTER = 12; // largo mínimo de la contraseña maestra

/** Lo que dice la tesela y el enunciado de la sección según el estado de la bóveda. */
export function vaultStatement(vault: Pick<VaultSession, "state" | "items" | "error" | "broken">): string {
  switch (vault.state) {
    case "loading":
      return "Comprobando tu bóveda…";
    case "error":
      return vault.error || "No se pudo leer la bóveda.";
    case "none":
      return "Aún no tienes bóveda. Crea una contraseña maestra para empezar.";
    case "locked":
      return "La bóveda está bloqueada. Escribe tu contraseña maestra.";
    default: {
      const n = vault.items.length;
      const base = n === 0 ? "Bóveda abierta y vacía." : `Bóveda abierta: ${n === 1 ? "1 entrada" : `${n} entradas`}.`;
      return vault.broken ? `${base} ${vault.broken} no se pudo${vault.broken === 1 ? "" : "ieron"} descifrar.` : base;
    }
  }
}

const STRENGTH_TEXT = ["muy débil", "débil", "aceptable", "buena", "fuerte"];

/** Una barrita de cinco tramos con la fuerza de lo que se escribe. */
function meter(): { el: HTMLElement; update: (password: string) => void } {
  const text = h("span", { class: "label" });
  const el = h("div", { class: "strength", "aria-live": "polite" }, h("span", { class: "strength-bar", "aria-hidden": "true" }, [0, 1, 2, 3, 4].map(() => h("span", { class: "strength-seg" }))), text);
  return {
    el,
    update(password) {
      const s = password ? strength(password) : -1;
      el.dataset.level = String(s);
      [...el.querySelectorAll<HTMLElement>(".strength-seg")].forEach((seg, i) => seg.classList.toggle("is-on", i <= s));
      text.textContent = password ? `Contraseña ${STRENGTH_TEXT[s]}` : "";
    },
  };
}

export const vaultSection: Section = (ctx: Ctx) => {
  const { vault, shell, store } = ctx;
  const cleanups: (() => void)[] = [];
  const root = h("div", { class: "vault" });
  const notice = h("p", { class: "notice", role: "status" });
  const saved = h("p", { class: "cfg-saved", role: "status" });
  let expanded: string | null = null;
  let editing: string | "new" | null = null;
  let search = "";
  let busy = false;
  const revealed = new Set<string>();

  const say = (text: string) => {
    saved.textContent = text;
  };

  // ----- crear la bóveda
  function createView(): HTMLElement {
    const pw = h("input", { type: "password", autocomplete: "new-password", "aria-label": "Contraseña maestra", placeholder: `Contraseña maestra (mínimo ${MIN_MASTER})` });
    const again = h("input", { type: "password", autocomplete: "new-password", "aria-label": "Repite la contraseña maestra", placeholder: "Repítela" });
    const ack = h("input", { type: "checkbox", id: "vault-ack" });
    const m = meter();
    const error = h("p", { class: "form-error", role: "alert" });
    const submit = h("button", { class: "btn-solid", type: "submit" }, icon("lock", "icon"), "Crear bóveda");
    pw.addEventListener("input", () => m.update(pw.value));
    const form = h(
      "form",
      { class: "vault-card", autocomplete: "off" },
      h("h3", { class: "label" }, "Crear tu bóveda"),
      h("p", { class: "cfg-help" }, "Tus contraseñas se cifran en este navegador con tu contraseña maestra antes de subirse. Supabase solo guarda texto cifrado: nadie, ni siquiera tú sin la maestra, puede leerlas."),
      pw,
      m.el,
      again,
      h("label", { class: "check", for: "vault-ack" }, ack, " Entiendo que si olvido la contraseña maestra no hay forma de recuperar mis datos."),
      error,
      submit,
    );
    form.addEventListener("submit", (e) => {
      e.preventDefault();
      if (pw.value.length < MIN_MASTER) return void (error.textContent = `Usa al menos ${MIN_MASTER} caracteres.`);
      if (pw.value !== again.value) return void (error.textContent = "Las dos contraseñas no coinciden.");
      if (!ack.checked) return void (error.textContent = "Marca que entiendes que no hay recuperación.");
      error.textContent = "";
      submit.disabled = true;
      submit.textContent = "Creando…";
      void (async () => {
        try {
          await vault.create(pw.value);
        } catch (err) {
          const code = (err as { code?: string })?.code;
          error.textContent = code === "23505" ? "Esta cuenta ya tiene una bóveda: desbloquéala con su contraseña maestra." : explainError(err);
          await vault.refresh();
        } finally {
          submit.disabled = false;
          submit.replaceChildren(icon("lock", "icon"), "Crear bóveda");
        }
      })();
    });
    return form;
  }

  // ----- desbloquear
  function unlockView(): HTMLElement {
    const pw = h("input", { type: "password", autocomplete: "current-password", "aria-label": "Contraseña maestra", placeholder: "Contraseña maestra" });
    const error = h("p", { class: "form-error", role: "alert" });
    const submit = h("button", { class: "btn-solid", type: "submit" }, icon("key", "icon"), "Desbloquear");
    const form = h("form", { class: "vault-card" }, h("h3", { class: "label" }, "Bóveda bloqueada"), pw, error, submit);
    form.addEventListener("submit", (e) => {
      e.preventDefault();
      if (!pw.value || busy) return;
      busy = true;
      error.textContent = "";
      submit.disabled = true;
      submit.textContent = "Desbloqueando…"; // derivar la clave tarda un instante a propósito
      void (async () => {
        try {
          const ok = await vault.unlock(pw.value);
          if (!ok) {
            error.textContent = "La contraseña maestra no es correcta.";
            pw.select();
          }
        } catch (err) {
          error.textContent = explainError(err);
        } finally {
          busy = false;
          submit.disabled = false;
          submit.replaceChildren(icon("key", "icon"), "Desbloquear");
        }
      })();
    });
    queueMicrotask(() => pw.focus());
    return form;
  }

  // ----- formulario de una entrada
  function itemForm(existing: VaultItem | null): HTMLElement {
    const service = h("input", { type: "text", maxlength: 120, placeholder: "Servicio o aplicación (ej. Netflix)", "aria-label": "Servicio o aplicación", autocomplete: "off", value: existing?.service ?? "" });
    service.value = existing?.service ?? "";
    const email = h("input", { type: "text", inputmode: "email", maxlength: 200, placeholder: "Correo", "aria-label": "Correo", autocomplete: "off", spellcheck: "false", value: existing?.email ?? "" });
    email.value = existing?.email ?? "";
    const user = h("input", { type: "text", maxlength: 120, placeholder: "Usuario (si es distinto del correo)", "aria-label": "Usuario", autocomplete: "off", spellcheck: "false", value: existing?.username ?? "" });
    user.value = existing?.username ?? "";
    const pass = h("input", { type: "password", maxlength: 500, placeholder: "Contraseña", "aria-label": "Contraseña", autocomplete: "new-password", spellcheck: "false", value: existing?.password ?? "" });
    pass.value = existing?.password ?? "";
    const show = h("button", { class: "btn-step", type: "button", "aria-label": "Mostrar la contraseña", "aria-pressed": "false" }, icon("eye", "icon"));
    show.addEventListener("click", () => {
      const on = pass.type === "password";
      pass.type = on ? "text" : "password";
      show.setAttribute("aria-pressed", String(on));
      show.setAttribute("aria-label", on ? "Ocultar la contraseña" : "Mostrar la contraseña");
      show.replaceChildren(icon(on ? "eyeOff" : "eye", "icon"));
    });
    const length = h("select", { "aria-label": "Largo de la contraseña generada" }, [12, 16, 20, 24, 32].map((n) => h("option", { value: n, selected: n === 20 }, `${n} caracteres`)));
    length.value = "20";
    const symbols = h("input", { type: "checkbox", id: "vault-symbols", checked: true });
    const m = meter();
    const gen = h("button", { class: "btn-edge", type: "button", onClick: () => {
      pass.value = generatePassword({ length: Number(length.value), symbols: symbols.checked });
      m.update(pass.value);
      pass.type = "text";
      show.setAttribute("aria-pressed", "true");
      show.replaceChildren(icon("eyeOff", "icon"));
    } }, "Generar");
    pass.addEventListener("input", () => m.update(pass.value));
    m.update(pass.value);
    const url = h("input", { type: "text", inputmode: "url", maxlength: 2048, placeholder: "Dirección web (opcional)", "aria-label": "Dirección web", autocomplete: "off", spellcheck: "false", value: existing?.url ?? "" });
    url.value = existing?.url ?? "";
    const notes = h("textarea", { rows: 3, placeholder: "Notas (opcional; también van cifradas)", "aria-label": "Notas" });
    notes.value = existing?.notes ?? "";
    const error = h("p", { class: "form-error", role: "alert" });
    const submit = h("button", { class: "btn-solid", type: "submit" }, existing ? "Guardar" : "Añadir a la bóveda");
    const form = h(
      "form",
      { class: "vault-card vault-form", autocomplete: "off" },
      h("h3", { class: "label" }, existing ? `Editar ${existing.service}` : "Nueva entrada"),
      service,
      email,
      user,
      h("div", { class: "vault-pass" }, pass, show),
      m.el,
      h("div", { class: "vault-gen" }, gen, length, h("label", { class: "check", for: "vault-symbols" }, symbols, " con símbolos")),
      url,
      notes,
      error,
      h("div", { class: "cal-form-actions" }, submit, h("button", { class: "btn-quiet", type: "button", onClick: () => { editing = null; render(); } }, "Cancelar")),
    );
    form.addEventListener("submit", (e) => {
      e.preventDefault();
      const name = service.value.trim();
      if (!name) return void (error.textContent = "Escribe el nombre del servicio o de la aplicación.");
      if (!email.value.trim() && !user.value.trim() && !pass.value) return void (error.textContent = "Escribe al menos el correo, el usuario o la contraseña.");
      if (url.value.trim() && !normalizeUrl(url.value)) return void (error.textContent = "La dirección web no es válida (debe ser http o https).");
      error.textContent = "";
      submit.disabled = true;
      const data = { service: name, email: email.value, username: user.value, password: pass.value, url: url.value.trim() ? (normalizeUrl(url.value) ?? "") : "", notes: notes.value };
      void (async () => {
        try {
          const item = existing ? await vault.update(existing.id, data) : await vault.add(data);
          expanded = item.id;
          editing = null;
          say(`${item.service}: guardado y cifrado.`);
          render(); // la sesión ya avisó antes de que `editing` cambiara: se repinta con el estado nuevo
        } catch (err) {
          error.textContent = `No se guardó. ${explainError(err)}`;
          submit.disabled = false;
        }
      })();
    });
    queueMicrotask(() => service.focus());
    return form;
  }

  // ----- la lista
  async function copy(text: string, what: string, secret: boolean) {
    const plain = async () => {
      try {
        await navigator.clipboard.writeText(text);
        return true;
      } catch {
        return false;
      }
    };
    const ok = secret ? await copySecret(text) : await plain();
    say(ok ? (secret ? `${what} copiada. Se borra del portapapeles en ${CLIPBOARD_MS / 1000} s.` : `${what} copiado.`) : "No se pudo copiar: el navegador no dio permiso.");
  }

  function entry(item: VaultItem): HTMLElement {
    const open = expanded === item.id;
    const shown = revealed.has(item.id);
    const link = item.url ? normalizeUrl(item.url) : null;
    const detail = open
      ? h(
          "div",
          { class: "vault-detail" },
          item.email ? h("p", { class: "vault-line" }, h("span", { class: "label" }, "Correo"), h("span", { class: "readout" }, item.email), h("button", { class: "btn-quiet", type: "button", onClick: () => void copy(item.email, "Correo", false) }, "Copiar")) : null,
          item.username ? h("p", { class: "vault-line" }, h("span", { class: "label" }, "Usuario"), h("span", { class: "readout" }, item.username), h("button", { class: "btn-quiet", type: "button", onClick: () => void copy(item.username, "Usuario", false) }, "Copiar")) : null,
          item.password
            ? h("p", { class: "vault-line" },
                h("span", { class: "label" }, "Contraseña"),
                h("span", { class: "readout vault-secret", "data-shown": String(shown) }, shown ? item.password : "•".repeat(Math.min(item.password.length, 16))),
                h("span", { class: "vault-line-actions" },
                  h("button", { class: "btn-quiet", type: "button", "aria-pressed": String(shown), onClick: () => { if (shown) revealed.delete(item.id); else revealed.add(item.id); render(); } }, shown ? "Ocultar" : "Mostrar"),
                  h("button", { class: "btn-quiet", type: "button", onClick: () => void copy(item.password, "Contraseña", true) }, "Copiar"),
                ),
              )
            : null,
          link ? h("p", { class: "vault-line" }, h("span", { class: "label" }, "Web"), h("a", { class: "readout", href: link, target: "_blank", rel: "noopener noreferrer" }, item.url)) : null,
          item.notes ? h("p", { class: "vault-notes" }, item.notes) : null,
          h("div", { class: "cal-form-actions" },
            h("button", { class: "btn-edge", type: "button", onClick: () => { editing = item.id; render(); } }, icon("pencil", "icon"), "Editar"),
            h("button", { class: "btn-edge is-danger", type: "button", onClick: () => {
              if (!confirm(`¿Borrar «${item.service}» de la bóveda?`)) return;
              void vault.remove(item.id).then(() => say(`${item.service}: borrado.`), (err) => (notice.textContent = `No se borró. ${explainError(err)}`));
            } }, icon("trash", "icon"), "Borrar"),
          ),
        )
      : null;
    return h(
      "li",
      { class: "vault-item", "data-open": String(open) },
      h("button", { class: "vault-head", type: "button", "aria-expanded": String(open), onClick: () => { expanded = open ? null : item.id; if (open) revealed.delete(item.id); render(); } },
        h("strong", { class: "vault-service" }, item.service),
        h("span", { class: "vault-who readout" }, item.email || item.username || "—"),
      ),
      detail,
    );
  }

  function unlockedView(): HTMLElement {
    const list = searchItems(vault.items, search);
    const q = h("input", { type: "text", placeholder: "Buscar por servicio, correo o usuario", "aria-label": "Buscar en la bóveda", value: search, autocomplete: "off" });
    q.value = search;
    q.addEventListener("input", () => {
      search = q.value;
      render();
      const again = root.querySelector<HTMLInputElement>('input[aria-label="Buscar en la bóveda"]');
      again?.focus();
      again?.setSelectionRange(search.length, search.length);
    });
    return h(
      "div",
      { class: "vault-open" },
      h("div", { class: "vault-bar" },
        q,
        h("button", { class: "btn-solid", type: "button", onClick: () => { editing = "new"; render(); } }, icon("plus", "icon"), "Nueva"),
        h("button", { class: "btn-edge", type: "button", onClick: () => vault.lock() }, icon("lock", "icon"), "Bloquear"),
      ),
      editing ? itemForm(editing === "new" ? null : (vault.items.find((i) => i.id === editing) ?? null)) : null,
      list.length ? h("ul", { class: "vault-list" }, list.map(entry)) : h("p", { class: "cfg-help" }, vault.items.length ? "Nada coincide con la búsqueda." : "Aún no hay entradas. Pulsa «Nueva» para guardar la primera."),
      h("p", { class: "cfg-note" }, "Se bloquea sola tras 5 minutos sin usar Merida. La clave solo vive en la memoria de esta pestaña."),
    );
  }

  function render() {
    shell.setStatement(vaultStatement(vault));
    const focusLabel = root.contains(document.activeElement) ? (document.activeElement as HTMLElement).getAttribute("aria-label") : null;
    switch (vault.state) {
      case "loading":
        root.replaceChildren(h("p", { class: "cfg-help" }, "Comprobando…"));
        break;
      case "error":
        root.replaceChildren(h("p", { class: "form-error", role: "alert" }, vault.error || "No se pudo leer la bóveda."), h("button", { class: "btn-edge", type: "button", onClick: () => void vault.refresh() }, "Reintentar"));
        break;
      case "none":
        root.replaceChildren(createView());
        break;
      case "locked":
        revealed.clear();
        expanded = null;
        editing = null;
        root.replaceChildren(unlockView());
        break;
      default:
        root.replaceChildren(unlockedView());
        if (focusLabel === "Buscar en la bóveda") root.querySelector<HTMLInputElement>('input[aria-label="Buscar en la bóveda"]')?.focus();
    }
  }

  shell.body.append(notice, root, saved);
  const handleIntent = () => {
    if (vault.state !== "unlocked") return; // se atiende al desbloquear (la orden caduca a los 3 s; si no, el usuario la repite)
    const secret = store.take("open-secret");
    if (secret?.arg) {
      expanded = secret.arg;
      editing = null;
      render();
      return;
    }
    if (store.take("new-secret")) {
      editing = "new";
      render();
    }
  };
  render();
  void vault.refresh().then(handleIntent);
  cleanups.push(vault.on(() => { render(); handleIntent(); }), store.onIntent(handleIntent));
  cleanups.push(() => revealed.clear());
  return () => {
    for (const fn of cleanups) fn();
  };
};
