CREATE TABLE arc_energo.yam_item (
    id int4 NOT NULL DEFAULT nextval('yam_item_id_seq'::regclass),
    yam_id int8 NOT NULL,
    item_name varchar NOT NULL,
    CONSTRAINT yam_item_pk PRIMARY KEY (id)
)
WITH (
    OIDS=FALSE
) ;