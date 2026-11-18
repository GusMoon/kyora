import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { config } from "./config";

let client: SupabaseClient | null = null;

/** El cliente de Supabase. Guarda la sesión en el navegador y la renueva solo. */
export function supabase(): SupabaseClient {
  client ??= createClient(config.url, config.anonKey, {
    auth: { persistSession: true, autoRefreshToken: true, storageKey: "merida-auth" },
  });
  return client;
}

/** El texto de un error de Supabase, en el idioma de la app. */
export function explainError(err: unknown): string {
  const info = (err ?? {}) as { code?: string; message?: string; status?: number };
  const text = `${info.code ?? ""} ${info.message ?? ""}`.toLowerCase();
  if (text.includes("invalid login") || text.includes("invalid_credentials")) {
    return "El usuario o la contraseña no coinciden con tu cuenta.";
  }
  if (text.includes("failed to fetch") || text.includes("network")) {
    return "No hay conexión con el servidor. Revisa internet y vuelve a intentarlo.";
  }
  if (text.includes("pgrst202") || text.includes("could not find the function")) {
    return "Falta crear la base de datos: ejecuta Server/supabase/schema.sql en Supabase.";
  }
  if (text.includes("pgrst205") || text.includes("could not find the table")) {
    return "Falta una tabla en la base de datos: ejecuta de nuevo Server/supabase/schema.sql en Supabase.";
  }
  if (info.code === "23505") return "Ya existe un registro igual.";
  if (text.includes("not_authenticated") || info.status === 401) {
    return "La sesión caducó. Vuelve a entrar.";
  }
  return info.message ? `El servidor respondió: ${info.message}` : "Algo falló al hablar con el servidor.";
}
