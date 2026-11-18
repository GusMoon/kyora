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
-- (Server/supabase/functions/cleanup-expired) borra el mensaje y sus archivos 24 horas después. Mientras sea null no se borra nada.
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
  created_at  timestamptz not null default now(),
  -- Cuentas que crea el administrador (ver §2c): verified = la persona ya canjeó su código de 6 dígitos.
  verified         boolean     not null default false,
  code_hash        text,
  code_expires_at  timestamptz,
  code_attempts    integer     not null default 0,
  last_seen        timestamptz
);
create unique index if not exists profiles_username_key on public.profiles (lower(username));

-- Tabla que ya existía sin esas columnas: se añaden, y SOLO esta vez las cuentas que ya había quedan verificadas
-- (así no se vuelve a pedir código a nadie; volver a ejecutar el script no verifica cuentas nuevas).
do $$ begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'profiles' and column_name = 'verified') then
    alter table public.profiles add column verified boolean not null default true;
    alter table public.profiles alter column verified set default false;
    alter table public.profiles add column if not exists code_hash text;
    alter table public.profiles add column if not exists code_expires_at timestamptz;
    alter table public.profiles add column if not exists code_attempts integer not null default 0;
    alter table public.profiles add column if not exists last_seen timestamptz;
  end if;
end $$;

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
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin' and verified);
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
insert into public.profiles (id, username, email, role, verified)
select u.id,
       case when char_length(regexp_replace(split_part(coalesce(u.email, ''), '@', 1), '[^A-Za-z0-9_.-]', '', 'g')) >= 3
            then left(regexp_replace(split_part(u.email, '@', 1), '[^A-Za-z0-9_.-]', '', 'g'), 24)
            else 'admin-' || substr(u.id::text, 1, 6) end,
       u.email, 'admin', true
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

-- Quién es quien llama: {id, username, email, role, created_at, verified}, o null si no tiene perfil. La app decide con esto qué
-- vista enseñar. (Sin code_hash ni intentos: eso no sale del servidor.)
create or replace function public.my_profile()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select jsonb_build_object('id', p.id, 'username', p.username, 'email', p.email, 'role', p.role,
                            'created_at', p.created_at, 'verified', p.verified)
    from public.profiles p where p.id = auth.uid();
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
-- 7b. Cuentas que crea el administrador: código de 6 dígitos y presencia (quién está en línea)
--     Las cuentas ya NO se crean solas: el registro público se apaga (Authentication > «Allow new users to sign up» = OFF)
--     y solo la función admin-users (con la clave de servicio) las crea, con un correo inventado <nombre>@kyra.local.
--     Esa función guarda solo el HASH del código; la persona lo canjea una vez con claim_account y desde entonces entra solo
--     con su contraseña. Hasta canjearlo (verified = false) no entra al chat familiar (is_family_member).
-- ---------------------------------------------------------------------------------------------------------------------

-- El hash del código y los intentos no salen del servidor: cada quien solo lee las columnas «públicas» de su perfil.
revoke select on public.profiles from authenticated;
grant select (id, username, email, role, created_at, verified, last_seen) on public.profiles to authenticated;

-- Canjea el código de 6 dígitos que el administrador le dio a quien llama. Caduca a las 72 h y se bloquea tras 5 fallos
-- (el administrador genera otro). Devuelve true si quedó verificada.
create or replace function public.claim_account(p_code text)
returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  v_p public.profiles;
  v_code text := btrim(coalesce(p_code, ''));
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select * into v_p from public.profiles where id = auth.uid() for update;
  if v_p.id is null then
    raise exception 'no_profile' using errcode = 'P0002';
  end if;
  if v_p.verified then
    return true;                                  -- ya estaba (el administrador, o un código ya canjeado)
  end if;
  if v_p.code_hash is null or v_p.code_expires_at is null or v_p.code_expires_at < now() then
    raise exception 'code_expired' using errcode = 'P0001';
  end if;
  if v_p.code_attempts >= 5 then
    raise exception 'code_locked' using errcode = 'P0001';
  end if;
  if v_code !~ '^[0-9]{6}$'
     or encode(sha256(convert_to(v_code || v_p.id::text, 'utf8')), 'hex') <> v_p.code_hash then
    update public.profiles set code_attempts = code_attempts + 1 where id = v_p.id;
    raise exception 'code_invalid' using errcode = 'P0001';
  end if;
  update public.profiles
     set verified = true, code_hash = null, code_expires_at = null, code_attempts = 0
   where id = v_p.id;
  return true;
end;
$$;

-- «Sigo aquí»: la app lo llama cada ~30 s mientras está abierta. Solo toca la fila de quien llama.
create or replace function public.touch_presence()
returns void
language sql security definer set search_path = public
as $$
  update public.profiles set last_seen = now() where id = auth.uid();
$$;

-- Quién está en línea (solo el administrador). En línea = visto en los últimos 90 s.
create or replace function public.list_presence()
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
    select jsonb_agg(jsonb_build_object(
             'id', p.id, 'username', p.username, 'role', p.role, 'verified', p.verified,
             'last_seen', p.last_seen,
             'online', (p.last_seen is not null and p.last_seen > now() - interval '90 seconds'),
             'code_pending', coalesce(p.code_hash is not null and p.code_expires_at > now() and p.code_attempts < 5, false),
             'me', p.id = auth.uid())
           order by (p.last_seen is not null and p.last_seen > now() - interval '90 seconds') desc, lower(p.username))
      from public.profiles p), '[]'::jsonb);
end;
$$;

revoke all on function public.claim_account(text)  from public, anon;
revoke all on function public.touch_presence()     from public, anon;
revoke all on function public.list_presence()      from public, anon;
grant execute on function public.claim_account(text) to authenticated;
grant execute on function public.touch_presence()    to authenticated;
grant execute on function public.list_presence()     to authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 8. Tareas: las del móvil (con copia en su SQLite, que sube aquí cuando hay internet). Mismo modelo que las tareas del
--    escritorio (Family/Kyora/kyora/tasks): estados pending / doing / review / done, subtareas de un solo nivel, etiquetas y tiempos.
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

-- ---------------------------------------------------------------------------------------------------------------------
-- 9. Hábitos: los del móvil, con el mismo esquema que las tareas (copia en su SQLite, ids del dispositivo, borrado suave,
--    gana el updated_at más reciente con sync_guard, synced_at del servidor para pedir solo las novedades).
--    - habits: el hábito, los días de la semana que toca (weekdays: un bit por día, lunes = 1 … domingo = 64; 127 = todos)
--      y la hora del aviso (remind_at: minutos desde medianoche, hora local del teléfono; null = sin aviso).
--    - habit_checks: que un hábito se cumplió un día (done). Desmarcar es done = false: así también se sincroniza.
--    Cada quien ve y toca solo lo suyo (owner_id).
-- ---------------------------------------------------------------------------------------------------------------------

