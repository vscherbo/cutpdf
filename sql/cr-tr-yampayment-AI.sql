create trigger "tr_yampayment_AI" after insert
on yampayment
for each row execute procedure fntr_set_bxorder_status()
