import { afterEach, describe, expect, it } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import { clearConversation, deleteMessages, type Message } from "../src/data/chat";
import { deleteCloudFile, mergeCloud, type CloudFile } from "../src/data/cloud";
import { chatSection } from "../src/sections/chat";
import { cloudSection } from "../src/sections/cloud";
import { Shell } from "../src/ui/shell";
import { Store } from "../src/store";
import { Status } from "../src/status";
import { DEFAULT_PREFS, PrefsStore } from "../src/prefs";
import { Backdrop } from "../src/backdrop";
import { Library } from "../src/data/library";
import type { Player } from "../src/player";
import type { Ctx } from "../src/sections/context";

type Result = { data: unknown; error: unknown };
type Responses = Record<string, Result | ((ops: string[]) => Result)>;

/** Un Supabase de mentira: apunta cada llamada y contesta lo que se le diga («tabla.select» o «tabla.delete»). */
function fakeClient(responses: Responses = {}, storageError: unknown = null) {
  const log: string[] = [];
  const make = (table: string) => {
    const ops: string[] = [];
    const key = () => `${table}.${ops.includes("delete") ? "delete" : "select"}`;
    const result = (): Result => {
      const r = responses[key()];
      return typeof r === "function" ? r(ops) : (r ?? { data: [], error: null });
    };
    const q: Record<string, unknown> = {};
    const add = (name: string) => (...args: unknown[]) => {
      ops.push(args.length && name !== "select" ? `${name}:${args.join("=")}` : name);
      return q;
    };
    for (const name of ["select", "delete", "in", "eq", "order", "range"]) q[name] = add(name);
    q.maybeSingle = async () => {
      log.push(`${key()} ${ops.join(" ")}`);
      return result();
    };
    q.then = (res: (v: Result) => unknown, rej: (e: unknown) => unknown) => {
      log.push(`${key()} ${ops.join(" ")}`);
      return Promise.resolve(result()).then(res, rej);
    };
    return q;
  };
  const client = {
    from: make,
    storage: {
      from: () => ({
        remove: async (paths: string[]) => {
          log.push(`storage.remove ${paths.join(",")}`);
          return { data: [], error: storageError };
        },
        createSignedUrl: async () => ({ data: { signedUrl: "https://x/y" }, error: null }),
        createSignedUrls: async (paths: string[]) => ({ data: paths.map((path) => ({ path, signedUrl: `https://x/${path}` })), error: null }),
      }),
    },
  } as unknown as SupabaseClient;
  return { client, log };
}

const flush = async (n = 4) => {
  for (let i = 0; i < n; i++) await new Promise((r) => setTimeout(r, 0));
};

const chatFile = (over: Partial<CloudFile> = {}): CloudFile => ({ id: "chat:a1", source: "chat", path: "u/c/m1/foto.jpg", name: "foto.jpg", mime: "image/jpeg", size: 100, at: "2026-11-12T10:00:00Z", from: "pc", kind: "image", messageId: "m1", thumbPath: "u/c/m1/foto.thumb.jpg", ...over });
const musicFile = (): CloudFile => ({ id: "music:t1", source: "music", path: "u/music/a.mp3", name: "a.mp3", mime: "audio/mpeg", size: 100, at: "2026-11-12T10:00:00Z", from: "para ti", kind: "audio" });

afterEach(() => {
  document.body.replaceChildren();
});

