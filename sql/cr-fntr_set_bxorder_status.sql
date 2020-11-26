CREATE OR REPLACE FUNCTION arc_energo.fntr_set_bxorder_status()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
-- 2: оплачен
UPDATE "Счета" SET "Статус" = 2 WHERE "ИнтернетЗаказ" = NEW.order_id AND ("Статус" < 2 OR "Статус" IS NULL);
PERFORM "fn_InetOrderNewStatus"(2, NEW.order_id);
RETURN NEW;
END;
$function$