create table if not exists public.habits (
  id          uuid        primary key,
  owner_id    uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  name        text        not null check (length(btrim(name)) > 0),
  weekdays    smallint    not null default 127 check (weekdays between 1 and 127),
  remind_at   smallint    check (remind_at is null or remind_at between 0 and 1439),
  position    integer     not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  synced_at   timestamptz not null default clock_timestamp()
);
create index if not exists habits_owner_synced_idx on public.habits (owner_id, synced_at);

create table if not exists public.habit_checks (
  habit_id    uuid        not null references public.habits (id) on delete cascade,
  day         date        not null,
  owner_id    uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  done        boolean     not null default true,
  updated_at  timestamptz not null default now(),
  synced_at   timestamptz not null default clock_timestamp(),
  primary key (habit_id, day)
);
create index if not exists habit_checks_owner_synced_idx on public.habit_checks (owner_id, synced_at);

drop trigger if exists habits_sync_guard on public.habits;
create trigger habits_sync_guard before insert or update on public.habits for each row execute function public.sync_guard();
drop trigger if exists habit_checks_sync_guard on public.habit_checks;
create trigger habit_checks_sync_guard before insert or update on public.habit_checks for each row execute function public.sync_guard();

alter table public.habits       enable row level security;
alter table public.habit_checks enable row level security;
revoke all on public.habits, public.habit_checks from anon;
-- Sin permiso de delete: los hábitos solo se borran «suave» (deleted_at) y las marcas se desmarcan (done = false).
revoke delete on public.habits, public.habit_checks from authenticated;
grant select, insert, update on public.habits, public.habit_checks to authenticated;

drop policy if exists "habits: owner select" on public.habits;
drop policy if exists "habits: owner insert" on public.habits;
drop policy if exists "habits: owner update" on public.habits;
create policy "habits: owner select" on public.habits for select to authenticated using (owner_id = (select auth.uid()));
create policy "habits: owner insert" on public.habits for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "habits: owner update" on public.habits for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

drop policy if exists "habit_checks: owner select" on public.habit_checks;
drop policy if exists "habit_checks: owner insert" on public.habit_checks;
drop policy if exists "habit_checks: owner update" on public.habit_checks;
create policy "habit_checks: owner select" on public.habit_checks for select to authenticated using (owner_id = (select auth.uid()));
create policy "habit_checks: owner insert" on public.habit_checks for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "habit_checks: owner update" on public.habit_checks for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

-- ---------------------------------------------------------------------------------------------------------------------
-- 10. Comandos del chat: atajos que se escriben en el chat con «/» para activar una función. Por ahora, abrir una página web:
--     en Configuración pones el nombre de la web, el comando (sin la «/») y la URL; al escribir «/comando» en el chat se abre
--     esa URL en lugar de mandar un mensaje. Pensada para crecer: más adelante se le puede añadir una columna «action».
--    - command: en minúsculas, de 1 a 24 letras, números, «-» o «_» (se guarda sin la «/»). No se repite por dueño.
--    - url: solo http:// o https://.
--    Cada quien ve y toca solo lo suyo (owner_id); crear comandos exige ser administrador, como el chat.
-- ---------------------------------------------------------------------------------------------------------------------

