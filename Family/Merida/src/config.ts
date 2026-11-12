declare const __SUPABASE_URL__: string;
declare const __SUPABASE_ANON_KEY__: string;

/** La URL del proyecto de Supabase y su clave pública. Los pone vite.config.ts al arrancar, leyendo el .env. */
export const config = {
  url: typeof __SUPABASE_URL__ === "string" ? __SUPABASE_URL__ : "",
  anonKey: typeof __SUPABASE_ANON_KEY__ === "string" ? __SUPABASE_ANON_KEY__ : "",
};

/** Qué falta para conectar (vacío si está todo). */
export function missingConfig(c: { url: string; anonKey: string } = config): string[] {
  const missing: string[] = [];
  if (!c.url) missing.push("SUPABASE_URL");
  if (!c.anonKey) missing.push("SUPABASE_ANON_KEY");
  return missing;
}

/** Cómo se llama este dispositivo en los mensajes (la PC es `pc` y el móvil `movil`). */
export const DEVICE = "web";
