/** {VARIABLE: valor} de un texto .env, con las mismas reglas que Kyora (Family/Kyora/kyora/chat/env.py):
 * sin líneas vacías ni comentarios (#), con o sin comillas, con `export` y con comentario al final de la línea. */
export function parseEnv(text: string): Record<string, string> {
  const values: Record<string, string> = {};
  for (const raw of (text ?? "").split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith("#") || !line.includes("=")) continue;
    const at = line.indexOf("=");
    const key = line.slice(0, at).trim().replace(/^export\s+/, "").trim();
    let value = line.slice(at + 1).trim();
    const quote = value[0];
    if (value.length >= 2 && (quote === '"' || quote === "'") && value.endsWith(quote)) {
      value = value.slice(1, -1);
    } else if (value.includes(" #")) {
      value = value.slice(0, value.indexOf(" #")).trimEnd();
    }
    if (key) values[key] = value;
  }
  return values;
}
