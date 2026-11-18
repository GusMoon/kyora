// Lo puro de la limpieza (sin Deno ni red) para poder probarlo desde Merida (tests/cleanup-family.test.ts).

/** Cuánto vive un mensaje, un archivo o una llamada del chat familiar. */
export const FAMILY_TTL_HOURS = 24;

/** La hora de corte: lo creado antes de ella ya caducó. Es ISO 8601, como la espera PostgREST. */
export function expiryCutoff(nowMs: number, hours: number = FAMILY_TTL_HOURS): string {
  return new Date(nowMs - hours * 3600 * 1000).toISOString();
}

/** Los archivos (adjuntos y miniaturas) de unos mensajes, sin repetir y sin vacíos. */
export function filesOf(messages: { attachments?: { storage_path?: string | null; thumb_path?: string | null }[] | null }[]): string[] {
  const paths = new Set<string>();
  for (const message of messages) {
    for (const a of message.attachments ?? []) {
      if (a.storage_path) paths.add(a.storage_path);
      if (a.thumb_path) paths.add(a.thumb_path);
    }
  }
  return [...paths];
}
