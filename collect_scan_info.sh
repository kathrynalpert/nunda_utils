#!/bin/bash

usage()
{
cat << EOF

This script collects scan-level info (ScanType, SeriesDescription, Quality, Frames) into a csv for a NUNDA project

USAGE: 
$0 [OPTIONS] [-d output directory] [-i projecct ID on NUNDA] 

OPTIONS:
[-s session labels comma separated] 
[-u username]       If you don't enter username and password as arguments to the script, you will be prompted to enter them interactively.
[-p password]       If you don't enter username and password as arguments to the script, you will be prompted to enter them interactively.

NOTE:
If you don't enter username and password as arguments to the script, you will be prompted to enter them interactively.

To see this message, enter $0 -h 

EOF
}

while getopts d:u:p:i:s:h opt
do
  case "$opt" in
    p)  pass="$OPTARG";;
    u)  uname="$OPTARG";;
    d)  base="$OPTARG";;
    i)  projectid="$OPTARG";;
    s)  sessions="$OPTARG";;
    h)  usage
        exit;;
    ?)  # Unknown flag
        usage
        exit 1;;
  esac
done

shift `expr $OPTIND - 1`

if [[ $OPTIND -le 1 ]]; then #no arguments
  usage
  exit 1
fi

if [[ -z $base ]]; then
  usage
  echo -e "\nPlease specify an output directory to -d flag.\n"
  exit 1
fi

if [[ -z $projectid ]]; then
  usage
  echo -e "\nPlease specify a NUNDA project ID to the -p flag.\n"
  exit 1
fi

#make base dir
mkdir -p $base
if [[ ! -d $base ]]; then
  echo -e "\nCannot create output directory $base. Please specify a valid output directory to -d flag."
  exit 1
fi

#make sure base dir has full path
if [[ ${base:0:1} != "/" ]]; then
  base=`pwd`/$base
fi

#get username and password if not given in argument list
if [[ -z $uname ]]; then
  echo -n "NUNDA Username: "
  read uname
fi
if [[ -z $pass ]]; then
  stty_orig=`stty -g`
  stty -echo
  echo -n "NUNDA Password: "
  read pass
  stty $stty_orig
fi

host=https://nunda.northwestern.edu/nunda
cd $base
finalfile=${projectid}_target_scans.csv
sesfile=${projectid}_sessions.csv
rm -f $sesfile $finalfile
echo "Subject,Group,Session,ID,Date,ScanID,ScanType,SeriesDescription,Quality,Frames" > $finalfile

login(){
jsessionid=`curl -u $uname:$pass -X POST $host/data/JSESSION`
}
login
curl --cookie JSESSIONID=$jsessionid  "$host/data/archive/projects/$projectid/experiments?xsiType=xnat:mrSessionData&format=csv&columns=ID,label,xnat:subjectData/label,xnat:subjectData/group" -X GET | tr -d \" > $sesfile

sed '1d' < $sesfile | while read line; do
    #collect T1 and nback info for all sessions with those types
    id=`echo $line | awk -F ',' '{print $1}'`
    label=`echo $line | awk -F ',' '{print $6}'`
    subject=`echo $line | awk -F ',' '{print $3}'`
    dx=`echo $line | awk -F ',' '{print $4}'`
    echo checking $subject - $id $label 
    curl --cookie JSESSIONID=$jsessionid "$host/data/archive/experiments/$id/scans?columns=ID,xnat:mrSessionData/date,xnat:mrScanData/ID,xnat:mrScanData/type,xnat:mrScanData/series_description,xnat:mrScanData/quality,xnat:mrScanData/frames&format=csv" 2>/dev/null | awk -F',' -v subj=$subject -v ses=$label -v id=$id -v dx="$dx" 'NR>1 {print subj "," dx "," ses "," id "," $7 "," $2 "," $3 "," $4 "," $5 "," $6}' | tr -d '[:blank:]' >> $finalfile
done

echo output in is $base/$finalfile
rm -f $sesfile
curl --cookie JSESSIONID=$jsessionid -X DELETE $host/data/JSESSION
