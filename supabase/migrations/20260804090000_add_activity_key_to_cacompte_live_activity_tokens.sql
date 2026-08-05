-- Doc 09 « Fin de partie » (révisé) — une Live Activity peut désormais survivre à un changement
-- de partie au sein d'une même session de partage (voir `cacompte_open_games.session_id`) : sa
-- clé de routage doit donc être stable pour toute la session, pas juste pour la partie affichée à
-- un instant donné. `activity_key` vaut `"session:<sessionID>"` tant qu'une session de partage est
-- active, `"match:<matchID>"` sinon (partie solo) — construit côté client
-- (`MatchLiveActivityController.activityKey`), jamais recalculé côté serveur.
alter table public.cacompte_live_activity_tokens
    add column activity_key text not null default ('match:' || match_id::text);

-- Le défaut n'existe que pour remplir les lignes déjà présentes au moment de la migration ; les
-- nouvelles lignes fournissent toujours leur propre `activity_key` explicitement
-- (`LiveActivityPushClient.registerToken`).
alter table public.cacompte_live_activity_tokens alter column activity_key drop default;

alter table public.cacompte_live_activity_tokens drop constraint cacompte_live_activity_tokens_pkey;
alter table public.cacompte_live_activity_tokens add constraint cacompte_live_activity_tokens_pkey primary key (activity_key, device_id);

drop index if exists public.cacompte_live_activity_tokens_match_id_idx;
create index if not exists cacompte_live_activity_tokens_activity_key_idx on public.cacompte_live_activity_tokens (activity_key);

-- Doc 09 « Fin de partie » — `updated_at` (déjà présent, jusqu'ici seulement mis à jour à
-- l'enregistrement/rotation d'un jeton) sert désormais aussi de repère d'activité : la fonction
-- Edge `cacompte-live-activity-push` le retouche à chaque push « update » réussi, et
-- `cacompte-live-activity-sweep` (nouvelle fonction, appelée périodiquement) s'en sert pour
-- terminer une Live Activity restée inactive plus de 30 minutes.
--
-- `last_content_state` retient le dernier contenu poussé (même forme que
-- `MatchActivityAttributes.ContentState`, encodée en JSON) : `cacompte-live-activity-sweep` n'a
-- par construction jamais reçu le score lui-même (seule l'app le connaît), il a besoin de ce
-- dernier contenu connu pour envoyer un push « end » valide plutôt que d'inventer un contenu vide.
alter table public.cacompte_live_activity_tokens
    add column last_content_state jsonb;
