-- Pocket Hoops world leaderboard: every player's best Arcade score, with the name they picked and
-- the character they play as (drawn as their avatar on the board).
--
-- The app only goes through the two functions below (Supabase's REST API serves them at
-- /rest/v1/rpc/<name>). App users can't read or write the table directly, and the board never
-- hands out anyone's player id.

create table if not exists public.arcade_scores (
  -- Made by the app when the player joins the board. There are no accounts, so the id is all that
  -- ties a device to its row.
  player_id  uuid primary key,
  -- 1–10 of A–Z, 0–9 and inner spaces: the letters the game's pixel font can draw.
  name       text not null check (name ~ '^[A-Z0-9]([A-Z0-9 ]{0,8}[A-Z0-9])?$'),
  -- "character:accessory,accessory,…" using the shop's ids, e.g. "maya:beanie,hoodie".
  outfit     text not null default 'kid:' check (outfit ~ '^[a-z0-9]{1,16}:[a-z0-9,]{0,120}$'),
  -- Far above anything a person can score in Arcade; only there to turn away junk.
  score      integer not null check (score between 1 and 3000),
  -- When the score was set. The earlier of two equal scores places higher.
  updated_at timestamptz not null default now()
);

create index if not exists arcade_scores_by_score on public.arcade_scores (score desc, updated_at);

alter table public.arcade_scores enable row level security;
revoke all on table public.arcade_scores from anon, authenticated;

-- Records a game. The best score is kept; the name and look are updated every time.
create or replace function public.submit_arcade_score(p_player uuid, p_name text, p_outfit text, p_score integer)
returns void
language sql
security definer
set search_path = public
as $$
  insert into arcade_scores as s (player_id, name, outfit, score)
  values (p_player, p_name, p_outfit, p_score)
  on conflict (player_id) do update
    set name = excluded.name,
        outfit = excluded.outfit,
        score = greatest(s.score, excluded.score),
        updated_at = case when excluded.score > s.score then now() else s.updated_at end;
$$;

-- The top of the board (at most 100 rows) plus the asking player's own row wherever it is, and the
-- number of players:
--   {"total": 812, "top": [{"rank": 1, "name": "ACE", "outfit": "robo:", "score": 931, "you": false}, …],
--    "you": {"rank": 57, "name": "JASON", "outfit": "maya:beanie", "score": 224, "you": true}}
-- Equal scores share a rank. p_player is left out by a player who hasn't joined.
create or replace function public.arcade_leaderboard(p_player uuid default null, p_limit integer default 50)
returns json
language sql
stable
security definer
set search_path = public
as $$
  with ranked as (
    select player_id, name, outfit, score,
           rank() over (order by score desc) as rank,
           row_number() over (order by score desc, updated_at, player_id) as place
    from arcade_scores
  )
  select json_build_object(
    'total', (select count(*) from arcade_scores),
    'top', coalesce((
      select json_agg(json_build_object('rank', rank, 'name', name, 'outfit', outfit, 'score', score,
                                        'you', coalesce(player_id = p_player, false)) order by place)
      from ranked
      where place <= least(greatest(coalesce(p_limit, 50), 1), 100)
    ), '[]'::json),
    'you', (
      select json_build_object('rank', rank, 'name', name, 'outfit', outfit, 'score', score, 'you', true)
      from ranked
      where player_id = p_player
    )
  );
$$;

revoke all on function public.submit_arcade_score(uuid, text, text, integer) from public;
revoke all on function public.arcade_leaderboard(uuid, integer) from public;
grant execute on function public.submit_arcade_score(uuid, text, text, integer) to anon, authenticated;
grant execute on function public.arcade_leaderboard(uuid, integer) to anon, authenticated;