create table if not exists public.chat_commands (
  id          uuid        primary key default gen_random_uuid(),
  owner_id    uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  name        text        not null check (char_length(btrim(name)) between 1 and 60),       -- el nombre de la web («YouTube»)
  command     text        not null check (command ~ '^[a-z0-9_-]{1,24}$'),                  -- lo que se escribe tras la «/»
  url         text        not null check (char_length(url) <= 2048 and url ~* '^https?://[^[:space:]]+$'),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists chat_commands_owner_command_key on public.chat_commands (owner_id, command);

alter table public.chat_commands enable row level security;
revoke all on public.chat_commands from anon;

drop policy if exists "chat_commands: owner select" on public.chat_commands;
drop policy if exists "chat_commands: owner insert" on public.chat_commands;
drop policy if exists "chat_commands: owner update" on public.chat_commands;
drop policy if exists "chat_commands: owner delete" on public.chat_commands;
create policy "chat_commands: owner select" on public.chat_commands for select to authenticated
  using (owner_id = (select auth.uid()));
create policy "chat_commands: owner insert" on public.chat_commands for insert to authenticated
  with check (owner_id = (select auth.uid()) and (select public.is_admin()));
create policy "chat_commands: owner update" on public.chat_commands for update to authenticated
  using (owner_id = (select auth.uid()) and (select public.is_admin()))
  with check (owner_id = (select auth.uid()) and (select public.is_admin()));
create policy "chat_commands: owner delete" on public.chat_commands for delete to authenticated
  using (owner_id = (select auth.uid()));

-- ---------------------------------------------------------------------------------------------------------------------
-- 11. Calendario (Merida): los eventos propios. Las tareas con fecha de entrega (tasks.due) salen en el calendario sin
--     tabla aparte. Mismo esquema que las tareas: ids del dispositivo, borrado suave, gana el updated_at más reciente
--     (sync_guard) y synced_at del servidor. task_id enlaza el evento con una tarea (opcional).
-- ---------------------------------------------------------------------------------------------------------------------

create table if not exists public.events (
  id           uuid        primary key,
  owner_id     uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  title        text        not null check (length(btrim(title)) > 0),
  description  text        not null default '',
  starts_at    timestamptz not null,
  ends_at      timestamptz,
  all_day      boolean     not null default false,
  color        text        not null default '#35d4ff',
  task_id      uuid        references public.tasks (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  synced_at    timestamptz not null default clock_timestamp()
);
create index if not exists events_owner_synced_idx on public.events (owner_id, synced_at);
create index if not exists events_owner_starts_idx on public.events (owner_id, starts_at);

drop trigger if exists events_sync_guard on public.events;
create trigger events_sync_guard before insert or update on public.events for each row execute function public.sync_guard();

alter table public.events enable row level security;
revoke all on public.events from anon;
revoke delete on public.events from authenticated;   -- solo borrado suave (deleted_at)
grant select, insert, update on public.events to authenticated;

drop policy if exists "events: owner select" on public.events;
drop policy if exists "events: owner insert" on public.events;
drop policy if exists "events: owner update" on public.events;
create policy "events: owner select" on public.events for select to authenticated using (owner_id = (select auth.uid()));
create policy "events: owner insert" on public.events for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "events: owner update" on public.events for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

-- ---------------------------------------------------------------------------------------------------------------------
-- 12. Contraseñas (Merida): una bóveda cifrada EN EL NAVEGADOR. Supabase solo guarda texto cifrado: nunca ve la contraseña
--     maestra ni ninguna contraseña. La clave sale de la contraseña maestra con PBKDF2-SHA-256 y la sal de vault_meta;
--     cada entrada se cifra con AES-GCM (IV aleatorio) y todo su contenido (servicio, correo, usuario, contraseña, URL,
--     notas) va dentro de `payload`. SIN la contraseña maestra no hay forma de recuperar nada.
--     - vault_meta: una fila por usuario con la sal, las vueltas del KDF y una «prueba» cifrada para validar la maestra.
--     - vault_entries: una fila por entrada (id del dispositivo, borrado suave, sync_guard).
-- ---------------------------------------------------------------------------------------------------------------------

create table if not exists public.vault_meta (
  owner_id    uuid        primary key default auth.uid() references auth.users (id) on delete cascade,
  salt        text        not null,                       -- base64
  kdf_iter    integer     not null check (kdf_iter >= 100000),
  verifier    text        not null,                       -- texto conocido, cifrado con la clave: valida la contraseña maestra
  version     smallint    not null default 1,
  created_at  timestamptz not null default now()
);

alter table public.vault_meta enable row level security;
revoke all on public.vault_meta from anon;
revoke update, delete on public.vault_meta from authenticated;   -- la sal y la prueba no cambian nunca desde la app
grant select, insert on public.vault_meta to authenticated;
drop policy if exists "vault_meta: owner select" on public.vault_meta;
drop policy if exists "vault_meta: owner insert" on public.vault_meta;
create policy "vault_meta: owner select" on public.vault_meta for select to authenticated using (owner_id = (select auth.uid()));
create policy "vault_meta: owner insert" on public.vault_meta for insert to authenticated with check (owner_id = (select auth.uid()));

create table if not exists public.vault_entries (
  id          uuid        primary key,
  owner_id    uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  payload     text        not null check (length(payload) > 0),   -- «v1.» + base64(iv + texto cifrado)
  version     smallint    not null default 1,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  synced_at   timestamptz not null default clock_timestamp()
);
create index if not exists vault_entries_owner_synced_idx on public.vault_entries (owner_id, synced_at);

drop trigger if exists vault_entries_sync_guard on public.vault_entries;
create trigger vault_entries_sync_guard before insert or update on public.vault_entries for each row execute function public.sync_guard();

alter table public.vault_entries enable row level security;
revoke all on public.vault_entries from anon;
revoke delete on public.vault_entries from authenticated;
grant select, insert, update on public.vault_entries to authenticated;
drop policy if exists "vault_entries: owner select" on public.vault_entries;
drop policy if exists "vault_entries: owner insert" on public.vault_entries;
drop policy if exists "vault_entries: owner update" on public.vault_entries;
create policy "vault_entries: owner select" on public.vault_entries for select to authenticated using (owner_id = (select auth.uid()));
create policy "vault_entries: owner insert" on public.vault_entries for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "vault_entries: owner update" on public.vault_entries for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

-- ---------------------------------------------------------------------------------------------------------------------
-- 13. Finanzas (Merida): ingresos y gastos. El importe va en centavos (entero > 0); el tipo (income o expense) dice si
--     suma o resta. Categorías propias por tipo. Mismo esquema que las tareas (borrado suave, sync_guard, synced_at).
-- ---------------------------------------------------------------------------------------------------------------------

create table if not exists public.finance_categories (
  id          uuid        primary key,
  owner_id    uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  name        text        not null check (char_length(btrim(name)) between 1 and 60),
  kind        text        not null check (kind in ('income', 'expense')),
  color       text        not null default '#9aa1ac',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  synced_at   timestamptz not null default clock_timestamp()
);
create unique index if not exists finance_categories_owner_name_key
  on public.finance_categories (owner_id, kind, lower(name)) where deleted_at is null;
create index if not exists finance_categories_owner_synced_idx on public.finance_categories (owner_id, synced_at);

create table if not exists public.finance_entries (
  id            uuid        primary key,
  owner_id      uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  kind          text        not null check (kind in ('income', 'expense')),
  amount_cents  bigint      not null check (amount_cents > 0),
  currency      text        not null default 'MXN' check (currency ~ '^[A-Z]{3}$'),
  category_id   uuid        references public.finance_categories (id) on delete set null,
  description   text        not null default '',
  occurred_on   date        not null default current_date,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  synced_at     timestamptz not null default clock_timestamp()
);
create index if not exists finance_entries_owner_day_idx on public.finance_entries (owner_id, occurred_on desc);
create index if not exists finance_entries_owner_synced_idx on public.finance_entries (owner_id, synced_at);

drop trigger if exists finance_categories_sync_guard on public.finance_categories;
create trigger finance_categories_sync_guard before insert or update on public.finance_categories for each row execute function public.sync_guard();
drop trigger if exists finance_entries_sync_guard on public.finance_entries;
create trigger finance_entries_sync_guard before insert or update on public.finance_entries for each row execute function public.sync_guard();

alter table public.finance_categories enable row level security;
alter table public.finance_entries    enable row level security;
revoke all on public.finance_categories, public.finance_entries from anon;
revoke delete on public.finance_categories, public.finance_entries from authenticated;
grant select, insert, update on public.finance_categories, public.finance_entries to authenticated;

drop policy if exists "finance_categories: owner select" on public.finance_categories;
drop policy if exists "finance_categories: owner insert" on public.finance_categories;
drop policy if exists "finance_categories: owner update" on public.finance_categories;
create policy "finance_categories: owner select" on public.finance_categories for select to authenticated using (owner_id = (select auth.uid()));
create policy "finance_categories: owner insert" on public.finance_categories for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "finance_categories: owner update" on public.finance_categories for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

drop policy if exists "finance_entries: owner select" on public.finance_entries;
drop policy if exists "finance_entries: owner insert" on public.finance_entries;
drop policy if exists "finance_entries: owner update" on public.finance_entries;
create policy "finance_entries: owner select" on public.finance_entries for select to authenticated using (owner_id = (select auth.uid()));
create policy "finance_entries: owner insert" on public.finance_entries for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "finance_entries: owner update" on public.finance_entries for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

-- ---------------------------------------------------------------------------------------------------------------------
-- 14. Recordatorios (Merida): algo que hay que recordar a una hora. Salen en el calendario junto a los eventos, las
--     entregas de tareas y los hábitos (sección 9). Sin estados ni subtareas: llega su hora, Merida avisa (con la pestaña
--     abierta) y se marca como hecho. Mismo esquema que las tareas: ids del dispositivo, borrado suave, gana el updated_at
--     más reciente (sync_guard) y synced_at del servidor.
-- ---------------------------------------------------------------------------------------------------------------------

create table if not exists public.reminders (
  id          uuid        primary key,
  owner_id    uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  title       text        not null check (length(btrim(title)) > 0),
  notes       text        not null default '',
  remind_at   timestamptz not null,
  done        boolean     not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  synced_at   timestamptz not null default clock_timestamp()
);
create index if not exists reminders_owner_synced_idx on public.reminders (owner_id, synced_at);
create index if not exists reminders_owner_remind_idx on public.reminders (owner_id, remind_at);

drop trigger if exists reminders_sync_guard on public.reminders;
create trigger reminders_sync_guard before insert or update on public.reminders for each row execute function public.sync_guard();

alter table public.reminders enable row level security;
revoke all on public.reminders from anon;
revoke delete on public.reminders from authenticated;   -- solo borrado suave (deleted_at)
grant select, insert, update on public.reminders to authenticated;

drop policy if exists "reminders: owner select" on public.reminders;
drop policy if exists "reminders: owner insert" on public.reminders;
drop policy if exists "reminders: owner update" on public.reminders;
create policy "reminders: owner select" on public.reminders for select to authenticated using (owner_id = (select auth.uid()));
create policy "reminders: owner insert" on public.reminders for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "reminders: owner update" on public.reminders for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

-- ---------------------------------------------------------------------------------------------------------------------
-- 15. Estadísticas del servidor (Merida, Nube): cuánto espacio ocupa la base de datos y el almacenamiento de archivos, para
--     avisar al llegar al 80 % del plan gratuito (500 MB de base de datos y 1 GB de archivos). Una sola función de solo
--     lectura: devuelve tamaños y conteos, nunca contenido. SECURITY DEFINER porque storage.objects y los tamaños del
--     sistema no se pueden leer con el rol de la app; solo la pueden llamar usuarios con sesión.
-- ---------------------------------------------------------------------------------------------------------------------

create or replace function public.server_stats()
returns jsonb
language plpgsql
security definer
set search_path = public, storage, pg_catalog
as $$
begin
  if auth.uid() is null then
    raise exception 'Se necesita una sesión abierta.' using errcode = '28000';
  end if;
  return jsonb_build_object(
    'db_bytes',        pg_database_size(current_database()),
    'storage_bytes',   coalesce((select sum((o.metadata ->> 'size')::bigint) from storage.objects o), 0),
    'storage_objects', (select count(*) from storage.objects),
    'buckets', coalesce((
      select jsonb_agg(b order by b.bytes desc)
      from (
        select o.bucket_id as bucket, count(*) as objects, coalesce(sum((o.metadata ->> 'size')::bigint), 0) as bytes
        from storage.objects o
        group by o.bucket_id
      ) b
    ), '[]'::jsonb),
    'tables', coalesce((
      select jsonb_agg(t order by t.bytes desc)
      from (
        select c.relname as name, pg_total_relation_size(c.oid) as bytes, greatest(c.reltuples, 0)::bigint as rows
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public' and c.relkind = 'r'
        order by pg_total_relation_size(c.oid) desc
        limit 12
      ) t
    ), '[]'::jsonb),
    'at', now()
  );
end;
$$;

revoke all on function public.server_stats() from public, anon;
grant execute on function public.server_stats() to authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 16. Calendario en tiempo real (Kyra, móvil): el calendario del móvil se pone al día solo cuando algo cambia en otro
--     dispositivo (Merida o el escritorio). Para eso Realtime tiene que publicar las tablas del calendario. Solo avisa de que
--     algo cambió: el móvil vuelve a leer lo suyo y la seguridad por fila (RLS) sigue mandando, así que nadie ve filas ajenas.
--     Idempotente: si una tabla ya estaba publicada, se ignora.
-- ---------------------------------------------------------------------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.tasks;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.habits;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.habit_checks;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.events;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.reminders;
exception when duplicate_object then null; when undefined_object then null; end $$;

-- Finanzas (Kyra, móvil): lo mismo para las categorías y los movimientos, así el móvil ve al instante lo anotado en Merida y al revés.
do $$ begin
  alter publication supabase_realtime add table public.finance_categories;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.finance_entries;
exception when duplicate_object then null; when undefined_object then null; end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 17. Mejoras pendientes (Merida y Kyra): lo que se quiere agregar o mejorar en el proyecto. Una fila por idea: la sección,
--     las funciones que se quieren (una por línea) y una descripción. Al terminar una, el botón «Hecho» la BORRA de verdad
--     (a diferencia de las demás tablas, aquí no hay borrado suave: una mejora hecha ya no hace falta). Cada cuenta ve solo
--     las suyas (RLS). Idempotente: se puede volver a ejecutar.
-- ---------------------------------------------------------------------------------------------------------------------
create table if not exists public.feature_requests (
  id          uuid        primary key default gen_random_uuid(),
  owner_id    uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  section     text        not null check (char_length(btrim(section)) between 1 and 80),
  functions   text        not null default '' check (char_length(functions) <= 4000),
  description text        not null default '' check (char_length(description) <= 4000),
  created_at  timestamptz not null default now()
);
create index if not exists feature_requests_owner_created_idx on public.feature_requests (owner_id, created_at desc);

alter table public.feature_requests enable row level security;
revoke all on public.feature_requests from anon;
grant select, insert, update, delete on public.feature_requests to authenticated;

drop policy if exists "feature_requests: owner select" on public.feature_requests;
drop policy if exists "feature_requests: owner insert" on public.feature_requests;
drop policy if exists "feature_requests: owner update" on public.feature_requests;
drop policy if exists "feature_requests: owner delete" on public.feature_requests;
create policy "feature_requests: owner select" on public.feature_requests for select to authenticated using (owner_id = (select auth.uid()));
create policy "feature_requests: owner insert" on public.feature_requests for insert to authenticated with check (owner_id = (select auth.uid()));
create policy "feature_requests: owner update" on public.feature_requests for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy "feature_requests: owner delete" on public.feature_requests for delete to authenticated using (owner_id = (select auth.uid()));

-- Tiempo real: si se anota o se termina una mejora en un dispositivo, el otro la ve al instante (solo avisa; la RLS manda).
alter table public.feature_requests replica identity full;
do $$ begin
  alter publication supabase_realtime add table public.feature_requests;
exception when duplicate_object then null; when undefined_object then null; end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 18. Chat familiar (Merida): un chat en línea para la familia (mamá, papá...), aparte del chat «General» de una sola cuenta.
--     Va en tablas propias (family_*) y en su propio bucket (family-files) a propósito: así Kyora y Kyra, que escuchan la tabla
--     messages entera, no reciben nada de la familia y el chat General queda exactamente como estaba.
--
--     - Quién entra: el administrador (siempre) y las cuentas que él agrega con add_family_member('<usuario>').
--     - Todo se borra a las 24 horas: la seguridad por fila (RLS) deja de mostrar un mensaje, sus archivos y las llamadas
--       pasadas 24 h desde que llegaron al servidor, y la función cleanup-expired borra de verdad filas y archivos.
--     - Llamadas (voz y video, WebRTC entre navegadores): family_calls dice quién llama y cómo va, y family_call_signals lleva
--       la oferta, la respuesta y los candidatos ICE de uno al otro por Realtime. El audio y el video NO pasan por Supabase.
--     Idempotente: se puede volver a ejecutar.
-- ---------------------------------------------------------------------------------------------------------------------

create table if not exists public.family_members (
  user_id   uuid        primary key references auth.users (id) on delete cascade,
  added_by  uuid        default auth.uid() references auth.users (id) on delete set null,
  added_at  timestamptz not null default now()
);
alter table public.family_members enable row level security;
revoke all on public.family_members from anon;
drop policy if exists "family_members: own select" on public.family_members;
create policy "family_members: own select" on public.family_members for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
-- Sin políticas de insert/update/delete: los miembros solo se cambian con add_family_member y remove_family_member.

-- ¿Quien llama puede usar el chat familiar? El administrador siempre; los demás, si están en family_members.
-- (security definer: las políticas lo consultan sin depender de la seguridad por fila)
create or replace function public.is_family_member()
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.is_admin()
      or exists (select 1 from public.family_members f join public.profiles p on p.id = f.user_id
                  where f.user_id = auth.uid() and p.verified);   -- sin canjear el código de 6 dígitos no entra
$$;
revoke all on function public.is_family_member() from public, anon;
grant execute on function public.is_family_member() to authenticated;

-- Los miembros (id y nombre de usuario): así cada quien ve de quién es cada mensaje sin poder leer los perfiles ajenos.
create or replace function public.family_members()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select case when public.is_family_member() then
    coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'username', p.username) order by lower(p.username))
                from public.profiles p
               where p.role = 'admin' or exists (select 1 from public.family_members f where f.user_id = p.id)), '[]'::jsonb)
  else '[]'::jsonb end;
