import { afterEach, describe, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  claimAccount, createAccount, explainClaim, lastSeenText, loginEmail, myVerified, passwordProblem, regenerateCode, removeAccount, roleLabel,
  setRole, touchPresence, usernameProblem, type PresenceEntry,
} from "../src/data/users";
import { usersPanel } from "../src/sections/usersPanel";
import { verifyScreen } from "../src/ui/login";
import { fxConfig } from "../src/ui/fx";
import type { Ctx } from "../src/sections/context";

fxConfig.hack = false;
fxConfig.holo = false;

const flush = () => new Promise((r) => setTimeout(r, 0));
const NOW = Date.parse("2026-11-17T12:00:00Z");

function entry(name: string, over: Partial<PresenceEntry> = {}): PresenceEntry {
  return { id: `id-${name}`, username: name, role: "intern", verified: true, last_seen: null, online: false, code_pending: false, me: false, ...over };
}

afterEach(() => {
  document.body.replaceChildren();
  vi.restoreAllMocks();
});

describe("cuentas: nombres, contraseñas y correo inventado", () => {
  it("un nombre se vuelve <nombre>@kyra.local y un correo se deja igual", () => {
    expect(loginEmail("  Ana ")).toBe("ana@kyra.local");
    expect(loginEmail(" yo@correo.com ")).toBe("yo@correo.com");
  });
  it("valida el nombre y la contraseña como el servidor", () => {
    expect(usernameProblem("Maria_01")).toBeNull();
    for (const bad of ["ab", "a".repeat(25), "mi nombre", "maría", ".ana", "an..a"]) expect(usernameProblem(bad), bad).not.toBeNull();
    expect(passwordProblem("12345")).not.toBeNull();
    expect(passwordProblem("123456")).toBeNull();
  });
  it("los roles se dicen en español", () => {
    expect(roleLabel("admin")).toBe("administrador");
    expect(roleLabel("intern")).toBe("visitante");
  });
});

describe("en línea o hace cuánto", () => {
  const ago = (ms: number) => new Date(NOW - ms).toISOString();
  it("dice en línea, hace un momento, minutos, horas, días y nunca", () => {
    expect(lastSeenText({ online: true, last_seen: null }, NOW)).toBe("en línea");
    expect(lastSeenText({ online: false, last_seen: ago(20_000) }, NOW)).toBe("hace un momento");
    expect(lastSeenText({ online: false, last_seen: ago(5 * 60_000) }, NOW)).toBe("hace 5 min");
    expect(lastSeenText({ online: false, last_seen: ago(3 * 3600_000) }, NOW)).toBe("hace 3 h");
    expect(lastSeenText({ online: false, last_seen: ago(2 * 86400_000) }, NOW)).toBe("hace 2 d");
    expect(lastSeenText({ online: false, last_seen: null }, NOW)).toBe("nunca entró");
  });
});

describe("el código de 6 dígitos", () => {
  it("explica en español los errores del servidor", () => {
    expect(explainClaim(new Error("code_invalid"))).toMatch(/no es correcto/);
    expect(explainClaim({ message: "code_expired" })).toMatch(/caducó/);
    expect(explainClaim({ message: "code_locked" })).toMatch(/Demasiados intentos/);
    expect(explainClaim({ message: "otra cosa" })).toMatch(/No se pudo comprobar/);
  });

  it("claimAccount llama a claim_account con el código y lanza el motivo", async () => {
    const rpc = vi.fn().mockResolvedValueOnce({ data: true, error: null }).mockResolvedValueOnce({ data: null, error: { message: "code_invalid" } });
    const client = { rpc } as unknown as SupabaseClient;
    await claimAccount(client, " 123456 ");
    expect(rpc).toHaveBeenCalledWith("claim_account", { p_code: "123456" });
    await expect(claimAccount(client, "000000")).rejects.toThrow(/no es correcto/);
  });

  it("myVerified: false solo si el perfil dice que no; sin respuesta no se bloquea", async () => {
    const make = (reply: unknown) => ({ rpc: vi.fn().mockResolvedValue(reply) }) as unknown as SupabaseClient;
    expect(await myVerified(make({ data: { verified: false }, error: null }))).toBe(false);
    expect(await myVerified(make({ data: { verified: true }, error: null }))).toBe(true);
    expect(await myVerified(make({ data: { username: "viejo" }, error: null }))).toBe(true); // esquema sin la columna
    expect(await myVerified(make({ data: null, error: { message: "offline" } }))).toBe(true);
  });

  it("la pantalla del código solo acepta 6 dígitos, dice el error y al acertar continúa", async () => {
    const rpc = vi.fn().mockResolvedValueOnce({ data: null, error: { message: "code_invalid" } }).mockResolvedValueOnce({ data: true, error: null });
    const done = vi.fn();
    const cancel = vi.fn();
    const screen = verifyScreen({ rpc } as unknown as SupabaseClient, done, cancel);
    document.body.append(screen);
    await flush();
    const type = async (value: string) => {
      const el = screen.querySelector<HTMLInputElement>(".prompt-row input")!;
      el.value = value;
      el.form!.dispatchEvent(new Event("submit", { cancelable: true, bubbles: true }));
      await flush();
    };
    const errors = () => [...screen.querySelectorAll(".console-line.is-err")].map((l) => l.textContent);
    await type("12");
    expect(rpc).not.toHaveBeenCalled();
    expect(errors()).toContain("el código tiene 6 dígitos");
    await type("111111");
    expect(errors().join(" ")).toMatch(/no es correcto/);
    expect(done).not.toHaveBeenCalled();
    await type("123456");
    expect(rpc).toHaveBeenLastCalledWith("claim_account", { p_code: "123456" });
    expect(done).toHaveBeenCalledOnce();
    expect(cancel).not.toHaveBeenCalled();
  });

  it("Esc en la pantalla del código sale", async () => {
    const cancel = vi.fn();
    const screen = verifyScreen({ rpc: vi.fn() } as unknown as SupabaseClient, vi.fn(), cancel);
    document.body.append(screen);
    await flush();
    screen.querySelector<HTMLInputElement>(".prompt-row input")!.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    await flush();
    expect(cancel).toHaveBeenCalledOnce();
  });
});

