#!/bin/sh

. /usr/local/bin/bashlib

DT=$(date +%F_%H_%M_%S)
#############
#DO=echo
DO=''
#############

[ +$1 = +fetch ] && DO_FETCH='YES' || DO_FETCH='NO'

#1. received email are processed by procmail and ripmime
# result is the csv file in directory specified with .procmailrc 
# i.e.  ripmime -i - -d /path/to/mailbox 
PDF_DIR=$(grep cutpdf ~/.procmailrc | awk -F '-d' '{print $2}' | awk '{print $1}')
[ +$PDF_DIR = + ] && { echo PDF_DIR unassigned, exiting; exit 123; }
LOG_DIR=$PDF_DIR/logs
CSV_DATA=$PDF_DIR/01-data
CSV_ARCH=$PDF_DIR/99-archive
ARCHIVE_DEPTH=10

[ -d $PDF_DIR ] || mkdir -p $PDF_DIR
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
    #$DO fetchmail -f $PDF_DIR/.fetchmailrc -ak -m "/usr/bin/procmail -d %T"
    $DO fetchmail -f $PDF_DIR/.fetchmailrc -k -m "/usr/bin/procmail -d %T"

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

    find $PDF_DIR -type f -name 'smime*.p7s' -delete
    find $PDF_DIR -type f -name 'yamregister*' -size 0c -delete

    # clean logs without mail
    grep -l 'There was no mail' $LOG_DIR/* |xargs --no-run-if-empty rm
    
    if [ $exit_rc -ne 1 ]
    then
       exit $exit_rc
    fi
fi # DO_FETCH

PG_COPY_SCRIPT=$CSV_DATA/pg-COPY-registry-$DT.sql

pushd $PDF_DIR

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
  if 1 
  then
     arch_name=$DT-`namename $txt`
     logmsg INFO "The registry $txt does not contain data row. Skip it, just archive as $arch_name"
     #echo '====================================='
     #cat $txt
     #echo '====================================='
     $DO mv $txt $CSV_ARCH/$arch_name
  fi
done
IFS=$IFS_BCK



/usr/sbin/logrotate --state get-yam-daily-registry.state get-yam-daily-registry.conf
cat $LOG >> $LOG_DIR/get-yam-daily-registry.log

popd