$$;
revoke all on function public.family_members() from public, anon;
grant execute on function public.family_members() to authenticated;

-- Agrega a la familia a una cuenta que ya existe (por su nombre de usuario). Solo el administrador.
create or replace function public.add_family_member(p_username text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_profile public.profiles;
begin
  if not public.is_admin() then
    raise exception 'admin_only' using errcode = '42501';
  end if;
  select * into v_profile from public.profiles where lower(username) = lower(btrim(coalesce(p_username, '')));
  if v_profile.id is null then
    raise exception 'user_not_found' using errcode = 'P0002';
  end if;
  insert into public.family_members (user_id) values (v_profile.id) on conflict (user_id) do nothing;
  return jsonb_build_object('id', v_profile.id, 'username', v_profile.username);
end;
$$;
revoke all on function public.add_family_member(text) from public, anon;
grant execute on function public.add_family_member(text) to authenticated;

-- Quita a alguien de la familia (deja de ver el chat). Solo el administrador.
create or replace function public.remove_family_member(p_username text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admin_only' using errcode = '42501';
  end if;
  delete from public.family_members
   where user_id in (select id from public.profiles where lower(username) = lower(btrim(coalesce(p_username, ''))));
end;
$$;
revoke all on function public.remove_family_member(text) from public, anon;
grant execute on function public.remove_family_member(text) to authenticated;

-- Mensajes y adjuntos. El id lo genera quien envía (reintentar no duplica), igual que en messages.
create table if not exists public.family_messages (
  id             uuid                primary key,
  sender_id      uuid                not null default auth.uid() references auth.users (id) on delete cascade,
  sender_device  text                not null default 'web',
  kind           public.message_kind not null default 'text',
  body           text,
  sent_at        timestamptz         not null default now(),
  created_at     timestamptz         not null default now(),
  constraint family_messages_text_needs_body check (kind <> 'text' or coalesce(length(body), 0) > 0)
);
create index if not exists family_messages_created_idx on public.family_messages (created_at);

create table if not exists public.family_attachments (
  id            uuid        primary key default gen_random_uuid(),
  message_id    uuid        not null references public.family_messages (id) on delete cascade,
  sender_id     uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  storage_path  text        not null,                                   -- <sender_id>/family/<message_id>/<archivo>
  file_name     text        not null,
  mime_type     text        not null default 'application/octet-stream',
  size_bytes    bigint      not null default 0 check (size_bytes >= 0),
  width         integer,
  height        integer,
  duration_ms   integer,
  thumb_path    text,
  created_at    timestamptz not null default now()
);
create index if not exists family_attachments_message_idx on public.family_attachments (message_id);

alter table public.family_messages    enable row level security;
alter table public.family_attachments enable row level security;
revoke all on public.family_messages, public.family_attachments from anon;
grant select, insert, delete on public.family_messages, public.family_attachments to authenticated;

drop policy if exists "family_messages: member select" on public.family_messages;
drop policy if exists "family_messages: member insert" on public.family_messages;
drop policy if exists "family_messages: sender delete" on public.family_messages;
create policy "family_messages: member select" on public.family_messages for select to authenticated
  using ((select public.is_family_member()) and created_at > now() - interval '24 hours');
create policy "family_messages: member insert" on public.family_messages for insert to authenticated
  with check (sender_id = (select auth.uid()) and (select public.is_family_member()));
create policy "family_messages: sender delete" on public.family_messages for delete to authenticated
  using (sender_id = (select auth.uid()));

drop policy if exists "family_attachments: member select" on public.family_attachments;
drop policy if exists "family_attachments: member insert" on public.family_attachments;
drop policy if exists "family_attachments: sender delete" on public.family_attachments;
create policy "family_attachments: member select" on public.family_attachments for select to authenticated
  using ((select public.is_family_member()) and created_at > now() - interval '24 hours');
create policy "family_attachments: member insert" on public.family_attachments for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and (select public.is_family_member())
    and exists (select 1 from public.family_messages m where m.id = message_id and m.sender_id = (select auth.uid()))
  );
create policy "family_attachments: sender delete" on public.family_attachments for delete to authenticated
  using (sender_id = (select auth.uid()));

-- Storage: bucket privado «family-files» (50 MB por archivo). Los archivos van en <sender_id>/family/<message_id>/<archivo>:
-- los sube quien envía (su carpeta), los ven los miembros mientras no pasen 24 h, y cada quien borra los suyos.
insert into storage.buckets (id, name, public, file_size_limit)
values ('family-files', 'family-files', false, 52428800)
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit;

drop policy if exists "family-files: member select" on storage.objects;
drop policy if exists "family-files: member insert" on storage.objects;
drop policy if exists "family-files: member update" on storage.objects;
drop policy if exists "family-files: sender delete" on storage.objects;
create policy "family-files: member select" on storage.objects for select to authenticated
  using (bucket_id = 'family-files' and (select public.is_family_member()) and created_at > now() - interval '24 hours');
create policy "family-files: member insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'family-files' and (storage.foldername(name))[1] = (select auth.uid())::text
              and (select public.is_family_member()));
