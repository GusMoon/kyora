/** Cifrado de la bóveda de contraseñas, todo con Web Crypto del navegador (sin librerías).
 *
 *  - La clave sale de la contraseña maestra con PBKDF2-SHA-256 (600 000 vueltas) y una sal aleatoria propia del usuario.
 *  - Cada texto se cifra con AES-GCM de 256 bits y un IV aleatorio de 12 bytes. AES-GCM autentica: si alguien cambia un
 *    byte del texto cifrado, descifrar falla en vez de devolver basura.
 *  - Se usa el id de la fila como «datos asociados» (AAD): una entrada copiada a la fila de otra no se puede descifrar.
 *  - La clave se crea como NO exportable: el código de la página no puede leer sus bytes, solo usarla.
 *  - Formato guardado: «v1.» + base64(IV ‖ texto cifrado). */

export const KDF_ITERATIONS = 600_000;
const PREFIX = "v1.";
export const VERIFIER_TEXT = "kyora-vault-v1";

const enc = new TextEncoder();
const dec = new TextDecoder();

export function randomBytes(n: number): Uint8Array {
  return crypto.getRandomValues(new Uint8Array(n));
}

export function toBase64(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}

export function fromBase64(text: string): Uint8Array {
  const s = atob(text);
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out;
}

/** La clave AES-GCM derivada de la contraseña maestra. Lenta a propósito (frena a quien pruebe contraseñas). */
export async function deriveKey(password: string, salt: Uint8Array, iterations: number = KDF_ITERATIONS): Promise<CryptoKey> {
  const base = await crypto.subtle.importKey("raw", enc.encode(password.normalize("NFKC")), "PBKDF2", false, ["deriveKey"]);
  return crypto.subtle.deriveKey(
    { name: "PBKDF2", hash: "SHA-256", salt: salt as BufferSource, iterations },
    base,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"],
  );
}

export async function encryptText(key: CryptoKey, plaintext: string, aad = ""): Promise<string> {
  const iv = randomBytes(12);
  const data = await crypto.subtle.encrypt({ name: "AES-GCM", iv: iv as BufferSource, additionalData: enc.encode(aad) as BufferSource }, key, enc.encode(plaintext));
  const packed = new Uint8Array(iv.length + data.byteLength);
  packed.set(iv, 0);
  packed.set(new Uint8Array(data), iv.length);
  return PREFIX + toBase64(packed);
}

/** Descifra. Lanza un error si la clave no es la correcta, el texto se alteró o el `aad` no coincide. */
export async function decryptText(key: CryptoKey, token: string, aad = ""): Promise<string> {
  if (!token.startsWith(PREFIX)) throw new Error("Formato de bóveda desconocido.");
  const packed = fromBase64(token.slice(PREFIX.length));
  if (packed.length < 13) throw new Error("Texto cifrado incompleto.");
  const iv = packed.slice(0, 12);
  const data = packed.slice(12);
  const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv: iv as BufferSource, additionalData: enc.encode(aad) as BufferSource }, key, data);
  return dec.decode(plain);
}

/** La «prueba» que se guarda en vault_meta: un texto conocido cifrado. Si descifra bien, la contraseña maestra es la correcta. */
export function makeVerifier(key: CryptoKey): Promise<string> {
  return encryptText(key, VERIFIER_TEXT, "vault_meta");
}

export async function checkVerifier(key: CryptoKey, verifier: string): Promise<boolean> {
  try {
    return (await decryptText(key, verifier, "vault_meta")) === VERIFIER_TEXT;
  } catch {
    return false;
  }
}

export interface PasswordOptions {
  length?: number;
  lower?: boolean;
  upper?: boolean;
  digits?: boolean;
  symbols?: boolean;
}

const SETS = {
  lower: "abcdefghijkmnpqrstuvwxyz", // sin l ni o: se confunden con 1 y 0
  upper: "ABCDEFGHJKLMNPQRSTUVWXYZ",
  digits: "23456789",
  symbols: "!@#$%^&*-_=+?",
};

/** Un número al azar en [0, max) sin sesgo (descarta lo que no cabe en un múltiplo exacto). */
function randomBelow(max: number): number {
  const limit = Math.floor(0x1_0000_0000 / max) * max;
  const buf = new Uint32Array(1);
  do crypto.getRandomValues(buf);
  while (buf[0] >= limit);
  return buf[0] % max;
}

/** Una contraseña al azar con `crypto.getRandomValues`. Lleva al menos un carácter de cada tipo elegido. */
export function generatePassword(opts: PasswordOptions = {}): string {
  const { length = 20, lower = true, upper = true, digits = true, symbols = true } = opts;
  const groups = ([lower && SETS.lower, upper && SETS.upper, digits && SETS.digits, symbols && SETS.symbols].filter(Boolean) as string[]);
  if (!groups.length) return "";
  const size = Math.min(128, Math.max(groups.length, length));
  const all = groups.join("");
  const chars = groups.map((g) => g[randomBelow(g.length)]);
  while (chars.length < size) chars.push(all[randomBelow(all.length)]);
  for (let i = chars.length - 1; i > 0; i--) {
    const j = randomBelow(i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join("");
}

/** Una estimación simple de la fuerza de una contraseña: 0 (muy débil) a 4 (fuerte). */
export function strength(password: string): 0 | 1 | 2 | 3 | 4 {
  if (!password) return 0;
  let pool = 0;
  if (/[a-z]/.test(password)) pool += 26;
  if (/[A-Z]/.test(password)) pool += 26;
  if (/\d/.test(password)) pool += 10;
  if (/[^A-Za-z0-9]/.test(password)) pool += 20;
  const bits = password.length * Math.log2(Math.max(pool, 2));
  return bits < 28 ? 0 : bits < 45 ? 1 : bits < 60 ? 2 : bits < 80 ? 3 : 4;
}
