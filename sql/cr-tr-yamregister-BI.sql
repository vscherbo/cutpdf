create trigger "tr_yamregister_BI" before insert
on yamregister
for each row execute procedure fntr_yamoney_order_id()