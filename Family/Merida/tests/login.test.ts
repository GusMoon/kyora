import { afterEach, describe, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import { loginScreen, missingConfigScreen } from "../src/ui/login";
import { fxConfig } from "../src/ui/fx";

// estas pruebas leen el texto de las líneas: sin el efecto hacking, que lo escribe poco a poco
fxConfig.hack = false;
fxConfig.holo = false;

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

function setup(signIn = vi.fn()) {
  const client = { auth: { signInWithPassword: signIn } } as unknown as SupabaseClient;
  const screen = loginScreen(client);
  document.body.append(screen);
  return { screen, signIn };
}

const input = (screen: HTMLElement) => screen.querySelector<HTMLInputElement>(".prompt-row input");
const lines = (screen: HTMLElement) => [...screen.querySelectorAll(".console-line")].map((l) => l.textContent);

/** Escribe en el renglón de ahora y pulsa Enter. */
async function type(screen: HTMLElement, value: string) {
  const el = input(screen)!;
  el.value = value;
  el.form!.dispatchEvent(new Event("submit", { cancelable: true, bubbles: true }));
  await flush();
}

afterEach(() => {
  document.body.replaceChildren();
});

describe("consola de acceso", () => {
  it("al abrir solo hay una consola que pide primero el correo", async () => {
    const { screen } = setup();
    await flush();
    expect(document.body.children).toHaveLength(1);
    expect(screen.querySelectorAll(".console")).toHaveLength(1);
    const el = input(screen)!;
    expect(el.type).toBe("email");
    expect(screen.querySelector(".prompt-row label")?.textContent).toBe("correo>");
    expect(screen.querySelector('input[type="password"]')).toBeNull();
  });

  it("después del correo pide la contraseña, sin enseñarla, y entra con las dos", async () => {
    const { screen, signIn } = setup(vi.fn().mockResolvedValue({ error: null }));
    await flush();
    await type(screen, "  yo@correo.com  ");
    expect(input(screen)!.type).toBe("password");
    expect(screen.querySelector(".prompt-row label")?.textContent).toBe("contraseña>");
    expect(lines(screen)).toContain("correo> yo@correo.com");

    await type(screen, "secreta123");
    expect(signIn).toHaveBeenCalledWith({ email: "yo@correo.com", password: "secreta123" });
    expect(lines(screen)).toContain("contraseña> ********");
    expect(screen.textContent).not.toContain("secreta123");
    expect(lines(screen)).toContain("acceso concedido");
    expect(input(screen)).toBeNull();
  });

  it("si no coinciden, lo dice y vuelve a pedir el correo, ya escrito", async () => {
    const { screen, signIn } = setup(vi.fn().mockResolvedValue({ error: { message: "Invalid login credentials" } }));
    await flush();
    await type(screen, "yo@correo.com");
    await type(screen, "mala");
    expect(signIn).toHaveBeenCalledTimes(1);
    expect(screen.querySelector(".console-line.is-err")?.textContent).toMatch(/correo o la contraseña/);
    const again = input(screen)!;
    expect(again.type).toBe("email");
    expect(again.value).toBe("yo@correo.com");
  });

  it("un renglón vacío no se envía y avisa", async () => {
    const { screen, signIn } = setup();
    await flush();
    await type(screen, "   ");
    expect(input(screen)!.type).toBe("email");
    expect(screen.querySelector(".console-line.is-err")?.textContent).toMatch(/correo/);
    expect(signIn).not.toHaveBeenCalled();
  });

  it("Esc en la contraseña vuelve al correo sin llamar al servidor", async () => {
    const { screen, signIn } = setup();
    await flush();
    await type(screen, "yo@correo.com");
    input(screen)!.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    await flush();
    expect(signIn).not.toHaveBeenCalled();
    expect(input(screen)!.type).toBe("email");
    expect(input(screen)!.value).toBe("yo@correo.com");
  });

  it("si la red falla, lo explica y deja volver a intentar", async () => {
    const { screen } = setup(vi.fn().mockRejectedValue(new Error("Failed to fetch")));
    await flush();
    await type(screen, "yo@correo.com");
    await type(screen, "algo");
    expect(screen.querySelector(".console-line.is-err")?.textContent).toMatch(/conexión/);
    expect(input(screen)).not.toBeNull();
  });

  it("sin configuración muestra la misma consola con el error", () => {
    const screen = missingConfigScreen(["SUPABASE_URL", "SUPABASE_ANON_KEY"]);
    expect(screen.querySelector(".console")).not.toBeNull();
    expect(screen.textContent).toContain("SUPABASE_URL ni SUPABASE_ANON_KEY");
    expect(screen.querySelector("input")).toBeNull();
  });
});