describe("borrar mensajes de verdad", () => {
  it("primero los archivos en Storage (y miniaturas) y luego los mensajes", async () => {
    const { client, log } = fakeClient({
      "attachments.select": { data: [{ storage_path: "u/c/m1/foto.jpg", thumb_path: "u/c/m1/foto.thumb.jpg" }, { storage_path: "u/c/m1/foto.jpg", thumb_path: null }], error: null },
      "messages.delete": { data: [{ id: "m1" }], error: null },
    });
    expect(await deleteMessages(client, ["m1"])).toEqual(["m1"]);
    const order = log.map((l) => l.split(" ")[0]);
    expect(order).toEqual(["attachments.select", "storage.remove", "messages.delete"]);
    expect(log[1]).toBe("storage.remove u/c/m1/foto.jpg,u/c/m1/foto.thumb.jpg"); // sin repetir
  });

  it("si Storage falla, no toca la base (se puede reintentar)", async () => {
    const { client, log } = fakeClient({ "attachments.select": { data: [{ storage_path: "p", thumb_path: null }], error: null } }, { message: "boom" });
    await expect(deleteMessages(client, ["m1"])).rejects.toMatchObject({ message: "boom" });
    expect(log.some((l) => l.startsWith("messages.delete"))).toBe(false);
  });

  it("sin adjuntos no llama a Storage, y los ids largos se borran por tandas", async () => {
    const ids = Array.from({ length: 230 }, (_, i) => `m${i}`);
    const { client, log } = fakeClient({ "messages.delete": (ops) => ({ data: ops.find((o) => o.startsWith("in:"))!.split("=")[1].split(",").map((id) => ({ id })), error: null }) });
    expect((await deleteMessages(client, ids)).length).toBe(230);
    expect(log.filter((l) => l.startsWith("messages.delete"))).toHaveLength(3);
    expect(log.some((l) => l.startsWith("storage.remove"))).toBe(false);
  });

  it("vaciar la conversación borra todos sus mensajes y dice cuántos", async () => {
    const { client } = fakeClient({
      "messages.select": { data: [{ id: "a" }, { id: "b" }, { id: "c" }], error: null },
      "messages.delete": { data: [{ id: "a" }, { id: "b" }], error: null }, // el servidor dejó borrar solo dos
    });
    expect(await clearConversation(client, "conv")).toEqual({ deleted: 2, total: 3 });
  });
});

describe("borrar un archivo de la nube", () => {
  it("un adjunto del chat: archivo, miniatura y fila; si el mensaje queda vacío, también el mensaje", async () => {
    const { client, log } = fakeClient({
      "attachments.delete": { data: [{ id: "a1" }], error: null },
      "messages.select": { data: { id: "m1", body: "", attachments: [] }, error: null },
      "messages.delete": { data: [{ id: "m1" }], error: null },
    });
    const res = await deleteCloudFile(client, chatFile());
    expect(res).toEqual({ messageDeleted: "m1" });
    expect(log[0]).toBe("storage.remove u/c/m1/foto.jpg,u/c/m1/foto.thumb.jpg");
    expect(log.map((l) => l.split(" ")[0])).toEqual(["storage.remove", "attachments.delete", "messages.select", "attachments.select", "messages.delete"]);
  });

  it("si el mensaje tiene texto, se queda (sin el adjunto)", async () => {
    const { client, log } = fakeClient({
      "attachments.delete": { data: [{ id: "a1" }], error: null },
      "messages.select": { data: { id: "m1", body: "mira esto", attachments: [] }, error: null },
    });
    expect(await deleteCloudFile(client, chatFile())).toEqual({ messageKept: "m1" });
    expect(log.some((l) => l.startsWith("messages.delete"))).toBe(false);
  });

  it("una canción: el MP3 y todas sus filas (para todos los destinatarios)", async () => {
    const { client, log } = fakeClient({ "music_tracks.delete": { data: [{ id: "t1" }, { id: "t2" }], error: null } });
    expect(await deleteCloudFile(client, musicFile())).toEqual({});
    expect(log).toEqual(["storage.remove u/music/a.mp3", "music_tracks.delete delete eq:storage_path=u/music/a.mp3 select"]);
  });

  it("si el servidor no deja borrar (no es tuyo), lo dice en lugar de fingir", async () => {
    const { client } = fakeClient({ "music_tracks.delete": { data: [], error: null } });
    await expect(deleteCloudFile(client, musicFile())).rejects.toThrow(/no dejó borrar/);
  });

  it("nunca llama a «Recibido»", async () => {
    const { client, log } = fakeClient({ "attachments.delete": { data: [{ id: "a1" }], error: null }, "messages.select": { data: null, error: null } });
    await deleteCloudFile(client, chatFile());
    expect(log.join()).not.toMatch(/confirm/);
  });
});

function mountSection(section: typeof cloudSection | typeof chatSection, route: "nube" | "chat", client: SupabaseClient, store = new Store()) {
  const shell = new Shell({ store });
  document.body.append(shell.root);
  shell.setSection(route, "");
  const ctx: Ctx = {
    client,
    shell,
    store,
    player: {} as Player,
    status: new Status(),
    prefs: new PrefsStore({ ...DEFAULT_PREFS }),
    backdrop: new Backdrop({ storage: null }),
    library: new Library(),
    vault: {} as never,
    userId: "u",
    signOut() {},
    reload: async () => {},
  };
  const unmount = section(ctx);
  return { shell, store, unmount };
}

