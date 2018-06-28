create extension if not exists "postgis";
create extension if not exists "uuid-ossp";

create role application_user;

create table if not exists users (
  id uuid default uuid_generate_v4() not null primary key,
  name text not null
);

create table if not exists items (
  id uuid default uuid_generate_v4() not null primary key,
  value text,
  created_at timestamp with time zone default now(),
  parent_id uuid references public.items(id),
  public boolean default false
);

create table if not exists user_items (
  item_id uuid references items(id),
  user_id uuid references users(id)
);

create view items_view
with (security_barrier)
as
  select items.*
  from items
  join user_items on item_id = items.id
  and user_id = current_setting('jwt.claims.role')::uuid;

grant all
on schema public
to application_user;

grant all
on all tables in schema public
to application_user;

create policy user_item_owner
on user_items
for all
to application_user
using (user_items.user_id = current_setting('jwt.claims.role')::uuid)
with check (user_items.user_id = current_setting('jwt.claims.role')::uuid);

create or replace function insert_user_item()
  returns trigger
  as $$
begin
  insert into user_items (item_id, user_id) values (
    new.id,
    current_setting('jwt.claims.role')::uuid
  );
  return new;
end
$$ language plpgsql;

create trigger insert_user_item_trigger
after insert
on items
for each row
execute procedure insert_user_item();

create or replace function create_role()
  returns trigger
  as $$
begin
  execute 'create role ' || quote_ident( new.id::text ) || ' inherit';
  execute 'grant application_user to ' || quote_ident( new.id::text );
  return new;
end
$$ language plpgsql;

create trigger insert_user_trigger
after insert
on users
for each row
execute procedure create_role();
