-- Button Panic leaderboards: tables and functions for a Supabase project.
--
-- Run this once in the project's SQL Editor (or `psql -f`). It is safe to run
-- again: everything is created "if not exists" or replaced.
--
-- How it works
--   * Players never touch the tables. Row level security is on with no
--     policies, and table rights are revoked from the public roles, so the
--     only way in is the four functions at the bottom.
--   * A run starts with bp_start_run (server notes the time) and ends with
--     bp_submit. A score is refused if it arrives faster than anyone could
--     play that many rounds, if the run id was already used or belongs to
--     someone else, or if the run is more than six hours old.
--   * Names are 2-14 letters, digits, spaces, dots, dashes or underscores,
--     and are checked against a list of slurs and swear words (also with
--     0/1/3/4/5/7/8 standing in for letters, and with spaces or repeated
--     letters squeezed out).
--   * Each device keeps one row per board: its best score.
--
-- Boards
--   daily:<phone|mouse|desktop>:<yyyy-mm-dd>   one per version per day
--   endless:<phone|mouse|desktop>              all-time

create table if not exists public.bp_runs (
  id uuid primary key default gen_random_uuid(),
  player uuid not null,
  board text not null,
  started_at timestamptz not null default now(),
  used_at timestamptz
);
create index if not exists bp_runs_player_time on public.bp_runs (player, started_at desc);

create table if not exists public.bp_scores (
  board text not null,
  player uuid not null,
  name text not null,
  score int not null check (score between 0 and 999),
  achieved_at timestamptz not null default now(),
  primary key (board, player)
);
create index if not exists bp_scores_rank on public.bp_scores (board, score desc, achieved_at asc);
create index if not exists bp_scores_player on public.bp_scores (player);

alter table public.bp_runs enable row level security;
alter table public.bp_scores enable row level security;
revoke all on table public.bp_runs from public, anon, authenticated;
revoke all on table public.bp_scores from public, anon, authenticated;

-- Seconds a round takes at the very least (a press, then the short pause
-- before the next round). A score of N needs at least N times this.
create or replace function public.bp_min_seconds_per_round() returns numeric
  language sql immutable as $$ select 0.45::numeric $$;

-- Checks a name and returns it tidied, or raises bp_name_invalid /
-- bp_name_blocked.
create or replace function public.bp_clean_name(p_name text) returns text
  language plpgsql immutable
  set search_path = public
as $$
declare
  n text;
  flat text;
  squeezed text;
  tokens text[];
  w text;
  -- Matched anywhere inside the name.
  inside constant text[] := array[
    'fuck', 'fck', 'shit', 'cunt', 'kunt', 'nigg', 'niga', 'nigr', 'faggot', 'fagot',
    'raper', 'rapist', 'nazi', 'hitler', 'kkk', 'wank', 'twat', 'bitch', 'biatch',
    'whore', 'slut', 'pussy', 'retard', 'spastic', 'spaz', 'kike', 'chink', 'gook',
    'wetback', 'tranny', 'dyke', 'porn', 'penis', 'vagina', 'dildo', 'jizz', 'bollock',
    'bellend', 'nonce', 'paedo', 'molest', 'incest', 'asshole', 'bastard', 'blowjob',
    'handjob', 'titty', 'boob', 'semen', 'sperm', 'orgasm', 'horny', 'jihad', 'golliwog',
    'raghead', 'towelhead', 'beaner', 'gyppo', 'pikey'
  ];
  -- Only matched as a whole word (they turn up inside ordinary words).
  whole constant text[] := array[
    'ass', 'arse', 'cum', 'fag', 'tit', 'tits', 'kys', 'nig', 'wog', 'coon', 'spic', 'sex',
    'cock', 'dick', 'anus', 'rape', 'hoe', 'pedo', 'paki', 'clit', 'negro', 'isis', 'fuk',
    'heil', 'boner'
  ];
begin
  n := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
  if n !~ '^[A-Za-z0-9 _.\-]{2,14}$' or n !~ '[A-Za-z0-9]' then
    raise exception 'bp_name_invalid';
  end if;
  flat := translate(lower(n), '0134578', 'oieastb');
  tokens := regexp_split_to_array(flat, '[^a-z]+');
  flat := regexp_replace(flat, '[^a-z]', '', 'g');
  squeezed := regexp_replace(flat, '(.)\1+', '\1', 'g');
  foreach w in array inside loop
    if position(w in flat) > 0 or position(w in squeezed) > 0 then
      raise exception 'bp_name_blocked';
    end if;
  end loop;
  if tokens && whole or array[flat] && whole or array[squeezed] && whole then
    raise exception 'bp_name_blocked';
  end if;
  return n;
end;
$$;

-- Starts a run on a board and returns its id.
create or replace function public.bp_start_run(p_player uuid, p_board text) returns uuid
  language plpgsql volatile security definer
  set search_path = public
