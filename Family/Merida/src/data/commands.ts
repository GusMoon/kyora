import type { SupabaseClient } from "@supabase/supabase-js";

/** Un comando del chat (tabla chat_commands de Server/supabase/schema.sql §10): «/command» abre `url`. */
export interface ChatCommand {
  id: string;
  name: string; // el nombre de la web
  command: string; // lo que se escribe tras la «/», sin ella
  url: string;
}

const COMMAND_RE = /^[a-z0-9_-]{1,24}$/;
const COLUMNS = "id, name, command, url";

/** «/YouTube » → «youtube». Quita la «/» del principio, los espacios y las mayúsculas. */
export function normalizeCommand(raw: string): string {
  return raw.trim().replace(/^\/+/, "").toLowerCase();
}

export function isValidCommand(command: string): boolean {
  return COMMAND_RE.test(command);
}

/** Una dirección web completa (sin «https://» se lo pone) o `null` si no es http(s). */
export function normalizeUrl(raw: string): string | null {
  const text = raw.trim();
  if (!text || /\s/.test(text) || text.length > 2048) return null;
  if (/^(?:javascript|data|vbscript|file|mailto|blob|about):/i.test(text)) return null; // «javascript:1» no es un host con puerto
  const full = /^[a-z][a-z0-9+.-]*:\/\//i.test(text) ? text : `https://${text}`;
  try {
    const url = new URL(full);
    return url.protocol === "http:" || url.protocol === "https:" ? full : null;
  } catch {
    return null;
  }
}

export type CommandInput = { name: string; command: string; url: string };

/** Revisa lo que se escribió en el formulario. Devuelve los datos limpios o el motivo (en español) por el que no valen. */
export function checkCommandInput(input: CommandInput, existing: ChatCommand[]): { ok: true; value: CommandInput } | { ok: false; error: string } {
  const name = input.name.trim();
  const command = normalizeCommand(input.command);
  const url = normalizeUrl(input.url);
  if (!name) return { ok: false, error: "Escribe el nombre de la web." };
  if (name.length > 60) return { ok: false, error: "El nombre es demasiado largo (máximo 60 letras)." };
  if (!command) return { ok: false, error: "Escribe el comando, por ejemplo youtube." };
  if (!isValidCommand(command)) return { ok: false, error: "El comando solo puede llevar letras sin acento, números, «-» o «_» (hasta 24)." };
  if (existing.some((c) => c.command === command)) return { ok: false, error: `Ya existe el comando /${command}.` };
  if (!url) return { ok: false, error: "La dirección no es válida: debe ser una web http o https." };
  return { ok: true, value: { name, command, url } };
}

export type ParsedCommand = { kind: "none" } | { kind: "open"; command: ChatCommand } | { kind: "unknown"; name: string };

/** ¿Lo escrito en el chat es un comando? Solo cuenta si empieza con «/» y la primera palabra tiene forma de comando
 * (así «/etc/hosts» sigue siendo un mensaje normal). Lo que venga después de la primera palabra se ignora. */
export function parseCommand(body: string, commands: ChatCommand[]): ParsedCommand {
  const first = body.trim().split(/\s+/)[0] ?? "";
  if (!first.startsWith("/")) return { kind: "none" };
  const name = first.slice(1).toLowerCase();
  if (!isValidCommand(name)) return { kind: "none" };
  const found = commands.find((c) => c.command === name);
  return found ? { kind: "open", command: found } : { kind: "unknown", name };
}

export const MAX_SUGGESTIONS = 8;

/** Los comandos que se ofrecen mientras se escribe «/algo». Solo hay sugerencias si lo escrito empieza con «/» y todavía
 * no lleva espacios (después de la primera palabra ya no es el nombre del comando). Primero los que empiezan por lo
 * escrito, luego los que lo contienen en el comando o en el nombre de la web; cada grupo por orden alfabético. */
export function suggestCommands(draft: string, commands: ChatCommand[]): ChatCommand[] {
  if (!draft.startsWith("/") || /\s/.test(draft)) return [];
  const typed = draft.slice(1).toLowerCase();
  const byName = (a: ChatCommand, b: ChatCommand) => a.command.localeCompare(b.command);
  const starts = commands.filter((c) => c.command.startsWith(typed)).sort(byName);
  const rest = commands.filter((c) => !c.command.startsWith(typed) && (c.command.includes(typed) || c.name.toLowerCase().includes(typed))).sort(byName);
  return [...starts, ...rest].slice(0, MAX_SUGGESTIONS);
}

export async function listCommands(client: SupabaseClient): Promise<ChatCommand[]> {
  const { data, error } = await client.from("chat_commands").select(COLUMNS).order("command");
  if (error) throw error;
  return (data ?? []) as ChatCommand[];
}

export async function addCommand(client: SupabaseClient, input: CommandInput): Promise<ChatCommand> {
  const { data, error } = await client.from("chat_commands").insert(input).select(COLUMNS).single();
  if (error) throw error;
  return data as ChatCommand;
}

export async function removeCommand(client: SupabaseClient, id: string): Promise<void> {
  const { error } = await client.from("chat_commands").delete().eq("id", id);
  if (error) throw error;
}
