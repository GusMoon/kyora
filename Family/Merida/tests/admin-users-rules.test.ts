// @vitest-environment node
import { describe, expect, it } from "vitest";
import { createHash } from "node:crypto";
import { emailFor, hashCode, newCode, normalizeUsername, parseRole, validPassword } from "../../../Server/supabase/functions/admin-users/rules";

/** Las reglas de la función admin-users (Server/supabase/functions/admin-users): lo puro, sin Deno ni red. */

describe("nombre de usuario", () => {
  it("acepta minúsculas, números, punto, guion y guion bajo, y pasa a minúsculas", () => {
    expect(normalizeUsername("  Maria_01 ")).toBe("maria_01");
    expect(normalizeUsername("a.b-c")).toBe("a.b-c");
  });
  it("rechaza lo corto, lo largo, los espacios, los acentos y los puntos seguidos", () => {
    for (const bad of ["ab", "a".repeat(25), "mi nombre", "maría", ".ana", "ana.", "an..a", "", null, undefined]) {
      expect(normalizeUsername(bad)).toBeNull();
    }
  });
  it("el correo inventado se arma con el dominio local", () => {
    expect(emailFor("ana")).toBe("ana@kyra.local");
  });
});

describe("contraseña y rol", () => {
  it("pide al menos 6 caracteres", () => {
    expect(validPassword("12345")).toBe(false);
    expect(validPassword("123456")).toBe(true);
    expect(validPassword(undefined)).toBe(false);
  });
  it("solo admin o intern", () => {
    expect(parseRole("admin")).toBe("admin");
    expect(parseRole("intern")).toBe("intern");
    expect(parseRole("root")).toBeNull();
  });
});

describe("código de 6 dígitos", () => {
  it("siempre tiene 6 dígitos, con ceros a la izquierda", () => {
    expect(newCode(() => 42)).toBe("000042");
    expect(newCode(() => 999_999)).toBe("999999");
    for (let i = 0; i < 200; i++) expect(newCode()).toMatch(/^\d{6}$/);
  });
  it("el hash es sha256(código + id): lo mismo que calcula claim_account en SQL", async () => {
    const id = "3f2c1b9e-0000-4000-8000-000000000001";
    const expected = createHash("sha256").update("123456" + id, "utf8").digest("hex");
    expect(await hashCode("123456", id)).toBe(expected);
    expect(await hashCode("123457", id)).not.toBe(expected);
  });
});
