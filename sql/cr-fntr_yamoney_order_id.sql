create or replace function fntr_yamoney_order_id()
returns trigger 
language plpgsql
as
$$
declare
--v_uid text := 'v.s.cherbo@gmail.com #15598';
--v_id integer;

begin
    -- EXCEPTION
    new.order_id := regexp_replace(new.order_uid, '.* #', '', 'g')::integer;
    -- raise notice 'id=%', new.order_id;
    return new;
end $$
