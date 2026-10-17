-- Checks for leaderboard.sql. Run against a scratch database that has the
-- anon role (Supabase has it; locally: create role anon nologin):
--   psql -v ON_ERROR_STOP=1 -d scratch -f leaderboard.sql -f test_leaderboard.sql
-- Prints PASS lines and stops at the first failure.

set role anon;

do $$
declare
  p1 uuid := gen_random_uuid();
  p2 uuid := gen_random_uuid();
  run uuid;
  rk int;
  bst int;
  today text := to_char((now() at time zone 'utc')::date, 'YYYY-MM-DD');
  board text := 'daily:phone:' || to_char((now() at time zone 'utc')::date, 'YYYY-MM-DD');
  n int;
  ok boolean;
  msg text;
begin
  -- Tables are closed to the public role.
  begin
    perform 1 from public.bp_scores;
    raise exception 'FAIL: anon can read bp_scores';
  exception when insufficient_privilege then raise notice 'PASS tables closed (read)';
  end;
  begin
    insert into public.bp_scores (board, player, name, score) values (board, p1, 'X', 999);
    raise exception 'FAIL: anon can write bp_scores';
  exception when insufficient_privilege then raise notice 'PASS tables closed (write)';
  end;

  -- Boards.
  for msg in select unnest(array['daily:phone:1999-01-01', 'weekly:phone', 'endless:toaster', 'daily:phone:2026-13-45', '']) loop
    begin
      perform public.bp_start_run(p1, msg);
      raise exception 'FAIL: board % accepted', msg;
    exception when raise_exception then
      if sqlerrm <> 'bp_bad_board' then raise; end if;
    end;
  end loop;
  raise notice 'PASS bad boards refused';

  -- A score faster than anyone could play is refused.
  run := public.bp_start_run(p1, board);
  begin
    perform public.bp_submit(run, p1, 'Andrew', 40);
    raise exception 'FAIL: instant 40 accepted';
  exception when raise_exception then
    if sqlerrm <> 'bp_too_fast' then raise; end if;
  end;
  raise notice 'PASS too fast refused';

  -- Someone else's run id is refused.
  begin
    perform public.bp_submit(run, p2, 'Thief', 0);
    raise exception 'FAIL: other player run accepted';
  exception when raise_exception then
    if sqlerrm <> 'bp_bad_run' then raise; end if;
  end;
  raise notice 'PASS other player run refused';

  -- A zero needs no time; a run id works once.
  select s.rank, s.best into rk, bst from public.bp_submit(run, p1, '  Andrew   J ', 0) s;
  if rk <> 1 or bst <> 0 then raise exception 'FAIL: first submit rank % best %', rk, bst; end if;
  begin
    perform public.bp_submit(run, p1, 'Andrew', 0);
    raise exception 'FAIL: run used twice';
  exception when raise_exception then
    if sqlerrm <> 'bp_used_run' then raise; end if;
  end;
  raise notice 'PASS run ids are single use';

  -- Names.
  for msg in select unnest(array['F U C K', 'fvck', 'sh1t', 'NAZI88', 'a', 'way too long a name', '<script>', '___', 'cum', 'big ass']) loop
    run := public.bp_start_run(p2, 'endless:desktop');
    begin
      perform public.bp_submit(run, p2, msg, 0);
      if msg <> 'fvck' then
        raise exception 'FAIL: name % accepted', msg;
      end if;
    exception when raise_exception then
      if sqlerrm not in ('bp_name_invalid', 'bp_name_blocked') then raise; end if;
    end;
  end loop;
  raise notice 'PASS bad names refused';
  -- Ranking: best kept, ties go to whoever got there first, own row shown.
  reset role;
  update public.bp_runs set started_at = now() - interval '10 minutes' where player in (p1, p2);
  set role anon;
  run := public.bp_start_run(p2, board);
  reset role;
  update public.bp_runs set started_at = now() - interval '10 minutes' where id = run;
  set role anon;
  select s.rank, s.best into rk, bst from public.bp_submit(run, p2, 'Charlie', 12) s;
  if rk <> 1 or bst <> 12 then raise exception 'FAIL: p2 rank % best %', rk, bst; end if;
  select count(*) into n from public.bp_top(board, p1, 20);
  if n <> 2 then raise exception 'FAIL: top has % rows', n; end if;
  select me into ok from public.bp_top(board, p1, 20) where name = 'Andrew J';
  if not ok then raise exception 'FAIL: own row not flagged (or name not tidied)'; end if;
  select count(*) into n from public.bp_top(board, p1, 1);
  if n <> 2 then raise exception 'FAIL: own row missing below the limit (% rows)', n; end if;
  raise notice 'PASS top list, own row, tidy names';

  -- A worse score later doesn't replace the best.
  run := public.bp_start_run(p2, board);
  reset role;
  update public.bp_runs set started_at = now() - interval '10 minutes' where id = run;
  set role anon;
  select s.rank, s.best into rk, bst from public.bp_submit(run, p2, 'Charlie', 3) s;
  if bst <> 12 then raise exception 'FAIL: best replaced by worse (%)', bst; end if;
  raise notice 'PASS best kept';

  -- Rename.
  perform public.bp_rename(p2, 'Chaz');
  select count(*) into n from public.bp_top(board, null, 20) where name = 'Chaz';
  if n <> 1 then raise exception 'FAIL: rename'; end if;
  begin
    perform public.bp_rename(p2, 'b1tch');
    raise exception 'FAIL: rename to blocked name accepted';
  exception when raise_exception then
    if sqlerrm <> 'bp_name_blocked' then raise; end if;
  end;
  raise notice 'PASS rename';

  -- Rate limit: 12 runs a minute per device.
  begin
    for n in 1..20 loop
      perform public.bp_start_run(p1, 'endless:phone');
    end loop;
    raise exception 'FAIL: no rate limit';
  exception when raise_exception then
    if sqlerrm <> 'bp_slow_down' then raise; end if;
  end;
  raise notice 'PASS rate limit';
end;
$$;

reset role;

-- Ordinary names that contain a blocked word inside them are allowed.
do $$
declare
  msg text;
begin
  foreach msg in array array['Arsenal fan', 'Cocoon', 'Grape', 'Phoebe', 'Sussex', 'Dickens', 'Torpedo', 'Hancock', 'Essex_Lad', 'Andy J', 'Mo', 'x.y-z_1'] loop
    perform public.bp_clean_name(msg);
  end loop;
  raise notice 'PASS ordinary names allowed';
end;
$$;
