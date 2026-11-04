-- =====================================================================================================================
-- Kyora · chat · esquema completo de Supabase
--
-- Pégalo entero en Supabase > SQL Editor y pulsa Run. Se puede ejecutar varias veces sin error (es idempotente).
-- Crea: los tipos, las tablas (conversaciones, mensajes, adjuntos y canciones), la seguridad por fila (RLS), el bucket
-- privado de archivos con sus políticas, la publicación para Realtime y las funciones RPC que usa Kyora como "endpoints".
--
-- Modelo: el ADMINISTRADOR (tú) con varios dispositivos (PC y móvil) entra con la misma cuenta de Supabase Auth.
-- Cada fila es de su dueño (owner_id = auth.uid()); nadie más ve ni toca nada, salvo la música: cada canción que la PC
-- manda a un PASANTE (cuenta que se registra sola desde la app) la ve y la baja ese pasante. Los pasantes no usan el chat.
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
-- Cuándo confirmó el dispositivo de destino que ya guardó el mensaje (confirm_messages_received). La limpieza automática
-- (supabase/functions/cleanup-expired) borra el mensaje y sus archivos 24 horas después. Mientras sea null no se borra nada.
alter table public.messages add column if not exists received_at timestamptz;
create index if not exists messages_received_idx on public.messages (received_at) where received_at is not null;

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
-- 2b. Perfiles y roles: 'admin' (tú: chat y música) o 'intern' (pasante: solo recibe música).
--     Quien se registra desde la app entra como pasante. Los usuarios que ya existían al ejecutar esto por primera vez
--     (tú) quedan como administrador.
-- ---------------------------------------------------------------------------------------------------------------------

create table if not exists public.profiles (
  id          uuid        primary key references auth.users (id) on delete cascade,
  username    text        not null check (char_length(btrim(username)) between 3 and 24),
  email       text,
  role        text        not null default 'intern' check (role in ('admin', 'intern')),
  created_at  timestamptz not null default now()
);
create unique index if not exists profiles_username_key on public.profiles (lower(username));

alter table public.profiles enable row level security;
revoke all on public.profiles from anon;
drop policy if exists "profiles: own select" on public.profiles;
create policy "profiles: own select" on public.profiles for select to authenticated
  using (id = (select auth.uid()));
-- Sin políticas de insert/update/delete: los perfiles solo los crea el trigger de abajo. Cada quien lee el suyo; el administrador
-- lee todos (así puede comprobar que un pasante existe al mandarle música). is_admin() es security definer: no hay recursión.
drop policy if exists "profiles: admin select" on public.profiles;
create policy "profiles: admin select" on public.profiles for select to authenticated
  using ((select public.is_admin()));

-- ¿Quien llama es administrador? (security definer: así las políticas pueden consultarlo sin depender de la seguridad por fila)
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;
revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

-- Cada usuario nuevo de Supabase Auth recibe su perfil de pasante. El nombre de usuario viaja en los metadatos del registro
-- (auth.signUp(..., data: {username})); si falta, está repetido o no es válido, se le pone uno provisional.
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_name text := btrim(coalesce(new.raw_user_meta_data ->> 'username', ''));
begin
  if char_length(v_name) not between 3 and 24 then
    v_name := 'usuario-' || substr(new.id::text, 1, 6);
  end if;
  begin
    insert into public.profiles (id, username, email, role) values (new.id, v_name, new.email, 'intern');
  exception when unique_violation then
    insert into public.profiles (id, username, email, role)
    values (new.id, left(v_name, 17) || '-' || substr(new.id::text, 1, 6), new.email, 'intern');
  end;
  return new;
end;
$$;
revoke all on function public.handle_new_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Solo la primera vez (tabla vacía): quienes ya existían son administradores.
insert into public.profiles (id, username, email, role)
select u.id,
       case when char_length(regexp_replace(split_part(coalesce(u.email, ''), '@', 1), '[^A-Za-z0-9_.-]', '', 'g')) >= 3
            then left(regexp_replace(split_part(u.email, '@', 1), '[^A-Za-z0-9_.-]', '', 'g'), 24)
            else 'admin-' || substr(u.id::text, 1, 6) end,
       u.email, 'admin'
  from auth.users u
 where not exists (select 1 from public.profiles)
