import { afterEach, describe, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import { chatSection } from "../src/sections/chat";
import { Shell } from "../src/ui/shell";
import { Store } from "../src/store";
import { Status } from "../src/status";
import { DEFAULT_PREFS, PrefsStore } from "../src/prefs";
import { Backdrop } from "../src/backdrop";
import { Library } from "../src/data/library";
import type { Player } from "../src/player";
import type { Ctx } from "../src/sections/context";

const COMMANDS = [
  { id: "1", name: "YouTube", command: "youtube", url: "https://youtube.com" },
  { id: "2", name: "GitHub", command: "gh", url: "https://github.com" },
];

/** Un Supabase de mentira que solo contesta la lista de comandos. */
function client(): SupabaseClient {
  const q: Record<string, unknown> = {};
  q.select = () => q;
  q.order = () => q;
  q.then = (res: (v: unknown) => unknown) => Promise.resolve({ data: COMMANDS, error: null }).then(res);
  return { from: () => q } as unknown as SupabaseClient;
}

const flush = async (n = 4) => {
  for (let i = 0; i < n; i++) await new Promise((r) => setTimeout(r, 0));
};

async function mount() {
  const store = new Store();
  store.conversationId = "conv";
  store.loaded.messages = true;
  const shell = new Shell({ store });
  document.body.append(shell.root);
  shell.setSection("chat", "");
  const ctx: Ctx = {
    client: client(),
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
  const unmount = chatSection(ctx);
  await flush();
  const text = shell.body.querySelector<HTMLTextAreaElement>("#chat-text")!;
  const list = shell.body.querySelector<HTMLElement>("#chat-cmd-list")!;
  text.focus();
  const type = (value: string) => {
    text.value = value;
    text.dispatchEvent(new Event("input", { bubbles: true }));
  };
  const key = (k: string) => {
    const ev = new KeyboardEvent("keydown", { key: k, bubbles: true, cancelable: true });
    text.dispatchEvent(ev);
    return ev;
  };
  const options = () => [...list.querySelectorAll<HTMLElement>("[role=option]")].map((o) => o.querySelector(".cmd-word")!.textContent);
  return { text, list, type, key, options, unmount, store };
}

afterEach(() => {
  document.body.replaceChildren();
  vi.restoreAllMocks();
});

describe("Chat: sugerencias al escribir «/»", () => {
  it("al escribir «/» aparecen los comandos y el foco sigue en el campo", async () => {
    const { text, list, type, options } = await mount();
    expect(list.hidden).toBe(true);
    type("/");
    expect(list.hidden).toBe(false);
    expect(options()).toEqual(["/gh", "/youtube"]);
    expect(document.activeElement).toBe(text);
    expect(text.getAttribute("aria-expanded")).toBe("true");
  });

  it("se filtra mientras se sigue escribiendo, y se puede escribir lo que sea", async () => {
    const { text, list, type, options } = await mount();
    type("/yo");
    expect(options()).toEqual(["/youtube"]);
    type("/yotu");
    expect(list.hidden).toBe(true); // ninguno coincide: se cierra y se sigue escribiendo
    expect(text.value).toBe("/yotu");
    type("hola");
    expect(list.hidden).toBe(true);
  });

  it("flechas mueven, Enter completa sin enviar y un segundo Enter ejecuta el comando", async () => {
    const { text, list, type, key, store } = await mount();
    const open = vi.spyOn(window, "open").mockReturnValue(null);
    type("/");
    key("ArrowDown");
    expect(list.querySelector("[aria-selected=true] .cmd-word")!.textContent).toBe("/youtube");
    const enter = key("Enter");
    expect(enter.defaultPrevented).toBe(true);
    expect(text.value).toBe("/youtube ");
    expect(list.hidden).toBe(true);
    expect(store.messages).toHaveLength(0); // no se mandó nada
    key("Enter"); // ya sin lista: envía, y «/youtube» abre la web en vez de mandar un mensaje
    expect(open).toHaveBeenCalledWith("https://youtube.com", "_blank", "noopener");
    expect(store.messages).toHaveLength(0);
  });

  it("si el comando ya está entero, Enter lo ejecuta directamente", async () => {
    const { type, key } = await mount();
    const open = vi.spyOn(window, "open").mockReturnValue(null);
    type("/gh");
    key("Enter");
    expect(open).toHaveBeenCalledWith("https://github.com", "_blank", "noopener");
  });

  it("Tab completa y Escape cierra sin perder lo escrito", async () => {
    const { text, list, type, key } = await mount();
    type("/y");
    expect(key("Tab").defaultPrevented).toBe(true);
    expect(text.value).toBe("/youtube ");
    type("/g");
    expect(list.hidden).toBe(false);
    key("Escape");
    expect(list.hidden).toBe(true);
    expect(text.value).toBe("/g");
    type("/gh"); // al cambiar el texto vuelve a abrirse
    expect(list.hidden).toBe(false);
  });

  it("elegir con el ratón completa el comando sin quitar el foco", async () => {
    const { text, list, type } = await mount();
    type("/");
    const option = list.querySelectorAll<HTMLElement>("[role=option]")[1];
    const down = new MouseEvent("mousedown", { bubbles: true, cancelable: true });
    option.dispatchEvent(down);
    expect(down.defaultPrevented).toBe(true); // así el campo no pierde el foco
    expect(text.value).toBe("/youtube ");
    expect(document.activeElement).toBe(text);
  });

  it("sin «/» nada cambia: Enter envía el mensaje como siempre", async () => {
    const { type, key, list, store } = await mount();
    type("hola");
    expect(list.hidden).toBe(true);
    const enter = key("Enter");
    expect(enter.defaultPrevented).toBe(true);
    expect(store.messages.some((m) => m.body === "hola")).toBe(true);
  });
});
