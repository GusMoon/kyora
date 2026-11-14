/** La paleta de comandos (`Ctrl+K`): una lista de cosas que se pueden hacer o abrir, filtrada mientras se escribe.
 * Aquí solo está la lógica pura (buscar y ordenar); la pantalla está en ui/palette.ts y la lista, en paletteItems.ts. */

export interface PaletteItem {
  id: string;
  label: string; // lo que se ve y por lo que se busca
  hint?: string; // un texto secundario (la tecla, el estado, el correo…)
  group: string; // «Ir a», «Acciones», «Tareas»…
  keywords?: string; // más palabras por las que encontrarlo
  run: () => void;
}

export const MAX_RESULTS = 40;

/** Minúsculas y sin acentos, para que «musica» encuentre «Música». */
export function normalize(text: string): string {
  return text.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();
}

/** Cuánto encaja una búsqueda con un elemento (0 = nada). Mejor si empieza igual, luego si una palabra empieza igual,
 * luego si lo contiene, luego por las palabras clave, y por último si las letras aparecen en orden (búsqueda difusa). */
export function score(query: string, item: PaletteItem): number {
  const q = normalize(query);
  if (!q) return 1;
  const label = normalize(item.label);
  if (label === q) return 120;
  if (label.startsWith(q)) return 100;
  if (label.split(/[\s\-_/.]+/).some((w) => w.startsWith(q))) return 80;
  if (label.includes(q)) return 60;
  if (normalize(`${item.keywords ?? ""} ${item.hint ?? ""}`).includes(q)) return 40;
  // todas las letras, en orden (por ejemplo «ntar» → «Nueva tarea»)
  let at = 0;
  for (const ch of label) if (ch === q[at]) at++;
  return at === q.length ? 20 : 0;
}

/** Los elementos que encajan, del mejor al peor (a igual puntuación, el orden original). Sin búsqueda, todos tal cual. */
export function rank(items: PaletteItem[], query: string, limit = MAX_RESULTS): PaletteItem[] {
  if (!normalize(query)) return items.slice(0, limit);
  return items
    .map((item, order) => ({ item, order, s: score(query, item) }))
    .filter((x) => x.s > 0)
    .sort((a, b) => b.s - a.s || a.item.label.length - b.item.label.length || a.order - b.order)
    .slice(0, limit)
    .map((x) => x.item);
}

/** Los resultados con su encabezado de grupo, en el orden en que aparecen (para pintar la lista). */
export function grouped(items: PaletteItem[]): { group: string; items: PaletteItem[] }[] {
  const out: { group: string; items: PaletteItem[] }[] = [];
  for (const item of items) {
    const last = out[out.length - 1];
    if (last && last.group === item.group) last.items.push(item);
    else out.push({ group: item.group, items: [item] });
  }
  return out;
}