on conflict do nothing;


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
  with check (owner_id = (select auth.uid()) and (select public.is_admin()));   -- los pasantes no usan el chat
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
    and (select public.is_admin())
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
    and (select public.is_admin())
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
-- Solo el administrador sube archivos: un pasante registrado no puede usar tu almacenamiento.
create policy "chat-files: owner insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'chat-files' and (storage.foldername(name))[1] = (select auth.uid())::text
              and (select public.is_admin()));
create policy "chat-files: owner update" on storage.objects for update to authenticated
  using (bucket_id = 'chat-files' and (storage.foldername(name))[1] = (select auth.uid())::text
         and (select public.is_admin()))
  with check (bucket_id = 'chat-files' and (storage.foldername(name))[1] = (select auth.uid())::text
              and (select public.is_admin()));
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

-- «Recibido» de los mensajes: el dispositivo de destino (la PC) avisa de los que ya guardó. Solo cuentan los mensajes de la
-- cuenta que llama que se mandaron desde OTRO dispositivo (p_device es el de quien confirma), y repetirlo no cambia la hora.
-- Devuelve cuántos se marcaron ahora.
create or replace function public.confirm_messages_received(p_ids uuid[], p_device text default 'unknown')
returns integer
language plpgsql security invoker set search_path = public
as $$
declare
  v_rows integer := 0;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  update public.messages
     set received_at = now()
   where id = any(coalesce(p_ids, '{}'::uuid[]))
     and owner_id = auth.uid()
     and received_at is null
     and sender_device <> coalesce(nullif(btrim(p_device), ''), 'unknown');
  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

-- Solo usuarios con sesión pueden llamarlas (nada de anónimos).
revoke all on function public.confirm_messages_received(uuid[], text)                     from public, anon;
grant execute on function public.confirm_messages_received(uuid[], text)                  to authenticated;
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

-- ---------------------------------------------------------------------------------------------------------------------
-- 7. Música: lo que la PC manda con «Descargar» sube a Storage y llega a la cuenta que elijas en la PC (tú, «Yo», o un
--    pasante); su app lo ve y lo guarda en su carpeta.
--    El MP3 vive en el mismo bucket (chat-files), en  <admin_id>/music/<id_del_vídeo>/<archivo>  (se sube una sola vez
--    aunque vaya a varias personas); aquí solo sus datos: una fila por canción y destinatario.
--    El id de la fila lo crea la PC a partir del vídeo y del destinatario: mandar la misma canción otra vez no la duplica.
--    owner_id = quien la manda (el administrador); recipient_id = quien la recibe.
-- ---------------------------------------------------------------------------------------------------------------------

create table if not exists public.music_tracks (
  id            uuid        primary key,
  owner_id      uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  recipient_id  uuid        references auth.users (id) on delete cascade,
  title         text        not null,
  file_name     text        not null,
  storage_path  text        not null,
  mime_type     text        not null default 'audio/mpeg',
  size_bytes    bigint      not null default 0 check (size_bytes >= 0),
  playlist      text,                                                   -- la lista de YouTube de la que viene (opcional)
  cover_url     text,                                                   -- la carátula (opcional)
  created_at    timestamptz not null default now()
);
-- Si la tabla ya existía (versión anterior, una sola cuenta): se añaden las columnas nuevas y lo viejo queda para su dueño.
alter table public.music_tracks add column if not exists recipient_id uuid references auth.users (id) on delete cascade;
alter table public.music_tracks add column if not exists cover_url text;
-- Cuándo confirmó quien la recibe que ya la tiene guardada en su teléfono (botón «Recibido»). Solo se escribe con
-- confirm_track_received; mientras sea null, nada de esta canción se borra de Supabase.
alter table public.music_tracks add column if not exists received_at timestamptz;
update public.music_tracks set recipient_id = owner_id where recipient_id is null;
alter table public.music_tracks alter column recipient_id set not null;
create index if not exists music_tracks_owner_created_idx on public.music_tracks (owner_id, created_at desc);
create index if not exists music_tracks_recipient_created_idx on public.music_tracks (recipient_id, created_at desc);

