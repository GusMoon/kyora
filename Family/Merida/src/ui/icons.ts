import { s } from "./dom";

/** Iconos de línea (24×24, trazo cuadrado, color del texto). Siempre decorativos: el nombre va en el texto o en aria-label. */
const PATHS = {
  tasks: "M3.5 6.5 L5.5 8.5 L9 4.5 M3.5 12.5 L5.5 14.5 L9 10.5 M3.5 18.5 L5.5 20.5 L9 16.5 M13 6.5 H21 M13 12.5 H21 M13 18.5 H21",
  music: "M12 3 A9 9 0 1 0 12 21 A9 9 0 1 0 12 3 M12 9 A3 3 0 1 0 12 15 A3 3 0 1 0 12 9 M12 6 A6 6 0 0 1 18 12",
  chat: "M3 5 H21 V16 H11 L6 20 V16 H3 Z M7 9 L9.5 11 L7 13 M11.5 13 H16",
  cloud: "M7 19 A4.5 4.5 0 0 1 6.6 10.2 A6.5 6.5 0 0 1 18.4 9.4 A4.8 4.8 0 0 1 17.5 19 Z",
  trash: "M4 7 H20 M9 7 V4 H15 V7 M6 7 L7 21 H17 L18 7 M10 11 V17 M14 11 V17",
  file: "M6 3 H14 L19 8 V21 H6 Z M14 3 V8 H19 M9 13 H16 M9 17 H16",
  download: "M12 4 V15 M7 11 L12 16 L17 11 M5 20 H19",
  refresh: "M20 5 V10 H15 M4 19 V14 H9 M5.6 9 A7.5 7.5 0 0 1 19 10 M18.4 15 A7.5 7.5 0 0 1 5 14",
  play: "M8 5 L19 12 L8 19 Z",
  pause: "M7 5 H10 V19 H7 Z M14 5 H17 V19 H14 Z",
  settings:
    "M10 2 H14 L14.6 5 L17 6.3 L19.8 5.1 L21.8 8.6 L19.5 10.6 V13.4 L21.8 15.4 L19.8 18.9 L17 17.7 L14.6 19 L14 22 H10 L9.4 19 L7 17.7 L4.2 18.9 L2.2 15.4 L4.5 13.4 V10.6 L2.2 8.6 L4.2 5.1 L7 6.3 L9.4 5 Z M12 9 A3 3 0 1 0 12 15 A3 3 0 1 0 12 9",
  phone: "M7 2 H17 V22 H7 Z M10.5 18.5 H13.5",
  pc: "M3 4 H21 V16 H3 Z M9 20 H15 M12 16 V20",
  web: "M12 3 A9 9 0 1 0 12 21 A9 9 0 1 0 12 3 M3 12 H21 M12 3 C8.5 7 8.5 17 12 21 M12 3 C15.5 7 15.5 17 12 21",
  device: "M4 6 H14 V18 H4 Z M17 9 H20 V18 H17 Z",
  close: "M6 6 L18 18 M18 6 L6 18",
  arrow: "M7 17 L17 7 M9 7 H17 V15",
  enter: "M20 5 V14 H6 M10 10 L6 14 L10 18",
  power: "M12 3 V12 M6.3 6.3 A8 8 0 1 0 17.7 6.3",
  check: "M4 12.5 L9.5 18 L20 6",
  calendar: "M3 5 H21 V21 H3 Z M3 10 H21 M8 2 V7 M16 2 V7 M7 14 H9 M11 14 H13 M15 14 H17 M7 17.5 H9 M11 17.5 H13",
  lock: "M5 11 H19 V21 H5 Z M8 11 V7 A4 4 0 0 1 16 7 V11 M12 15 V18",
  wallet: "M3 6 H19 V9 M3 6 V20 H21 V9 H3 M16 14.5 H18",
  paperclip: "M19 11 L11.5 18.5 A4.5 4.5 0 0 1 5.1 12.1 L13 4.2 A3 3 0 0 1 17.3 8.5 L9.7 16.1 A1.5 1.5 0 0 1 7.6 14",
  pencil: "M4 20 L5 15 L16 4 L20 8 L9 19 Z M13.5 6.5 L17.5 10.5",
  tag: "M3 3 H12 L21 12 L12 21 L3 12 Z M7.5 7.5 H8.5",
  clock: "M12 3 A9 9 0 1 0 12 21 A9 9 0 1 0 12 3 M12 7 V12 L15.5 14",
  command: "M7 4 H17 M7 20 H17 M4 7 V17 M20 7 V17 M9 9 H15 V15 H9 Z",
  plus: "M12 5 V19 M5 12 H19",
  home: "M3 11 L12 3 L21 11 M6 9.5 V21 H18 V9.5 M10 21 V14 H14 V21",
  eye: "M2 12 C5 6.5 8.5 5 12 5 C15.5 5 19 6.5 22 12 C19 17.5 15.5 19 12 19 C8.5 19 5 17.5 2 12 Z M12 9 A3 3 0 1 0 12 15 A3 3 0 1 0 12 9",
  eyeOff: "M3 3 L21 21 M10.6 5.2 C11 5.1 11.5 5 12 5 C15.5 5 19 6.5 22 12 C21.2 13.5 20.3 14.7 19.3 15.7 M6.6 6.7 C4.7 8 3.2 9.8 2 12 C5 17.5 8.5 19 12 19 C13.4 19 14.7 18.7 16 18.2 M9.9 9.9 A3 3 0 0 0 14.1 14.1",
  copy: "M8 8 H20 V21 H8 Z M16 8 V3 H4 V16 H8",
  key: "M8 8 A4 4 0 1 0 8 16 A4 4 0 1 0 8 8 M12 12 H21 M18 12 V16 M21 12 V15",
  chevronLeft: "M15 5 L8 12 L15 19",
  chevronRight: "M9 5 L16 12 L9 19",
  up: "M6 15 L12 9 L18 15",
  down: "M6 9 L12 15 L18 9",
  bell: "M6 17 V11 A6 6 0 0 1 18 11 V17 L20 19 H4 Z M10 21 H14",
} as const;

export type IconName = keyof typeof PATHS;

export function icon(name: IconName, cls = "icon"): SVGSVGElement {
  return s(
    "svg",
    { viewBox: "0 0 24 24", class: cls, "aria-hidden": "true", focusable: "false" },
    s("path", { d: PATHS[name], fill: name === "play" || name === "pause" ? "currentColor" : "none", stroke: "currentColor", "stroke-width": 2, "stroke-linecap": "square", "stroke-linejoin": "miter" }),
  );
}

/** El icono del dispositivo de un mensaje: teléfono, PC, esta web u otro (como deviceIcon de Kyra). */
export function deviceIconName(device: string): IconName {
  const d = device.toLowerCase();
  if (["movil", "móvil", "phone", "telefono"].includes(d)) return "phone";
  if (d === "pc") return "pc";
  if (d === "web") return "web";
  return "device";
}
