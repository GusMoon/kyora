import { beep, showAlert } from "../notify";
import { formatDuration, phaseText } from "../data/calls";
import type { CallController } from "../data/call-controller";
import { h } from "./dom";
import { icon } from "./icons";

/** El panel de las llamadas de la familia: una ventana flotante abajo a la derecha, visible en cualquier sección. Suena y avisa
 * cuando entra una llamada, muestra a quien habla (y el video), y tiene contestar, rechazar, silenciar, apagar la cámara y colgar.
 * Es solo el dibujo: lo que ocurre lo decide el `CallController`. */

const DISMISS_MS = 4000; // lo que se queda el aviso de «llamada terminada»
const RING_BEEP_MS = 2500;

export function callPanel(controller: CallController, opts: { now?: () => number } = {}): { el: HTMLElement; destroy: () => void } {
  const now = opts.now ?? Date.now;
  const title = h("p", { class: "call-title", role: "status" });
  const clock = h("p", { class: "call-clock", "aria-hidden": "true" });
  const problem = h("p", { class: "form-error call-problem", role: "alert" });
  const remote = h("video", { class: "call-remote", autoplay: true, playsinline: true });
  const local = h("video", { class: "call-local", autoplay: true, playsinline: true, muted: true });
  (local as HTMLVideoElement).muted = true; // sin esto el navegador te devolvería tu propia voz
  const stage = h("div", { class: "call-stage" }, remote, local);
  const actions = h("div", { class: "call-actions" });
  const el = h("section", { class: "call-panel", role: "dialog", "aria-label": "Llamada de la familia", hidden: true }, title, stage, clock, problem, actions);

  let ringing: ReturnType<typeof setInterval> | null = null;
  let ticking: ReturnType<typeof setInterval> | null = null;
  let dismissing: ReturnType<typeof setTimeout> | null = null;
  let announced: string | null = null; // la llamada de la que ya se avisó (para no repetir el aviso)

  const stopRing = () => {
    if (ringing) clearInterval(ringing);
    ringing = null;
  };
  const stopTick = () => {
    if (ticking) clearInterval(ticking);
    ticking = null;
  };

  const button = (cls: string, label: string, name: Parameters<typeof icon>[0] | null, onClick: () => void, key: string) =>
    h("button", { class: cls, type: "button", "data-call": key, onClick }, name ? icon(name, "icon") : null, label);

  function paintClock() {
    const { phase, startedAt } = controller.view;
    clock.textContent = phase === "active" && startedAt !== null ? formatDuration(now() - startedAt) : "";
  }

  function render() {
    const v = controller.view;
    const shown = v.phase !== "idle" || !!v.error;
    el.hidden = !shown;
    el.dataset.phase = v.phase;
    el.dataset.kind = v.kind;
    title.textContent = v.phase === "idle" ? "" : phaseText(v.phase, v.kind, v.peer);
    problem.textContent = v.error;
    paintClock();

    // los videos: el del otro grande y el propio pequeño (en audio no se ven, pero el del otro suena)
    const wantsStream = v.phase === "active" || v.phase === "calling";
    const remoteEl = remote as HTMLVideoElement;
    const localEl = local as HTMLVideoElement;
    if (remoteEl.srcObject !== controller.remote) remoteEl.srcObject = controller.remote;
    const mine = wantsStream ? controller.local : null;
    if (localEl.srcObject !== mine) localEl.srcObject = mine;
    stage.hidden = v.kind === "audio" || !wantsStream;

    const list: HTMLElement[] = [];
    if (v.phase === "incoming") {
      list.push(button("btn-solid", "Contestar", "call", () => void controller.accept(), "accept"), button("btn-edge is-danger", "Rechazar", "close", () => void controller.decline(), "decline"));
    } else if (v.phase === "calling") {
      list.push(button("btn-edge is-danger", "Cancelar", "close", () => void controller.hangup(), "hangup"));
    } else if (v.phase === "active") {
      list.push(button("btn-edge", v.muted ? "Activar micrófono" : "Silenciar", v.muted ? "micOff" : "mic", () => controller.toggleMute(), "mute"));
      if (v.kind === "video") list.push(button("btn-edge", v.cameraOff ? "Encender cámara" : "Apagar cámara", v.cameraOff ? "videoOff" : "video", () => controller.toggleCamera(), "camera"));
      list.push(button("btn-edge is-danger", "Colgar", "close", () => void controller.hangup(), "hangup"));
    } else if (v.phase !== "idle" || v.error) {
      list.push(button("btn-edge", "Cerrar", null, () => controller.dismiss(), "dismiss"));
    }
    actions.replaceChildren(...list);

    // el timbre: mientras suena, un pitido cada tanto y un aviso del navegador (una vez por llamada)
    if (v.phase === "incoming") {
      if (!ringing) {
        beep();
        ringing = setInterval(beep, RING_BEEP_MS);
      }
      if (v.callId && announced !== v.callId) {
        announced = v.callId;
        showAlert({ key: v.callId, title: phaseText("incoming", v.kind, v.peer), body: "Abre Merida para contestar." }, { sound: false }, () => window.focus());
      }
    } else stopRing();

    if (v.phase === "active") {
      if (!ticking) ticking = setInterval(paintClock, 1000);
    } else stopTick();

    // lo terminado, rechazado o perdido se quita solo
    if (dismissing) clearTimeout(dismissing);
    dismissing = null;
    if (v.phase === "ended" || v.phase === "declined" || v.phase === "missed") dismissing = setTimeout(() => controller.dismiss(), DISMISS_MS);
  }

  const off = controller.on(render);
  render();
  return {
    el,
    destroy() {
      off();
      stopRing();
      stopTick();
      if (dismissing) clearTimeout(dismissing);
      el.remove();
    },
  };
}
