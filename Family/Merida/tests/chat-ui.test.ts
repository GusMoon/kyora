import { describe, expect, it } from "vitest";
import { dayLabel, withDays } from "../src/sections/chat";
import { deviceIconName } from "../src/ui/icons";
import type { Message } from "../src/data/chat";

const NOW = new Date(2026, 10, 12, 10, 0);
const msg = (id: string, at: Date, device = "pc"): Message => ({
  id, conversation_id: "c", sender_device: device, kind: "text", body: id, status: "sent",
  sent_at: at.toISOString(), created_at: at.toISOString(), deleted_at: null, attachments: [],
});

describe("chat como el de Kyra", () => {
  it("los separadores dicen Hoy, Ayer o la fecha (con el año si no es este)", () => {
    expect(dayLabel(new Date(2026, 10, 12, 8).toISOString(), NOW)).toBe("Hoy");
    expect(dayLabel(new Date(2026, 10, 11, 23).toISOString(), NOW)).toBe("Ayer");
    expect(dayLabel(new Date(2026, 9, 30, 12).toISOString(), NOW)).toBe("30 de octubre");
    expect(dayLabel(new Date(2025, 9, 30, 12).toISOString(), NOW)).toBe("30 de octubre de 2025");
  });

  it("pone un separador antes del primer mensaje de cada día", () => {
    const items = withDays([
      msg("a", new Date(2026, 10, 10, 9)),
      msg("b", new Date(2026, 10, 10, 18)),
      msg("c", new Date(2026, 10, 12, 8), "web"),
    ], NOW);
    expect(items.map((i) => (i.type === "day" ? `[${i.label}]` : i.message.id))).toEqual(["[10 de noviembre]", "a", "b", "[Hoy]", "c"]);
  });

  it("el icono del dispositivo: teléfono, PC, esta web u otro", () => {
    expect(deviceIconName("movil")).toBe("phone");
    expect(deviceIconName("móvil")).toBe("phone");
    expect(deviceIconName("pc")).toBe("pc");
    expect(deviceIconName("web")).toBe("web");
    expect(deviceIconName("laptop")).toBe("device");
  });
});
