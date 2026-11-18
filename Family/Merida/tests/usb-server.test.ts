// @vitest-environment node
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { request, type Server } from "node:http";
import { createServer } from "../usb/server.mjs";

let dir: string;
let server: Server;
let base: string;

/** El código de una petición sin que el cliente la «arregle» (fetch normaliza «..» y cambia la cabecera Host). */
const status = (path: string, headers: Record<string, string> = {}) =>
  new Promise<number>((ok, fail) => {
    const url = new URL(base);
    request({ host: url.hostname, port: url.port, path, headers }, (res) => {
      res.resume();
      ok(res.statusCode ?? 0);
    })
      .on("error", fail)
      .end();
  });

async function start(appData?: string) {
  server = createServer({ webDir: join(dir, "web"), appData: appData ?? join(dir, "appdata") });
  await new Promise<void>((ok) => server.listen(0, "127.0.0.1", ok));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
}

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "merida-usb-"));
  mkdirSync(join(dir, "web", "assets"), { recursive: true });
  writeFileSync(join(dir, "web", "index.html"), "<!doctype html><title>Merida</title>");
  writeFileSync(join(dir, "web", "assets", "app-abc123.js"), "console.log(1)");
  writeFileSync(join(dir, "web", "assets", "font.woff2"), "x");
  writeFileSync(join(dir, "secreto.txt"), "no debe salir"); // fuera de web/
});

afterEach(async () => {
  await new Promise((ok) => server?.close(ok));
  rmSync(dir, { recursive: true, force: true });
});

describe("usb/server.mjs", () => {
  it("sirve index.html en la raíz y los archivos con su tipo", async () => {
    await start();
    const home = await fetch(`${base}/`);
    expect(home.status).toBe(200);
    expect(home.headers.get("content-type")).toBe("text/html; charset=utf-8");
    expect(await home.text()).toContain("<title>Merida</title>");
    const js = await fetch(`${base}/assets/app-abc123.js`);
    expect(js.headers.get("content-type")).toBe("text/javascript; charset=utf-8");
    expect(js.headers.get("cache-control")).toContain("immutable");
    expect((await fetch(`${base}/assets/font.woff2`)).headers.get("content-type")).toBe("font/woff2");
  });

  it("no existe → 404, y no sale de web/", async () => {
    await start();
    expect((await fetch(`${base}/nada.js`)).status).toBe(404);
    // el cliente de fetch normaliza «..», así que se manda a pelo
    const raw = (path: string) => status(path);
    expect(await raw("/../secreto.txt")).toBeGreaterThanOrEqual(400);
    expect(await raw("/..%2fsecreto.txt")).toBeGreaterThanOrEqual(400);
    expect(await raw("/%2e%2e/secreto.txt")).toBeGreaterThanOrEqual(400);
    expect(await raw("/%00")).toBe(400);
    expect(await raw("/%E0%A4%A")).toBe(400); // porcentaje mal formado
  });

  it("solo atiende GET/HEAD y a su propia dirección (no a una web ajena por DNS)", async () => {
    await start();
    expect((await fetch(`${base}/`, { method: "POST" })).status).toBe(405);
    expect((await fetch(`${base}/`, { method: "HEAD" })).status).toBe(200);
    expect(await status("/", { Host: "evil.example" })).toBe(403);
  });

  it("/__music entrega la dirección y el token del servicio de música", async () => {
    mkdirSync(join(dir, "appdata", "Kyora"), { recursive: true });
    writeFileSync(join(dir, "appdata", "Kyora", "merida_service.json"), JSON.stringify({ url: "http://127.0.0.1:5190", token: "abc", extra: "no" }));
    await start();
    const res = await fetch(`${base}/__music`, { headers: { "sec-fetch-site": "same-origin" } });
    expect(res.status).toBe(200);
    expect(res.headers.get("cache-control")).toBe("no-store");
    expect(await res.json()).toEqual({ url: "http://127.0.0.1:5190", token: "abc" });
    expect((await fetch(`${base}/__music`)).status).toBe(200); // sin cabecera (curl, pruebas)
  });

  it("/__music rechaza a otra web y avisa si el servicio no está abierto", async () => {
    await start();
    expect((await fetch(`${base}/__music`, { headers: { "sec-fetch-site": "cross-site" } })).status).toBe(403);
    const none = await fetch(`${base}/__music`, { headers: { "sec-fetch-site": "same-origin" } });
    expect(none.status).toBe(503);
    expect(await none.json()).toMatchObject({ error: expect.stringMatching(/música/) });
  });
});
