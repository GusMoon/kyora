import { describe, expect, it } from "vitest";
import { uploadAttachments } from "../src/data/attachments";
import {
  FAMILY_BUCKET,
  FAMILY_CONVERSATION,
  FAMILY_TTL_MS,
  familyDraft,
  familyMembers,
  familyPayload,
  familyStatement,
  fromRow,
  isExpired,
  listFamilyMessages,
  mergeFamily,
  nextExpiryIn,
  senderLabel,
  sendFamilyMessage,
  visibleMessages,
  watchFamily,
  type FamilyMessage,
} from "../src/data/family-chat";
import { fakeClient, flush } from "./family-fakes";

const NOW = Date.parse("2026-11-15T12:00:00Z");
const ago = (h: number) => new Date(NOW - h * 3600_000).toISOString();

const msg = (id: string, sender: string, createdAt: string, extra: Partial<FamilyMessage> = {}): FamilyMessage => ({
  id, sender_id: sender, conversation_id: FAMILY_CONVERSATION, sender_device: "web", kind: "text", body: id, status: "sent",
  sent_at: createdAt, created_at: createdAt, deleted_at: null, attachments: [], ...extra,
});

describe("chat familiar: el borrado a las 24 horas", () => {
  it("un mensaje caduca justo a las 24 horas de llegar al servidor, no antes", () => {
    expect(isExpired({ created_at: ago(23.99) }, NOW)).toBe(false);
    expect(isExpired({ created_at: new Date(NOW - FAMILY_TTL_MS).toISOString() }, NOW)).toBe(true);
    expect(isExpired({ created_at: ago(30) }, NOW)).toBe(true);
  });

  it("solo se ve lo que no caducó", () => {
    const list = [msg("viejo", "m", ago(25)), msg("justo", "m", ago(24)), msg("nuevo", "m", ago(1))];
    expect(visibleMessages(list, NOW).map((m) => m.id)).toEqual(["nuevo"]);
  });

  it("calcula cuánto falta para que caduque el más próximo (y nada si no hay)", () => {
    expect(nextExpiryIn([], NOW)).toBeNull();
    expect(nextExpiryIn([msg("a", "m", ago(25))], NOW)).toBeNull(); // ya caducó
    expect(nextExpiryIn([msg("a", "m", ago(23)), msg("b", "m", ago(2))], NOW)).toBe(3600_000);
  });

  it("al juntar mensajes se quitan los caducados", () => {
    const merged = mergeFamily([msg("a", "m", ago(30))], [msg("b", "p", ago(1))], NOW);
    expect(merged.map((m) => m.id)).toEqual(["b"]);
  });

});

describe("chat familiar: mensajes", () => {
  it("quien escribe es «Tú» si eres tú, su nombre de usuario si es de la familia y «alguien» si ya no está", () => {
    const members = [{ id: "mama", username: "mamá" }, { id: "papa", username: "papá" }];
    expect(senderLabel({ sender_id: "papa" }, members, "papa")).toBe("Tú");
    expect(senderLabel({ sender_id: "mama" }, members, "papa")).toBe("mamá");
    expect(senderLabel({ sender_id: "otro" }, members, "papa")).toBe("alguien");
  });

  it("juntar mensajes no duplica por id, gana el del servidor y quedan de más antiguo a más nuevo", () => {
    const draft = { ...msg("x", "mama", ago(2)), local: "sending" as const };
    const merged = mergeFamily([draft, msg("a", "papa", ago(5))], [msg("x", "mama", ago(2), { body: "servidor" })], NOW);
    expect(merged.map((m) => m.id)).toEqual(["a", "x"]);
    expect(merged[1].body).toBe("servidor");
    expect(merged[1].local).toBeUndefined();
    expect(merged[1].sender_id).toBe("mama");
  });

  it("la fila del servidor se completa con lo que el chat necesita", () => {
    const m = fromRow({ id: "1", sender_id: "u", sender_device: "web", kind: "text", body: "hola", sent_at: ago(1), created_at: ago(1) });
    expect(m).toMatchObject({ conversation_id: FAMILY_CONVERSATION, status: "sent", deleted_at: null, attachments: [] });
  });

  it("el enunciado cuenta los mensajes que se ven y avisa de las 24 horas", () => {
    expect(familyStatement([], false)).toMatch(/Abriendo/);
    expect(familyStatement([], true)).toMatch(/24 horas/);
    expect(familyStatement([{ created_at: new Date().toISOString() }], true)).toMatch(/1 mensaje /);
    expect(familyStatement([], true, "Sin conexión")).toBe("Sin conexión");
  });

  it("el borrador lleva quien lo envía y la clase de su primer adjunto (imagen, video o documento)", () => {
    const att = (mime: string) => ({ storage_path: "p", file_name: "f", mime_type: mime, size_bytes: 1, width: null, height: null, duration_ms: null, thumb_path: null });
    const kind = (mime: string) => familyDraft(familyPayload("", "id", new Date(), [att(mime)]), "yo").kind;
    expect(kind("image/png")).toBe("image");
    expect(kind("video/mp4")).toBe("video");
    expect(kind("application/pdf")).toBe("file");
    expect(familyDraft(familyPayload("hola", "id"), "yo")).toMatchObject({ sender_id: "yo", kind: "text", body: "hola", local: "sending" });
  });
});