const button = (root: ParentNode, text: string) => [...root.querySelectorAll("button")].find((b) => b.textContent?.trim() === text) as HTMLButtonElement;

describe("Nube: eliminar", () => {
  it("pide confirmación, borra de verdad y quita la tarjeta (y el mensaje vacío del chat)", async () => {
    const { client, log } = fakeClient({
      "attachments.delete": { data: [{ id: "a1" }], error: null },
      "messages.select": { data: { id: "m1", body: null, attachments: [] }, error: null },
      "messages.delete": { data: [{ id: "m1" }], error: null },
    });
    const store = new Store();
    store.files = [chatFile()];
    store.loaded.files = true;
    store.messages = [{ id: "m1", conversation_id: "c", sender_device: "pc", kind: "image", body: null, status: "sent", sent_at: "2026-11-12T10:00:00Z", created_at: "2026-11-12T10:00:00Z", deleted_at: null, attachments: [] } as Message];
    const { shell, unmount } = mountSection(cloudSection, "nube", client, store);
    await flush();
    expect(shell.body.querySelector(".cloud-name")?.textContent).toBe("foto.jpg");
    button(shell.body, "Eliminar").click();
    expect(shell.body.querySelector(".cloud-confirm")?.textContent).toContain("No se puede deshacer");
    expect(log.some((l) => l.startsWith("storage.remove"))).toBe(false); // todavía nada
    button(shell.body, "Cancelar").click();
    expect(button(shell.body, "Eliminar")).toBeTruthy();
    button(shell.body, "Eliminar").click();
    button(shell.body, "Sí, eliminar").click();
    await flush(8);
    expect(log.some((l) => l.startsWith("storage.remove u/c/m1/foto.jpg"))).toBe(true);
    expect(store.files).toHaveLength(0);
    expect(store.messages).toHaveLength(0);
    expect(shell.body.querySelector(".cloud-card")).toBeNull();
    unmount();
  });

  it("una canción avisa de que se borra para todos, y la quita de Música", async () => {
    const { client } = fakeClient({ "music_tracks.delete": { data: [{ id: "t1" }], error: null } });
    const store = new Store();
    store.files = [musicFile()];
    store.tracks = [{ id: "t1", title: "A", file_name: "a.mp3", storage_path: "u/music/a.mp3", mime_type: "audio/mpeg", size_bytes: 1, playlist: null, cover_url: null, created_at: "2026-11-12T10:00:00Z", received_at: null }];
    store.loaded.files = true;
    const { shell, unmount } = mountSection(cloudSection, "nube", client, store);
    await flush();
    button(shell.body, "Eliminar").click();
    expect(shell.body.querySelector(".cloud-confirm")?.textContent).toContain("para todos los que la tienen");
    button(shell.body, "Sí, eliminar").click();
    await flush(8);
    expect(store.files).toHaveLength(0);
    expect(store.tracks).toHaveLength(0);
    unmount();
  });

  it("si el servidor no deja, el archivo sigue y se ve el motivo", async () => {
    const { client } = fakeClient({ "music_tracks.delete": { data: [], error: null } });
    const store = new Store();
    store.files = [musicFile()];
    store.loaded.files = true;
    const { shell, unmount } = mountSection(cloudSection, "nube", client, store);
    await flush();
    button(shell.body, "Eliminar").click();
    button(shell.body, "Sí, eliminar").click();
    await flush(8);
    expect(store.files).toHaveLength(1);
    expect(shell.body.querySelector(".form-error")?.textContent).toContain("No se pudo eliminar a.mp3");
    unmount();
  });
});

