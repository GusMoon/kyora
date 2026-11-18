import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  RING_TIMEOUT_MS,
  answerCall,
  finishCall,
  formatDuration,
  listSignals,
  nextCallState,
  phaseOf,
  phaseText,
  sendSignal,
  startCall,
  watchCalls,
  type CallEvent,
  type CallPhase,
  type CallRow,
  type SignalRow,
} from "../src/data/calls";
import { CallController } from "../src/data/call-controller";
import { CallSession, browserEnv, constraintsFor } from "../src/data/webrtc";
import { callPanel } from "../src/ui/call-panel";
import { ICE_SERVERS } from "../src/config";
import { fakeClient, fakeEnv, flush, type TableCall } from "./family-fakes";

const NOW = Date.parse("2026-11-15T12:00:00Z");
const row = (over: Partial<CallRow> = {}): CallRow => ({ id: "call-1", caller_id: "papa", kind: "audio", status: "ringing", answered_by: null, created_at: new Date(NOW).toISOString(), ended_at: null, ...over });
const signal = (over: Partial<SignalRow> = {}): SignalRow => ({ id: "s1", call_id: "call-1", sender_id: "papa", kind: "offer", payload: { type: "offer", sdp: "o" }, created_at: new Date(NOW).toISOString(), ...over });

