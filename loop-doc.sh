#!/bin/sh

for doc in $(ls -1 ___*pdf)
do
    sh ./cut-pdf.sh $doc
done
