-- =====================================================================================================================
-- Kyora · chat · esquema completo de Supabase
--
-- Pégalo entero en Supabase > SQL Editor y pulsa Run. Se puede ejecutar varias veces sin error (es idempotente).
-- Crea: los tipos, las tablas (conversaciones, mensajes y adjuntos), la seguridad por fila (RLS), el bucket privado de
-- archivos con sus políticas, la publicación para Realtime y las funciones RPC que usa Kyora como "endpoints".
--
-- Modelo: una sola persona con varios dispositivos (PC y móvil) que entran con la misma cuenta de Supabase Auth.
-- Cada fila es de su dueño (owner_id = auth.uid()); nadie más ve ni toca nada.
-- =====================================================================================================================


-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Tipos
-- ---------------------------------------------------------------------------------------------------------------------

-- Qué clase de contenido es un mensaje (cualquiera: texto, fotos, audios, vídeos, archivos y todo lo demás).
do $$ begin
  create type public.message_kind as enum ('text', 'image', 'file', 'audio', 'video', 'other');
exception when duplicate_object then null; end $$;

-- Estado de envío: 'pending' = en espera (el dispositivo aún no consiguió enviarlo), 'sent' = enviado.
-- Para añadir más estados después: alter type public.message_status add value 'delivered';
do $$ begin
  create type public.message_status as enum ('pending', 'sent');
exception when duplicate_object then null; end $$;


-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Tablas
-- ---------------------------------------------------------------------------------------------------------------------

-- Conversaciones (canales). Kyora crea una llamada "General" la primera vez (ensure_default_conversation).
create table if not exists public.conversations (
  id          uuid        primary key default gen_random_uuid(),
  owner_id    uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  name        text        not null default 'General' check (length(btrim(name)) > 0),
  created_at  timestamptz not null default now()
);
create unique index if not exists conversations_owner_name_key on public.conversations (owner_id, name);

-- Mensajes. El id lo genera el dispositivo que envía: así, si reintenta un envío (sin internet, corte...), no se duplica.
create table if not exists public.messages (
  id              uuid                  primary key,
  conversation_id uuid                  not null references public.conversations (id) on delete cascade,
  owner_id        uuid                  not null default auth.uid() references auth.users (id) on delete cascade,
  sender_device   text                  not null default 'unknown',      -- 'pc', 'phone'...
  kind            public.message_kind   not null default 'text',
  body            text,                                                  -- el texto (o el pie de una foto o archivo)
  status          public.message_status not null default 'sent',
  sent_at         timestamptz           not null default now(),          -- la hora de envío, según el dispositivo
  created_at      timestamptz           not null default now(),          -- la hora en que llegó al servidor
  edited_at       timestamptz,
  deleted_at      timestamptz,                                           -- borrado suave: el mensaje deja de salir
  metadata        jsonb                 not null default '{}'::jsonb,    -- lo que haga falta (respuesta a otro mensaje...)
  constraint messages_text_needs_body check (kind <> 'text' or coalesce(length(body), 0) > 0)
);
create index if not exists messages_conversation_sent_idx on public.messages (conversation_id, sent_at desc, id desc);
create index if not exists messages_conversation_created_idx on public.messages (conversation_id, created_at);

-- Adjuntos de un mensaje (varios por mensaje). El archivo vive en Storage (bucket chat-files); aquí solo sus datos.
create table if not exists public.attachments (
  id            uuid        primary key default gen_random_uuid(),
  message_id    uuid        not null references public.messages (id) on delete cascade,
  owner_id      uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  storage_path  text        not null,                                   -- <owner_id>/<conversation_id>/<message_id>/<archivo>
  file_name     text        not null,
  mime_type     text        not null default 'application/octet-stream',
  size_bytes    bigint      not null default 0 check (size_bytes >= 0),
  width         integer,                                                -- fotos y vídeos
  height        integer,
  duration_ms   integer,                                                -- audios y vídeos
  thumb_path    text,                                                   -- miniatura en Storage (opcional)
  created_at    timestamptz not null default now()
);
create index if not exists attachments_message_idx on public.attachments (message_id);


-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Seguridad por fila (RLS): cada uno ve y toca solo lo suyo
-- ---------------------------------------------------------------------------------------------------------------------

alter table public.conversations enable row level security;
alter table public.messages      enable row level security;
alter table public.attachments   enable row level security;

revoke all on public.conversations, public.messages, public.attachments from anon;

-- conversations
drop policy if exists "conversations: owner select" on public.conversations;
drop policy if exists "conversations: owner insert" on public.conversations;
drop policy if exists "conversations: owner update" on public.conversations;
drop policy if exists "conversations: owner delete" on public.conversations;
create policy "conversations: owner select" on public.conversations for select to authenticated
  using (owner_id = (select auth.uid()));
create policy "conversations: owner insert" on public.conversations for insert to authenticated
  with check (owner_id = (select auth.uid()));
