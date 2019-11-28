#!/bin/bash -xe

OLD=$1
NEW=$2

echo $OLD $NEW

#sed -e 's/'$OLD'/'$NEW'/g' ../json_parameters_aws/*
#echo "continue?"
#read
sed -i 's/'$OLD'/'$NEW'/g' ../json_parameters_aws/*
