#!/bin/sh

#ORG=Накладные_СД148497_СД148498_СД148499_СД148500_СД148501_СД148502_СД148503_СД148504_СД148505_СД148506_СД148507_СД148508_СД148509_СД148510_.pdf
ORG=$1

#ECHO=echo
#ECHO=''

DOC_LIST=$(pdfgrep -n 'Счет-фактура №' $ORG)

IFS_BAK=$IFS
IFS=$'\n'
ix=0
for doc in $DOC_LIST
do
    doc=$(echo $doc |sed 's^[ :\/]^_^g')
    echo $doc
    IFS='_' read -r -a arr1 <<< "$doc"
    arr_doc[$ix]=${arr1[0]}_${arr1[4]}
    let ix=$ix+1
    echo 'Total: '${#arr_doc[*]}
    #IFS='\n'
done
IFS=$IFS_BAK


for ind in "${!arr_doc[@]}"
do
    echo [$ind]: "${arr_doc[$ind]}"
    IFS='_' read -r -a arr_this <<< ${arr_doc[$ind]}
    IFS='_' read -r -a arr_next <<< ${arr_doc[$ind+1]}
    # arr_this[0] - start page
    # arr_this[1] - docN
    last_page=$((${arr_next[0]}-1))
    [ _$last_page == _-1 ] && last_page=end
    echo ---[$ind]: "${arr_doc[$ind]}"
    $ECHO pdftk $ORG cat ${arr_this[0]}-$last_page output 'СД'${arr_this[1]}.pdf
done