create policy "conversations: owner update" on public.conversations for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy "conversations: owner delete" on public.conversations for delete to authenticated
  using (owner_id = (select auth.uid()));

-- messages (solo se puede escribir en conversaciones propias)
drop policy if exists "messages: owner select" on public.messages;
drop policy if exists "messages: owner insert" on public.messages;
drop policy if exists "messages: owner update" on public.messages;
drop policy if exists "messages: owner delete" on public.messages;
create policy "messages: owner select" on public.messages for select to authenticated
  using (owner_id = (select auth.uid()));
create policy "messages: owner insert" on public.messages for insert to authenticated
  with check (
    owner_id = (select auth.uid())
    and exists (select 1 from public.conversations c where c.id = conversation_id and c.owner_id = (select auth.uid()))
  );
create policy "messages: owner update" on public.messages for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy "messages: owner delete" on public.messages for delete to authenticated
  using (owner_id = (select auth.uid()));

-- attachments (solo en mensajes propios)
drop policy if exists "attachments: owner select" on public.attachments;
drop policy if exists "attachments: owner insert" on public.attachments;
drop policy if exists "attachments: owner update" on public.attachments;
drop policy if exists "attachments: owner delete" on public.attachments;
create policy "attachments: owner select" on public.attachments for select to authenticated
  using (owner_id = (select auth.uid()));
create policy "attachments: owner insert" on public.attachments for insert to authenticated
  with check (
    owner_id = (select auth.uid())
    and exists (select 1 from public.messages m where m.id = message_id and m.owner_id = (select auth.uid()))
  );
create policy "attachments: owner update" on public.attachments for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy "attachments: owner delete" on public.attachments for delete to authenticated
  using (owner_id = (select auth.uid()));


-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Storage: bucket privado "chat-files" (50 MB por archivo, el máximo del plan gratuito; súbelo si tu plan lo permite)
--    Los archivos van en  <owner_id>/<conversation_id>/<message_id>/<archivo>  y solo los ve su dueño.
-- ---------------------------------------------------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit)
values ('chat-files', 'chat-files', false, 52428800)
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit;

drop policy if exists "chat-files: owner select" on storage.objects;
drop policy if exists "chat-files: owner insert" on storage.objects;
drop policy if exists "chat-files: owner update" on storage.objects;
drop policy if exists "chat-files: owner delete" on storage.objects;
create policy "chat-files: owner select" on storage.objects for select to authenticated
  using (bucket_id = 'chat-files' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "chat-files: owner insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'chat-files' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "chat-files: owner update" on storage.objects for update to authenticated
  using (bucket_id = 'chat-files' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'chat-files' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "chat-files: owner delete" on storage.objects for delete to authenticated
  using (bucket_id = 'chat-files' and (storage.foldername(name))[1] = (select auth.uid())::text);


-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Realtime: los mensajes y adjuntos nuevos llegan al instante a todos tus dispositivos
-- ---------------------------------------------------------------------------------------------------------------------

alter table public.messages    replica identity full;   -- los cambios y borrados traen la fila completa
alter table public.attachments replica identity full;

do $$ begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.attachments;
exception when duplicate_object then null; when undefined_object then null; end $$;


-- ---------------------------------------------------------------------------------------------------------------------
-- 6. Funciones RPC (los "endpoints" de Kyora): POST /rest/v1/rpc/<nombre>
--    Se ejecutan con tus permisos (security invoker): la seguridad por fila de arriba sigue mandando.
-- ---------------------------------------------------------------------------------------------------------------------

-- Un mensaje (con sus adjuntos) como JSON: {…fila del mensaje…, "attachments": [ … ]}
create or replace function public.message_json(p_message_id uuid)
returns jsonb
language sql stable security invoker set search_path = public
as $$
  select to_jsonb(m) || jsonb_build_object(
           'attachments',
           coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at, a.id)
                       from public.attachments a where a.message_id = m.id), '[]'::jsonb))
    from public.messages m
   where m.id = p_message_id;
$$;

-- La conversación "General": la crea la primera vez y devuelve su id.
create or replace function public.ensure_default_conversation()
returns uuid
language plpgsql security invoker set search_path = public
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select id into v_id from public.conversations where owner_id = auth.uid() order by created_at, id limit 1;
  if v_id is null then
    insert into public.conversations (name) values ('General')
      on conflict (owner_id, name) do nothing
      returning id into v_id;
    if v_id is null then
      select id into v_id from public.conversations where owner_id = auth.uid() order by created_at, id limit 1;
    end if;
  end if;
  return v_id;
end;
$$;

