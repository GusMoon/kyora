import type { SupabaseClient } from "@supabase/supabase-js";

/** Cuánto ocupa tu proyecto de Supabase (la función `server_stats()` de Server/supabase/schema.sql §15) frente a los límites del
 * plan gratuito. El aviso salta al llegar al 80 %. Solo se pueden medir la base de datos y los archivos: el tráfico del mes
 * (egress) y los usuarios activos no salen por ninguna API que la app pueda leer. */

export interface BucketStat {
  bucket: string;
  objects: number;
  bytes: number;
}
export interface TableStat {
  name: string;
  bytes: number;
  rows: number;
}
export interface ServerStats {
  db_bytes: number;
  storage_bytes: number;
  storage_objects: number;
  buckets: BucketStat[];
  tables: TableStat[];
  at: string;
}

export const MB = 1024 * 1024;
/** Los límites del plan gratuito de Supabase, en MB (se pueden cambiar en Configuración si cambias de plan). */
export const FREE_DB_MB = 500;
export const FREE_FILES_MB = 1024;
/** A partir de aquí hay advertencia, y a partir de `CRITICAL` está casi lleno. */
export const WARN_AT = 0.8;
export const CRITICAL_AT = 0.95;

export type Level = "ok" | "warn" | "critical";

export interface Quota {
  id: "db" | "files";
  label: string;
  used: number; // bytes
  limit: number; // bytes
  ratio: number; // 0 … (puede pasar de 1)
  level: Level;
}

export const levelOf = (ratio: number): Level => (ratio >= CRITICAL_AT ? "critical" : ratio >= WARN_AT ? "warn" : "ok");

export function quotas(stats: ServerStats, limitsMb: { db: number; files: number }): Quota[] {
  const make = (id: Quota["id"], label: string, used: number, mb: number): Quota => {
    const limit = Math.max(1, mb) * MB;
    const ratio = used / limit;
    return { id, label, used, limit, ratio, level: levelOf(ratio) };
  };
  return [make("db", "Base de datos", stats.db_bytes, limitsMb.db), make("files", "Archivos (Storage)", stats.storage_bytes, limitsMb.files)];
}

/** Los que están en el 80 % o más. */
export const overQuota = (stats: ServerStats, limitsMb: { db: number; files: number }): Quota[] => quotas(stats, limitsMb).filter((q) => q.level !== "ok");

export const percent = (ratio: number): string => `${Math.floor(ratio * 100)} %`; // se redondea hacia abajo: «80 %» solo si de verdad llegó

/** «412,3 MB» o «1,24 GB». */
export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < MB) return `${(bytes / 1024).toFixed(0)} KB`;
  if (bytes < 1024 * MB) return `${(bytes / MB).toFixed(1).replace(".", ",")} MB`;
  return `${(bytes / (1024 * MB)).toFixed(2).replace(".", ",")} GB`;
}

/** El mensaje de la advertencia (para el aviso de la nube y la notificación). */
export function warningText(q: Quota): string {
  const left = Math.max(0, q.limit - q.used);
  return q.level === "critical" && q.ratio >= 1
    ? `${q.label}: superaste el límite del plan gratuito (${formatBytes(q.used)} de ${formatBytes(q.limit)}).`
    : `${q.label}: llevas ${percent(q.ratio)} del plan gratuito (${formatBytes(q.used)} de ${formatBytes(q.limit)}; quedan ${formatBytes(left)}).`;
}

/** Solo se vuelve a notificar lo mismo pasado un día (la advertencia dentro de la app no se esconde). */
export const RENOTIFY_MS = 24 * 3600 * 1000;

export function shouldRenotify(lastWarnedAt: number | null, now: number): boolean {
  return lastWarnedAt === null || now - lastWarnedAt >= RENOTIFY_MS;
}

const num = (v: unknown): number => (typeof v === "number" && Number.isFinite(v) ? v : Number(v) || 0);

/** Lo que devuelve la función, saneado (los `bigint` de Postgres a veces llegan como texto). */
export function parseStats(raw: unknown): ServerStats {
  const o = (raw ?? {}) as Record<string, unknown>;
  const list = (v: unknown): Record<string, unknown>[] => (Array.isArray(v) ? (v as Record<string, unknown>[]) : []);
  return {
    db_bytes: num(o.db_bytes),
    storage_bytes: num(o.storage_bytes),
    storage_objects: num(o.storage_objects),
    buckets: list(o.buckets).map((b) => ({ bucket: String(b.bucket ?? "?"), objects: num(b.objects), bytes: num(b.bytes) })),
    tables: list(o.tables).map((t) => ({ name: String(t.name ?? "?"), bytes: num(t.bytes), rows: num(t.rows) })),
    at: typeof o.at === "string" ? o.at : new Date().toISOString(),
  };
}

export async function loadServerStats(client: SupabaseClient): Promise<ServerStats> {
  const { data, error } = await client.rpc("server_stats");
  if (error) {
    const msg = String(error.message ?? "");
    if (error.code === "PGRST202" || /could not find the function|server_stats/i.test(msg)) {
      throw new Error("Falta la función server_stats en Supabase. Vuelve a ejecutar Server/supabase/schema.sql en el SQL Editor.");
    }
    throw error;
  }
  return parseStats(data);
}

const QUOTA_KEY = "merida-quota-warned";

/** Cuándo se notificó cada límite por última vez (en este navegador). */
export function loadWarned(store: Pick<Storage, "getItem"> | null): Record<string, number> {
  try {
    const raw = JSON.parse(store?.getItem(QUOTA_KEY) ?? "{}") as Record<string, unknown>;
    return Object.fromEntries(Object.entries(raw).filter(([, v]) => typeof v === "number")) as Record<string, number>;
  } catch {
    return {};
  }
}

export function saveWarned(store: Pick<Storage, "setItem"> | null, warned: Record<string, number>): void {
  try {
    store?.setItem(QUOTA_KEY, JSON.stringify(warned));
  } catch {
    /* sin almacenamiento: puede repetirse el aviso */
  }
}
