import type { SupabaseClient } from "@supabase/supabase-js";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { Backdrop } from "../src/backdrop";
import { CallController } from "../src/data/call-controller";
import { Library } from "../src/data/library";
import type { Player } from "../src/player";
import { DEFAULT_PREFS, PrefsStore } from "../src/prefs";
import { chatSection } from "../src/sections/chat";
import type { Ctx } from "../src/sections/context";
import { familyChatView } from "../src/sections/family-chat";
import { Status } from "../src/status";
import { Store } from "../src/store";
import { Shell } from "../src/ui/shell";
import { fakeClient, fakeEnv, type FakeOptions } from "./family-fakes";

const NOW = Date.parse("2026-11-15T12:00:00Z");
const ago = (h: number) => new Date(NOW - h * 3600_000).toISOString();
const MEMBERS = [{ id: "mama", username: "mamá" }, { id: "papa", username: "papá" }];

const serverMsg = (id: string, sender: string, createdAt: string, extra: Record<string, unknown> = {}) => ({
  id, sender_id: sender, sender_device: "web", kind: "text", body: id, sent_at: createdAt, created_at: createdAt, attachments: [], ...extra,
});

/** Un `family_send_message` que contesta lo que el servidor devolvería. */
const echo = (userId: string) => (a: Record<string, unknown>) => ({
  id: a.p_id, sender_id: userId, sender_device: "web", kind: (a.p_attachments as { mime_type: string }[])[0] ? "file" : "text", body: a.p_body || null,
  sent_at: a.p_sent_at, created_at: a.p_sent_at, attachments: ((a.p_attachments as object[]) ?? []).map((x, i) => ({ id: `${a.p_id}:${i}`, ...x })),
});

function mount(opts: { userId?: string; members?: typeof MEMBERS; messages?: unknown[]; rpc?: FakeOptions["rpc"]; storeSetup?: (s: Store) => void; section?: "view" | "chat" } = {}) {
  const userId = opts.userId ?? "mama";
  const fake = fakeClient({
    rpc: {
      family_members: () => opts.members ?? MEMBERS,
      family_list_messages: () => opts.messages ?? [],
      family_send_message: echo(userId),
      ...opts.rpc,
    },
  });
  const env = fakeEnv();
  const calls = new CallController({ client: fake.client, userId, env: env.env, members: () => opts.members ?? MEMBERS });
  const store = new Store();
  opts.storeSetup?.(store);
  const prefs = new PrefsStore({ ...DEFAULT_PREFS, keys: { ...DEFAULT_PREFS.keys } });
  const shell = new Shell({ store, prefs });
  document.body.append(shell.root);
  shell.setSection("chat", "");
  const ctx: Ctx = {
    client: fake.client as SupabaseClient, shell, store, player: {} as Player, status: new Status(), prefs, backdrop: new Backdrop({ storage: null }), library: new Library(),
    vault: {} as never, userId, calls, signOut() {}, reload: vi.fn(async () => {}),
  };
  const out = opts.section === "chat" ? { unmount: chatSection(ctx), view: null } : (() => { const v = familyChatView(ctx); shell.body.append(v.el); return { unmount: v.destroy, view: v }; })();
  return { ...fake, ...env, ctx, shell, store, calls, ...out };
}

const typeInto = (el: HTMLTextAreaElement, value: string) => {
  el.value = value;
  el.dispatchEvent(new Event("input", { bubbles: true }));
};
const submit = (form: HTMLFormElement) => form.dispatchEvent(new Event("submit", { bubbles: true, cancelable: true }));
const pickFiles = (input: HTMLInputElement, files: File[]) => {
  Object.defineProperty(input, "files", { value: files, configurable: true });
  input.dispatchEvent(new Event("change", { bubbles: true }));
};

beforeEach(() => vi.useFakeTimers({ now: NOW, toFake: ["setTimeout", "clearTimeout", "setInterval", "clearInterval", "Date"] }));
afterEach(() => {
  document.body.replaceChildren();
  location.hash = "";
  vi.useRealTimers();
  vi.restoreAllMocks();
});

const settle = async () => {
  await vi.advanceTimersByTimeAsync(10);
  for (let i = 0; i < 4; i++) await Promise.resolve();
};
const texts = (el: HTMLElement, sel: string) => [...el.querySelectorAll(sel)].map((n) => n.textContent);

