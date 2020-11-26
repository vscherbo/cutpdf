#!/bin/sh

. /usr/local/bin/bashlib

DT=`date +%F_%H_%M_%S`
#############
#DO=echo
DO=''
PG_SRV=vm-pg
#############

[ +$1 = +fetch ] && DO_FETCH='YES' || DO_FETCH='NO'

#1. received email are processed by procmail and ripmime
# result is the csv file in directory specified with .procmailrc 
# i.e.  ripmime -i - -d /path/to/mailbox 
CSV_DIR=`grep yamregister ~/.procmailrc | awk -F '-d' '{print $2}' | awk '{print $1}'`
[ +$CSV_DIR = + ] && { echo CSV_DIR unassigned, exiting; exit 123; }
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


if [ $DO_FETCH = 'YES' ]
then
    #1. get email with register in the body - after 05:00
    #
    #$DO fetchmail -f $CSV_DIR/.fetchmailrc -ak -m "/usr/bin/procmail -d %T"
    $DO fetchmail -f $CSV_DIR/.fetchmailrc -k -m "/usr/bin/procmail -d %T"

    RC=$?
    case $RC in
       0) logmsg INFO "One or more messages were successfully retrieved." 
          exit_rc=1 # work
          ;;
       1) logmsg INFO "There was no mail."
          exit_rc=0 # skip
          ;;
       *) logmsg $RC "fetchmail completed."
          exit_rc=$RC # unexpected RC
          ;;
    esac

    find $CSV_DIR -type f -name 'smime*.p7s' -delete
    find $CSV_DIR -type f -name 'yamregister*' -size 0c -delete

    # clean logs without mail
    grep -l 'There was no mail' $LOG_DIR/* |xargs --no-run-if-empty rm
    
    if [ $exit_rc -ne 1 ]
    then
       exit $exit_rc
    fi
fi # DO_FETCH

PG_COPY_SCRIPT=$CSV_DATA/pg-COPY-registry-$DT.sql

pushd $CSV_DIR

> $PG_COPY_SCRIPT
IMPORT='NO'
IMPORT_PAYMENT='NO'
IMPORT_ITEM='NO'
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
     # reg_no=`awk -F'№ ' '/РЕЕСТР ПЛАТЕЖЕЙ В ООО "АРКОМ". №/ {print $2}' $txt`
     reg_date=`awk -F': ' '/Дата платежей:/ {print $2}' $txt`
IFS=. read loc_day loc_mon loc_year <<EODATE
${reg_date}
EODATE
     PAY_DT=${loc_year}-${loc_mon}-${loc_day}
     csv_name=$PAY_DT-`namename $txt`
     PG_CSV=$CSV_DATA/$csv_name.csv
     #grep 'kipspb.ru' $txt |sed -e 's/; /;/g' -e "s/$/$reg_date;/" > $PG_CSV
     awk '/kipspb\.ru/ {N=split($0,arr,";"); for (i=1;i<=9;i++) printf "%s;", arr[i]; print ";"}' $txt |sed -e 's/; /;/g' -e "s/$/$reg_date;/" > $PG_CSV
     mv $txt $CSV_DATA/$PAY_DT-`namename $txt`

     echo "\COPY yamregister FROM '"$PG_CSV"' WITH ( FORMAT CSV, HEADER false, DELIMITER ';') ;" >> $PG_COPY_SCRIPT
     IMPORT='YES'
  elif $(grep -q 'Извещение №' $txt)
  then
     IMPORT_PAYMENT=$CSV_DATA/${DT}-yampayments.csv
     IMPORT_ITEM=$CSV_DATA/${DT}-yam_item.csv
     $CSV_DIR/bin/yampayment-parser.py --yampayment_txt $txt --yampayment_csv $IMPORT_PAYMENT --yam_item_csv $IMPORT_ITEM

     THIS_PAY_DT=`date +%F_%H_%M_%S`
     mv $txt $CSV_ARCH/$THIS_PAY_DT-`namename $txt`
  else
     arch_name=$DT-`namename $txt`
     logmsg INFO "The registry $txt does not contain data row. Skip it, just archive as $arch_name"
     #echo '====================================='
     #cat $txt
     #echo '====================================='
     $DO mv $txt $CSV_ARCH/$arch_name
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
      ORDERS_SET=`awk -F ";" '$2 ~ / #[0-9]+/ {split($2, arr, "#"); s=s arr[2]","}END{gsub(/\"/, "", s); printf "%s", substr(s, 1, length(s)-1) }' $PG_CSV` 
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
      fi # ORDER_SET

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


#5. Import payment into PG
# use ~/.pgpass
if [ $IMPORT_PAYMENT != 'NO' ] # csv filename
then
   logmsg INFO "Import payments from $IMPORT_PAYMENT into $PG_SRV"
   cat $IMPORT_PAYMENT
   echo ""
   # psql -h vm-pg-devel -U arc_energo -c '\COPY yampayment FROM ''/smb/system/Scripts/yamregister/devel/01-data/2017-05-31_18_14_58-yampayments.csv'' WITH (FORMAT CSV, DELIMITER ";", HEADER false);'
   $DO psql -h $PG_SRV -U arc_energo -d arc_energo -c '\COPY yampayment FROM '$IMPORT_PAYMENT' WITH (FORMAT CSV, DELIMITER "^", HEADER false);'
   $DO mv $IMPORT_PAYMENT $CSV_ARCH/
fi

#6. Import items into PG
# use ~/.pgpass
if [ $IMPORT_ITEM != 'NO' ] # csv filename
then
   logmsg INFO "Import items from $IMPORT_ITEM into $PG_SRV"
   cat $IMPORT_ITEM
   echo ""
   $DO psql -h $PG_SRV -U arc_energo -d arc_energo -c '\COPY yam_item(yam_id, item_name, item_qnt, item_price) FROM '$IMPORT_ITEM' WITH (FORMAT CSV, DELIMITER "^", HEADER false);'
   $DO mv $IMPORT_ITEM $CSV_ARCH/
fi

/usr/sbin/logrotate --state get-yam-daily-registry.state get-yam-daily-registry.conf
cat $LOG >> $LOG_DIR/get-yam-daily-registry.log

popd

