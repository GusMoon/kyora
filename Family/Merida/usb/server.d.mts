import type { Server } from "node:http";

export const PORT: number;

export interface UsbServerOptions {
  /** Carpeta del build de Merida (la que tiene index.html). */
  webDir: string;
  /** El %APPDATA% donde el servicio de música escribe Kyora/merida_service.json. */
  appData?: string;
}

export function createServer(options: UsbServerOptions): Server;
