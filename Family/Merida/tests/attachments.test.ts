import { describe, expect, it, vi } from "vitest";
import { MAX_BYTES, MAX_FILES, checkFiles, discardUploads, safeName, storagePath, uniqueNames, uploadAttachments } from "../src/data/attachments";
import { draftMessage, kindOfMime, sendPayload } from "../src/data/chat";

const file = (name: string, size = 10, type = "text/plain") => {
  const f = new File(["x"], name, { type });
  Object.defineProperty(f, "size", { value: size });
  return f;
};

describe("adjuntos: nombres y rutas", () => {
  it("deja solo letras, números, punto, guion y guion bajo (como safe_name de Kyora)", () => {
    expect(safeName("foto vacaciones (1).jpg")).toBe("foto_vacaciones__1_.jpg");
    expect(safeName("Año nuevo.pdf")).toBe("A_o_nuevo.pdf");
    expect(safeName("../../etc/passwd")).toBe("__.._etc_passwd"); // sin «/», un nombre nunca sale de su carpeta
    expect(safeName("../../etc/passwd")).not.toContain("/");
    expect(safeName("")).toBe("archivo");
    expect(safeName(".oculto")).toBe("_oculto");
    expect(safeName("a".repeat(300))).toHaveLength(120);
  });

  it("dos archivos con el mismo nombre no se pisan dentro de un mensaje", () => {
    expect(uniqueNames(["foto.jpg", "foto.jpg", "FOTO.jpg", "notas"])).toEqual(["foto.jpg", "foto-2.jpg", "FOTO-3.jpg", "notas"]);
    expect(uniqueNames(["a", "a", "a"])).toEqual(["a", "a-2", "a-3"]);
  });

  it("la ruta es <cuenta>/<conversación>/<mensaje>/<archivo>: la primera carpeta es la de tu cuenta (lo exige Storage)", () => {
    expect(storagePath("u1", "c1", "m1", "f.pdf")).toBe("u1/c1/m1/f.pdf");
  });
});

describe("adjuntos: validación", () => {
  it("acepta lo normal y rechaza lo vacío o demasiado grande, diciendo por qué", () => {
    const { accepted, errors } = checkFiles([file("ok.txt"), file("vacio.txt", 0), file("enorme.zip", MAX_BYTES + 1)]);
    expect(accepted.map((f) => f.name)).toEqual(["ok.txt"]);
    expect(errors).toHaveLength(2);
    expect(errors[0]).toMatch(/«vacio\.txt» está vacío/);
    expect(errors[1]).toMatch(/«enorme\.zip» pesa .*el límite es 50\.0 MB/);
  });

  it("el límite es exactamente 50 MB y hasta 10 archivos por mensaje", () => {
    expect(checkFiles([file("justo.bin", MAX_BYTES)]).accepted).toHaveLength(1);
    const many = Array.from({ length: 12 }, (_, i) => file(`f${i}.txt`));
    const res = checkFiles(many);
    expect(res.accepted).toHaveLength(MAX_FILES);
    expect(res.errors.join(" ")).toMatch(/10 archivos por mensaje/);
    expect(checkFiles([file("otro.txt")], many.slice(0, MAX_FILES)).accepted).toHaveLength(0); // ya hay 10 elegidos
  });
});

describe("adjuntos: subida", () => {
  function client(failOn?: string) {
    const upload = vi.fn(async (path: string, _file?: unknown, _opts?: unknown) => (path.endsWith(failOn ?? "\u0000") ? { error: { message: "boom" } } : { data: { path }, error: null }));
    const remove = vi.fn(async () => ({ data: [], error: null }));
    return { upload, remove, c: { storage: { from: () => ({ upload, remove }) } } as never };
  }

  it("sube cada archivo a su ruta con su tipo y devuelve los descriptores que pide send_message", async () => {
    const { upload, c } = client();
    const progress: string[] = [];
    const out = await uploadAttachments(c, "u1", "c1", "m1", [file("a b.pdf", 100, "application/pdf"), file("a b.pdf", 50, "")], (d, t) => progress.push(`${d}/${t}`));
    expect(upload).toHaveBeenCalledTimes(2);
    expect(upload.mock.calls[0]).toEqual(["u1/c1/m1/a_b.pdf", expect.anything(), { contentType: "application/pdf", upsert: true }]);
    expect(upload.mock.calls[1][0]).toBe("u1/c1/m1/a_b-2.pdf");
    expect(upload.mock.calls[1][2]).toEqual({ contentType: "application/octet-stream", upsert: true });
    expect(out[0]).toEqual({ storage_path: "u1/c1/m1/a_b.pdf", file_name: "a b.pdf", mime_type: "application/pdf", size_bytes: 100, width: null, height: null, duration_ms: null, thumb_path: null });
    expect(progress).toEqual(["0/2", "1/2", "2/2"]);
  });

  it("si un archivo falla lanza el error (el reintento repite las mismas rutas)", async () => {
    const { upload, c } = client("b.txt");
    await expect(uploadAttachments(c, "u", "c", "m", [file("a.txt"), file("b.txt"), file("c.txt")])).rejects.toMatchObject({ message: "boom" });
    expect(upload).toHaveBeenCalledTimes(2); // no sigue con el tercero
  });

  it("descartar quita de Storage lo subido, y nunca lanza", async () => {
    const { remove, c } = client();
    await discardUploads(c, [{ storage_path: "u/c/m/a", file_name: "a", mime_type: "x", size_bytes: 1, width: null, height: null, duration_ms: null, thumb_path: null }]);
    expect(remove).toHaveBeenCalledWith(["u/c/m/a"]);
    await expect(discardUploads({ storage: { from: () => ({ remove: async () => Promise.reject(new Error("x")) }) } } as never, [{ storage_path: "p" } as never])).resolves.toBeUndefined();
  });
});

describe("adjuntos: el mensaje", () => {
  const att = { storage_path: "u/c/m/f.jpg", file_name: "f.jpg", mime_type: "image/jpeg", size_bytes: 9, width: 1, height: 1, duration_ms: null, thumb_path: null };

  it("el envío lleva los adjuntos y el mismo id de mensaje que sus rutas", () => {
    const p = sendPayload("c", "hola", "m", new Date("2026-11-13T10:00:00Z"), [att]);
    expect(p).toMatchObject({ p_id: "m", p_conversation_id: "c", p_body: "hola", p_device: "web", p_attachments: [att] });
    expect(sendPayload("c", "solo texto").p_attachments).toEqual([]);
  });

  it("la clase de un mensaje sale del primer adjunto, igual que en el servidor", () => {
    expect(kindOfMime(undefined)).toBe("text");
    expect(kindOfMime("image/png")).toBe("image");
    expect(kindOfMime("audio/mpeg")).toBe("audio");
    expect(kindOfMime("video/mp4")).toBe("video");
    expect(kindOfMime("application/pdf")).toBe("file");
  });

  it("el borrador muestra los archivos mientras se envía, y sin texto el cuerpo es nulo", () => {
    const d = draftMessage(sendPayload("c", "", "m", new Date(), [att]));
    expect(d).toMatchObject({ id: "m", kind: "image", body: null, local: "sending" });
    expect(d.attachments).toEqual([{ id: "m:0", storage_path: "u/c/m/f.jpg", file_name: "f.jpg", mime_type: "image/jpeg", size_bytes: 9 }]);
    expect(draftMessage(sendPayload("c", "hola")).kind).toBe("text");
  });
});