-- Envía un mensaje (texto y/o adjuntos ya subidos a Storage). Es atómico y se puede repetir con el mismo p_id sin duplicar:
-- el segundo intento devuelve el mensaje que ya existe. p_attachments es un arreglo JSON de
--   {"storage_path", "file_name", "mime_type", "size_bytes", "width", "height", "duration_ms", "thumb_path"}.
create or replace function public.send_message(
  p_id               uuid,
  p_conversation_id  uuid,
  p_body             text        default null,
  p_sent_at          timestamptz default now(),
  p_device           text        default 'unknown',
  p_attachments      jsonb       default '[]'::jsonb
)
returns jsonb
language plpgsql security invoker set search_path = public
as $$
declare
  v_attachments jsonb := coalesce(p_attachments, '[]'::jsonb);
  v_kind        public.message_kind := 'text';
  v_mime        text;
  v_rows        integer := 0;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if jsonb_typeof(v_attachments) <> 'array' then
    raise exception 'attachments_must_be_an_array' using errcode = '22023';
  end if;
  if coalesce(length(btrim(p_body)), 0) = 0 and jsonb_array_length(v_attachments) = 0 then
    raise exception 'empty_message' using errcode = '22023';
  end if;

  if jsonb_array_length(v_attachments) > 0 then   -- la clase del mensaje la da su primer adjunto
    v_mime := lower(coalesce(v_attachments -> 0 ->> 'mime_type', ''));
    v_kind := case
                when v_mime like 'image/%' then 'image'
                when v_mime like 'audio/%' then 'audio'
                when v_mime like 'video/%' then 'video'
                when v_mime = ''           then 'other'
                else 'file'
              end::public.message_kind;
  end if;

  insert into public.messages (id, conversation_id, kind, body, status, sent_at, sender_device)
  values (p_id, p_conversation_id, v_kind, nullif(btrim(p_body), ''), 'sent',
          coalesce(p_sent_at, now()), coalesce(nullif(btrim(p_device), ''), 'unknown'))
  on conflict (id) do nothing;
  get diagnostics v_rows = row_count;

  if v_rows > 0 then
    insert into public.attachments (message_id, storage_path, file_name, mime_type, size_bytes,
                                    width, height, duration_ms, thumb_path)
    select p_id,
           a ->> 'storage_path',
           coalesce(nullif(a ->> 'file_name', ''), 'archivo'),
           coalesce(nullif(a ->> 'mime_type', ''), 'application/octet-stream'),
           coalesce((a ->> 'size_bytes')::bigint, 0),
           (a ->> 'width')::integer,
           (a ->> 'height')::integer,
           (a ->> 'duration_ms')::integer,
           a ->> 'thumb_path'
      from jsonb_array_elements(v_attachments) a;
  elsif not exists (select 1 from public.messages where id = p_id) then
    raise exception 'message_id_taken' using errcode = '42501';   -- ese id es de otra cuenta
  end if;

  return public.message_json(p_id);
end;
$$;

-- El historial de una conversación, del más antiguo al más nuevo, con sus adjuntos.
--   p_before: solo lo enviado antes de esa hora (para cargar más hacia atrás)
--   p_after:  solo lo que llegó al servidor después de esa hora (para ponerse al día tras una desconexión)
create or replace function public.list_messages(
  p_conversation_id uuid,
  p_before          timestamptz default null,
  p_after           timestamptz default null,
  p_limit           integer     default 50
)
returns jsonb
language sql stable security invoker set search_path = public
as $$
  select coalesce(jsonb_agg(public.message_json(t.id) order by t.sent_at, t.id), '[]'::jsonb)
    from (
      select m.id, m.sent_at
        from public.messages m
       where m.conversation_id = p_conversation_id
         and m.deleted_at is null
         and (p_before is null or m.sent_at < p_before)
         and (p_after  is null or m.created_at > p_after)
       order by m.sent_at desc, m.id desc
       limit least(greatest(coalesce(p_limit, 50), 1), 200)
    ) t;
$$;

-- Borra un mensaje (borrado suave: deja de salir en el historial y en los dispositivos).
create or replace function public.delete_message(p_id uuid)
returns jsonb
language plpgsql security invoker set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  update public.messages set deleted_at = now() where id = p_id and deleted_at is null;
  return public.message_json(p_id);
end;
$$;

-- Solo usuarios con sesión pueden llamarlas (nada de anónimos).
revoke all on function public.message_json(uuid)                                          from public, anon;
revoke all on function public.ensure_default_conversation()                               from public, anon;
revoke all on function public.send_message(uuid, uuid, text, timestamptz, text, jsonb)    from public, anon;
revoke all on function public.list_messages(uuid, timestamptz, timestamptz, integer)      from public, anon;
revoke all on function public.delete_message(uuid)                                        from public, anon;
grant execute on function public.message_json(uuid)                                       to authenticated;
grant execute on function public.ensure_default_conversation()                            to authenticated;
grant execute on function public.send_message(uuid, uuid, text, timestamptz, text, jsonb) to authenticated;
grant execute on function public.list_messages(uuid, timestamptz, timestamptz, integer)   to authenticated;
grant execute on function public.delete_message(uuid)                                    to authenticated;

-- Fin. Ahora crea tu usuario en Authentication > Users (ver supabase/README.md).