describe("chat familiar: lo que se ve", () => {
  it("lista los mensajes con el nombre de quien los escribió, marca los propios y quita los de más de 24 horas", async () => {
    const { shell } = mount({ messages: [serverMsg("viejo", "papa", ago(25)), serverMsg("hola", "papa", ago(3)), serverMsg("ya voy", "mama", ago(1))] });
    await settle();
    expect(texts(shell.body, ".msg-text")).toEqual(["hola", "ya voy"]);
    expect(texts(shell.body, ".fam-sender")).toEqual(["papá", "Tú"]);
    expect([...shell.body.querySelectorAll(".msg")].map((m) => m.classList.contains("is-mine"))).toEqual([false, true]);
    expect(shell.body.querySelector(".fam-note")?.textContent).toMatch(/24 horas/);
    expect(shell.body.closest(".tile")?.querySelector(".tile-statement")?.textContent).toMatch(/2 mensajes/);
  });

  it("un mensaje desaparece de la pantalla justo cuando cumple 24 horas, sin recargar", async () => {
    const { shell } = mount({ messages: [serverMsg("casi", "papa", new Date(NOW - 24 * 3600_000 + 5000).toISOString())] });
    await settle();
    expect(texts(shell.body, ".msg-text")).toEqual(["casi"]);
    await vi.advanceTimersByTimeAsync(6000);
    expect(shell.body.querySelectorAll(".msg")).toHaveLength(0);
    expect(shell.body.querySelector(".chat-empty")?.textContent).toMatch(/sin mensajes/);
  });

  it("imágenes, videos y documentos se enseñan cada uno a su manera", async () => {
    const attachments = [
      { id: "a1", storage_path: "papa/family/m/foto.png", file_name: "foto.png", mime_type: "image/png", size_bytes: 1000 },
      { id: "a2", storage_path: "papa/family/m/clip.mp4", file_name: "clip.mp4", mime_type: "video/mp4", size_bytes: 5000 },
      { id: "a3", storage_path: "papa/family/m/receta.pdf", file_name: "receta.pdf", mime_type: "application/pdf", size_bytes: 2000 },
    ];
    const { shell } = mount({ messages: [serverMsg("m", "papa", ago(1), { kind: "image", body: null, attachments })] });
    await settle();
    const img = shell.body.querySelector<HTMLImageElement>("img.msg-img")!;
    const video = shell.body.querySelector<HTMLVideoElement>("video.msg-video")!;
    expect(img.src).toBe("https://files.test/family-files/papa/family/m/foto.png?token=t"); // firmada, del bucket de la familia
    expect(video.src).toContain("/family-files/papa/family/m/clip.mp4");
    expect(video.hasAttribute("controls")).toBe(true);
    // cada archivo, también las fotos y los videos, tiene su enlace con el nombre (el texto suelto entre «:: » y el tamaño)
    expect([...shell.body.querySelectorAll(".msg-file")].map((b) => b.childNodes[1].textContent)).toEqual(["foto.png", "clip.mp4", "receta.pdf"]);
    expect(shell.body.querySelectorAll(".msg-files li")).toHaveLength(3);
  });

  it("quien no está en la familia lo ve, no puede escribir ni llamar", async () => {
    const { shell, rpcCalls } = mount({ members: [], userId: "extraño" });
    await settle();
    expect(shell.body.querySelector(".chat-empty")?.textContent).toMatch(/no estás en la familia/);
    expect(shell.body.querySelector<HTMLTextAreaElement>("#fam-text")!.disabled).toBe(true);
    expect([...shell.body.querySelectorAll<HTMLButtonElement>("[data-call-start]")].every((b) => b.disabled)).toBe(true);
    submit(shell.body.querySelector("form")!);
    expect(rpcCalls.some((c) => c.name === "family_send_message")).toBe(false);
  });

  it("si el servidor falla al abrir, lo dice", async () => {
    const { shell } = mount({ rpc: { family_list_messages: () => ({ error: { message: "Failed to fetch" } }) } });
    await settle();
    expect(shell.body.querySelector(".form-error")?.textContent).toMatch(/No se pudo abrir el chat de la familia/);
  });
});

