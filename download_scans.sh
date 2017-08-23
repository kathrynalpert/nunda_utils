#!/bin/bash


usage()
{
cat << EOF

This script downloads scans from NUNDA.

USAGE: 
$0 [OPTIONS] [-d output directory] [-i projecct ID on NUNDA] 

OPTIONS:
-x    overwrite directories if they exist already (default is to skip the session if a directory by that name already exists)
[-s session labels comma separated] 
[-t typename]       Only download scans of this type (must match the "type" field in NUNDA). Can enter a space-separeted list, be sure to quote it (e.g., "MPRAGE REST")
[-f format]         Only download scans in this format (default is to download everything). Choose from DICOM, NIFTI, ANALYZE  
[-u username]       If you don't enter username and password as arguments to the script, you will be prompted to enter them interactively.
[-p password]       If you don't enter username and password as arguments to the script, you will be prompted to enter them interactively.

NOTE:
If you don't enter username and password as arguments to the script, you will be prompted to enter them interactively.

To see this message, enter $0 -h 

EOF
}

overwrite=0
scantypes=ALL
while getopts d:u:p:i:s:t:f:xh opt
do
  case "$opt" in
    p)  pass="$OPTARG";;
    u)  uname="$OPTARG";;
    d)  base="$OPTARG";;
    i)  projectid="$OPTARG";;
    s)  sessions="$OPTARG";;
    t)  scantypes="$OPTARG";;
    f)  format="$OPTARG";;
    x)  overwrite=1;;
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

if [[ -n $format ]]; then
    if [[ $format != DICOM && $format != NIFTI && $format != ANALYZE ]]; then
        usage
        echo -e "\nInvalid format $format, must be DICOM, NIFTI, ANALYZE.\n"
        exit 1
    else
        format="resources/$format/"
    fi
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
mkdir -p $base/NUNDA_metadata

login(){
jses=`curl -u $uname:$pass -X POST $host/data/JSESSION`
}
login

echo -e "\nRetrieving all sessions for project $projectid...\n"
sessionfile=$base/NUNDA_metadata/mrsessions_`date +\%Y\%m\%d`.csv
curl --cookie JSESSIONID=$jses -X GET "$host/data/archive/projects/$projectid/experiments?xsiType=xnat:mrSessionData&format=csv&columns=ID,label,xnat:subjectData/label" 2>/dev/null | tr -d '[:blank:]' | tr -d \" > $sessionfile

tmp=`wc -l $sessionfile | awk '{print $1}'`
if [[ $tmp -lt 2 ]]; then
  echo "The curl command is failing, please make sure you entered a valid projectid ($projectid) and that your username and password are correct. You can try running \"cat $sessionfile\" to debug."
  exit 1
fi
echo -e "Done.\n"
if [[ -z $sessions ]]; then
    ses_list=( `awk -F',' 'NR>1 {print $5}' $sessionfile` )
else
    ses_list=( `echo $sessions | tr ',' ' '` )
fi

pushd $base > /dev/null
for label in ${ses_list[@]}; do
  each=`awk -F',' -v ses=$label '$5==ses {print}' $sessionfile`
  id=`echo $each | awk -F ',' '{print $1}'`
  #slabel=`echo $each | awk -F ',' '{print $3}'`

  #check for data locally (skip if already downloaded)
  if [[ -d $base/$label && $overwrite -eq 0 && $scantypes == "ALL" ]]; then
    echo -e "$base/$label directory exists, assuming data downloaded previously.\n"
    continue
  fi

  #download from NUNDA
  echo -e "Downloading images directories for $label:\n"
  for scantype in $scantypes; do
    zipfile=$label.$scantype.scans.zip
    curl --cookie JSESSIONID=$jses -X GET "$host/data/experiments/$id/scans/$scantype/${format}files?format=zip&structure=legacy" > $zipfile
    zip -T $zipfile
    if [[ $? -ne 0 ]]; then
        login
        curl --cookie JSESSIONID=$jses -X GET "$host/data/experiments/$id/scans/$scantype/${format}files?format=zip&structure=legacy" > $zipfile
        zip -T $zipfile
        if [[ $? -ne 0 ]]; then
            echo "Issue downloading $label $id, see `pwd`/$zipfile"
            continue
        fi
    fi
    unzip scans.zip
    if [[ $? -ne 0 ]]; then
        echo "The curl command is failing for $label (type=$scantype). You can try running \"cat $(pwd)/$zipfile\" to debug."
        exit 1
    else
        rm $zipfile
    fi
  done
  echo -e "Done.\n"
done
popd > /dev/null

