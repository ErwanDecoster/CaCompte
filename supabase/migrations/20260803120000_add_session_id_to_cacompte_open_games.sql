-- Doc 09 « Fin de partie » (révisé) — une session de partage n'est plus liée à une seule partie :
-- l'hôte peut enchaîner plusieurs parties (même jeu rejoué ou jeu différent) sans jamais rouvrir
-- le canal Realtime ni changer de code d'appairage. Le canal et la ligne de découverte doivent
-- donc être adressés par un identifiant de session stable, distinct de `match_id` qui continue de
-- décrire seulement la partie *courante*.
alter table public.cacompte_open_games
    add column session_id uuid not null default gen_random_uuid();

-- Le défaut n'existe que pour remplir les lignes déjà présentes au moment de la migration
-- (normalement aucune — ces lignes ne survivent pas plus de quelques heures, voir le commentaire
-- sur `cacompte_open_games_created_at_idx`) ; les nouvelles lignes fournissent toujours leur propre
-- `session_id` explicitement (`SupabaseTransport.advertise`).
alter table public.cacompte_open_games alter column session_id drop default;

alter table public.cacompte_open_games
    add constraint cacompte_open_games_session_id_key unique (session_id);

-- Manquait jusqu'ici (seules select/insert/delete existaient) : un changement de partie au sein
-- d'une même session met désormais à jour `match_id`/`game_id`/`participant_count` sur la ligne
-- existante (`SupabaseTransport.updateActiveMatch`) plutôt que d'en recréer une — sans cette
-- policy, RLS bloque silencieusement chaque changement de partie.
create policy "anon can update cacompte_open_games" on public.cacompte_open_games
    for update
    to anon
    using (true)
    with check (true);
