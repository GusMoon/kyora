import { webcrypto } from "node:crypto";
import { beforeAll, describe, expect, it, vi } from "vitest";
import { checkVerifier, decryptText, deriveKey, encryptText, fromBase64, generatePassword, makeVerifier, randomBytes, strength, toBase64 } from "../src/vault/crypto";
import { VaultSession, copySecret } from "../src/vault/session";
import { searchItems, newVaultItem, updateVaultItem } from "../src/data/vault";
import { vaultStatement } from "../src/sections/vault";

// jsdom no trae `crypto.subtle`: se usa el de Node (es el mismo estándar Web Crypto que usa el navegador)
beforeAll(() => {
  if (!globalThis.crypto?.subtle) Object.defineProperty(globalThis, "crypto", { value: webcrypto, configurable: true });
});

const ITER = 1000; // pocas vueltas solo en las pruebas (en la app son 600 000)

describe("bóveda: cifrado", () => {
  it("cifra y descifra de ida y vuelta, con acentos y símbolos", async () => {
    const key = await deriveKey("maestra-larga-123", randomBytes(16), ITER);
    const text = JSON.stringify({ service: "Café ☕", password: "p@ss'\"\\ñ" });
    const token = await encryptText(key, text, "id-1");
    expect(token.startsWith("v1.")).toBe(true);
    expect(token).not.toContain("Café");
    expect(await decryptText(key, token, "id-1")).toBe(text);
  });

  it("el mismo texto cifrado dos veces da resultados distintos (IV aleatorio)", async () => {
    const key = await deriveKey("maestra-larga-123", randomBytes(16), ITER);
    expect(await encryptText(key, "hola", "a")).not.toBe(await encryptText(key, "hola", "a"));
  });

  it("con otra contraseña no se puede descifrar", async () => {
    const salt = randomBytes(16);
    const good = await deriveKey("maestra-larga-123", salt, ITER);
    const bad = await deriveKey("maestra-larga-124", salt, ITER);
    const token = await encryptText(good, "secreto", "a");
    await expect(decryptText(bad, token, "a")).rejects.toThrow();
  });

  it("detecta si el texto cifrado se alteró", async () => {
    const key = await deriveKey("maestra-larga-123", randomBytes(16), ITER);
    const bytes = fromBase64((await encryptText(key, "secreto", "a")).slice(3));
    bytes[bytes.length - 1] ^= 1; // un solo bit
    await expect(decryptText(key, "v1." + toBase64(bytes), "a")).rejects.toThrow();
  });

  it("una entrada copiada a la fila de otra no se descifra (el id va autenticado)", async () => {
    const key = await deriveKey("maestra-larga-123", randomBytes(16), ITER);
    const token = await encryptText(key, "secreto", "fila-1");
    await expect(decryptText(key, token, "fila-2")).rejects.toThrow();
  });

  it("rechaza formatos desconocidos o incompletos", async () => {
    const key = await deriveKey("x", randomBytes(16), ITER);
    await expect(decryptText(key, "v9.AAAA", "a")).rejects.toThrow();
    await expect(decryptText(key, "v1.AAAA", "a")).rejects.toThrow();
  });

  it("la prueba de la contraseña maestra acepta la buena y rechaza la mala", async () => {
    const salt = randomBytes(16);
    const key = await deriveKey("correcta-correcta", salt, ITER);
    const verifier = await makeVerifier(key);
    expect(await checkVerifier(key, verifier)).toBe(true);
    expect(await checkVerifier(await deriveKey("incorrecta-xxxx", salt, ITER), verifier)).toBe(false);
    expect(await checkVerifier(key, "basura")).toBe(false);
  });

  it("la clave derivada no se puede exportar (la página no puede leer sus bytes)", async () => {
    const key = await deriveKey("maestra-larga-123", randomBytes(16), ITER);
    expect(key.extractable).toBe(false);
    await expect(crypto.subtle.exportKey("raw", key)).rejects.toThrow();
  });
});

