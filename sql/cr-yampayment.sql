CREATE TABLE arc_energo.yampayment (
	id int4 NOT NULL,
	payment_dt timestamp NULL,
	sum numeric NULL,
	yam_id int8 NULL,
	order_uid varchar NULL,
	order_id int4 NULL,
	send_status_result varchar NULL,
	CONSTRAINT yampayment_pk PRIMARY KEY (id)
)
WITH (
	OIDS=FALSE
) ;
