import { afterEach, describe, expect, it } from "vitest";
import { GLYPHS, fxConfig, glitchOpacity, glitchShift, hackDuration, hackFrame, hackText, hologramFrames, noise, plainText } from "../src/ui/fx";

afterEach(() => {
  fxConfig.hack = true;
  fxConfig.holo = true;
});

describe("ruido de Kyra", () => {
  it("es determinista y va de 0 a 1", () => {
    expect(noise(3, 7)).toBe(noise(3, 7));
    for (let seed = 0; seed < 20; seed++) {
      for (let tick = 0; tick < 9; tick++) {
        const v = noise(seed, tick);
        expect(v).toBeGreaterThanOrEqual(0);
        expect(v).toBeLessThanOrEqual(1);
      }
    }
    expect(new Set([0, 1, 2, 3, 4].map((t) => noise(1, t))).size).toBeGreaterThan(1);
  });
});

describe("texto hacking", () => {
  it("dura 14 ms por carácter (más 3), entre 180 y 560 ms", () => {
    expect(hackDuration(1)).toBe(180);
    expect(hackDuration(20)).toBe(14 * 23);
    expect(hackDuration(200)).toBe(560);
  });

  it("escribe de izquierda a derecha con una ventana de 3 caracteres de ruido", () => {
    const text = "Configuración";
    expect(hackFrame(text, 0, 0)).toEqual({ done: "", noise: "", rest: text });
    const mid = hackFrame(text, 0.5, 4);
    expect(mid.done.length + mid.noise.length + mid.rest.length).toBe(text.length);
    expect(mid.noise.length).toBe(3);
    expect(text.startsWith(mid.done)).toBe(true);
    expect([...mid.noise].every((c) => GLYPHS.includes(c))).toBe(true);
    expect(hackFrame(text, 1, 9)).toEqual({ done: text, noise: "", rest: "" });
  });

  it("los espacios y saltos de línea no se cifran", () => {
    const text = "a b\nc d e";
    for (let step = 0; step <= 10; step++) {
      const frame = hackFrame(text, step / 10, step);
      const start = frame.done.length;
      [...frame.noise].forEach((ch, i) => {
        const real = text[start + i];
        if (real === " " || real === "\n") expect(ch).toBe(real);
        else expect(GLYPHS.includes(ch)).toBe(true);
      });
    }
  });

  it("apagado, pone el texto de golpe; encendido, deja el texto entero para los lectores de pantalla", async () => {
    const el = document.createElement("p");
    fxConfig.hack = false;
    await hackText(el, "hola");
    expect(el.textContent).toBe("hola");
    fxConfig.hack = true;
    const done = hackText(el, "Tareas abiertas");
    expect(el.querySelector(".sr-only")?.textContent).toBe("Tareas abiertas");
    expect(el.querySelector("[aria-hidden=true]")).not.toBeNull();
    await done;
    expect(el.textContent).toBe("Tareas abiertas");
  });

  it("a medio escribir, el texto de verdad no se duplica (antes salía «MÚSICAMÚSICA»)", async () => {
    const el = document.createElement("p");
    const first = hackText(el, "Música");
    expect(el.textContent).not.toBe("Música"); // lleva la copia de lectores de pantalla y la animada
    expect(plainText(el)).toBe("Música");
    const again = hackText(el, plainText(el)); // se vuelve a escribir encima, como al cambiar de sección rápido
    await Promise.all([first, again]);
    expect(el.textContent).toBe("Música");
  });
});

describe("holograma", () => {
  it("parpadea (cae a 0.3) en algunos pasos y está entero al terminar", () => {
    expect(glitchOpacity(0, 1, 0)).toBe(0);
    expect(glitchOpacity(1, 1, 9)).toBe(1);
    const values = Array.from({ length: 30 }, (_, i) => glitchOpacity(0.8, i, 3));
    expect(values.some((v) => v === 0.8)).toBe(true);
    expect(values.some((v) => Math.abs(v - 0.24) < 1e-9)).toBe(true);
  });

  it("salta hasta 14 px a los lados y deriva 10 px hacia su borde", () => {
    for (let seed = 0; seed < 30; seed++) {
      const { x, y } = glitchShift(0, seed, 0, "top");
      expect(Math.abs(x)).toBeLessThanOrEqual(14);
      expect(y).toBe(-10);
    }
    expect(glitchShift(1, 4, 9, "left")).toEqual({ x: 0, y: 0 });
  });

  it("entra en 10 fotogramas a saltos, de invisible a entero, y sale al revés", () => {
    const enter = hologramFrames(2, "left", "in");
    expect(enter).toHaveLength(10);
    expect(enter[0].opacity).toBe(0);
    expect(enter[9]).toMatchObject({ offset: 1, opacity: 1, transform: "translate(0.0px, 0.0px)" });
    expect(enter.every((f) => f.easing === "steps(1, end)")).toBe(true);
    const exit = hologramFrames(2, "left", "out");
    expect(exit[0].opacity).toBe(1);
    expect(exit[9].opacity).toBe(0);
  });
});