describe("Chat: borrar", () => {
  const message = (id: string, body: string, local?: "sending"): Message => ({
    id, conversation_id: "conv", sender_device: "pc", kind: "text", body, status: "sent",
    sent_at: "2026-11-12T10:00:00Z", created_at: "2026-11-12T10:00:00Z", deleted_at: null, attachments: [], ...(local ? { local } : {}),
  });

  it("cada mensaje tiene Borrar, pide confirmación y lo borra del servidor", async () => {
    const { client, log } = fakeClient({ "messages.delete": { data: [{ id: "m1" }], error: null } });
    const store = new Store();
    store.messages = [message("m1", "hola"), message("m2", "adiós")];
    store.loaded.messages = true;
    store.files = [chatFile()];
    store.conversationId = "conv";
    const { shell, unmount } = mountSection(chatSection, "chat", client, store);
    const del = shell.body.querySelectorAll<HTMLButtonElement>(".msg-del");
    expect(del).toHaveLength(2);
    del[0].click();
    expect(shell.body.textContent).toContain("¿Borrar del servidor?");
    button(shell.body, "No").click();
    expect(shell.body.textContent).not.toContain("¿Borrar del servidor?");
    shell.body.querySelectorAll<HTMLButtonElement>(".msg-del")[0].click();
    button(shell.body, "Sí").click();
    await flush(8);
    expect(log.some((l) => l.startsWith("messages.delete") && l.includes("m1"))).toBe(true);
    expect(store.messages.map((m) => m.id)).toEqual(["m2"]);
    expect(store.files).toHaveLength(0); // su adjunto también sale de la nube
    unmount();
  });

  it("lo que aún se está enviando no se puede borrar", () => {
    const { client } = fakeClient();
    const store = new Store();
    store.messages = [message("l1", "enviando…", "sending")];
    store.loaded.messages = true;
    const { shell, unmount } = mountSection(chatSection, "chat", client, store);
    expect(shell.body.querySelector(".msg-del")).toBeNull();
    unmount();
  });

  it("«Vaciar chat» pide confirmación y borra la conversación entera", async () => {
    const { client, log } = fakeClient({
      "messages.select": { data: [{ id: "m1" }, { id: "m2" }], error: null },
      "messages.delete": { data: [{ id: "m1" }, { id: "m2" }], error: null },
    });
    const store = new Store();
    store.messages = [message("m1", "hola"), message("m2", "adiós")];
    store.loaded.messages = true;
    store.conversationId = "conv";
    const { shell, unmount } = mountSection(chatSection, "chat", client, store);
    button(shell.body, "Vaciar chat").click();
    expect(shell.body.querySelector(".chat-confirm")?.textContent).toContain("los 2 mensajes y sus archivos del servidor");
    expect(log).toHaveLength(0); // todavía nada
    button(shell.body, "Sí, vaciar todo").click();
    await flush(10);
    expect(log.some((l) => l.startsWith("messages.delete"))).toBe(true);
    expect(store.messages).toHaveLength(0);
    expect(shell.root.querySelector(".tile-chat .tile-statement")?.textContent).toBe("La conversación General está vacía. Escribe el primer mensaje.");
    expect(button(shell.body, "Vaciar chat").disabled).toBe(true);
    unmount();
  });

  it("con un chat vacío no hay nada que vaciar; y se puede cancelar", () => {
    const { client } = fakeClient();
    const store = new Store();
    store.loaded.messages = true;
    store.conversationId = "conv";
    const empty = mountSection(chatSection, "chat", client, store);
    expect(button(empty.shell.body, "Vaciar chat").disabled).toBe(true);
    empty.unmount();
    document.body.replaceChildren();

    const store2 = new Store();
    store2.messages = [message("m1", "hola")];
    store2.loaded.messages = true;
    store2.conversationId = "conv";
    const { shell, unmount } = mountSection(chatSection, "chat", client, store2);
    button(shell.body, "Vaciar chat").click();
    button(shell.body, "Cancelar").click();
    expect(button(shell.body, "Vaciar chat")).toBeTruthy();
    expect(store2.messages).toHaveLength(1);
    unmount();
  });
});

describe("mergeCloud guarda lo necesario para borrar", () => {
  it("el mensaje y la miniatura de cada adjunto", () => {
    const [f] = mergeCloud([{ id: "a1", message_id: "m1", thumb_path: "t.jpg", storage_path: "p.jpg", file_name: "p.jpg", mime_type: "image/jpeg", size_bytes: 1, created_at: "2026-11-12T10:00:00Z", message: { sender_device: "pc", deleted_at: null } }], [], "me");
    expect(f).toMatchObject({ messageId: "m1", thumbPath: "t.jpg" });
  });
});
