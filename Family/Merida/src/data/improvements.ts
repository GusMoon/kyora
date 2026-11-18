import type { SupabaseClient } from "@supabase/supabase-js";

/** Mejoras pendientes del proyecto (tabla `feature_requests` de Server/supabase/schema.sql §17): qué sección se quiere agregar o mejorar, qué
 * funciones se quieren y una descripción. Las comparten Merida y Kyra. Al terminar una se pulsa «Hecho» y se **borra** de la base de datos. */
export interface Improvement {
  id: string;
  section: string; // la sección que se quiere agregar o mejorar
  functions: string; // las funciones que se quieren, una por línea
  description: string;
  created_at: string;
}

export const MAX_SECTION = 80;
export const MAX_TEXT = 4000;

/** Una mejora nueva: los textos recortados y un id del dispositivo (así repetir el guardado no la duplica). */
export function newImprovement(
  input: { section: string; functions?: string; description?: string },
  now: Date = new Date(),
  id: string = crypto.randomUUID(),
): Improvement {
  return { id, section: input.section.trim(), functions: (input.functions ?? "").trim(), description: (input.description ?? "").trim(), created_at: now.toISOString() };
}

/** Lo que falta o sobra en lo escrito, con el aviso ya explicado; `null` si está bien. */
export function validateImprovement(input: { section: string; functions?: string; description?: string }): string | null {
  const section = input.section.trim();
  if (!section) return "Escribe qué sección quieres agregar o mejorar.";
  if (section.length > MAX_SECTION) return `El nombre de la sección admite hasta ${MAX_SECTION} caracteres.`;
  if (!(input.functions ?? "").trim() && !(input.description ?? "").trim()) return "Anota al menos una función o una descripción.";
  if ((input.functions ?? "").length > MAX_TEXT || (input.description ?? "").length > MAX_TEXT) return `Cada texto admite hasta ${MAX_TEXT} caracteres.`;
  return null;
}

/** Las funciones como lista: una por línea, sin las viñetas («-», «*», «•») con que se hayan escrito. */
export function functionLines(text: string): string[] {
  return text
    .split(/\r?\n/)
    .map((line) => line.replace(/^\s*(?:[-*•·]\s+|\d+[.)]\s+)/, "").trim())
    .filter(Boolean);
}

/** De la más nueva a la más antigua. */
export function sortImprovements(list: Improvement[]): Improvement[] {
  return [...list].sort((a, b) => b.created_at.localeCompare(a.created_at));
}

/** Quita (o pone) filas de la lista, sin duplicar. */
export function withImprovement(list: Improvement[], item: Improvement): Improvement[] {
  return sortImprovements([...list.filter((x) => x.id !== item.id), item]);
}

export function withoutImprovement(list: Improvement[], id: string): Improvement[] {
  return list.filter((x) => x.id !== id);
}

/** El prompt en Markdown, listo para pegar en un IDE con un asistente: contexto del proyecto, una tarea por cada mejora escogida (con sus
 * funciones como casillas y su descripción citada) e instrucciones para trabajarlas. Las mejoras salen en el orden recibido. */
export function buildImprovementsPrompt(items: Improvement[]): string {
  const tasks = items.map((item, i) => {
    const lines = functionLines(item.functions);
    const out = [`### ${i + 1}. ${oneLine(item.section)}`];
    if (lines.length) out.push("", "**Funciones que se quieren:**", ...lines.map((l) => `- [ ] ${l}`));
    const desc = item.description.trim();
    if (desc) out.push("", "**Descripción:**", ...desc.split(/\r?\n/).map((l) => (l.trim() ? `> ${l}` : ">")));
    return out.join("\n");
  });
  const noun = items.length === 1 ? "la mejora" : `las ${items.length} mejoras`;
  return [
    "# Mejoras para Merida",
    "",
    "## Contexto",
    "",
    "Trabajas en **Merida** (`Family/Merida`): la consola web de la familia Kyora, hecha con TypeScript, Vite y Supabase, y probada con Vitest. Cada sección vive en `src/sections/`, sus datos y reglas en `src/data/`, los estilos en `src/styles/` y las pruebas en `tests/`. Los textos de la interfaz están en español.",
    "",
    `## Tareas (${items.length})`,
    "",
    tasks.join("\n\n"),
    "",
    "## Instrucciones",
    "",
    `1. Lee primero el código de las secciones implicadas y sigue los patrones que ya usa el proyecto (helper \`h()\` para el DOM, lógica en \`src/data/\`, estilos con los tokens existentes). No agregues dependencias nuevas sin necesidad.`,
    `2. Implementa ${noun} en el orden indicado. Si algo es ambiguo, elige lo más simple y dilo al final en lugar de bloquearte.`,
    "3. Cubre cada función con pruebas de Vitest en `tests/`, siguiendo el estilo de las existentes.",
    "4. Antes de terminar ejecuta `npm run typecheck` y `npm test` dentro de `Family/Merida` y corrige lo que falle.",
    "5. Haz solo los cambios necesarios para estas tareas; no refactorices código ajeno a ellas.",
    "6. Al final resume qué cambió, en qué archivos y qué funciones quedaron completas.",
    "",
  ].join("\n");
}

/** Un texto en una sola línea (para que un título no rompa el Markdown). */
function oneLine(text: string): string {
  return text.replace(/\s+/g, " ").trim();
}

/** Lo que dice la tesela y el enunciado de la sección. */
export function improvementsStatement(list: Improvement[], loaded: boolean, error?: string): string {
  if (error) return error;
  if (!loaded) return "Cargando tus mejoras pendientes.";
  if (!list.length) return "No hay mejoras pendientes. Anota abajo la primera idea.";
  return list.length === 1 ? "1 mejora pendiente." : `${list.length} mejoras pendientes.`;
}

const COLUMNS = "id,section,functions,description,created_at";

export async function loadImprovements(client: SupabaseClient): Promise<Improvement[]> {
  const { data, error } = await client.from("feature_requests").select(COLUMNS).order("created_at", { ascending: false }).limit(500);
  if (error) throw error;
  return (data ?? []) as unknown as Improvement[];
}

export async function saveImprovement(client: SupabaseClient, item: Improvement): Promise<void> {
  const { error } = await client.from("feature_requests").upsert(item, { onConflict: "id" });
  if (error) throw error;
}

/** «Hecho»: se borra de verdad de la base de datos. */
export async function finishImprovement(client: SupabaseClient, id: string): Promise<void> {
  const { error } = await client.from("feature_requests").delete().eq("id", id);
  if (error) throw error;
}