describe("bóveda: generador y fuerza", () => {
  it("genera del largo pedido y con al menos un carácter de cada tipo", () => {
    for (let i = 0; i < 50; i++) {
      const p = generatePassword({ length: 16 });
      expect(p).toHaveLength(16);
      expect(p).toMatch(/[a-z]/);
      expect(p).toMatch(/[A-Z]/);
      expect(p).toMatch(/[0-9]/);
      expect(p).toMatch(/[^A-Za-z0-9]/);
    }
  });

  it("sin símbolos no los lleva, y nunca usa caracteres que se confunden (l, o, 0, 1, I, O)", () => {
    for (let i = 0; i < 50; i++) {
      const p = generatePassword({ length: 32, symbols: false });
      expect(p).toMatch(/^[A-Za-z0-9]+$/);
      expect(p).not.toMatch(/[lo01IO]/);
    }
  });

  it("dos contraseñas generadas casi nunca coinciden", () => {
    expect(new Set(Array.from({ length: 100 }, () => generatePassword())).size).toBe(100);
  });

  it("sin ningún tipo elegido no devuelve nada, y el largo se acota", () => {
    expect(generatePassword({ lower: false, upper: false, digits: false, symbols: false })).toBe("");
    expect(generatePassword({ length: 5000 })).toHaveLength(128);
  });

  it("estima la fuerza de menos a más", () => {
    expect(strength("")).toBe(0);
    expect(strength("abc")).toBe(0);
    expect(strength("abcdefgh")).toBeLessThan(strength("Abcdefgh1234!xyz"));
    expect(strength(generatePassword({ length: 24 }))).toBe(4);
  });
});

describe("bóveda: entradas", () => {
  const T0 = new Date("2026-11-13T10:00:00Z");
  const items = [
    newVaultItem({ service: "Netflix", email: "ana@correo.com", password: "secreto-1" }, T0, "1"),
    newVaultItem({ service: "banco", username: "ana.perez", url: "https://banco.example" }, T0, "2"),
    newVaultItem({ service: "Álbum", notes: "palabra-secreta" }, T0, "3"),
  ];

  it("busca por servicio, correo, usuario y web, pero nunca por la contraseña ni las notas", () => {
    expect(searchItems(items, "net").map((i) => i.id)).toEqual(["1"]);
    expect(searchItems(items, "ana@").map((i) => i.id)).toEqual(["1"]);
    expect(searchItems(items, "ana.perez").map((i) => i.id)).toEqual(["2"]);
    expect(searchItems(items, "banco.example").map((i) => i.id)).toEqual(["2"]);
    expect(searchItems(items, "secreto")).toEqual([]);
    expect(searchItems(items, "").map((i) => i.service)).toEqual(["Álbum", "banco", "Netflix"]); // por nombre, sin importar mayúsculas
  });

  it("editar sube updated_at y no deja el servicio vacío", () => {
    const edited = updateVaultItem(items[0], { service: "  Netflix HD " }, new Date("2020-01-01"));
    expect(edited.service).toBe("Netflix HD");
    expect(edited.updated_at > items[0].updated_at).toBe(true);
    expect(updateVaultItem(items[0], { service: "  " }).service).toBe("Netflix");
  });

  it("el enunciado dice el estado de la bóveda", () => {
    const base = { items: [], error: "", broken: 0 };
    expect(vaultStatement({ ...base, state: "loading" })).toMatch(/Comprobando/);
    expect(vaultStatement({ ...base, state: "none" })).toMatch(/Crea una contraseña maestra/);
    expect(vaultStatement({ ...base, state: "locked" })).toMatch(/bloqueada/);
    expect(vaultStatement({ ...base, state: "unlocked" })).toBe("Bóveda abierta y vacía.");
    expect(vaultStatement({ ...base, state: "unlocked", items })).toBe("Bóveda abierta: 3 entradas.");
    expect(vaultStatement({ ...base, state: "unlocked", items, broken: 1 })).toMatch(/1 no se pudo descifrar/);
    expect(vaultStatement({ ...base, state: "error", error: "Sin red" })).toBe("Sin red");
  });
});

