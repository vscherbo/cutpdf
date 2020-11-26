#!/bin/sh

for doc in $(ls -1 Накл*pdf)
do
    sh ./cut-pdf.sh $doc
done
