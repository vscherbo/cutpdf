#!/bin/sh

. /usr/local/bin/bashlib

DT=`date +%F_%H_%M_%S`
#############
#DO=echo
DO=''
PG_SRV=vm-pg
#############

#1. received email are processed by procmail and ripmime
# result is the csv file in directory specified with .procmailrc 
# i.e.  ripmime -i - -d /path/to/mailbox 
CSV_DIR=`grep yamregister ~/.procmailrc | awk -F '-d' '{print $2}' | awk '{print $1}'`
LOG_DIR=$CSV_DIR/logs
CSV_DATA=$CSV_DIR/01-data
CSV_ARCH=$CSV_DIR/99-archive
ARCHIVE_DEPTH=60

[ -d $CSV_DIR ] || mkdir -p $CSV_DIR
[ -d $LOG_DIR ] || mkdir -p $LOG_DIR
[ -d $CSV_DATA ] || mkdir -p $CSV_DATA
[ -d $CSV_ARCH ] || mkdir -p $CSV_ARCH

find $CSV_ARCH -type f -mtime +$ARCHIVE_DEPTH -delete # -exec rm -f {} \+
find $LOG_DIR -type f -mtime +$ARCHIVE_DEPTH -delete # -exec rm -f {} \+

LOG=$LOG_DIR/$DT-`namename $0`.log
exec 1>>$LOG 2>&1

#1. get email with register in the body - after 05:00
#

PG_COPY_SCRIPT=$CSV_DATA/pg-COPY-registry-$DT.sql

pushd $CSV_DIR

> $PG_COPY_SCRIPT
IMPORT='NO'
IFS_BCK=$IFS
IFS=$'\n'
#3. Prepare COPY commands for PG
REGS_LIST=`ls -1 *yamregister*`
logmsg INFO "REGS_LIST=$REGS_LIST"
for csv1251 in $REGS_LIST
do
  txt=$CSV_DATA/${csv1251}.txt
  iconv -f cp1251 -t utf8 $csv1251 |dos2unix > $txt
  rm -f $csv1251
  # import files containing not only header 
  # input file doesn't contain CR on the last line. Use grep+wc
  ROWS=`grep 'kipspb.ru' $txt | wc -l`
  if [ $ROWS -gt 0 ]
  then 
     logmsg INFO "TXT file $txt contains $ROWS rows. Prepare \\COPY command to load CSV into PG"
     set -vx
     # reg_no=`awk -F'№ ' '/РЕЕСТР ПЛАТЕЖЕЙ В ООО "АРКОМ". №/ {print $2}' $txt`
     reg_date=`awk -F': ' '/Дата платежей:/ {print $2}' $txt`
IFS=. read loc_day loc_mon loc_year <<EODATE
${reg_date}
EODATE
     PAY_DT=${loc_year}-${loc_mon}-${loc_day}
     csv_name=$PAY_DT-`namename $txt`
     PG_CSV=$CSV_DATA/$csv_name.csv
     grep 'kipspb.ru' $txt |sed -e 's/; /;/g' -e "s/$/$reg_date/" > $PG_CSV
     mv $txt $CSV_DATA/$PAY_DT-`namename $txt`

     echo "\COPY yamregister FROM '"$PG_CSV"' WITH ( FORMAT CSV, HEADER false, DELIMITER ';') ;" >> $PG_COPY_SCRIPT
     IMPORT='YES'
     set +vx
  else
     logmsg INFO "The registry $txt does not contain data row. Skip it, just archive"
     #echo '====================================='
     #cat $txt
     #echo '====================================='
     $DO mv $txt $CSV_ARCH/$DT-`namename $txt`
  fi
done
IFS=$IFS_BCK

#4. Import registry into PG
# use ~/.pgpass
if [ $IMPORT == 'YES' ]
then
   logmsg INFO "\\COPY $PG_CSV into $PG_SRV"
   cat $PG_CSV
   echo ""

   $DO psql --set ON_ERROR_STOP=on -h $PG_SRV -U arc_energo -d arc_energo -w -f $PG_COPY_SCRIPT
   RC_IMP=$?
   logmsg $RC_IMP "The Yandex.money registry($PG_COPY_SCRIPT) imported."

   #4. Link registry with Bills and SET inetamount
   if [ $RC_IMP -eq 0 ]
   then 
      logmsg INFO "CSV successfully loaded into $PG_SRV"
      ORDERS_SET=`awk -F ";" '$2 ~ /[0-9]+/ {s=s $2 ","}END{gsub(/\"/, "", s); printf "%s", substr(s, 1, length(s)-1) }' $PG_CSV` 
      if [ +$ORDERS_SET != '+' ]
      then
         logmsg INFO "Check Счета: ИнтернетЗаказ $ORDERS_SET"
         echo "SELECT \"ИнтернетЗаказ\", \"Интернет\", \"Оплачен\", inetamount FROM \"Счета\" WHERE \"ИнтернетЗаказ\" IN ("$ORDERS_SET");" > sql.file
         cat sql.file
         $DO psql -h $PG_SRV -U arc_energo -d arc_energo -w -f sql.file
         #
         logmsg INFO "Check yamregister: order_id $ORDERS_SET"
         echo "SELECT * FROM yamregister WHERE order_id IN ("$ORDERS_SET");" > sql.file
         cat sql.file
         $DO psql -h $PG_SRV -U arc_energo -d arc_energo -w -f sql.file
         #
         logmsg INFO "Try JOIN Счета and yamregister tables on ORDERS_SET=$ORDERS_SET"
         echo "SELECT \"ИнтернетЗаказ\", yamregister.order_id, \"Интернет\", \"Оплачен\", inetamount FROM \"Счета\", yamregister WHERE \"ИнтернетЗаказ\" = yamregister.order_id AND yamregister.order_id IN ("$ORDERS_SET");" > sql.file
         cat sql.file
         $DO psql -h $PG_SRV -U arc_energo -d arc_energo -w -f sql.file
         rm -f sql.file
      fi

      logmsg INFO "Try UPDATE Счета table"
      $DO psql -h $PG_SRV -U arc_energo -d arc_energo -w -c "UPDATE Счета SET inetamount = yamregister.net_amount, Сообщение = 't', inetdt = yamregister.payment_ts, ps_id = 3 FROM yamregister WHERE ИнтернетЗаказ = yamregister.order_id AND Интернет = 't' AND Оплачен = 'f' AND inetamount IS NULL;" 
      RC_LINK=$?
      logmsg $RC_LINK "Linking the Yandex.money registry with Счета finished."
      #
      $DO mv $CSV_DATA/*yamregister* $CSV_ARCH/
      $DO mv $PG_COPY_SCRIPT $CSV_ARCH/
   fi # if RC_IMP=0 
else
   rm -f $PG_COPY_SCRIPT
fi # if IMPORT

popd