describe("chat familiar: enviar", () => {
  it("envía un mensaje de texto: sale en la lista, queda enviado y se vacía el campo", async () => {
    const { shell, rpcCalls } = mount();
    await settle();
    const text = shell.body.querySelector<HTMLTextAreaElement>("#fam-text")!;
    typeInto(text, "  ¿Quién compra el pan?  ");
    submit(shell.body.querySelector("form")!);
    await settle();
    const sent = rpcCalls.find((c) => c.name === "family_send_message")!;
    expect(sent.args).toMatchObject({ p_body: "¿Quién compra el pan?", p_device: "web", p_attachments: [] });
    expect(sent.args.p_id).toMatch(/^[0-9a-f-]{36}$/);
    expect(text.value).toBe("");
    expect(texts(shell.body, ".msg-text")).toEqual(["¿Quién compra el pan?"]);
    expect(shell.body.querySelector(".msg-check")).not.toBeNull();
  });

  it("un campo vacío no envía nada", async () => {
    const { shell, rpcCalls } = mount();
    await settle();
    submit(shell.body.querySelector("form")!);
    expect(rpcCalls.some((c) => c.name === "family_send_message")).toBe(false);
  });

  it("envía una imagen, un video y un documento: los sube al bucket de la familia y manda sus datos", async () => {
    const { shell, rpcCalls, uploads } = mount();
    await settle();
    const files = [new File(["i"], "foto.png", { type: "image/png" }), new File(["v"], "clip.mp4", { type: "video/mp4" }), new File(["d"], "receta.pdf", { type: "application/pdf" })];
    pickFiles(shell.body.querySelector<HTMLInputElement>("#fam-files")!, files);
    expect(texts(shell.body, ".staged-name")).toEqual(["foto.png", "clip.mp4", "receta.pdf"]);
    submit(shell.body.querySelector("form")!);
    await settle();
    expect(uploads.map((u) => [u.bucket, u.path.replace(/[0-9a-f-]{36}/, "<id>"), u.type])).toEqual([
      ["family-files", "mama/family/<id>/foto.png", "image/png"],
      ["family-files", "mama/family/<id>/clip.mp4", "video/mp4"],
      ["family-files", "mama/family/<id>/receta.pdf", "application/pdf"],
    ]);
    const att = (rpcCalls.find((c) => c.name === "family_send_message")!.args.p_attachments as { file_name: string; mime_type: string }[]).map((a) => [a.file_name, a.mime_type]);
    expect(att).toEqual([["foto.png", "image/png"], ["clip.mp4", "video/mp4"], ["receta.pdf", "application/pdf"]]);
    expect(shell.body.querySelectorAll(".staged-item")).toHaveLength(0); // ya no quedan por enviar
    expect(shell.body.querySelectorAll(".msg-files li")).toHaveLength(3);
  });

  it("un archivo vacío o demasiado grande se rechaza con su motivo", async () => {
    const { shell } = mount();
    await settle();
    const huge = new File(["x"], "enorme.mov", { type: "video/quicktime" });
    Object.defineProperty(huge, "size", { value: 60 * 1024 * 1024 });
    pickFiles(shell.body.querySelector<HTMLInputElement>("#fam-files")!, [new File([], "vacio.txt"), huge]);
    expect(shell.body.querySelector(".form-error")?.textContent).toMatch(/vacío/);
    expect(shell.body.querySelector(".form-error")?.textContent).toMatch(/límite/);
    expect(shell.body.querySelectorAll(".staged-item")).toHaveLength(0);
  });

  it("si falla el envío queda «no se envió» y Reintentar usa el mismo id sin duplicar", async () => {
    let failing = true;
    const { shell, rpcCalls } = mount({ rpc: { family_send_message: (a) => (failing ? { error: { message: "Failed to fetch" } } : echo("mama")(a)) } });
    await settle();
    typeInto(shell.body.querySelector<HTMLTextAreaElement>("#fam-text")!, "hola");
    submit(shell.body.querySelector("form")!);
    await settle();
    expect(shell.body.querySelector(".msg-error")?.textContent).toMatch(/no se envió/);
    failing = false;
    shell.body.querySelector<HTMLButtonElement>("[data-retry]")!.click();
    await settle();
    const ids = rpcCalls.filter((c) => c.name === "family_send_message").map((c) => c.args.p_id);
    expect(ids).toHaveLength(2);
    expect(ids[0]).toBe(ids[1]);
    expect(shell.body.querySelectorAll(".msg")).toHaveLength(1);
    expect(shell.body.querySelector(".msg-error")).toBeNull();
  });

  it("Enter envía y Mayús+Enter hace salto de línea", async () => {
    const { shell, rpcCalls } = mount();
    await settle();
    const text = shell.body.querySelector<HTMLTextAreaElement>("#fam-text")!;
    typeInto(text, "uno");
    text.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", shiftKey: true, bubbles: true, cancelable: true }));
    expect(rpcCalls.some((c) => c.name === "family_send_message")).toBe(false);
    const form = shell.body.querySelector("form")!;
    form.requestSubmit = () => submit(form); // jsdom no trae requestSubmit completo
    text.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }));
    await settle();
    expect(rpcCalls.some((c) => c.name === "family_send_message")).toBe(true);
  });
});

