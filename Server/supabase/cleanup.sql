-- =====================================================================================================================
-- Kyora · limpieza automática: programa la función cleanup-expired para que corra cada hora.
--
-- Hazlo UNA vez, después de ejecutar schema.sql y de desplegar la función (ver "Limpieza automática" en README.md):
--   1. Cambia  TU_PROYECTO  por el identificador de tu proyecto (la parte de https://TU_PROYECTO.supabase.co).
--   2. Cambia  TU_SECRETO   por el mismo texto que pusiste en  supabase secrets set CLEANUP_SECRET=...
--   3. Pégalo en Supabase > SQL Editor y pulsa Run. Se puede ejecutar varias veces (reemplaza la tarea anterior).
--
-- Para quitarla:  select cron.unschedule('kyora-cleanup-expired');
-- Para ver cómo le va:  select * from cron.job_run_details order by start_time desc limit 10;
-- =====================================================================================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

do $$ begin
  perform cron.unschedule('kyora-cleanup-expired');
exception when others then null;   -- no existía todavía
end $$;

select cron.schedule(
  'kyora-cleanup-expired',
  '0 * * * *',                                   -- al minuto 0 de cada hora
  $job$
    select net.http_post(
      url     := 'https://TU_PROYECTO.supabase.co/functions/v1/cleanup-expired',
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-cleanup-secret', 'TU_SECRETO'),
      body    := '{}'::jsonb
    );
  $job$
);
