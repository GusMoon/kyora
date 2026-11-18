import { describe, expect, it } from "vitest";
import { FAMILY_TTL_HOURS, expiryCutoff, filesOf } from "../../../Server/supabase/functions/cleanup-expired/cutoff";
import { FAMILY_TTL_MS } from "../src/data/family-chat";

/** La limpieza automática del chat familiar (Server/supabase/functions/cleanup-expired): lo puro, sin Deno ni red. */

const NOW = Date.parse("2026-11-15T12:00:00Z");

describe("limpieza del chat familiar a las 24 horas", () => {
  it("el servidor y Merida cuentan las mismas 24 horas", () => {
    expect(FAMILY_TTL_HOURS * 3600 * 1000).toBe(FAMILY_TTL_MS);
  });

  it("la hora de corte es 24 horas antes de ahora, en ISO 8601", () => {
    expect(expiryCutoff(NOW)).toBe("2026-11-14T12:00:00.000Z");
    expect(expiryCutoff(NOW, 1)).toBe("2026-11-15T11:00:00.000Z");
  });

  it("junta los archivos de los mensajes (adjuntos y miniaturas) sin repetir ni dejar vacíos", () => {
    expect(
      filesOf([
        { attachments: [{ storage_path: "u/family/1/a.jpg", thumb_path: "u/family/1/a-t.jpg" }, { storage_path: "u/family/1/a.jpg" }] },
        { attachments: null },
        {},
        { attachments: [{ storage_path: null, thumb_path: undefined }, { storage_path: "u/family/2/b.pdf" }] },
      ]),
    ).toEqual(["u/family/1/a.jpg", "u/family/1/a-t.jpg", "u/family/2/b.pdf"]);
    expect(filesOf([])).toEqual([]);
  });
});
