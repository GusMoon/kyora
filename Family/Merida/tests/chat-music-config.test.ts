import { describe, expect, it } from "vitest";
import { deviceLabel, draftMessage, latestCreatedAt, mergeMessages, sendPayload, type Message } from "../src/data/chat";
import { formatSize, formatTime, playlists, type Track } from "../src/data/music";
import { missingConfig } from "../src/config";
import { parseEnv } from "../src/env-file";
import { musicStatement } from "../src/sections/music";
import { chatStatement } from "../src/sections/chat";
import { explainError } from "../src/supabase";

function msg(id: string, sent: string, patch: Partial<Message> = {}): Message {
  return {
    id,
    conversation_id: "c",
    sender_device: "pc",
    kind: "text",
    body: id,
    status: "sent",
    sent_at: sent,
    created_at: sent,
    deleted_at: null,
    attachments: [],
    ...patch,
  };
}

describe("chat", () => {
  it("el envío lleva el id del dispositivo, la hora y el dispositivo web, sin adjuntos", () => {
    const p = sendPayload("conv", "Hola", "id-1", new Date("2026-11-11T10:00:00Z"));
    expect(p).toEqual({ p_id: "id-1", p_conversation_id: "conv", p_body: "Hola", p_sent_at: "2026-11-11T10:00:00.000Z", p_device: "web", p_attachments: [] });
    expect(draftMessage(p)).toMatchObject({ id: "id-1", sender_device: "web", local: "sending" });
  });

  it("junta sin duplicar, gana el servidor, quita borrados y ordena por hora de envío", () => {
    const draft = draftMessage(sendPayload("c", "yo", "m2", new Date("2026-11-11T10:02:00Z")));
    const current = [msg("m1", "2026-11-11T10:01:00Z"), draft];
    const merged = mergeMessages(current, [
      msg("m2", "2026-11-11T10:02:00Z", { sender_device: "web", body: "yo" }),
      msg("m0", "2026-11-11T10:00:00Z"),
      msg("m1", "2026-11-11T10:01:00Z", { deleted_at: "2026-11-11T10:05:00Z" }),
    ]);
    expect(merged.map((m) => m.id)).toEqual(["m0", "m2"]);
    expect(merged[1].local).toBeUndefined();
  });

  it("se pone al día desde el último mensaje del servidor, sin contar los que se están enviando", () => {
    const list = [msg("a", "2026-11-11T10:00:00Z"), msg("b", "2026-11-11T10:03:00Z"), { ...msg("c", "2026-11-11T10:09:00Z"), local: "sending" as const }];
    expect(latestCreatedAt(list)).toBe("2026-11-11T10:03:00Z");
    expect(latestCreatedAt([])).toBeNull();
  });

  it("nombra los dispositivos", () => {
    expect(deviceLabel("movil")).toBe("móvil");
    expect(deviceLabel("web")).toBe("web");
    expect(deviceLabel("laptop")).toBe("laptop");
  });

  it("el enunciado del chat", () => {
    expect(chatStatement([], true)).toMatch(/vacía/);
    expect(chatStatement([msg("a", "x")], true)).toBe("Conversación General: 1 mensaje con la PC y el móvil.");
  });
});

describe("música", () => {
  const track = (id: string, playlist: string | null): Track => ({
    id, title: id, file_name: `${id}.mp3`, storage_path: `u/music/${id}.mp3`, mime_type: "audio/mpeg",
    size_bytes: 4_500_000, playlist, cover_url: null, created_at: "2026-11-11T10:00:00Z", received_at: null,
  });

  it("formatea tamaños y tiempos", () => {
    expect(formatSize(0)).toBe("0 KB");
    expect(formatSize(300)).toBe("1 KB");
    expect(formatSize(4_500_000)).toBe("4.3 MB");
    expect(formatTime(0)).toBe("0:00");
    expect(formatTime(125.9)).toBe("2:05");
    expect(formatTime(NaN)).toBe("0:00");
  });

  it("cuenta las listas distintas", () => {
    const tracks = [track("a", "Lo-fi"), track("b", "Lo-fi"), track("c", null), track("d", "Rock")];
    expect(playlists(tracks)).toEqual(["Lo-fi", "Rock"]);
    expect(musicStatement(tracks, true)).toBe("4 canciones en 2 listas.");
    expect(musicStatement([], true)).toMatch(/^Aún no hay canciones/);
  });
});

describe("configuración", () => {
  it("lee el .env como Kyora y solo pide URL y clave pública", () => {
    const env = parseEnv('# comentario\nSUPABASE_URL=https://x.supabase.co\nexport SUPABASE_ANON_KEY="abc"\nCHAT_DEVICE=pc # la PC\n\nROTA\n');
    expect(env).toEqual({ SUPABASE_URL: "https://x.supabase.co", SUPABASE_ANON_KEY: "abc", CHAT_DEVICE: "pc" });
    expect(missingConfig({ url: "u", anonKey: "" })).toEqual(["SUPABASE_ANON_KEY"]);
    expect(missingConfig({ url: "u", anonKey: "k" })).toEqual([]);
  });

  it("explica los errores sin jerga", () => {
    expect(explainError({ message: "Invalid login credentials" })).toMatch(/correo o la contraseña/);
    expect(explainError({ message: "Failed to fetch" })).toMatch(/conexión/);
    expect(explainError({ code: "PGRST202", message: "x" })).toMatch(/schema\.sql/);
  });
});
