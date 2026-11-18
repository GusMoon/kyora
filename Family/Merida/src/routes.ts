/** Las secciones de Merida y las teclas con que se abren. Sin dependencias: lo usan el tablero, las preferencias y los atajos. */

export type RouteId = "inicio" | "tareas" | "calendario" | "musica" | "nube" | "chat" | "contrasenas" | "finanzas" | "mejoras" | "configuracion";
export type SectionId = Exclude<RouteId, "inicio">;

export const ROUTES: { id: RouteId; title: string; key: string }[] = [
  { id: "inicio", title: "Inicio", key: "I" },
  { id: "tareas", title: "Tareas", key: "T" },
  { id: "calendario", title: "Calendario", key: "K" },
  { id: "musica", title: "Música", key: "M" },
  { id: "nube", title: "Nube", key: "N" },
  { id: "chat", title: "Chat", key: "C" },
  { id: "contrasenas", title: "Contraseñas", key: "P" },
  { id: "finanzas", title: "Finanzas", key: "F" },
  { id: "mejoras", title: "Mejoras", key: "J" },
  { id: "configuracion", title: "Configuración", key: "A" },
];

export type KeyMap = Record<RouteId, string>;

/** Las teclas de siempre (en mayúscula, como se muestran). */
export const DEFAULT_KEYS: KeyMap = Object.fromEntries(ROUTES.map((r) => [r.id, r.key])) as KeyMap;

export const routeTitle = (id: RouteId): string => ROUTES.find((r) => r.id === id)?.title ?? id;