create policy "family-files: member update" on storage.objects for update to authenticated
  using (bucket_id = 'family-files' and (storage.foldername(name))[1] = (select auth.uid())::text
         and (select public.is_family_member()))
  with check (bucket_id = 'family-files' and (storage.foldername(name))[1] = (select auth.uid())::text
              and (select public.is_family_member()));
create policy "family-files: sender delete" on storage.objects for delete to authenticated
  using (bucket_id = 'family-files' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- Un mensaje familiar (con sus adjuntos) como JSON: {…fila…, "attachments": [ … ]}
create or replace function public.family_message_json(p_message_id uuid)
returns jsonb
language sql stable security invoker set search_path = public
as $$
  select to_jsonb(m) || jsonb_build_object(
           'attachments',
           coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at, a.id)
                       from public.family_attachments a where a.message_id = m.id), '[]'::jsonb))
    from public.family_messages m
   where m.id = p_message_id;
$$;

-- Envía un mensaje a la familia (texto y/o adjuntos ya subidos a family-files). Atómico y repetible con el mismo p_id.
create or replace function public.family_send_message(
  p_id           uuid,
  p_body         text        default null,
  p_sent_at      timestamptz default now(),
  p_device       text        default 'web',
  p_attachments  jsonb       default '[]'::jsonb
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
  if not public.is_family_member() then
    raise exception 'not_family_member' using errcode = '42501';
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

  insert into public.family_messages (id, kind, body, sent_at, sender_device)
  values (p_id, v_kind, nullif(btrim(p_body), ''), coalesce(p_sent_at, now()), coalesce(nullif(btrim(p_device), ''), 'web'))
  on conflict (id) do nothing;
  get diagnostics v_rows = row_count;

  if v_rows > 0 then
    insert into public.family_attachments (message_id, storage_path, file_name, mime_type, size_bytes,
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
  elsif not exists (select 1 from public.family_messages where id = p_id) then
    raise exception 'message_id_taken' using errcode = '42501';
  end if;

  return public.family_message_json(p_id);
end;
$$;

-- Los mensajes de las últimas 24 horas, del más antiguo al más nuevo, con sus adjuntos.
--   p_before: solo lo enviado antes de esa hora;  p_after: solo lo que llegó al servidor después de esa hora (ponerse al día)
create or replace function public.family_list_messages(
  p_before  timestamptz default null,
  p_after   timestamptz default null,
  p_limit   integer     default 100
)
returns jsonb
language sql stable security invoker set search_path = public
as $$
  select coalesce(jsonb_agg(public.family_message_json(t.id) order by t.sent_at, t.id), '[]'::jsonb)
    from (
      select m.id, m.sent_at
        from public.family_messages m
       where m.created_at > now() - interval '24 hours'
         and (p_before is null or m.sent_at < p_before)
         and (p_after  is null or m.created_at > p_after)
       order by m.sent_at desc, m.id desc
       limit least(greatest(coalesce(p_limit, 100), 1), 200)
    ) t;
$$;
grant execute on function public.family_message_json(uuid) to authenticated;
grant execute on function public.family_send_message(uuid, text, timestamptz, text, jsonb) to authenticated;
grant execute on function public.family_list_messages(timestamptz, timestamptz, integer) to authenticated;
revoke all on function public.family_message_json(uuid) from public, anon;
revoke all on function public.family_send_message(uuid, text, timestamptz, text, jsonb) from public, anon;
revoke all on function public.family_list_messages(timestamptz, timestamptz, integer) from public, anon;

-- Llamadas: una fila por llamada (quién llama, si es de voz o de video y cómo va) y las señales de WebRTC que se pasan los dos.
create table if not exists public.family_calls (
  id          uuid        primary key,
  caller_id   uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  kind        text        not null check (kind in ('audio', 'video')),
  status      text        not null default 'ringing' check (status in ('ringing', 'active', 'ended', 'declined', 'missed')),
  answered_by uuid        references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  ended_at    timestamptz
);
create index if not exists family_calls_created_idx on public.family_calls (created_at);

create table if not exists public.family_call_signals (
  id          uuid        primary key default gen_random_uuid(),
  call_id     uuid        not null references public.family_calls (id) on delete cascade,
  sender_id   uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  kind        text        not null check (kind in ('offer', 'answer', 'candidate')),
  payload     jsonb       not null,
  created_at  timestamptz not null default now()
);
create index if not exists family_call_signals_call_idx on public.family_call_signals (call_id, created_at);

alter table public.family_calls        enable row level security;
alter table public.family_call_signals enable row level security;
revoke all on public.family_calls, public.family_call_signals from anon;
grant select, insert, update on public.family_calls to authenticated;
grant select, insert on public.family_call_signals to authenticated;

drop policy if exists "family_calls: member select" on public.family_calls;
drop policy if exists "family_calls: caller insert" on public.family_calls;
drop policy if exists "family_calls: member update" on public.family_calls;
create policy "family_calls: member select" on public.family_calls for select to authenticated
  using ((select public.is_family_member()) and created_at > now() - interval '24 hours');
create policy "family_calls: caller insert" on public.family_calls for insert to authenticated
  with check (caller_id = (select auth.uid()) and (select public.is_family_member()));
create policy "family_calls: member update" on public.family_calls for update to authenticated
  using ((select public.is_family_member())) with check ((select public.is_family_member()));

drop policy if exists "family_call_signals: member select" on public.family_call_signals;
drop policy if exists "family_call_signals: member insert" on public.family_call_signals;
create policy "family_call_signals: member select" on public.family_call_signals for select to authenticated
  using ((select public.is_family_member()) and created_at > now() - interval '24 hours');
create policy "family_call_signals: member insert" on public.family_call_signals for insert to authenticated
  with check (sender_id = (select auth.uid()) and (select public.is_family_member()));

-- Tiempo real: mensajes, llamadas y señales llegan al instante a los miembros (solo a quien la RLS deja verlos).
alter table public.family_messages replica identity full;
alter table public.family_attachments replica identity full;
alter table public.family_calls replica identity full;
do $$ begin
  alter publication supabase_realtime add table public.family_messages;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.family_attachments;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.family_calls;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.family_call_signals;
exception when duplicate_object then null; when undefined_object then null; end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 19. Chat privado 1 a 1 (Kyra: KyraFamily y KyraAdmin): cualquier cuenta verificada puede escribirle a cualquier otra.
--     - Cada conversación (dm_threads) es de un par de personas (user_a < user_b, una sola por par).
--     - Los mensajes (dm_messages) son PERMANENTES: nadie los borra de la base de datos salvo el administrador.
--     - «Borrar para mí»: cada quien oculta un mensaje (dm_hidden_messages) o vacía la conversación (dm_thread_state.cleared_before)
--       solo para sí; el otro lo sigue viendo y la base de datos no cambia.
--     - El administrador ve todas las conversaciones (supervisión) y es el único que borra de verdad.
--     - Todo se escribe por las funciones de abajo (security definer, con sus comprobaciones): las tablas solo se pueden leer.
--     Idempotente: se puede volver a ejecutar. No toca el chat familiar (§18), que sigue usando Merida.
-- ---------------------------------------------------------------------------------------------------------------------

create table if not exists public.dm_threads (
  id               uuid        primary key default gen_random_uuid(),
  user_a           uuid        not null references auth.users (id) on delete cascade,
  user_b           uuid        not null references auth.users (id) on delete cascade,
  created_at       timestamptz not null default now(),
  last_message_at  timestamptz,
  constraint dm_threads_ordered check (user_a < user_b),
  constraint dm_threads_pair unique (user_a, user_b)
);
create index if not exists dm_threads_b_idx on public.dm_threads (user_b);

create table if not exists public.dm_messages (
  id             uuid        primary key,                                  -- lo crea quien envía: reintentar no duplica
  thread_id      uuid        not null references public.dm_threads (id) on delete cascade,
  sender_id      uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  sender_device  text        not null default 'movil',
  body           text        not null check (char_length(btrim(body)) > 0 and char_length(body) <= 4000),
  sent_at        timestamptz not null default now(),
  created_at     timestamptz not null default now()
);
create index if not exists dm_messages_thread_idx on public.dm_messages (thread_id, sent_at);

create table if not exists public.dm_hidden_messages (
  user_id     uuid        not null references auth.users (id) on delete cascade,
  message_id  uuid        not null references public.dm_messages (id) on delete cascade,
  hidden_at   timestamptz not null default now(),
  primary key (user_id, message_id)
);

create table if not exists public.dm_thread_state (
  user_id         uuid        not null references auth.users (id) on delete cascade,
  thread_id       uuid        not null references public.dm_threads (id) on delete cascade,
  cleared_before  timestamptz,                                             -- «vaciar chat»: lo de antes ya no se le enseña
  last_read_at    timestamptz,                                             -- para contar los no leídos
  primary key (user_id, thread_id)
);

-- ¿Quien llama está en esa conversación?
create or replace function public.dm_is_participant(p_thread uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.dm_threads t where t.id = p_thread and auth.uid() in (t.user_a, t.user_b));
$$;
revoke all on function public.dm_is_participant(uuid) from public, anon;
grant execute on function public.dm_is_participant(uuid) to authenticated;

-- ¿Quien llama puede usar el chat? (cuenta verificada: ya canjeó su código; el administrador siempre)
create or replace function public.dm_can_chat()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and verified);
$$;
revoke all on function public.dm_can_chat() from public, anon;
grant execute on function public.dm_can_chat() to authenticated;

alter table public.dm_threads         enable row level security;
alter table public.dm_messages        enable row level security;
alter table public.dm_hidden_messages enable row level security;
alter table public.dm_thread_state    enable row level security;
revoke all on public.dm_threads, public.dm_messages, public.dm_hidden_messages, public.dm_thread_state from anon, authenticated;
grant select on public.dm_threads, public.dm_messages, public.dm_hidden_messages, public.dm_thread_state to authenticated;

drop policy if exists "dm_threads: participant select" on public.dm_threads;
create policy "dm_threads: participant select" on public.dm_threads for select to authenticated
  using ((select auth.uid()) in (user_a, user_b) or (select public.is_admin()));
drop policy if exists "dm_messages: participant select" on public.dm_messages;
create policy "dm_messages: participant select" on public.dm_messages for select to authenticated
  using (public.dm_is_participant(thread_id) or (select public.is_admin()));
drop policy if exists "dm_hidden_messages: own select" on public.dm_hidden_messages;
create policy "dm_hidden_messages: own select" on public.dm_hidden_messages for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists "dm_thread_state: own select" on public.dm_thread_state;
create policy "dm_thread_state: own select" on public.dm_thread_state for select to authenticated
  using (user_id = (select auth.uid()));

-- Una persona como JSON: {id, username, role, online}
create or replace function public.dm_person_json(p_user uuid)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select jsonb_build_object('id', p.id, 'username', p.username, 'role', p.role,
                            'online', (p.last_seen is not null and p.last_seen > now() - interval '90 seconds'))
    from public.profiles p where p.id = p_user;
$$;
revoke all on function public.dm_person_json(uuid) from public, anon, authenticated;

-- A quién se le puede escribir: todas las cuentas verificadas menos uno mismo, por nombre.
create or replace function public.dm_directory()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select case when public.dm_can_chat() then
    coalesce((select jsonb_agg(public.dm_person_json(p.id) order by lower(p.username))
                from public.profiles p where p.verified and p.id <> auth.uid()), '[]'::jsonb)
  else '[]'::jsonb end;
$$;

-- Lo que se le enseña a quien llama de una conversación: sus mensajes, sin los que ocultó ni los de antes de «vaciar chat».
create or replace function public.dm_visible(p_thread uuid)
returns setof public.dm_messages
language sql stable security definer set search_path = public
as $$
  select m.* from public.dm_messages m
    left join public.dm_thread_state st on st.thread_id = m.thread_id and st.user_id = auth.uid()
   where m.thread_id = p_thread
     and (st.cleared_before is null or m.created_at > st.cleared_before)
     and not exists (select 1 from public.dm_hidden_messages h where h.message_id = m.id and h.user_id = auth.uid());
$$;
revoke all on function public.dm_visible(uuid) from public, anon, authenticated;

-- Un resumen de conversación para quien llama: {id, other, last, unread, last_message_at}
create or replace function public.dm_thread_json(p_thread uuid)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select jsonb_build_object(
           'id', t.id,
           'other', public.dm_person_json(case when t.user_a = auth.uid() then t.user_b else t.user_a end),
           'last', (select to_jsonb(v) from public.dm_visible(t.id) v order by v.sent_at desc, v.id desc limit 1),
           'unread', (select count(*) from public.dm_visible(t.id) v
                        left join public.dm_thread_state st on st.thread_id = t.id and st.user_id = auth.uid()
                       where v.sender_id <> auth.uid() and (st.last_read_at is null or v.created_at > st.last_read_at)),
           'last_message_at', t.last_message_at)
    from public.dm_threads t where t.id = p_thread;
$$;
revoke all on function public.dm_thread_json(uuid) from public, anon, authenticated;

-- Abre (o crea) la conversación con otra persona y la devuelve.
create or replace function public.dm_open_thread(p_user uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_id uuid;
begin
  if v_me is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not public.dm_can_chat() then raise exception 'not_verified' using errcode = '42501'; end if;
  if p_user is null or p_user = v_me or not exists (select 1 from public.profiles where id = p_user and verified) then
    raise exception 'user_not_found' using errcode = 'P0002';
  end if;
  insert into public.dm_threads (user_a, user_b) values (least(v_me, p_user), greatest(v_me, p_user))
  on conflict (user_a, user_b) do nothing;
  select id into v_id from public.dm_threads where user_a = least(v_me, p_user) and user_b = greatest(v_me, p_user);
  return public.dm_thread_json(v_id);
end;
$$;

-- Las conversaciones de quien llama que tienen algo que enseñar, de la más reciente a la más vieja.
create or replace function public.dm_list_threads()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(j order by (j -> 'last' ->> 'sent_at') desc), '[]'::jsonb)
    from (select public.dm_thread_json(t.id) as j
            from public.dm_threads t
           where auth.uid() in (t.user_a, t.user_b) and public.dm_can_chat()) x
   where j -> 'last' is not null and jsonb_typeof(j -> 'last') = 'object';
$$;

-- Los mensajes de una conversación (lo que quien llama puede ver), del más antiguo al más nuevo.
--   p_before: solo lo enviado antes de esa hora;  p_after: solo lo que llegó al servidor después de esa hora.
create or replace function public.dm_list_messages(
  p_thread  uuid,
  p_before  timestamptz default null,
  p_after   timestamptz default null,
  p_limit   integer     default 100
)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.dm_is_participant(p_thread) then raise exception 'not_participant' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.sent_at, x.id)
                     from (select v.* from public.dm_visible(p_thread) v
                            where (p_before is null or v.sent_at < p_before)
                              and (p_after  is null or v.created_at > p_after)
                            order by v.sent_at desc, v.id desc
                            limit least(greatest(coalesce(p_limit, 100), 1), 200)) x), '[]'::jsonb);