afterEach(() => {
  document.body.replaceChildren();
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe("llamadas: la máquina de estados", () => {
  const table: [CallPhase, CallEvent, CallPhase][] = [
    ["idle", "start", "calling"],
    ["idle", "incoming", "incoming"],
    ["calling", "answered", "active"],
    ["calling", "declined", "declined"],
    ["calling", "timeout", "missed"],
    ["calling", "hangup", "ended"],
    ["incoming", "accept", "active"],
    ["incoming", "decline", "declined"],
    ["incoming", "timeout", "missed"],
    ["incoming", "remote-ended", "missed"],
    ["incoming", "taken", "idle"],
    ["active", "hangup", "ended"],
    ["active", "remote-ended", "ended"],
    ["ended", "start", "calling"],
    ["missed", "incoming", "incoming"],
    ["declined", "reset", "idle"],
    ["ended", "reset", "idle"],
    ["missed", "reset", "idle"],
  ];
  it.each(table)("%s + %s → %s", (from, event, to) => {
    expect(nextCallState(from, event)).toBe(to);
  });

  it("un evento que no toca en ese momento no cambia nada", () => {
    expect(nextCallState("idle", "hangup")).toBe("idle");
    expect(nextCallState("active", "start")).toBe("active");
    expect(nextCallState("calling", "accept")).toBe("calling");
    expect(nextCallState("incoming", "answered")).toBe("incoming");
    expect(nextCallState("active", "reset")).toBe("active"); // no se quita el aviso de una llamada en curso
  });

  it("una fila de la base de datos se ve distinto según quién mira", () => {
    expect(phaseOf(row(), "papa")).toBe("calling");
    expect(phaseOf(row(), "mama")).toBe("incoming");
    expect(phaseOf(row({ status: "active", answered_by: "mama" }), "papa")).toBe("active");
    expect(phaseOf(row({ status: "active", answered_by: "mama" }), "mama")).toBe("active");
    expect(phaseOf(row({ status: "active", answered_by: "mama" }), "abuela")).toBe("idle"); // otra la contestó: ya no me suena
    expect(phaseOf(row({ status: "declined" }), "papa")).toBe("declined");
    expect(phaseOf(row({ status: "declined" }), "mama")).toBe("idle");
    expect(phaseOf(row({ status: "missed" }), "mama")).toBe("missed");
    expect(phaseOf(row({ status: "ended" }), "papa")).toBe("ended");
  });

  it("el cronómetro y las frases", () => {
    expect(formatDuration(0)).toBe("00:00");
    expect(formatDuration(125_000)).toBe("02:05");
    expect(formatDuration(3_725_000)).toBe("1:02:05");
    expect(formatDuration(-5)).toBe("00:00");
    expect(phaseText("calling", "audio", "mamá")).toBe("Llamando a mamá…");
    expect(phaseText("incoming", "video", "papá")).toBe("Videollamada de papá");
    expect(phaseText("active", "audio", null)).toBe("En llamada con la familia");
    expect(phaseText("missed", "audio", "papá")).toBe("Llamada perdida con papá");
    expect(phaseText("idle", "audio", null)).toBe("");
  });
});

describe("llamadas: la base de datos", () => {
  it("empieza una llamada con su id, quién llama y si es de voz o de video", async () => {
    const { client, tableCalls } = fakeClient({ table: (c) => (c.op === "insert" ? { data: row({ kind: "video" }) } : undefined) });
    const call = await startCall(client, "papa", "video", "call-1");
    expect(tableCalls[0]).toMatchObject({ table: "family_calls", op: "insert", payload: { id: "call-1", caller_id: "papa", kind: "video" } });
    expect(call.kind).toBe("video");
  });

  it("contestar solo gana si la llamada seguía sonando (otra persona pudo adelantarse)", async () => {
    let free = true;
    const { client, tableCalls } = fakeClient({ table: () => ({ data: free ? [row({ status: "active" })] : [] }) });
    expect(await answerCall(client, "mama", "call-1")).toBe(true);
    expect(tableCalls[0]).toMatchObject({ op: "update", payload: { status: "active", answered_by: "mama" } });
    expect(tableCalls[0].filters).toEqual([["id", "eq", "call-1"], ["status", "eq", "ringing"]]);
    free = false;
    expect(await answerCall(client, "abuela", "call-1")).toBe(false);
  });

  it("colgar, rechazar o dar por perdida solo afecta a una llamada que sigue sonando o en curso", async () => {
    const { client, tableCalls } = fakeClient();
    await finishCall(client, "call-1", "declined", new Date(NOW));
    expect(tableCalls[0]).toMatchObject({ op: "update", payload: { status: "declined", ended_at: new Date(NOW).toISOString() } });
    expect(tableCalls[0].filters).toContainEqual(["status", "in", ["ringing", "active"]]);
  });

  it("manda y lee las señales de WebRTC de una llamada", async () => {
    const { client, tableCalls } = fakeClient({ table: (c) => (c.op === "select" ? { data: [signal()] } : undefined) });
    await sendSignal(client, "call-1", "papa", "candidate", { candidate: "x" });
    expect(tableCalls[0]).toMatchObject({ table: "family_call_signals", op: "insert", payload: { call_id: "call-1", sender_id: "papa", kind: "candidate", payload: { candidate: "x" } } });
    expect(await listSignals(client, "call-1")).toHaveLength(1);
  });

  it("un error del servidor se lanza", async () => {
    const { client } = fakeClient({ table: () => ({ error: { message: "no", code: "42501" } }) });
    await expect(startCall(client, "papa", "audio")).rejects.toMatchObject({ code: "42501" });
    await expect(sendSignal(client, "c", "p", "offer", {})).rejects.toBeTruthy();
  });

  it("escucha las llamadas y sus señales en vivo (los borrados no cuentan)", async () => {
    const { client, emit, removedChannels } = fakeClient();
    const calls: CallRow[] = [];
    const signals: SignalRow[] = [];
    const stop = watchCalls(client, { onCall: (c) => calls.push(c), onSignal: (s) => signals.push(s) });
    await flush();
    emit("family_calls", "INSERT", row());
    emit("family_calls", "UPDATE", row({ status: "active" }));
    emit("family_calls", "DELETE", row());
    emit("family_call_signals", "INSERT", signal());
    expect(calls.map((c) => c.status)).toEqual(["ringing", "active"]);
    expect(signals).toHaveLength(1);
    stop();
    expect(removedChannels).toHaveLength(1);
  });
});

describe("llamadas: WebRTC", () => {
  const start = async (role: "caller" | "callee", kind: "audio" | "video" = "audio", env = fakeEnv()) => {
    const sent: { kind: string; payload: unknown }[] = [];
    const remote: unknown[] = [];
    const states: string[] = [];
    const session = new CallSession({ env: env.env, kind, role, send: async (k, p) => void sent.push({ kind: k, payload: p }), onRemote: (s) => remote.push(s), onConnection: (s) => states.push(s) });
    await session.start();
    return { session, sent, remote, states, ...env };
  };

  it("el navegador de pruebas no tiene WebRTC: se avisa y no se rompe", () => {
    expect(browserEnv()).toBeNull();
    expect(constraintsFor("audio").video).toBe(false);
    expect(constraintsFor("video").video).toBe(true);
  });

  it("quien llama saca el micrófono, arma la conexión con el STUN y manda la oferta", async () => {
    const { session, sent, peers, requested, states } = await start("caller");
    expect(requested).toHaveLength(1);
    expect(peers[0].config).toEqual({ iceServers: ICE_SERVERS });
    expect(peers[0].added).toHaveLength(1); // solo el micrófono
    expect(states).toEqual(["connecting"]);
    expect(sent).toEqual([]); // la oferta se manda aparte, cuando la llamada ya está registrada
    await session.offer();
    expect(sent).toEqual([{ kind: "offer", payload: { type: "offer", sdp: "sdp-offer" } }]);
    expect(peers[0].localDescription).toEqual({ type: "offer", sdp: "sdp-offer" });
  });

  it("en video también se pide la cámara", async () => {
    const { requested, peers } = await start("caller", "video");
    expect(requested[0].video).toBe(true);
    expect(peers[0].added.map((t) => t.kind)).toEqual(["audio", "video"]);
  });

  it("quien contesta recibe la oferta y responde con su respuesta", async () => {
    const { session, sent, peers } = await start("callee");
    await session.handleSignal("offer", { type: "offer", sdp: "o" });
    expect(peers[0].remoteDescription).toEqual({ type: "offer", sdp: "o" });
    expect(sent).toEqual([{ kind: "answer", payload: { type: "answer", sdp: "sdp-answer" } }]);
  });

  it("quien llama recibe la respuesta y la acepta", async () => {
    const { session, peers } = await start("caller");
    await session.handleSignal("answer", { type: "answer", sdp: "a" });
    expect(peers[0].remoteDescription).toEqual({ type: "answer", sdp: "a" });
  });

  it("los candidatos que llegan antes que la descripción esperan y luego se aplican en orden", async () => {
    const { session, peers } = await start("callee");
    await session.handleSignal("candidate", { candidate: "c1" });
    await session.handleSignal("candidate", { candidate: "c2" });
    expect(peers[0].candidates).toEqual([]);
    await session.handleSignal("offer", { type: "offer", sdp: "o" });
    await session.handleSignal("candidate", { candidate: "c3" });
    expect(peers[0].candidates).toEqual([{ candidate: "c1" }, { candidate: "c2" }, { candidate: "c3" }]);
  });

  it("las señales se procesan en orden aunque lleguen antes de terminar de arrancar", async () => {
    const env = fakeEnv();
    const sent: string[] = [];
    const session = new CallSession({ env: env.env, kind: "audio", role: "callee", send: async (k) => void sent.push(k), onRemote: () => {}, onConnection: () => {} });
    const early = session.handleSignal("offer", { type: "offer", sdp: "o" }); // aún sin `start`
    await session.start();
    await early;
    expect(sent).toEqual(["answer"]);
  });

  it("manda al otro lado cada candidato que encuentra, y avisa del video del otro y del estado", async () => {
    const { peers, sent, remote, states } = await start("caller");
    peers[0].fireCandidate({ candidate: "mio" });
    expect(sent).toEqual([{ kind: "candidate", payload: { candidate: "mio" } }]);
    const stream = { id: "remoto" };
    peers[0].ontrack?.({ streams: [stream] });
    expect(remote).toEqual([stream]);
    peers[0].fireState("connected");
    peers[0].fireState("failed");
    peers[0].fireState("disconnected");
    expect(states).toEqual(["connecting", "connected", "failed", "closed"]);
  });

  it("silenciar apaga solo el micrófono y apagar la cámara solo el video", async () => {
    const { session, streams } = await start("caller", "video");
    session.setMuted(true);
    expect(streams[0].getAudioTracks()[0].enabled).toBe(false);
    expect(streams[0].getVideoTracks()[0].enabled).toBe(true);
    session.setCameraOff(true);
    expect(streams[0].getVideoTracks()[0].enabled).toBe(false);
    session.setMuted(false);
    expect(streams[0].getAudioTracks()[0].enabled).toBe(true);
  });

  it("colgar para el micrófono y la cámara, cierra la conexión y se puede repetir", async () => {
    const { session, streams, peers } = await start("caller", "video");
    session.close();
    session.close();
    expect(streams[0].getTracks().every((t) => t.stopped)).toBe(true);
    expect(peers[0].closed).toBe(true);
    expect(session.localStream).toBeNull();
  });

  it("sin permiso de micrófono, empezar lanza el error", async () => {
    const env = fakeEnv({ denyMedia: true });
    const session = new CallSession({ env: env.env, kind: "audio", role: "caller", send: async () => {}, onRemote: () => {}, onConnection: () => {} });
    await expect(session.start()).rejects.toThrow(/Permission denied/);
    expect(env.peers).toHaveLength(0);
  });
});

describe("llamadas: el controlador", () => {
  beforeEach(() => vi.useFakeTimers({ now: NOW, toFake: ["setTimeout", "clearTimeout", "setInterval", "clearInterval", "Date"] }));

  const members = [{ id: "papa", username: "papá" }, { id: "mama", username: "mamá" }];

  /** Una llamada desde `userId`; las filas de family_calls y las señales viven en `store`. */
  function setup(userId: string, opts: { env?: ReturnType<typeof fakeEnv> | null; won?: boolean; signals?: SignalRow[] } = {}) {
    const env = opts.env === undefined ? fakeEnv() : opts.env;
    const log: TableCall[] = [];
    const fake = fakeClient({
      table: (c) => {
        log.push(c);
        if (c.table === "family_calls" && c.op === "insert") return { data: row({ ...(c.payload as object) }) };
        if (c.table === "family_calls" && c.op === "update" && (c.payload as { status: string }).status === "active") return { data: opts.won === false ? [] : [row({ status: "active", answered_by: userId })] };
        if (c.table === "family_call_signals" && c.op === "select") return { data: opts.signals ?? [] };
        return undefined;
      },
    });
    const controller = new CallController({ client: fake.client, userId, env: env?.env ?? null, members: () => members, now: () => Date.now() });
    const finished = () => log.filter((c) => c.table === "family_calls" && c.op === "update" && !["active"].includes((c.payload as { status: string }).status)).map((c) => (c.payload as { status: string }).status);
    const signalsSent = () => log.filter((c) => c.table === "family_call_signals" && c.op === "insert").map((c) => (c.payload as { kind: string }).kind);
    return { controller, env, log, finished, signalsSent, ...fake };
  }

  it("llamar: pide el micrófono, registra la llamada, manda la oferta y queda sonando", async () => {
    const { controller, log, signalsSent, env } = setup("papa");
    await controller.start("audio");
    expect(controller.view).toMatchObject({ phase: "calling", kind: "audio", connection: "connecting" });
    expect(log.find((c) => c.table === "family_calls" && c.op === "insert")?.payload).toMatchObject({ caller_id: "papa", kind: "audio" });
    expect(signalsSent()).toEqual(["offer"]);
    expect(env!.requested).toHaveLength(1);
  });

  it("si no hay permiso de micrófono no suena nada en las otras casas", async () => {
    const { controller, log } = setup("papa", { env: fakeEnv({ denyMedia: true }) });
    await controller.start("audio");
    expect(controller.view.phase).toBe("idle");
    expect(controller.view.error).toMatch(/No se pudo llamar/);
    expect(log.filter((c) => c.table === "family_calls")).toHaveLength(0);
  });

  it("sin WebRTC en el navegador lo dice y no llama", async () => {
    const { controller, log } = setup("papa", { env: null });
    await controller.start("video");
    expect(controller.view.phase).toBe("idle");
    expect(controller.view.error).toMatch(/no permite llamadas/);
    expect(log).toHaveLength(0);
  });

  it("cuando la otra persona contesta, la llamada pasa a en curso con su nombre y su cronómetro", async () => {
    const { controller } = setup("papa");
    await controller.start("audio");
    controller.handleCall(row({ id: controller.view.callId!, status: "active", answered_by: "mama" }));
    expect(controller.view).toMatchObject({ phase: "active", peer: "mamá", startedAt: NOW });
  });

  it("si nadie contesta en 30 segundos queda perdida y se registra así", async () => {
    const { controller, finished, env } = setup("papa");
    await controller.start("audio");
    await vi.advanceTimersByTimeAsync(RING_TIMEOUT_MS + 10);
    expect(controller.view.phase).toBe("missed");
    expect(finished()).toEqual(["missed"]);
    expect(env!.streams[0].getTracks().every((t) => t.stopped)).toBe(true); // el micrófono se suelta
  });

  it("si la otra persona rechaza, se ve y se cuelga todo", async () => {
    const { controller, env } = setup("papa");
    await controller.start("audio");
    controller.handleCall(row({ id: controller.view.callId!, status: "declined" }));
    expect(controller.view.phase).toBe("declined");
    expect(env!.peers[0].closed).toBe(true);
  });

  it("colgar mientras suena (cancelar) o en curso registra que terminó y suelta el micrófono", async () => {
    const { controller, finished, env } = setup("papa");
    await controller.start("audio");
    await controller.hangup();
    expect(controller.view.phase).toBe("ended");
    expect(finished()).toEqual(["ended"]);
    expect(env!.streams[0].getTracks().every((t) => t.stopped)).toBe(true);
  });

  it("una llamada nueva de otra persona suena; contestarla pide el micrófono, gana la llamada y aplica la oferta", async () => {
    const { controller, env, signalsSent } = setup("mama", { signals: [signal()] });
    controller.handleCall(row());
    expect(controller.view).toMatchObject({ phase: "incoming", peer: "papá", callId: "call-1" });
    await controller.accept();
    await vi.advanceTimersByTimeAsync(10);
    expect(controller.view.phase).toBe("active");
    expect(env!.peers[0].remoteDescription).toEqual({ type: "offer", sdp: "o" });
    expect(signalsSent()).toEqual(["answer"]);
  });

  it("las señales repetidas (la lista y Realtime traen la misma) y las propias se aplican una sola vez o ninguna", async () => {
    const { controller, env } = setup("mama", { signals: [signal()] });
    controller.handleCall(row());
    await controller.accept();
    controller.handleSignal(signal()); // la misma oferta por Realtime
    controller.handleSignal(signal({ id: "mia", sender_id: "mama", kind: "candidate", payload: { candidate: "mio" } })); // una mía
    controller.handleSignal(signal({ id: "otra-llamada", call_id: "otra", kind: "candidate" }));
    controller.handleSignal(signal({ id: "c1", kind: "candidate", payload: { candidate: "suyo" } }));
    await vi.advanceTimersByTimeAsync(10);
    expect(env!.peers[0].candidates).toEqual([{ candidate: "suyo" }]);
  });

  it("si otro miembro de la familia contesta antes, la llamada deja de sonar sin avisar de perdida", async () => {
    const { controller, env } = setup("mama", { won: false });
    controller.handleCall(row());
    await controller.accept();
    expect(controller.view.phase).toBe("idle");
    expect(env!.streams[0].getTracks().every((t) => t.stopped)).toBe(true);
  });

  it("si otra persona contesta mientras me suena, se quita sin más", () => {
    const { controller } = setup("mama");
    controller.handleCall(row());
    controller.handleCall(row({ status: "active", answered_by: "abuela" }));
    expect(controller.view.phase).toBe("idle");
  });

  it("rechazar la registra y vuelve a reposo", async () => {
    const { controller, finished } = setup("mama");
    controller.handleCall(row());
    await controller.decline();
    expect(controller.view.phase).toBe("idle");
    expect(finished()).toEqual(["declined"]);
  });

  it("si quien llamó cuelga antes de contestar, la perdí", () => {
    const { controller } = setup("mama");
    controller.handleCall(row());
    controller.handleCall(row({ status: "ended" }));
    expect(controller.view.phase).toBe("missed");
  });

  it("no suena una llamada vieja (al abrir Merida después) ni la que yo mismo hice, ni con otra en curso", () => {
    const old = setup("mama").controller;
    old.handleCall(row({ created_at: new Date(NOW - 5 * 60_000).toISOString() }));
    expect(old.view.phase).toBe("idle");
    const mine = setup("papa").controller;
    mine.handleCall(row());
    expect(mine.view.phase).toBe("idle");
    const busy = setup("mama").controller;
    busy.handleCall(row());
    busy.handleCall(row({ id: "call-2", caller_id: "abuela" }));
    expect(busy.view.callId).toBe("call-1");
  });

  it("silenciar y apagar la cámara cambian el estado y las pistas", async () => {
    const { controller, env } = setup("papa");
    await controller.start("video");
    controller.handleCall(row({ id: controller.view.callId!, kind: "video", status: "active", answered_by: "mama" }));
    controller.toggleMute();
    controller.toggleCamera();
    expect(controller.view).toMatchObject({ muted: true, cameraOff: true });
    expect(env!.streams[0].getAudioTracks()[0].enabled).toBe(false);
    expect(env!.streams[0].getVideoTracks()[0].enabled).toBe(false);
    controller.toggleMute();
    expect(controller.view.muted).toBe(false);
  });

  it("dejar de escuchar cuelga lo que haya y no deja el micrófono abierto", async () => {
    const { controller, env } = setup("papa");
    const detach = controller.attach();
    await controller.start("audio");
    detach();
    expect(controller.view.phase).toBe("idle");
    expect(env!.streams[0].getTracks().every((t) => t.stopped)).toBe(true);
  });

  it("escuchar por Realtime hace sonar la llamada que entra", async () => {
    const { controller, emit } = setup("mama");
    controller.attach();
    emit("family_calls", "INSERT", row());
    expect(controller.view.phase).toBe("incoming");
  });
});

describe("llamadas: el panel flotante", () => {
  beforeEach(() => vi.useFakeTimers({ now: NOW, toFake: ["setTimeout", "clearTimeout", "setInterval", "clearInterval", "Date"] }));
  const members = [{ id: "papa", username: "papá" }, { id: "mama", username: "mamá" }];
  const make = (userId: string) => {
    const env = fakeEnv();
    const fake = fakeClient({ table: (c) => (c.op === "update" && (c.payload as { status: string }).status === "active" ? { data: [row({ status: "active" })] } : c.op === "insert" ? { data: row() } : undefined) });
    const controller = new CallController({ client: fake.client, userId, env: env.env, members: () => members, now: () => Date.now() });
    const panel = callPanel(controller, { now: () => Date.now() });
    document.body.append(panel.el);
    return { controller, panel, env, ...fake };
  };
  const btn = (el: HTMLElement, key: string) => el.querySelector<HTMLButtonElement>(`[data-call="${key}"]`);

  it("en reposo no se ve", () => {
    const { panel } = make("mama");
    expect(panel.el.hidden).toBe(true);
  });

  it("una llamada entrante se ve con Contestar y Rechazar, y no es una ventana modal (Esc sigue funcionando)", () => {
    const { controller, panel } = make("mama");
    controller.handleCall(row());
    expect(panel.el.hidden).toBe(false);
    expect(panel.el.dataset.phase).toBe("incoming");
    expect(panel.el.querySelector(".call-title")?.textContent).toBe("Llamada de papá");
    expect(btn(panel.el, "accept")).not.toBeNull();
    expect(btn(panel.el, "decline")).not.toBeNull();
    expect(panel.el.getAttribute("aria-modal")).toBeNull();
  });

  it("Contestar contesta; en curso muestra el cronómetro, silenciar y colgar", async () => {
    const { controller, panel } = make("mama");
    controller.handleCall(row());
    btn(panel.el, "accept")!.click();
    await vi.advanceTimersByTimeAsync(10);
    expect(panel.el.dataset.phase).toBe("active");
    await vi.advanceTimersByTimeAsync(65_000);
    expect(panel.el.querySelector(".call-clock")?.textContent).toBe("01:05");
    expect(btn(panel.el, "camera")).toBeNull(); // en una llamada de voz no hay botón de cámara
    btn(panel.el, "mute")!.click();
    expect(controller.view.muted).toBe(true);
    expect(btn(panel.el, "mute")!.textContent).toContain("Activar micrófono");
    btn(panel.el, "hangup")!.click();
    await vi.advanceTimersByTimeAsync(10);
    expect(panel.el.dataset.phase).toBe("ended");
  });

  it("en videollamada hay botón de cámara y se ven los videos", async () => {
    const { controller, panel } = make("papa");
    await controller.start("video");
    controller.handleCall(row({ kind: "video", status: "active", answered_by: "mama" }));
    expect(panel.el.querySelector<HTMLElement>(".call-stage")!.hidden).toBe(false);
    btn(panel.el, "camera")!.click();
    expect(btn(panel.el, "camera")!.textContent).toContain("Encender cámara");
  });

  it("lo terminado se quita solo a los pocos segundos", async () => {
    const { controller, panel } = make("mama");
    controller.handleCall(row());
    controller.handleCall(row({ status: "missed" }));
    expect(panel.el.querySelector(".call-title")?.textContent).toMatch(/perdida/);
    await vi.advanceTimersByTimeAsync(4100);
    expect(panel.el.hidden).toBe(true);
  });

  it("un error se muestra aunque no haya llamada, con su botón de cerrar", async () => {
    const env = fakeEnv();
    const fake = fakeClient();
    const controller = new CallController({ client: fake.client, userId: "papa", env: null, members: () => members });
    void env;
    const panel = callPanel(controller);
    await controller.start("audio");
    expect(panel.el.hidden).toBe(false);
    expect(panel.el.querySelector(".call-problem")?.textContent).toMatch(/no permite llamadas/);
    btn(panel.el, "dismiss")!.click();
    expect(panel.el.hidden).toBe(true);
  });

  it("destruir el panel lo quita de la página", () => {
    const { panel } = make("mama");
    panel.destroy();
    expect(document.querySelector(".call-panel")).toBeNull();
  });
});