as $$
declare
  today date := (now() at time zone 'utc')::date;
  d date;
  recent int;
  rid uuid;
begin
  if p_player is null then
    raise exception 'bp_bad_player';
  end if;
  if p_board ~ '^daily:(phone|mouse|desktop):\d{4}-\d{2}-\d{2}$' then
    begin
      d := split_part(p_board, ':', 3)::date;
    exception when others then
      raise exception 'bp_bad_board';
    end;
    -- Local dates run from UTC-12 to UTC+14.
    if d < today - 1 or d > today + 1 then
      raise exception 'bp_bad_board';
    end if;
  elsif p_board !~ '^endless:(phone|mouse|desktop)$' then
    raise exception 'bp_bad_board';
  end if;

  select count(*) into recent from bp_runs where player = p_player and started_at > now() - interval '1 minute';
  if recent >= 12 then
    raise exception 'bp_slow_down';
  end if;

  -- Old run ids are only needed for a few hours; tidy now and then.
  if random() < 0.02 then
    delete from bp_runs where started_at < now() - interval '2 days';
  end if;

  insert into bp_runs (player, board) values (p_player, p_board) returning id into rid;
  return rid;
end;
$$;

-- Ends a run with a score. Keeps the player's best on that board and
-- returns where it ranks.
create or replace function public.bp_submit(p_run uuid, p_player uuid, p_name text, p_score int)
  returns table (rank int, best int)
  language plpgsql volatile security definer
  set search_path = public
as $$
declare
  r bp_runs%rowtype;
  clean text;
  elapsed numeric;
  mine bp_scores%rowtype;
begin
  select * into r from bp_runs where id = p_run and player = p_player for update;
  if not found then
    raise exception 'bp_bad_run';
  end if;
  if r.used_at is not null then
    raise exception 'bp_used_run';
  end if;
  elapsed := extract(epoch from now() - r.started_at);
  if elapsed > 6 * 3600 then
    raise exception 'bp_stale_run';
  end if;
  if p_score is null or p_score < 0 or p_score > 999 then
    raise exception 'bp_bad_score';
  end if;
  if p_score > 0 and elapsed < p_score * bp_min_seconds_per_round() then
    raise exception 'bp_too_fast';
  end if;
  clean := bp_clean_name(p_name);

  update bp_runs set used_at = now() where id = r.id;

  insert into bp_scores as s (board, player, name, score)
  values (r.board, p_player, clean, p_score)
  on conflict (board, player) do update
    set name = excluded.name,
        score = greatest(s.score, excluded.score),
        achieved_at = case when excluded.score > s.score then now() else s.achieved_at end;

  select * into mine from bp_scores where board = r.board and player = p_player;
  rank := 1 + (
    select count(*) from bp_scores o
    where o.board = r.board
      and (o.score > mine.score or (o.score = mine.score and o.achieved_at < mine.achieved_at))
  );
  best := mine.score;
  return next;
end;
$$;

-- The top of a board, plus the asking player's own row if they're further
-- down. Never returns player ids.
create or replace function public.bp_top(p_board text, p_player uuid default null, p_limit int default 20)
  returns table (rank bigint, name text, score int, me boolean)
  language sql stable security definer
  set search_path = public
as $$
  with ranked as (
    select s.name, s.score, s.player,
           row_number() over (order by s.score desc, s.achieved_at asc) as rank
    from bp_scores s
    where s.board = p_board
  )
  select ranked.rank, ranked.name, ranked.score, coalesce(ranked.player = p_player, false) as me
  from ranked
  where ranked.rank <= least(greatest(coalesce(p_limit, 20), 1), 50)
     or ranked.player = p_player
  order by ranked.rank;
$$;

-- Changes the name on all of a player's rows.
create or replace function public.bp_rename(p_player uuid, p_name text) returns text
  language plpgsql volatile security definer
  set search_path = public
as $$
declare
  clean text := bp_clean_name(p_name);
begin
  update bp_scores set name = clean where player = p_player;
  return clean;
end;
$$;

revoke all on function public.bp_min_seconds_per_round() from public;
revoke all on function public.bp_clean_name(text) from public;
revoke all on function public.bp_start_run(uuid, text) from public;
revoke all on function public.bp_submit(uuid, uuid, text, int) from public;
revoke all on function public.bp_top(text, uuid, int) from public;
revoke all on function public.bp_rename(uuid, text) from public;

grant execute on function public.bp_start_run(uuid, text) to anon, authenticated;
grant execute on function public.bp_submit(uuid, uuid, text, int) to anon, authenticated;
grant execute on function public.bp_top(text, uuid, int) to anon, authenticated;
grant execute on function public.bp_rename(uuid, text) to anon, authenticated;