describe("chat familiar: en vivo y llamadas", () => {
  it("un mensaje de otra persona aparece solo, y uno borrado se quita", async () => {
    let list: unknown[] = [serverMsg("a", "papa", ago(2))];
    const { shell, emit, rpcCalls } = mount({ rpc: { family_list_messages: () => list } });
    await settle();
    list = [serverMsg("b", "papa", ago(0.01))];
    emit("family_messages", "INSERT", { id: "b" });
    await settle();
    expect(texts(shell.body, ".msg-text")).toEqual(["a", "b"]);
    const lastList = rpcCalls.filter((c) => c.name === "family_list_messages").at(-1)!;
    expect(lastList.args.p_after).toBe(ago(2)); // solo pide lo posterior a lo último que tenía
    emit("family_messages", "DELETE", { id: "a" });
    await settle();
    expect(texts(shell.body, ".msg-text")).toEqual(["b"]);
  });

  it("deja de escuchar al cerrar la vista", async () => {
    const { unmount, removedChannels } = mount();
    await settle();
    unmount();
    expect(removedChannels).toHaveLength(1);
  });

  it("los botones llaman a la familia: de voz o de video", async () => {
    const { shell, calls, requested } = mount();
    await settle();
    shell.body.querySelector<HTMLButtonElement>('[data-call-start="video"]')!.click();
    await settle();
    expect(calls.view).toMatchObject({ phase: "calling", kind: "video" });
    expect(requested[0].video).toBe(true);
    // mientras hay una llamada no se puede empezar otra
    expect([...shell.body.querySelectorAll<HTMLButtonElement>("[data-call-start]")].every((b) => b.disabled)).toBe(true);
  });
});

describe("la sección Chat: pestañas General | Familia", () => {
  const tab = (shell: Shell, name: string) => shell.body.querySelector<HTMLButtonElement>(`[data-tab="${name}"]`)!;

  it("abre en General y Familia se monta solo al pulsarla, sin tocar General", async () => {
    const { shell, unmount } = mount({ section: "chat" });
    expect(tab(shell, "general").getAttribute("aria-selected")).toBe("true");
    expect(shell.body.querySelector(".fam")).toBeNull();
    tab(shell, "familia").click();
    await settle();
    expect(shell.body.querySelector(".fam")).not.toBeNull();
    expect(shell.body.querySelector<HTMLElement>(".chat-wrap > .chat:not(.fam)")!.hidden).toBe(true);
    expect(tab(shell, "familia").getAttribute("aria-selected")).toBe("true");
    tab(shell, "general").click();
    expect(shell.body.querySelector(".fam")).toBeNull();
    expect(shell.body.querySelector<HTMLElement>(".chat-wrap > .chat")!.hidden).toBe(false);
    unmount();
  });

  it("una cuenta que no puede usar General (no es la del administrador) entra directo a Familia", async () => {
    const { shell } = mount({ section: "chat", storeSetup: (s) => s.fail("messages", "No tienes permiso") });
    await settle();
    expect(shell.body.querySelector(".fam")).not.toBeNull();
    expect(tab(shell, "familia").getAttribute("aria-selected")).toBe("true");
  });

  it("si llega el error después de abrir, también cambia sola, salvo que ya hayas elegido tú", async () => {
    const auto = mount({ section: "chat" });
    auto.store.fail("messages", "No tienes permiso");
    auto.store.emit("messages");
    await settle();
    expect(auto.shell.body.querySelector(".fam")).not.toBeNull();
    document.body.replaceChildren();

    const chosen = mount({ section: "chat" });
    tab(chosen.shell, "general").click(); // la persona eligió General
    chosen.store.fail("messages", "No tienes permiso");
    chosen.store.emit("messages");
    await settle();
    expect(chosen.shell.body.querySelector(".fam")).toBeNull();
  });

  it("al desmontar la sección se cierra también la vista de la familia", async () => {
    const { shell, unmount, removedChannels } = mount({ section: "chat" });
    tab(shell, "familia").click();
    await settle();
    unmount();
    expect(removedChannels).toHaveLength(1);
  });
});