describe("chat familiar: el servidor", () => {
  it("lee la familia, lista los mensajes de las últimas 24 horas y los normaliza", async () => {
    const { client, rpcCalls } = fakeClient({
      rpc: {
        family_members: () => [{ id: "mama", username: "mamá" }],
        family_list_messages: () => [{ id: "1", sender_id: "mama", sender_device: "web", kind: "text", body: "hola", sent_at: ago(1), created_at: ago(1), attachments: [] }],
      },
    });
    expect(await familyMembers(client)).toEqual([{ id: "mama", username: "mamá" }]);
    const list = await listFamilyMessages(client, { after: "2026-01-01T00:00:00Z", limit: 20 });
    expect(list[0]).toMatchObject({ id: "1", conversation_id: FAMILY_CONVERSATION, deleted_at: null });
    expect(rpcCalls[1]).toEqual({ name: "family_list_messages", args: { p_before: null, p_after: "2026-01-01T00:00:00Z", p_limit: 20 } });
  });

  it("envía con el mismo id para poder reintentar sin duplicar", async () => {
    const { client, rpcCalls } = fakeClient({
      rpc: { family_send_message: (a) => ({ id: a.p_id, sender_id: "yo", sender_device: "web", kind: "text", body: a.p_body, sent_at: a.p_sent_at, created_at: a.p_sent_at, attachments: [] }) },
    });
    const payload = familyPayload("hola", "11111111-1111-1111-1111-111111111111", new Date("2026-11-15T12:00:00Z"));
    const sent = await sendFamilyMessage(client, payload);
    expect(rpcCalls[0]).toEqual({ name: "family_send_message", args: payload });
    expect(payload).toMatchObject({ p_id: "11111111-1111-1111-1111-111111111111", p_body: "hola", p_device: "web", p_attachments: [] });
    expect(sent.id).toBe(payload.p_id);
  });

  it("un error del servidor se lanza (por ejemplo, no ser de la familia)", async () => {
    const { client } = fakeClient({ rpc: { family_send_message: () => ({ error: { message: "not_family_member", code: "42501" } }) } });
    await expect(sendFamilyMessage(client, familyPayload("hola"))).rejects.toMatchObject({ code: "42501" });
  });

  it("los archivos se suben al bucket de la familia, en la carpeta de quien los envía", async () => {
    const { client, uploads } = fakeClient();
    const file = new File(["x"], "foto vacaciones.png", { type: "image/png" });
    const out = await uploadAttachments(client, "mama", FAMILY_CONVERSATION, "m1", [file], () => {}, FAMILY_BUCKET);
    expect(uploads).toEqual([{ bucket: "family-files", path: "mama/family/m1/foto_vacaciones.png", type: "image/png" }]);
    expect(out[0]).toMatchObject({ storage_path: "mama/family/m1/foto_vacaciones.png", mime_type: "image/png", file_name: "foto vacaciones.png" });
  });

  it("el chat General sigue subiendo a chat-files (el bucket no cambió por defecto)", async () => {
    const { client, uploads } = fakeClient();
    await uploadAttachments(client, "yo", "conv", "m1", [new File(["x"], "a.txt", { type: "text/plain" })]);
    expect(uploads[0].bucket).toBe("chat-files");
  });

  it("escucha los mensajes en vivo: avisa de nuevos y de borrados, y deja de escuchar al cerrar", async () => {
    const { client, emit, removedChannels } = fakeClient();
    const changes: { id: string; deleted: boolean }[] = [];
    const states: string[] = [];
    const stop = watchFamily(client, (c) => changes.push(c), (s) => states.push(s));
    await flush();
    emit("family_messages", "INSERT", { id: "a" });
    emit("family_messages", "DELETE", { id: "b" });
    expect(changes).toEqual([{ id: "a", deleted: false }, { id: "b", deleted: true }]);
    expect(states).toEqual(["connecting", "live"]);
    stop();
    expect(removedChannels).toHaveLength(1);
  });
});