alter table public.music_tracks enable row level security;
revoke all on public.music_tracks from anon;

drop policy if exists "music_tracks: owner select" on public.music_tracks;
drop policy if exists "music_tracks: owner insert" on public.music_tracks;
drop policy if exists "music_tracks: owner update" on public.music_tracks;
drop policy if exists "music_tracks: owner delete" on public.music_tracks;
-- Las ve quien las manda y quien las recibe; solo el administrador las crea, cambia o borra.
create policy "music_tracks: owner select" on public.music_tracks for select to authenticated
  using (owner_id = (select auth.uid()) or recipient_id = (select auth.uid()));
create policy "music_tracks: owner insert" on public.music_tracks for insert to authenticated
  with check (owner_id = (select auth.uid()) and (select public.is_admin()));
create policy "music_tracks: owner update" on public.music_tracks for update to authenticated
  using (owner_id = (select auth.uid()) and (select public.is_admin()))
  with check (owner_id = (select auth.uid()) and (select public.is_admin()));
create policy "music_tracks: owner delete" on public.music_tracks for delete to authenticated
  using (owner_id = (select auth.uid()) and (select public.is_admin()));

-- El destinatario puede bajar el MP3 que le mandaron (su archivo está en la carpeta del administrador).
drop policy if exists "chat-files: recipient select" on storage.objects;
create policy "chat-files: recipient select" on storage.objects for select to authenticated
  using (bucket_id = 'chat-files'
         and exists (select 1 from public.music_tracks t
                      where t.storage_path = storage.objects.name and t.recipient_id = (select auth.uid())));

alter table public.music_tracks replica identity full;
do $$ begin
  alter publication supabase_realtime add table public.music_tracks;
exception when duplicate_object then null; when undefined_object then null; end $$;

-- Registra (o actualiza) una canción ya subida a Storage para un destinatario (por defecto, quien llama). Solo el
-- administrador. Repetirla con el mismo p_id no la duplica.
drop function if exists public.add_music_track(uuid, text, text, text, text, bigint, text);   -- la versión de una sola cuenta
create or replace function public.add_music_track(
  p_id            uuid,
  p_title         text,
  p_file_name     text,
  p_storage_path  text,
  p_mime_type     text   default 'audio/mpeg',
  p_size_bytes    bigint default 0,
  p_playlist      text   default null,
  p_recipient_id  uuid   default null,
  p_cover_url     text   default null
)
returns jsonb
language plpgsql security invoker set search_path = public
as $$
declare
  v_recipient uuid := coalesce(p_recipient_id, auth.uid());
  v_row       public.music_tracks;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if not public.is_admin() then
    raise exception 'not_admin' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles where id = v_recipient) then
    raise exception 'unknown_recipient' using errcode = '22023';
  end if;
  -- El MP3 se sube una vez y la limpieza automática lo borra cuando todos lo confirmaron: no se registra una canción cuyo archivo ya no está.
  if not exists (select 1 from storage.objects where bucket_id = 'chat-files' and name = p_storage_path) then
    raise exception 'file_missing' using errcode = '22023';
  end if;
  insert into public.music_tracks (id, recipient_id, title, file_name, storage_path, mime_type, size_bytes, playlist, cover_url)
  values (p_id, v_recipient, coalesce(nullif(btrim(p_title), ''), p_file_name), p_file_name, p_storage_path,
          coalesce(nullif(p_mime_type, ''), 'audio/mpeg'), coalesce(p_size_bytes, 0), nullif(btrim(p_playlist), ''),
          nullif(btrim(p_cover_url), ''))
  on conflict (id) do update
     set title = excluded.title, file_name = excluded.file_name, storage_path = excluded.storage_path,
         mime_type = excluded.mime_type, size_bytes = excluded.size_bytes, playlist = excluded.playlist,
         cover_url = excluded.cover_url
   where public.music_tracks.owner_id = auth.uid()
  returning * into v_row;
  if v_row.id is null then
    raise exception 'track_id_taken' using errcode = '42501';   -- ese id es de otra cuenta
  end if;
  return to_jsonb(v_row);
end;
$$;

