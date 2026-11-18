import type { RealtimeChannel, SupabaseClient } from "@supabase/supabase-js";
import type { LiveState } from "./chat";

/** Llamadas de voz y video de la familia (Server/supabase/schema.sql §18). Aquí vive lo que no toca el navegador:
 *  - los tipos y la máquina de estados de una llamada (pura, se prueba sin red);
 *  - las operaciones sobre family_calls y family_call_signals (insertar, contestar, colgar, señales);
 *  - la escucha de Realtime.
 * El audio y el video van directos entre navegadores (WebRTC, ver webrtc.ts); Supabase solo pasa las señales para encontrarse. */

export type CallKind = "audio" | "video";
export type CallStatus = "ringing" | "active" | "ended" | "declined" | "missed";
export type SignalKind = "offer" | "answer" | "candidate";

export interface CallRow {
  id: string;
  caller_id: string;
  kind: CallKind;
  status: CallStatus;
  answered_by: string | null;
  created_at: string;
  ended_at: string | null;
}

export interface SignalRow {
  id: string;
  call_id: string;
  sender_id: string;
  kind: SignalKind;
  payload: unknown;
  created_at: string;
}

/** Cuánto suena una llamada sin contestar antes de quedar «perdida». */
export const RING_TIMEOUT_MS = 30_000;

/** Cómo ve una llamada quien mira: nada, llamando (yo llamé), entrante (me llaman), en curso o terminada de una forma u otra. */
export type CallPhase = "idle" | "calling" | "incoming" | "active" | "ended" | "declined" | "missed";

export type CallEvent =
  | "start" // yo empiezo una llamada
  | "incoming" // alguien me llama
  | "answered" // el otro contestó mi llamada
  | "accept" // yo contesto
  | "decline" // yo la rechazo
  | "declined" // el otro la rechazó
  | "hangup" // yo cuelgo
  | "remote-ended" // el otro colgó
  | "timeout" // nadie contestó a tiempo
  | "taken" // otro miembro de la familia contestó antes que yo
  | "reset"; // se quita el aviso de lo ocurrido

/** La máquina de estados de una llamada, vista por quien mira. Un evento que no toca en ese momento no cambia nada. */
export function nextCallState(phase: CallPhase, event: CallEvent): CallPhase {
  if (event === "reset") return phase === "idle" || phase === "calling" || phase === "incoming" || phase === "active" ? phase : "idle";
  switch (phase) {
    case "idle":
    case "ended":
    case "declined":
    case "missed":
      if (event === "start") return "calling";
      if (event === "incoming") return "incoming";
      return phase;
    case "calling":
      if (event === "answered") return "active";
      if (event === "declined") return "declined";
      if (event === "timeout") return "missed";
      if (event === "hangup") return "ended";
      return phase;
    case "incoming":
      if (event === "accept") return "active";
      if (event === "decline") return "declined";
      if (event === "timeout" || event === "remote-ended") return "missed";
      if (event === "taken") return "idle";
      return phase;
    case "active":
      if (event === "hangup" || event === "remote-ended") return "ended";
      return phase;
  }
}

/** La fase que corresponde a una fila de la base de datos para este usuario. Una llamada que otro miembro contestó no me suena. */
export function phaseOf(call: Pick<CallRow, "caller_id" | "status" | "answered_by">, userId: string): CallPhase {
  const mine = call.caller_id === userId;
  switch (call.status) {
    case "ringing":
      return mine ? "calling" : "incoming";
    case "active":
      return mine || call.answered_by === userId ? "active" : "idle";
    case "declined":
      return mine ? "declined" : "idle";
    case "missed":
      return "missed";
    case "ended":
      return "ended";
  }
}

/** «02:05» o «1:02:05»: lo que lleva una llamada en curso. */
export function formatDuration(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const two = (n: number) => String(n).padStart(2, "0");
  return h ? `${h}:${two(m)}:${two(s)}` : `${two(m)}:${two(s)}`;
}

