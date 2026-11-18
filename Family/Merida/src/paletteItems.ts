import type { SupabaseClient } from "@supabase/supabase-js";
import type { PaletteItem } from "./palette";
import type { Store } from "./store";
import type { PrefsStore } from "./prefs";
import type { VaultSession } from "./vault/session";
import { ROUTES } from "./routes";
import { STATUS_LABEL, groupByStatus } from "./data/tasks";
import { listCommands } from "./data/commands";
import { dayKey, isoDayKey } from "./data/events";
import { minutesToHHMM, weekdaysLabel } from "./data/habits";

export interface PaletteDeps {
  client: SupabaseClient;
  store: Store;
  prefs: PrefsStore;
  vault: VaultSession;
  go: (hash: string) => void;
}

/** Lo que ofrece la paleta ahora mismo: secciones, acciones, tus tareas, tus comandos del chat y, con la bóveda abierta, tus
 * entradas (solo el servicio y el correo; nunca la contraseña). */
export async function buildPaletteItems(deps: PaletteDeps): Promise<PaletteItem[]> {
  const { client, store, prefs, vault, go } = deps;
  const keys = prefs.value.keys;
  const items: PaletteItem[] = [];

  for (const r of ROUTES) {
    items.push({
      id: `go:${r.id}`,
      label: r.id === "inicio" ? "Volver al mosaico" : `Ir a ${r.title}`,
      hint: `tecla ${keys[r.id]}${r.id === "inicio" ? " o Esc" : ""}`,
      group: "Ir a",
      keywords: r.title,
      run: () => go(`#/${r.id}`),
    });
  }

  const act = (id: string, label: string, route: string, intent: string, keywords = ""): PaletteItem => ({
    id: `do:${id}`,
    label,
    group: "Acciones",
    keywords,
    run: () => {
      store.raise(intent);
      go(`#/${route}`);
    },
  });
  items.push(
    act("new-task", "Nueva tarea", "tareas", "new-task", "añadir crear pendiente"),
    act("new-event", "Nuevo evento", "calendario", "new-event", "añadir crear cita reunión"),
    act("new-reminder", "Nuevo recordatorio", "calendario", "new-reminder", "avisar recordar alarma"),
    act("new-habit", "Nuevo hábito", "calendario", "new-habit", "rutina costumbre diario"),
    act("new-entry", "Nuevo movimiento (ingreso o gasto)", "finanzas", "new-entry", "dinero pago cobro"),
    act("new-secret", "Nueva contraseña", "contrasenas", "new-secret", "clave correo servicio"),
    act("new-improvement", "Nueva mejora pendiente", "mejoras", "new-improvement", "idea función agregar mejorar pendiente"),
    { id: "do:lock", label: "Bloquear la bóveda", group: "Acciones", keywords: "contraseñas cerrar", hint: vault.state === "unlocked" ? undefined : "ya está bloqueada", run: () => vault.lock() },
    { id: "do:keys", label: "Cambiar atajos de teclado", group: "Acciones", keywords: "teclas configuración", run: () => go("#/configuracion") },
  );

  // tareas: las principales abiertas primero, luego las hechas; hasta 200
  const groups = groupByStatus(store.tasks);
  const ordered = [...groups.doing, ...groups.pending, ...groups.review, ...groups.done].slice(0, 200);
  for (const t of ordered) {
    items.push({
      id: `task:${t.id}`,
      label: t.name,
      hint: STATUS_LABEL[t.status],
      group: "Tareas",
      keywords: t.description.slice(0, 120),
      run: () => {
        store.raise("open-task", t.id);
        go("#/tareas");
      },
    });
  }

  // calendario: eventos y recordatorios cercanos (hasta 300 de cada uno, los más próximos a hoy) y los hábitos; al elegir uno se abre su día
  const todayKey = dayKey(new Date());
  const near = <T,>(rows: T[], keyOf: (r: T) => string) =>
    rows
      .filter((r) => Math.abs(new Date(keyOf(r)).getTime() - Date.now()) < 400 * 86_400_000)
      .sort((a, b) => Math.abs(new Date(keyOf(a)).getTime() - Date.now()) - Math.abs(new Date(keyOf(b)).getTime() - Date.now()))
      .slice(0, 300);
  const when = (iso: string, allDay = false) => {
    const d = new Date(iso);
    const day = d.toLocaleDateString("es", { weekday: "short", day: "numeric", month: "short" }).replace(/\./g, "");
    return allDay ? day : `${day} · ${minutesToHHMM(d.getHours() * 60 + d.getMinutes())}`;
  };
  const openDay = (key: string) => () => {
    store.raise("open-day", key);
    go("#/calendario");
  };
  for (const e of near(store.events, (x) => x.starts_at)) {
    items.push({ id: `event:${e.id}`, label: e.title, hint: `evento · ${when(e.starts_at, e.all_day)}`, group: "Calendario", keywords: e.description.slice(0, 120), run: openDay(isoDayKey(e.starts_at)) });
  }
  for (const r of near(store.reminders, (x) => x.remind_at)) {
    items.push({ id: `reminder:${r.id}`, label: r.title, hint: `recordatorio · ${when(r.remind_at)}${r.done ? " · hecho" : ""}`, group: "Calendario", keywords: r.notes.slice(0, 120), run: openDay(isoDayKey(r.remind_at)) });
  }
  for (const h of store.habits) {
    items.push({ id: `habit:${h.id}`, label: h.name, hint: `hábito · ${weekdaysLabel(h.weekdays)}${h.remind_at !== null ? ` · ${minutesToHHMM(h.remind_at)}` : ""}`, group: "Calendario", keywords: "rutina", run: openDay(todayKey) });
  }

  if (vault.state === "unlocked") {
    for (const i of vault.items) {
      items.push({
        id: `secret:${i.id}`,
        label: i.service,
        hint: i.email || i.username,
        group: "Contraseñas",
        keywords: `${i.url} ${i.username}`,
        run: () => {
          store.raise("open-secret", i.id);
          go("#/contrasenas");
        },
      });
    }
  }

  try {
    for (const c of await listCommands(client)) {
      items.push({ id: `web:${c.id}`, label: `/${c.command}`, hint: c.name, group: "Webs del chat", keywords: c.url, run: () => void window.open(c.url, "_blank", "noopener") });
    }
  } catch {
    /* sin comandos cargados: el resto de la paleta sigue funcionando */
  }
  return items;
}