end;
$$;

-- Envía un mensaje de texto. Repetible con el mismo p_id sin duplicar.
create or replace function public.dm_send(
  p_id       uuid,
  p_thread   uuid,
  p_body     text,
  p_sent_at  timestamptz default now(),
  p_device   text        default 'movil'
)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_rows integer := 0;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not public.dm_can_chat() then raise exception 'not_verified' using errcode = '42501'; end if;
  if not public.dm_is_participant(p_thread) then raise exception 'not_participant' using errcode = '42501'; end if;
  if coalesce(length(btrim(p_body)), 0) = 0 then raise exception 'empty_message' using errcode = '22023'; end if;
  insert into public.dm_messages (id, thread_id, sender_id, sender_device, body, sent_at)
  values (p_id, p_thread, auth.uid(), coalesce(nullif(btrim(p_device), ''), 'movil'), p_body, coalesce(p_sent_at, now()))
  on conflict (id) do nothing;
  get diagnostics v_rows = row_count;
  if v_rows = 0 and not exists (select 1 from public.dm_messages where id = p_id and sender_id = auth.uid()) then
    raise exception 'message_id_taken' using errcode = '42501';
  end if;
  update public.dm_threads set last_message_at = now() where id = p_thread;
  return (select to_jsonb(m) from public.dm_messages m where m.id = p_id);
