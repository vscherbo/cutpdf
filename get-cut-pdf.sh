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
PDF_DIR=$(grep cutpdf ~/.procmailrc |egrep -v '^#' | awk -F '-d' '{print $2}' | awk '{print $1}')
[ +$PDF_DIR = + ] && { echo PDF_DIR unassigned, exiting; exit 123; }
LOG_DIR=$PDF_DIR/logs
PDF_DATA=$PDF_DIR/01-data
PDF_FAILED=$PDF_DIR/98-failed
PDF_ARCH=$PDF_DIR/99-archive
ARCHIVE_DEPTH=10

[ $HOSTNAME = scherbova ] && FETCH_DIR=$HOME || FETCH_DIR=$PDF_DIR


[ -d $PDF_DIR ] || mkdir -p $PDF_DIR
[ -d $LOG_DIR ] || mkdir -p $LOG_DIR
[ -d $PDF_DATA ] || mkdir -p $PDF_DATA
[ -d $PDF_FAILED ] || mkdir -p $PDF_FAILED
[ -d $PDF_ARCH ] || mkdir -p $PDF_ARCH

find $PDF_ARCH -type f -mtime +$ARCHIVE_DEPTH -delete # -exec rm -f {} \+
find $LOG_DIR -type f -mtime +$ARCHIVE_DEPTH -delete # -exec rm -f {} \+

SCRIPT_NAME=$(namename $0)
LOG=$LOG_DIR/$DT-$SCRIPT_NAME.log
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
    #find $PDF_DIR -type f -name 'cutpdf*' -size 0c -delete
    find $PDF_DIR -type f -name 'cutpdf*' -delete

    # clean logs without mail
    grep -l 'There was no mail' $LOG_DIR/* |xargs --no-run-if-empty rm
    
    if [ $exit_rc -ne 1 ]
    then
       logmsg INFO 'Nothing to do. Exiting.'
       exit $exit_rc
    fi
fi # DO_FETCH

pushd $PDF_DIR

PDF_TO=blazhevskaya@kipspb.ru
#PDF_TO=blazhevskaya@kipspb.ru,vscherbo@kipspb.ru
#PDF_TO=vscherbo@kipspb.ru

for doc in $(ls -1 Накладн*)
do
    good_name=${doc%_*}
    mv $doc $good_name
    doc=$good_name
    PDF_NAME=$(namename $doc)
    CUT_DIR=cut-$PDF_NAME
    [ -d $CUT_DIR ] || mkdir $CUT_DIR
    pushd $CUT_DIR
    sh $PDF_DIR/cut-pdf.sh ../$doc
    unset ATTACH
    for pdf in $(ls -1 *.pdf)
    do 
        ATTACH=${ATTACH}" -a $pdf"
    done
    mailx -s "$PDF_NAME" -r cut-pdf@kipspb.ru $ATTACH $PDF_TO < /dev/null
    mv -f *.pdf $PDF_ARCH/
    popd
    mv -f $doc $PDF_DATA/
    logmsg INFO "rmdir $CUT_DIR"
    rmdir $CUT_DIR 2>/dev/null
    if [ $? -ne 0 ]
    then
        mv $CUT_DIR $PDF_FAILED
    fi
done

/usr/sbin/logrotate --state rotate-$SCRIPT_NAME.state rotate-$SCRIPT_NAME.conf
cat $LOG >> $LOG_DIR/$SCRIPT_NAME.log

popd