-- Las canciones que TÚ recibes (administrador: las que te mandas con «Yo»; pasante: las que te manda el administrador),
-- de la más nueva a la más antigua.
create or replace function public.list_music_tracks(p_limit integer default 100)
returns jsonb
language sql stable security invoker set search_path = public
as $$
  select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc, t.id), '[]'::jsonb)
    from (
      select * from public.music_tracks
       where recipient_id = auth.uid()
       order by created_at desc, id
       limit least(greatest(coalesce(p_limit, 100), 1), 500)
    ) t;
$$;

-- «Recibido»: quien recibe la canción confirma que ya la guardó en su teléfono. Solo puede hacerlo el destinatario, solo sobre
-- sus canciones, y repetirlo no cambia la hora de la primera vez. Devuelve la fila. (Los destinatarios no pueden actualizar
-- la tabla directamente: esta es su única vía, y solo toca received_at.)
create or replace function public.confirm_track_received(p_id uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_row public.music_tracks;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  update public.music_tracks
     set received_at = coalesce(received_at, now())
   where id = p_id and recipient_id = auth.uid()
  returning * into v_row;
  if v_row.id is null then
    raise exception 'unknown_track' using errcode = '22023';   -- no existe o no es tuya
  end if;
  return to_jsonb(v_row);
end;
$$;

-- Quién es quien llama: {id, username, email, role, created_at}, o null si no tiene perfil. La app decide con esto qué vista enseñar.
create or replace function public.my_profile()
returns jsonb
language sql stable security invoker set search_path = public
as $$
  select to_jsonb(p) from public.profiles p where p.id = auth.uid();
$$;

-- ¿Está libre ese nombre de usuario? Es lo único que puede preguntar alguien sin cuenta (para el registro); solo responde sí o no.
create or replace function public.username_available(p_username text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select not exists (select 1 from public.profiles where lower(username) = lower(btrim(coalesce(p_username, ''))));
$$;

-- A quién se le puede mandar música (solo el administrador): tú primero (me = true) y luego los pasantes por nombre.
create or replace function public.list_recipients()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if not public.is_admin() then
    raise exception 'not_admin' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', p.id, 'username', p.username, 'role', p.role, 'me', p.id = auth.uid())
                     order by (p.id = auth.uid()) desc, lower(p.username))
      from public.profiles p), '[]'::jsonb);
end;
$$;

revoke all on function public.add_music_track(uuid, text, text, text, text, bigint, text, uuid, text) from public, anon;
revoke all on function public.list_music_tracks(integer)                                  from public, anon;
revoke all on function public.confirm_track_received(uuid)                                from public, anon;
revoke all on function public.my_profile()                                                from public, anon;
revoke all on function public.list_recipients()                                          from public, anon;
revoke all on function public.username_available(text)                                    from public;
grant execute on function public.add_music_track(uuid, text, text, text, text, bigint, text, uuid, text) to authenticated;
grant execute on function public.list_music_tracks(integer)                                  to authenticated;
grant execute on function public.confirm_track_received(uuid)                                to authenticated;
grant execute on function public.my_profile()                                                to authenticated;
grant execute on function public.list_recipients()                                          to authenticated;
grant execute on function public.username_available(text)                                    to anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 8. Tareas: las del móvil (con copia en su SQLite, que sube aquí cuando hay internet). Mismo modelo que las tareas del
--    escritorio (code/kyora/tasks): estados pending / doing / review / done, subtareas de un solo nivel, etiquetas y tiempos.
--    - Los ids (uuid) los crea el dispositivo: así dos dispositivos nunca chocan y repetir una subida no duplica.
--    - Borrado suave (deleted_at): el borrado también llega a los demás dispositivos. Nada se borra de verdad desde la app.
--    - Si dos dispositivos cambian lo mismo, gana el cambio con updated_at más reciente (sync_guard descarta el más viejo).
--    - synced_at lo pone el servidor en cada escritura: la app pide «lo que cambió desde la última vez» con él.
--    Cada quien ve y toca solo lo suyo (owner_id); no hace falta ser administrador.
-- ---------------------------------------------------------------------------------------------------------------------

