-- Doc utilisateur P9 — remplace la découverte Wi-Fi/BLE (jamais fiable en conditions réelles,
-- voir historique des correctifs BLE) : résout un code d'appairage tapé à la main vers la partie
-- correspondante, sans aucun scan réseau/Bluetooth. Contenu volontairement minimal — le contenu
-- réel des manches ne transite jamais ici, seulement le nécessaire pour rejoindre le bon canal
-- Realtime (`match:<match_id>`). Aucune ligne n'est censée survivre longtemps : l'hôte supprime la
-- sienne à l'arrêt du partage (voir `SupabaseTransport.stopAdvertising`).
create table if not exists public.open_games (
    pairing_code text primary key,
    match_id uuid not null,
    game_id text not null,
    participant_count integer not null,
    device_name text not null,
    platform text not null,
    created_at timestamptz not null default now()
);

alter table public.open_games enable row level security;

-- Doc utilisateur — même modèle de confiance qu'aujourd'hui (Wi-Fi/BLE) : quiconque connaît le
-- code peut rejoindre : ce n'est pas une permission par utilisateur (pas d'authentification
-- Supabase dans ce projet), le contenu réel reste protégé par le chiffrement côté client
-- (`SessionCrypto`, dérivé du code d'appairage), pas par une règle de base de données.
create policy "anon can read open_games" on public.open_games
    for select
    to anon
    using (true);

create policy "anon can insert open_games" on public.open_games
    for insert
    to anon
    with check (true);

create policy "anon can delete own open_games" on public.open_games
    for delete
    to anon
    using (true);

-- Doc utilisateur — évite d'accumuler indéfiniment des parties abandonnées sans qu'un appareil
-- n'ait pu supprimer proprement sa ligne (app tuée en plein partage) : purge tout ce qui dépasse
-- 24h, largement au-delà de la durée d'une partie normale.
create index if not exists open_games_created_at_idx on public.open_games (created_at);