describe("presencia y administración", () => {
  it("touchPresence llama a touch_presence y un fallo no lanza nada", async () => {
    const ok = { rpc: vi.fn().mockResolvedValue({ data: null, error: null }) } as unknown as SupabaseClient;
    await touchPresence(ok);
    expect(ok.rpc).toHaveBeenCalledWith("touch_presence");
    const broken = { rpc: vi.fn().mockRejectedValue(new Error("Failed to fetch")) } as unknown as SupabaseClient;
    await expect(touchPresence(broken)).resolves.toBeUndefined();
  });

  it("las acciones llaman a la función admin-users con lo que toca", async () => {
    const invoke = vi.fn(async (_: string, opts: { body: { action: string } }) => ({ data: opts.body.action === "create" ? { username: "marta", code: "482913" } : opts.body.action === "regenerate_code" ? { code: "111222" } : { ok: true }, error: null }));
    const client = { functions: { invoke } } as unknown as SupabaseClient;
    expect(await createAccount(client, { username: " Marta ", password: "secreta1", role: "intern" })).toEqual({ username: "marta", code: "482913" });
    expect(invoke).toHaveBeenLastCalledWith("admin-users", { body: { action: "create", username: "Marta", password: "secreta1", role: "intern" } });
    await setRole(client, "u1", "admin");
    expect(invoke).toHaveBeenLastCalledWith("admin-users", { body: { action: "set_role", user_id: "u1", role: "admin" } });
    expect(await regenerateCode(client, "u1", "marta")).toEqual({ username: "marta", code: "111222" });
    await removeAccount(client, "u1");
    expect(invoke).toHaveBeenLastCalledWith("admin-users", { body: { action: "remove", user_id: "u1" } });
  });

  it("un error de la función llega en español", async () => {
    const reply = (error: string, status: number) => ({ data: null, error: { context: new Response(JSON.stringify({ error }), { status }) } });
    const client = (r: unknown) => ({ functions: { invoke: vi.fn().mockResolvedValue(r) } }) as unknown as SupabaseClient;
    await expect(createAccount(client(reply("username_taken", 409)), { username: "ana", password: "secreta1", role: "intern" })).rejects.toThrow("Ese nombre de usuario ya existe.");
    await expect(removeAccount(client(reply("not_admin", 403)), "u")).rejects.toThrow("Solo el administrador");
    const missing = { data: null, error: { context: new Response("", { status: 404 }) } };
    await expect(removeAccount(client(missing), "u")).rejects.toThrow(/Falta desplegar la función admin-users/);
  });
});