end;
$$;

-- «Borrar para mí» un mensaje: deja de enseñárselo a quien llama (el otro lo sigue viendo; la base de datos no cambia).
create or replace function public.dm_hide_message(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not exists (select 1 from public.dm_messages m where m.id = p_id and public.dm_is_participant(m.thread_id)) then
    raise exception 'not_participant' using errcode = '42501';
  end if;
  insert into public.dm_hidden_messages (user_id, message_id) values (auth.uid(), p_id) on conflict do nothing;
end;
$$;

-- «Vaciar chat» solo para quien llama: lo enviado hasta ahora deja de enseñársele.
create or replace function public.dm_clear_thread(p_thread uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.dm_is_participant(p_thread) then raise exception 'not_participant' using errcode = '42501'; end if;
  insert into public.dm_thread_state (user_id, thread_id, cleared_before, last_read_at) values (auth.uid(), p_thread, now(), now())
  on conflict (user_id, thread_id) do update set cleared_before = now(), last_read_at = now();
end;
$$;

-- Marca como leída la conversación (para el contador de no leídos).
create or replace function public.dm_mark_read(p_thread uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.dm_is_participant(p_thread) then raise exception 'not_participant' using errcode = '42501'; end if;
  insert into public.dm_thread_state (user_id, thread_id, last_read_at) values (auth.uid(), p_thread, now())
  on conflict (user_id, thread_id) do update set last_read_at = now();
end;
$$;

-- ---------- supervisión (solo el administrador) ----------

-- Todas las conversaciones: {id, a, b, count, last_message_at}, de la más reciente a la más vieja.
create or replace function public.dm_admin_threads()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'admin_only' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
                     'id', t.id,
                     'a', public.dm_person_json(t.user_a),
                     'b', public.dm_person_json(t.user_b),
                     'count', (select count(*) from public.dm_messages m where m.thread_id = t.id),
                     'last_message_at', t.last_message_at) order by t.last_message_at desc nulls last)
                     from public.dm_threads t
                    where exists (select 1 from public.dm_messages m where m.thread_id = t.id)), '[]'::jsonb);