create table if not exists public.tasks (
  id             uuid        primary key,
  owner_id       uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  parent_id      uuid        references public.tasks (id) on delete cascade,        -- subtarea de otra (un solo nivel)
  position       integer     not null default 0,
  name           text        not null check (length(btrim(name)) > 0),
  description    text        not null default '',
  status         text        not null default 'pending' check (status in ('pending', 'doing', 'review', 'done')),
  expected_min   integer     check (expected_min is null or expected_min >= 0),    -- minutos que se espera que lleve
  real_s         integer     not null default 0 check (real_s >= 0),               -- segundos del cronómetro
  timer_started  timestamptz,
  due            timestamptz,                                                      -- entrega
  finished       timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,
  synced_at      timestamptz not null default clock_timestamp()
);
create index if not exists tasks_owner_synced_idx on public.tasks (owner_id, synced_at);
create index if not exists tasks_parent_idx on public.tasks (parent_id, position);

create table if not exists public.tags (
  id          uuid        primary key,
  owner_id    uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  name        text        not null check (length(btrim(name)) > 0),
  color       text        not null default '#888888',
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  synced_at   timestamptz not null default clock_timestamp()
);
create unique index if not exists tags_owner_name_key on public.tags (owner_id, lower(name)) where deleted_at is null;
create index if not exists tags_owner_synced_idx on public.tags (owner_id, synced_at);

create table if not exists public.task_tags (
  task_id     uuid        not null references public.tasks (id) on delete cascade,
  tag_id      uuid        not null references public.tags (id) on delete cascade,
  owner_id    uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  synced_at   timestamptz not null default clock_timestamp(),
  primary key (task_id, tag_id)
);
create index if not exists task_tags_owner_synced_idx on public.task_tags (owner_id, synced_at);

-- Gana el cambio más reciente: una escritura con updated_at igual o más viejo que el guardado se ignora en silencio.
-- Toda escritura que se acepta lleva la hora del servidor en synced_at.
create or replace function public.sync_guard()
returns trigger
language plpgsql set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and new.updated_at <= old.updated_at then
    return null;
  end if;
  new.synced_at := clock_timestamp();
  return new;
end;
$$;

drop trigger if exists tasks_sync_guard on public.tasks;
create trigger tasks_sync_guard before insert or update on public.tasks for each row execute function public.sync_guard();
drop trigger if exists tags_sync_guard on public.tags;
create trigger tags_sync_guard before insert or update on public.tags for each row execute function public.sync_guard();
drop trigger if exists task_tags_sync_guard on public.task_tags;
create trigger task_tags_sync_guard before insert or update on public.task_tags for each row execute function public.sync_guard();

alter table public.tasks     enable row level security;
alter table public.tags      enable row level security;
alter table public.task_tags enable row level security;
revoke all on public.tasks, public.tags, public.task_tags from anon;
-- Sin permiso de delete: las tareas solo se borran «suave» (deleted_at).
revoke delete on public.tasks, public.tags, public.task_tags from authenticated;
grant select, insert, update on public.tasks, public.tags, public.task_tags to authenticated;

drop policy if exists "tasks: owner select" on public.tasks;
drop policy if exists "tasks: owner insert" on public.tasks;
drop policy if exists "tasks: owner update" on public.tasks;
create policy "tasks: owner select" on public.tasks for select to authenticated using (owner_id = (select auth.uid()));
create policy "tasks: owner insert" on public.tasks for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "tasks: owner update" on public.tasks for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

drop policy if exists "tags: owner select" on public.tags;
drop policy if exists "tags: owner insert" on public.tags;
drop policy if exists "tags: owner update" on public.tags;
create policy "tags: owner select" on public.tags for select to authenticated using (owner_id = (select auth.uid()));
create policy "tags: owner insert" on public.tags for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "tags: owner update" on public.tags for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

drop policy if exists "task_tags: owner select" on public.task_tags;
drop policy if exists "task_tags: owner insert" on public.task_tags;
drop policy if exists "task_tags: owner update" on public.task_tags;
create policy "task_tags: owner select" on public.task_tags for select to authenticated using (owner_id = (select auth.uid()));
create policy "task_tags: owner insert" on public.task_tags for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "task_tags: owner update" on public.task_tags for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

-- Fin. Ahora crea tu usuario en Authentication > Users (ver supabase/README.md).
