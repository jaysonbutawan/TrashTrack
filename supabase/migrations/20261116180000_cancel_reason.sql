-- Collectors say why they give a reservation back ("Price not agreed",
-- "Not collected – no one was home", …); the household sees it.
alter table public.posts
  add column if not exists cancel_reason text not null default '';

drop function if exists public.cancel_reservation(uuid);

create function public.cancel_reservation(post_id uuid, reason text default '')
returns void
language plpgsql security definer set search_path = public as $$
begin
  update posts set status = 'available', reserved_by = null,
                   reserved_by_name = null, reserved_at = null,
                   cancel_reason = left(coalesce(trim(reason), ''), 120)
   where id = post_id and status = 'reserved' and reserved_by = auth.uid();
  if not found then
    raise exception 'You can no longer cancel this.';
  end if;
end $$;

revoke execute on function public.cancel_reservation(uuid, text) from anon, public;
grant execute on function public.cancel_reservation(uuid, text) to authenticated;
