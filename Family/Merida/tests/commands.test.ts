import { describe, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import { addCommand, checkCommandInput, normalizeCommand, normalizeUrl, parseCommand, suggestCommands, type ChatCommand } from "../src/data/commands";

const yt: ChatCommand = { id: "1", name: "YouTube", command: "youtube", url: "https://youtube.com" };

describe("comandos del chat", () => {
  it("normaliza el comando: sin «/», sin espacios y en minúsculas", () => {
    expect(normalizeCommand(" /YouTube ")).toBe("youtube");
    expect(normalizeCommand("//gh")).toBe("gh");
  });

  it("la dirección: añade https:// si falta y rechaza lo que no es una web", () => {
    expect(normalizeUrl("youtube.com")).toBe("https://youtube.com");
    expect(normalizeUrl(" http://localhost:3000/x ")).toBe("http://localhost:3000/x");
    expect(normalizeUrl("javascript:alert(1)")).toBeNull();
    expect(normalizeUrl("ftp://sitio.com")).toBeNull();
    expect(normalizeUrl("dos palabras.com")).toBeNull();
    expect(normalizeUrl("")).toBeNull();
  });

  it("el formulario explica por qué no vale", () => {
    const bad = (name: string, command: string, url: string) => {
      const r = checkCommandInput({ name, command, url }, [yt]);
      return r.ok ? "ok" : r.error;
    };
    expect(bad("", "gh", "github.com")).toMatch(/nombre/);
    expect(bad("GitHub", "", "github.com")).toMatch(/comando/);
    expect(bad("GitHub", "mi web", "github.com")).toMatch(/letras sin acento/);
    expect(bad("GitHub", "YouTube", "github.com")).toBe("Ya existe el comando /youtube.");
    expect(bad("GitHub", "gh", "javascript:1")).toMatch(/dirección/);
    expect(checkCommandInput({ name: " GitHub ", command: "/GH", url: "github.com" }, [yt])).toEqual({
      ok: true,
      value: { name: "GitHub", command: "gh", url: "https://github.com" },
    });
  });

  it("reconoce «/comando» en el chat y no confunde rutas ni texto normal", () => {
    expect(parseCommand("/youtube", [yt])).toEqual({ kind: "open", command: yt });
    expect(parseCommand("  /YouTube  algo más ", [yt])).toEqual({ kind: "open", command: yt });
    expect(parseCommand("/nada", [yt])).toEqual({ kind: "unknown", name: "nada" });
    expect(parseCommand("/etc/hosts", [yt])).toEqual({ kind: "none" });
    expect(parseCommand("hola /youtube", [yt])).toEqual({ kind: "none" });
    expect(parseCommand("/", [yt])).toEqual({ kind: "none" });
  });

  it("sugiere al escribir «/»: primero los que empiezan igual, luego los que lo contienen, y nada tras un espacio", () => {
    const all: ChatCommand[] = [
      yt,
      { id: "2", name: "GitHub", command: "gh", url: "https://github.com" },
      { id: "3", name: "Mi YouTube Music", command: "music", url: "https://music.youtube.com" },
    ];
    expect(suggestCommands("/", all).map((c) => c.command)).toEqual(["gh", "music", "youtube"]);
    expect(suggestCommands("/Y", all).map((c) => c.command)).toEqual(["youtube", "music"]); // «music» por el nombre
    expect(suggestCommands("/gh", all).map((c) => c.command)).toEqual(["gh"]);
    expect(suggestCommands("/zzz", all)).toEqual([]);
    expect(suggestCommands("/youtube ", all)).toEqual([]);
    expect(suggestCommands("youtube", all)).toEqual([]);
    expect(suggestCommands("/", [])).toEqual([]);
  });

  it("al guardar manda nombre, comando y url a la tabla chat_commands", async () => {
    const single = vi.fn(async () => ({ data: yt, error: null }));
    const insert = vi.fn(() => ({ select: () => ({ single }) }));
    const from = vi.fn(() => ({ insert }));
    const created = await addCommand({ from } as unknown as SupabaseClient, { name: "YouTube", command: "youtube", url: "https://youtube.com" });
    expect(from).toHaveBeenCalledWith("chat_commands");
    expect(insert).toHaveBeenCalledWith({ name: "YouTube", command: "youtube", url: "https://youtube.com" });
    expect(created).toEqual(yt);
  });
});
