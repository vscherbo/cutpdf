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
PDF_DATA=$PDF_DIR/01-data
PDF_ARCH=$PDF_DIR/99-archive
ARCHIVE_DEPTH=10

[ $HOSTNAME = scherbova ] && FETCH_DIR=$HOME || FETCH_DIR=$PDF_DIR


[ -d $PDF_DIR ] || mkdir -p $PDF_DIR
[ -d $LOG_DIR ] || mkdir -p $LOG_DIR
[ -d $PDF_DATA ] || mkdir -p $PDF_DATA
[ -d $PDF_ARCH ] || mkdir -p $PDF_ARCH

find $PDF_ARCH -type f -mtime +$ARCHIVE_DEPTH -delete # -exec rm -f {} \+
find $LOG_DIR -type f -mtime +$ARCHIVE_DEPTH -delete # -exec rm -f {} \+

LOG=$LOG_DIR/$DT-`namename $0`.log
exec 1>>$LOG 2>&1


if [ $DO_FETCH = 'YES' ]
then
    #1. get email with register in the body - after 05:00
    #
    #$DO fetchmail -f $PDF_DIR/.fetchmailrc -ak -m "/usr/bin/procmail -d %T"
    $DO fetchmail -f $FETCH_DIR/.fetchmailrc -k -m "/usr/bin/procmail -d %T"

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
    find $PDF_DIR -type f -name 'cutpdf*' -size 0c -delete

    # clean logs without mail
    grep -l 'There was no mail' $LOG_DIR/* |xargs --no-run-if-empty rm
    
    if [ $exit_rc -ne 1 ]
    then
       exit $exit_rc
    fi
fi # DO_FETCH

pushd $PDF_DIR

./loop-doc.sh



/usr/sbin/logrotate --state cutpdf.state cutpdf.conf
cat $LOG >> $LOG_DIR/cutpdf.log

popd

