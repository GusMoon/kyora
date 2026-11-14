import type { Message } from "./data/chat";
import { deviceLabel } from "./data/chat";

/** Avisos de mensajes nuevos: una notificación del navegador (y un sonido corto, si se quiere) cuando llega un mensaje de
 * otro dispositivo y no lo estás viendo. Solo funciona con la pestaña abierta (aunque esté en segundo plano): no hay
 * Web Push, así que con la pestaña cerrada no avisa. */

export type Permission = NotificationPermission | "unsupported";

export function permission(): Permission {
  return typeof Notification === "undefined" ? "unsupported" : Notification.permission;
}

/** Pide permiso. Debe llamarse desde un clic (si no, el navegador lo ignora). */
export async function requestPermission(): Promise<Permission> {
  if (typeof Notification === "undefined") return "unsupported";
  if (Notification.permission !== "default") return Notification.permission;
  try {
    return await Notification.requestPermission();
  } catch {
    return Notification.permission;
  }
}

export interface ViewState {
  hidden: boolean; // la pestaña está en segundo plano o la ventana minimizada
  route: string; // la sección abierta ahora
}

/** ¿Este mensaje nuevo está sin leer? Solo si es de otro dispositivo y no lo estás mirando (pestaña oculta, o abierta en
 * otra sección que no sea el chat). Los propios (`web`) y los que aún se están enviando no cuentan. Con esto se llena el
 * contador de la pestaña; el aviso además exige la preferencia y el permiso (`shouldNotify`). */
export function countsAsUnread(msg: Message, view: ViewState): boolean {
  if (msg.local || msg.deleted_at || msg.sender_device === "web") return false;
  return view.hidden || view.route !== "chat";
}

/** ¿Hay que mostrar una notificación? Sin lo anterior, o con el aviso apagado o sin permiso, no. */
export function shouldNotify(msg: Message, view: ViewState, enabled: boolean, perm: Permission = permission()): boolean {
  return enabled && perm === "granted" && countsAsUnread(msg, view);
}

const PREVIEW_MAX = 140;

/** El título y el cuerpo del aviso. Con la vista previa apagada, nunca se muestra el texto del mensaje. */
export function notificationText(msg: Message, preview: boolean): { title: string; body: string } {
  const title = `Kyora · ${deviceLabel(msg.sender_device)}`;
  if (!preview) return { title, body: "Mensaje nuevo" };
  const text = (msg.body ?? "").trim();
  const files = msg.attachments?.length ?? 0;
  const clip = files ? `📎 ${files === 1 ? msg.attachments[0].file_name : `${files} archivos`}` : "";
  const body = [text, clip].filter(Boolean).join("  ") || "Mensaje nuevo";
  return { title, body: body.length > PREVIEW_MAX ? `${body.slice(0, PREVIEW_MAX - 1)}…` : body };
}

/** Un pitido corto con Web Audio (sin archivos). Si el navegador no deja sonar aún, no hace nada. */
export function beep(): void {
  try {
    const Ctx = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!Ctx) return;
    const ac = new Ctx();
    const osc = ac.createOscillator();
    const gain = ac.createGain();
    osc.type = "square";
    osc.frequency.setValueAtTime(880, ac.currentTime);
    osc.frequency.setValueAtTime(1320, ac.currentTime + 0.08);
    gain.gain.setValueAtTime(0.0001, ac.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.08, ac.currentTime + 0.01);
    gain.gain.exponentialRampToValueAtTime(0.0001, ac.currentTime + 0.22);
    osc.connect(gain).connect(ac.destination);
    osc.start();
    osc.stop(ac.currentTime + 0.24);
    osc.onended = () => void ac.close();
  } catch {
    /* sin sonido */
  }
}

/** Un aviso del calendario (un recordatorio que llegó a su hora, un hábito con aviso). Al pulsarlo abre el calendario. */
export function showAlert(alert: { key: string; title: string; body: string }, opts: { sound: boolean }, onClick: () => void = () => {}): boolean {
  if (permission() !== "granted") return false;
  try {
    const n = new Notification(`Merida · ${alert.title}`, { body: alert.body, tag: alert.key });
    n.onclick = () => {
      window.focus();
      onClick();
      n.close();
    };
  } catch {
    return false;
  }
  if (opts.sound) beep();
  return true;
}

/** Muestra la notificación. Al pulsarla, enfoca esta ventana y abre el chat. Devuelve false si no se pudo. */
export function showNotification(msg: Message, opts: { preview: boolean; sound: boolean }, onClick: () => void = () => {}): boolean {
  if (permission() !== "granted") return false;
  const { title, body } = notificationText(msg, opts.preview);
  try {
    const n = new Notification(title, { body, tag: msg.id }); // el mismo id no se repite
    n.onclick = () => {
      window.focus();
      onClick();
      n.close();
    };
  } catch {
    return false;
  }
  if (opts.sound) beep();
  return true;
}
