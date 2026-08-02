-- Doc utilisateur P9 — un jeton de push ActivityKit par (partie, appareil) : permet à la fonction
-- Edge `cacompte-live-activity-push` de mettre à jour l'écran verrouillé/Dynamic Island d'un appareil même
-- quand son app est suspendue en arrière-plan (un `Activity.update` local ne peut s'exécuter que
-- pendant que le code tourne — Apple ne fournit aucun autre moyen). Contenu volontairement
-- minimal : seul le jeton nécessaire à APNs, jamais le score lui-même (qui reste transmis en
-- clair uniquement dans le corps du push lui-même, construit à la demande par la fonction Edge).
create table if not exists public.cacompte_live_activity_tokens (
    match_id uuid not null,
    device_id text not null,
    push_token text not null,
    updated_at timestamptz not null default now(),
    primary key (match_id, device_id)
);

alter table public.cacompte_live_activity_tokens enable row level security;

-- Doc utilisateur — un appareil n'a besoin que d'écrire son propre jeton (à l'ouverture de la
-- Live Activity, puis à chaque rotation de jeton signalée par `Activity.pushTokenUpdates`) ;
-- `service_role` (fonction Edge) contourne RLS de toute façon. La policy `select` ci-dessous est
-- requise même si l'app ne lit jamais cette table : Postgres a besoin de pouvoir évaluer une
-- policy SELECT pour détecter une ligne en conflit lors d'un `INSERT ... ON CONFLICT DO UPDATE`
-- (l'`upsert` utilisé par `LiveActivityPushClient.registerToken`), sans quoi RLS le bloque même
-- quand aucun conflit ne survient réellement.
create policy "anon can select own cacompte_live_activity_tokens" on public.cacompte_live_activity_tokens
    for select
    to anon
    using (true);

create policy "anon can upsert own cacompte_live_activity_tokens" on public.cacompte_live_activity_tokens
    for insert
    to anon
    with check (true);

create policy "anon can update own cacompte_live_activity_tokens" on public.cacompte_live_activity_tokens
    for update
    to anon
    using (true)
    with check (true);

create policy "anon can delete own cacompte_live_activity_tokens" on public.cacompte_live_activity_tokens
    for delete
    to anon
    using (true);

create index if not exists cacompte_live_activity_tokens_match_id_idx on public.cacompte_live_activity_tokens (match_id);
