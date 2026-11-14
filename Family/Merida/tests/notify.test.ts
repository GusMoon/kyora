import { afterEach, describe, expect, it, vi } from "vitest";
import { countsAsUnread, notificationText, permission, shouldNotify, showNotification } from "../src/notify";
import type { Message } from "../src/data/chat";

const msg = (patch: Partial<Message> = {}): Message => ({
  id: "m1", conversation_id: "c", sender_device: "movil", kind: "text", body: "Hola desde el móvil", status: "sent",
  sent_at: "2026-11-13T10:00:00Z", created_at: "2026-11-13T10:00:00Z", deleted_at: null, attachments: [], ...patch,
});

afterEach(() => vi.unstubAllGlobals());

describe("avisos: cuándo avisar", () => {
  it("avisa de un mensaje de otro dispositivo si la pestaña está oculta o estás en otra sección", () => {
    expect(countsAsUnread(msg(), { hidden: true, route: "chat" })).toBe(true);
    expect(countsAsUnread(msg(), { hidden: false, route: "tareas" })).toBe(true);
    expect(countsAsUnread(msg(), { hidden: false, route: "inicio" })).toBe(true);
  });

  it("no avisa si lo estás viendo (chat abierto con la pestaña visible)", () => {
    expect(countsAsUnread(msg(), { hidden: false, route: "chat" })).toBe(false);
  });

  it("nunca avisa de lo que mandaste tú (web), de lo que se está enviando ni de lo borrado", () => {
    const away = { hidden: true, route: "tareas" };
    expect(countsAsUnread(msg({ sender_device: "web" }), away)).toBe(false);
    expect(countsAsUnread(msg({ local: "sending" }), away)).toBe(false);
    expect(countsAsUnread(msg({ deleted_at: "2026-11-13T11:00:00Z" }), away)).toBe(false);
  });

  it("para mostrar la notificación hace falta además la preferencia y el permiso", () => {
    const away = { hidden: true, route: "chat" };
    expect(shouldNotify(msg(), away, true, "granted")).toBe(true);
    expect(shouldNotify(msg(), away, false, "granted")).toBe(false); // apagado en Configuración
    expect(shouldNotify(msg(), away, true, "denied")).toBe(false);
    expect(shouldNotify(msg(), away, true, "default")).toBe(false);
    expect(shouldNotify(msg(), away, true, "unsupported")).toBe(false);
  });
});

describe("avisos: el texto", () => {
  it("el título dice de dónde viene y el cuerpo, lo que dice", () => {
    expect(notificationText(msg(), true)).toEqual({ title: "Kyora · móvil", body: "Hola desde el móvil" });
    expect(notificationText(msg({ sender_device: "pc" }), true).title).toBe("Kyora · pc");
  });

  it("con la vista previa apagada nunca enseña el texto", () => {
    expect(notificationText(msg({ body: "dato privado" }), false)).toEqual({ title: "Kyora · móvil", body: "Mensaje nuevo" });
  });

  it("nombra los archivos adjuntos y recorta los textos largos", () => {
    const one = msg({ body: null, attachments: [{ id: "a", storage_path: "p", file_name: "contrato.pdf", mime_type: "application/pdf", size_bytes: 1 }] });
    expect(notificationText(one, true).body).toBe("📎 contrato.pdf");
    const two = msg({ body: "mira", attachments: [one.attachments[0], one.attachments[0]] });
    expect(notificationText(two, true).body).toBe("mira  📎 2 archivos");
    const long = notificationText(msg({ body: "x".repeat(500) }), true).body;
    expect(long).toHaveLength(140);
    expect(long.endsWith("…")).toBe(true);
    expect(notificationText(msg({ body: "  " }), true).body).toBe("Mensaje nuevo");
  });
});

describe("avisos: mostrar", () => {
  function fakeNotification(perm: NotificationPermission) {
    const made: { title: string; opts: NotificationOptions; close: () => void; onclick?: () => void }[] = [];
    class N {
      static permission = perm;
      onclick: (() => void) | null = null;
      close = vi.fn();
      constructor(public title: string, public opts: NotificationOptions) {
        made.push(this as never);
      }
    }
    vi.stubGlobal("Notification", N);
    return made;
  }

  it("sin permiso no muestra nada", () => {
    const made = fakeNotification("denied");
    expect(showNotification(msg(), { preview: true, sound: false })).toBe(false);
    expect(made).toHaveLength(0);
  });

  it("con permiso crea la notificación con el id como etiqueta y, al pulsarla, enfoca la ventana y abre el chat", () => {
    const made = fakeNotification("granted");
    const focus = vi.spyOn(window, "focus").mockImplementation(() => {});
    const open = vi.fn();
    expect(showNotification(msg(), { preview: true, sound: false }, open)).toBe(true);
    expect(made[0].title).toBe("Kyora · móvil");
    expect(made[0].opts).toEqual({ body: "Hola desde el móvil", tag: "m1" });
    (made[0] as unknown as { onclick: () => void }).onclick();
    expect(focus).toHaveBeenCalled();
    expect(open).toHaveBeenCalled();
    expect((made[0] as unknown as { close: ReturnType<typeof vi.fn> }).close).toHaveBeenCalled();
    focus.mockRestore();
  });

  it("sin soporte del navegador, dice que no hay permiso y no se rompe", () => {
    vi.stubGlobal("Notification", undefined);
    expect(permission()).toBe("unsupported");
    expect(showNotification(msg(), { preview: true, sound: true })).toBe(false);
  });
});