describe("el panel «Usuarios»", () => {
  function setup(entries: PresenceEntry[], extra: Record<string, unknown> = {}) {
    const list = [...entries];
    const rpc = vi.fn(async (name: string) => (name === "list_presence" ? { data: list, error: null } : { data: null, error: null }));
    const invoke = vi.fn(async (_: string, opts: { body: { action: string; username?: string } }) => {
      if (opts.body.action === "create") {
        list.push(entry(opts.body.username!.toLowerCase(), { verified: false, code_pending: true }));
        return { data: { username: opts.body.username!.toLowerCase(), code: "482913" }, error: null };
      }
      if (opts.body.action === "remove") list.splice(list.findIndex((e) => e.username === "luis"), 1);
      return { data: opts.body.action === "regenerate_code" ? { code: "777888" } : { ok: true }, error: null };
    });
    const ctx = { client: { rpc, functions: { invoke }, ...extra } as unknown as SupabaseClient } as Ctx;
    const panel = usersPanel(ctx, { every: 1000, now: () => NOW });
    document.body.append(panel.el);
    return { panel, rpc, invoke, list };
  }
  const q = (sel: string) => document.body.querySelector<HTMLElement>(sel);
  const rows = () => [...document.body.querySelectorAll<HTMLElement>(".usr-row")];

  it("enseña quién está en línea, el rol, lo pendiente y hace cuánto se vio a los demás", async () => {
    const { panel } = setup([
      entry("gustavo", { role: "admin", online: true, me: true }),
      entry("ana", { online: true }),
      entry("luis", { last_seen: new Date(NOW - 2 * 3600_000).toISOString() }),
      entry("nueva", { verified: false, code_pending: true }),
    ]);
    await flush();
    expect(q('[data-usr="count"]')!.textContent).toBe("2 en línea de 4");
    expect(rows().map((r) => r.dataset.user)).toEqual(["gustavo", "ana", "luis", "nueva"]);
    expect(rows()[0].classList.contains("is-online")).toBe(true);
    expect(rows()[0].textContent).toContain("administrador · en línea");
    expect(rows()[2].textContent).toContain("visitante · hace 2 h");
    expect(rows()[3].textContent).toContain("código pendiente");
    expect(rows()[0].querySelector("button")).toBeNull(); // tu propia cuenta no tiene acciones
    expect(rows()[1].querySelectorAll("button")).toHaveLength(3);
    panel.off();
  });

  it("crear una cuenta valida antes de llamar y luego enseña el código una sola vez", async () => {
    const { panel, invoke } = setup([entry("gustavo", { role: "admin", me: true, online: true })]);
    await flush();
    const name = q('[data-usr="name"]') as HTMLInputElement;
    const password = q('[data-usr="password"]') as HTMLInputElement;
    const submit = () => (q("form.usr-form") as HTMLFormElement).dispatchEvent(new Event("submit", { cancelable: true, bubbles: true }));
    name.value = "ab";
    password.value = "secreta1";
    submit();
    await flush();
    expect(invoke).not.toHaveBeenCalled();
    expect(q(".usr-form .form-error")!.hidden).toBe(false);
    name.value = "Marta";
    submit();
    await flush();
    await flush();
    expect(invoke).toHaveBeenCalledWith("admin-users", { body: { action: "create", username: "Marta", password: "secreta1", role: "intern" } });
    expect(q('[data-usr="code"]')!.textContent).toBe("482913");
    expect(rows().map((r) => r.dataset.user)).toContain("marta"); // la lista se volvió a leer
    expect((q('[data-usr="name"]') as HTMLInputElement).value).toBe(""); // el formulario queda limpio
    q('[data-usr="issued"] button')!.click();
    expect(q('[data-usr="issued"]')).toBeNull(); // no se vuelve a mostrar
    panel.off();
  });

  it("pasar a admin, pedir otro código y quitar (con confirmación)", async () => {
    const { panel, invoke } = setup([entry("gustavo", { role: "admin", me: true }), entry("luis")]);
    await flush();
    const button = (user: string, kind: string) => document.body.querySelector<HTMLButtonElement>(`.usr-row[data-user="${user}"] [data-usr="${kind}"]`)!;
    button("luis", "role").click();
    await flush();
    expect(invoke).toHaveBeenLastCalledWith("admin-users", { body: { action: "set_role", user_id: "id-luis", role: "admin" } });
    button("luis", "code").click();
    await flush();
    await flush();
    expect(q('[data-usr="code"]')!.textContent).toBe("777888");
    vi.spyOn(window, "confirm").mockReturnValueOnce(false);
    button("luis", "remove").click();
    await flush();
    expect(invoke).not.toHaveBeenCalledWith("admin-users", { body: { action: "remove", user_id: "id-luis" } });
    vi.spyOn(window, "confirm").mockReturnValueOnce(true);
    button("luis", "remove").click();
    await flush();
    await flush();
    expect(invoke).toHaveBeenLastCalledWith("admin-users", { body: { action: "remove", user_id: "id-luis" } });
    expect(rows().map((r) => r.dataset.user)).toEqual(["gustavo"]);
    panel.off();
  });

  it("se vuelve a leer sola y deja de hacerlo al cerrarse", async () => {
    vi.useFakeTimers();
    try {
      const { panel, rpc } = setup([entry("gustavo", { role: "admin", me: true })]);
      await vi.advanceTimersByTimeAsync(0);
      const first = rpc.mock.calls.filter(([n]) => n === "list_presence").length;
      await vi.advanceTimersByTimeAsync(1000);
      expect(rpc.mock.calls.filter(([n]) => n === "list_presence").length).toBeGreaterThan(first);
      panel.off();
      const after = rpc.mock.calls.length;
      await vi.advanceTimersByTimeAsync(5000);
      expect(rpc.mock.calls.length).toBe(after);
    } finally {
      vi.useRealTimers();
    }
  });

  it("si no se pueden leer las cuentas, lo dice", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { message: "not_admin", code: "42501" } }));
    const panel = usersPanel({ client: { rpc } as unknown as SupabaseClient } as Ctx, { every: 100000 });
    document.body.append(panel.el);
    await flush();
    expect(document.body.querySelector('[data-usr="error"]')).not.toBeNull();
    panel.off();
  });
});