/** Un cliente en memoria con solo lo que usa la sesión de la bóveda. */
function fakeClient() {
  const tables: Record<string, Record<string, unknown>[]> = { vault_meta: [], vault_entries: [] };
  const from = (name: string) => {
    const rows = tables[name];
    let op = "select";
    let payload: unknown;
    let id: unknown;
    let maybe = false;
    const b: Record<string, unknown> = {
      select: () => b,
      is: () => b,
      limit: () => b,
      eq: (_c: string, v: unknown) => ((id = v), b),
      maybeSingle: () => ((maybe = true), b),
      insert: (p: Record<string, unknown>) => ((op = "insert"), (payload = p), b),
      upsert: (p: Record<string, unknown>) => ((op = "upsert"), (payload = p), b),
      update: (p: Record<string, unknown>) => ((op = "update"), (payload = p), b),
      then: (resolve: (v: unknown) => unknown) => {
        if (op === "insert") rows.push({ ...(payload as object) });
        else if (op === "upsert") {
          const i = rows.findIndex((r) => r.id === (payload as { id: unknown }).id);
          if (i >= 0) rows[i] = { ...(payload as object) };
          else rows.push({ ...(payload as object) });
        } else if (op === "update") rows.filter((r) => r.id === id).forEach((r) => Object.assign(r, payload));
        const live = rows.filter((r) => !r.deleted_at);
        return Promise.resolve({ data: op === "select" ? (maybe ? (live[0] ?? null) : live) : null, error: null }).then(resolve);
      },
    };
    return b;
  };
  return { client: { from } as never, tables };
}

describe("bóveda: sesión", () => {
  // las vueltas del KDF son 600 000 en la app: es lento a propósito, así que se prueba lo justo
  it("crea, guarda cifrado, bloquea y desbloquea; la contraseña mala no abre y nada sale en claro", async () => {
    const { client, tables } = fakeClient();
    const vault = new VaultSession(client);
    await vault.refresh();
    expect(vault.state).toBe("none");

    await vault.create("una-maestra-bien-larga");
    expect(vault.state).toBe("unlocked");
    expect(tables.vault_meta[0]).toMatchObject({ kdf_iter: 600000, version: 1 });

    const item = await vault.add({ service: "Netflix", email: "ana@correo.com", password: "Sup3r-secreta" });
    expect(vault.items).toHaveLength(1);
    const stored = JSON.stringify(tables);
    for (const secret of ["Netflix", "ana@correo.com", "Sup3r-secreta"]) expect(stored).not.toContain(secret);

    const edited = await vault.update(item.id, { password: "Otra-clave-9" });
    expect(edited.password).toBe("Otra-clave-9");
    expect(JSON.stringify(tables)).not.toContain("Otra-clave-9");

    vault.lock();
    expect(vault.state).toBe("locked");
    expect(vault.items).toEqual([]); // nada descifrado queda en memoria
    await expect(vault.add({ service: "x" })).rejects.toThrow(/bloqueada/);

    expect(await vault.unlock("incorrecta-incorrecta")).toBe(false);
    expect(vault.state).toBe("locked");
    expect(await vault.unlock("una-maestra-bien-larga")).toBe(true);
    expect(vault.items.map((i) => [i.service, i.password])).toEqual([["Netflix", "Otra-clave-9"]]);

    await vault.remove(item.id);
    expect(vault.items).toEqual([]);
    vault.destroy();
  }, 60_000);

  it("se bloquea sola tras el tiempo sin usarla, y tocarla reinicia el reloj", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
    try {
      const { client } = fakeClient();
      const vault = new VaultSession(client, 1000);
      await vault.create("una-maestra-bien-larga");
      vi.advanceTimersByTime(800);
      vault.touch();
      vi.advanceTimersByTime(800);
      expect(vault.state).toBe("unlocked"); // el toque reinició el reloj
      vi.advanceTimersByTime(300);
      expect(vault.state).toBe("locked");
    } finally {
      vi.useRealTimers();
    }
  }, 60_000);
});

describe("bóveda: portapapeles", () => {
  it("copia y, pasado el tiempo, borra lo copiado solo si sigue siendo lo mismo", async () => {
    vi.useFakeTimers();
    try {
      let content = "";
      const clip = { writeText: vi.fn(async (t: string) => void (content = t)), readText: vi.fn(async () => content) };
      expect(await copySecret("clave", clip, 500)).toBe(true);
      expect(content).toBe("clave");
      await vi.advanceTimersByTimeAsync(600);
      expect(content).toBe(""); // se borró

      await copySecret("otra", clip, 500);
      content = "lo que el usuario copió después"; // ya no es la clave
      await vi.advanceTimersByTimeAsync(600);
      expect(content).toBe("lo que el usuario copió después"); // no se pisa
    } finally {
      vi.useRealTimers();
    }
  });

  it("si el navegador no deja copiar, lo dice", async () => {
    expect(await copySecret("x", undefined)).toBe(false);
    expect(await copySecret("x", { writeText: async () => Promise.reject(new Error("no")), readText: async () => "" }, 10)).toBe(false);
  });
});
