import { afterEach, describe, expect, it } from "vitest";
import { BACKDROP_DIM, Backdrop, accentOf, hsvToHex } from "../src/backdrop";

function memory() {
  const data: Record<string, string> = {};
  return {
    data,
    getItem: (k: string) => (k in data ? data[k] : null),
    setItem: (k: string, v: string) => void (data[k] = v),
    removeItem: (k: string) => void delete data[k],
  };
}

const pixels = (...rgb: [number, number, number][]) => Uint8ClampedArray.from(rgb.flatMap(([r, g, b]) => [r, g, b, 255]));
const prepare = async () => ({ url: "data:image/jpeg;base64,QUJD", accent: "#35d4ff" });
const file = new Blob(["x"], { type: "image/png" });
const tick = () => new Promise((r) => setTimeout(r, 0));

afterEach(() => {
  document.documentElement.removeAttribute("data-backdrop");
  document.body.replaceChildren();
});

describe("color del fondo (accentOf de Kyra)", () => {
  it("elige el tono que más pesa, con saturación 0,78 y brillo de neón", () => {
    const blue = accentOf(pixels([20, 40, 230], [30, 50, 220], [10, 30, 240], [200, 40, 40]))!;
    expect(blue).toMatch(/^#[0-9a-f]{6}$/);
    const n = parseInt(blue.slice(1), 16);
    expect(n & 255).toBe(255); // brillo máximo: el canal más alto es 255
    expect(n & 255).toBeGreaterThan((n >> 16) & 255); // y domina el azul
    expect(accentOf(pixels([255, 0, 0], [255, 0, 0], [0, 255, 0]))).toBe(hsvToHex(0, 0.78, 1));
    expect(hsvToHex(0, 0.78, 1)).toBe("#ff3838");
  });

  it("una foto gris, negra o blanca no da color", () => {
    expect(accentOf(pixels([128, 128, 128], [10, 10, 10], [250, 250, 250]))).toBeNull();
    expect(accentOf(new Uint8ClampedArray())).toBeNull();
  });
});

describe("fondo de pantalla temporal", () => {
  it("sin nada puesto no oscurece ni cambia las superficies", () => {
    const b = new Backdrop({ storage: memory(), prepare });
    expect(b.active).toBe(false);
    expect(b.accent).toBeNull();
    expect(document.documentElement.hasAttribute("data-backdrop")).toBe(false);
    expect((b.el.querySelector(".backdrop-dim") as HTMLElement).hidden).toBe(true);
    expect(BACKDROP_DIM).toBe(0.42);
  });

  it("al poner una imagen se oscurece, deja ver el fondo en las superficies y da su color", async () => {
    const store = memory();
    const b = new Backdrop({ storage: store, prepare });
    let calls = 0;
    b.on(() => calls++);
    expect(await b.setWallpaper(file)).toBe(true);
    expect(b.active).toBe(true);
    expect(b.accent).toBe("#35d4ff");
    expect(document.documentElement.hasAttribute("data-backdrop")).toBe(true);
    expect((b.el.querySelector(".backdrop-wall") as HTMLElement).style.backgroundImage).toContain("data:image/jpeg");
    expect((b.el.querySelector(".backdrop-dim") as HTMLElement).hidden).toBe(false);
    expect(calls).toBeGreaterThanOrEqual(2); // «guardando» y «listo»
    expect(JSON.parse(store.data["merida-wallpaper"]).accent).toBe("#35d4ff");
  });

  it("sobrevive a recargar la página (la sesión del navegador) y se va al quitarlo", async () => {
    const store = memory();
    await new Backdrop({ storage: store, prepare }).setWallpaper(file);
    const again = new Backdrop({ storage: store, prepare });
    expect(again.wallpaper).toContain("data:image/jpeg");
    again.clearWallpaper();
    expect(store.data["merida-wallpaper"]).toBeUndefined();
    expect(new Backdrop({ storage: store, prepare }).active).toBe(false);
  });

  it("si falla, dice por qué y se queda el fondo que había", async () => {
    const b = new Backdrop({ storage: memory(), prepare });
    await b.setWallpaper(file);
    b.on(() => {});
    const broken = new Backdrop({ storage: memory(), prepare: async () => Promise.reject(new Error("Ese archivo no es una imagen.")) });
    expect(await broken.setWallpaper(file)).toBe(false);
    expect(broken.error).toBe("Ese archivo no es una imagen.");
    expect(broken.busy).toBe(false);
    expect(b.wallpaper).not.toBeNull();
  });

  it("lo guardado que no es una imagen se ignora", () => {
    const store = memory();
    store.data["merida-wallpaper"] = JSON.stringify({ url: "javascript:alert(1)" });
    expect(new Backdrop({ storage: store, prepare }).active).toBe(false);
    store.data["merida-wallpaper"] = "{roto";
    expect(new Backdrop({ storage: store, prepare }).active).toBe(false);
  });

  it("sin almacenamiento funciona igual, solo hasta recargar", async () => {
    const b = new Backdrop({ storage: null, prepare });
    expect(await b.setWallpaper(file)).toBe(true);
    expect(b.active).toBe(true);
  });
});

describe("portada que suena", () => {
  it("pasa a ser el fondo con su color, manda sobre el de la imagen y al pausar vuelve lo de antes", async () => {
    const b = new Backdrop({ storage: memory(), prepare, coverAccent: async () => "#ff4fd8" });
    await b.setWallpaper(file);
    b.setCover("https://i.ytimg.com/vi/abc/mqdefault.jpg");
    expect(b.el.querySelector(".backdrop-cover")).not.toBeNull();
    await tick();
    expect(b.accent).toBe("#ff4fd8");
    b.setCover(null);
    expect(b.accent).toBe("#35d4ff");
    expect(b.active).toBe(true); // la imagen sigue
  });

  it("si la portada no deja leer su color, no inventa uno; y no oscura si no hay nada", async () => {
    const b = new Backdrop({ storage: memory(), prepare, coverAccent: async () => null });
    b.setCover("https://i.ytimg.com/vi/abc/mqdefault.jpg");
    await tick();
    expect(b.active).toBe(true);
    expect(b.accent).toBeNull();
    b.setCover(null);
    expect(b.active).toBe(false);
  });

  it("un color que llega tarde de otra canción no pisa al de la actual", async () => {
    const waiting: Record<string, (c: string) => void> = {};
    const b = new Backdrop({ storage: memory(), prepare, coverAccent: (url) => new Promise((res) => (waiting[url] = res)) });
    b.setCover("a");
    b.setCover("b");
    waiting["a"]("#111111");
    waiting["b"]("#222222");
    await tick();
    expect(b.accent).toBe("#222222");
  });

  it("al cerrar sesión se borra todo", async () => {
    const store = memory();
    const b = new Backdrop({ storage: store, prepare, coverAccent: async () => null });
    await b.setWallpaper(file);
    b.setCover("x");
    b.reset();
    expect(b.active).toBe(false);
    expect(store.data["merida-wallpaper"]).toBeUndefined();
  });
});