end;
$$;

-- Todos los mensajes de una conversación (también los que alguien ocultó para sí), con el nombre de quien envía.
create or replace function public.dm_admin_messages(p_thread uuid, p_before timestamptz default null, p_limit integer default 200)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'admin_only' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(to_jsonb(x) || jsonb_build_object('sender_name', (select username from public.profiles where id = x.sender_id))
                                    order by x.sent_at, x.id)
                     from (select m.* from public.dm_messages m
                            where m.thread_id = p_thread and (p_before is null or m.sent_at < p_before)
                            order by m.sent_at desc, m.id desc
                            limit least(greatest(coalesce(p_limit, 200), 1), 500)) x), '[]'::jsonb);
end;
$$;

-- Borra DE VERDAD un mensaje (para los dos). Solo el administrador.
create or replace function public.dm_admin_delete_message(p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'admin_only' using errcode = '42501'; end if;
  delete from public.dm_messages where id = p_id;
end;
$$;

-- Borra DE VERDAD una conversación entera con sus mensajes. Solo el administrador.
create or replace function public.dm_admin_delete_thread(p_thread uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'admin_only' using errcode = '42501'; end if;
  delete from public.dm_threads where id = p_thread;
end;
$$;

do $$
declare f text;
begin
  foreach f in array array[
    'dm_directory()', 'dm_open_thread(uuid)', 'dm_list_threads()', 'dm_list_messages(uuid, timestamptz, timestamptz, integer)',
    'dm_send(uuid, uuid, text, timestamptz, text)', 'dm_hide_message(uuid)', 'dm_clear_thread(uuid)', 'dm_mark_read(uuid)',
    'dm_admin_threads()', 'dm_admin_messages(uuid, timestamptz, integer)', 'dm_admin_delete_message(uuid)', 'dm_admin_delete_thread(uuid)'
  ] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- Tiempo real: los mensajes nuevos llegan al instante a los dos (y al administrador); la seguridad por fila decide quién los recibe.
alter table public.dm_messages replica identity full;
do $$ begin
  alter publication supabase_realtime add table public.dm_messages;
exception when duplicate_object then null; when undefined_object then null; end $$;

-- Fin. Ahora crea tu usuario en Authentication > Users (ver Server/supabase/README.md).