/** La frase para cada fase (se dice en el panel de la llamada). `who` es la otra persona, si se sabe. */
export function phaseText(phase: CallPhase, kind: CallKind, who: string | null): string {
  const what = kind === "video" ? "videollamada" : "llamada";
  const name = who ?? "la familia";
  switch (phase) {
    case "calling":
      return `Llamando a ${name}…`;
    case "incoming":
      return `${what[0].toUpperCase()}${what.slice(1)} de ${name}`;
    case "active":
      return `En ${what} con ${name}`;
    case "declined":
      return `${name} no pudo contestar.`;
    case "missed":
      return `${what[0].toUpperCase()}${what.slice(1)} perdida con ${name}`;
    case "ended":
      return `${what[0].toUpperCase()}${what.slice(1)} terminada`;
    case "idle":
      return "";
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Base de datos

/** Empieza una llamada: queda «sonando» para toda la familia. */
export async function startCall(client: SupabaseClient, userId: string, kind: CallKind, id: string = crypto.randomUUID()): Promise<CallRow> {
  const { data, error } = await client.from("family_calls").insert({ id, caller_id: userId, kind }).select().single();
  if (error) throw error;
  return data as CallRow;
}

/** Contesta. Devuelve false si otro miembro se adelantó (la llamada ya no estaba sonando). */
export async function answerCall(client: SupabaseClient, userId: string, callId: string): Promise<boolean> {
  const { data, error } = await client.from("family_calls").update({ status: "active", answered_by: userId }).eq("id", callId).eq("status", "ringing").select();
  if (error) throw error;
  return (data ?? []).length > 0;
}

/** Termina una llamada que sigue sonando o en curso (rechazada, perdida o colgada). Repetirlo no cambia nada. */
export async function finishCall(client: SupabaseClient, callId: string, status: "ended" | "declined" | "missed", now: Date = new Date()): Promise<void> {
  const { error } = await client.from("family_calls").update({ status, ended_at: now.toISOString() }).eq("id", callId).in("status", ["ringing", "active"]);
  if (error) throw error;
}

export async function sendSignal(client: SupabaseClient, callId: string, userId: string, kind: SignalKind, payload: unknown): Promise<void> {
  const { error } = await client.from("family_call_signals").insert({ call_id: callId, sender_id: userId, kind, payload });
  if (error) throw error;
}

/** Las señales que ya se mandaron en una llamada, en orden (quien contesta tarde necesita la oferta que llegó antes). */
export async function listSignals(client: SupabaseClient, callId: string): Promise<SignalRow[]> {
  const { data, error } = await client.from("family_call_signals").select("*").eq("call_id", callId).order("created_at", { ascending: true });
  if (error) throw error;
  return (data ?? []) as SignalRow[];
}

/** Escucha las llamadas y sus señales. Devuelve la función que deja de escuchar. */
export function watchCalls(
  client: SupabaseClient,
  handlers: { onCall: (call: CallRow) => void; onSignal: (signal: SignalRow) => void },
  onState: (state: LiveState) => void = () => {},
): () => void {
  onState("connecting");
  const channel: RealtimeChannel = client
    .channel(`merida-calls-${Date.now()}`)
    .on("postgres_changes", { event: "*", schema: "public", table: "family_calls" }, (payload) => {
      if (payload.eventType !== "DELETE" && payload.new) handlers.onCall(payload.new as CallRow);
    })
    .on("postgres_changes", { event: "INSERT", schema: "public", table: "family_call_signals" }, (payload) => {
      if (payload.new) handlers.onSignal(payload.new as SignalRow);
    })
    .subscribe((status) => {
      if (status === "SUBSCRIBED") onState("live");
      else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT" || status === "CLOSED") onState("offline");
    });
  return () => {
    void client.removeChannel(channel);
  };
}
