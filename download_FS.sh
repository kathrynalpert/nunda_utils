#!/bin/bash


usage()
{
cat << EOF

This script downloads FreeSurfer files from NUNDA.

USAGE: 
$0 [OPTIONS] [-d output directory] [-i projecct ID on NUNDA]

OPTIONS:
-q    download quickcheck images (will be collected in a subdirectory of the output directory called quickcheck)
-x    overwrite directories if they exist already (default is to skip the session if a directory by that name already exists)
[-s session label(s)]  If you don't specify a session label, all sessions will be downloaded (comma- or space- separated if multiple, if you use spaces, be sure to quote your argument e.g., -s "sub1 sub2 sub3")
[-u username]       If you don't enter username and password as arguments to the script, you will be prompted to enter them interactively.
[-p password]       If you don't enter username and password as arguments to the script, you will be prompted to enter them interactively.
[-t target]         This parameter should be an input string that is found in the FS assessor IDs you wish to download.  It is useful if you have multiple FS assessors for a given session (for example, if you ran your sessions with 2 different versions of FS and only want v5.3.0 data, you could use -t 'FS_v5-3-0') 

NOTE:
If you don't enter username and password as arguments to the script, you will be prompted to enter them interactively.
If you don't specify a session label, all sessions will be downloaded

EXAMPLES:
$0 -d `pwd`/from_NUNDA -i CHEM -s CH001B
$0 -d from_NUNDA -i CHEM -s CH001B -t 'FS_v5-3-0' -q
$0 -d from_NUNDA -i CHEM -u some_user -p users_passwd -x

To see this message, enter $0 -h 

EOF
}

overwrite=0
target=
quickcheck=0
while getopts d:u:p:i:s:t:xqh opt
do
  case "$opt" in
    p)  pass="$OPTARG";;
    u)  uname="$OPTARG";;
    d)  base="$OPTARG";;
    i)  projectid="$OPTARG";;
    s)  sessions="$OPTARG";;
    x)  overwrite=1;;
    q)  quickcheck=1;;
    t)  target="$OPTARG";;
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
mkdir -p $base/NUNDA_metadata
if [[ $quickcheck -eq 1 ]]; then
  mkdir -p $base/quickcheck
fi

login(){
jses=`curl -u $uname:$pass -X POST $host/data/JSESSION`
}
login

echo -e "\nRetrieving all sessions for project $projectid...\n"
sessionfile=$base/NUNDA_metadata/mrsessions_`date +\%Y\%m\%d`.csv
curl --cookie JSESSIONID=$jses -X GET "$host/data/archive/projects/$projectid/experiments?xsiType=xnat:mrSessionData&format=csv" | tr -d '[:blank:]' | tr -d \" > $sessionfile 2>/dev/null

fsfile=$base/NUNDA_metadata/fsdata_`date +\%Y\%m\%d`.csv
curl --cookie JSESSIONID=$jses -X GET "$host/data/archive/projects/$projectid/experiments?xsiType=fs:fsData&format=csv" | tr -d '[:blank:]' | tr -d \" > $fsfile 2>/dev/null

tmp=`wc -l $sessionfile | awk '{print $1}'`
if [[ $tmp -lt 2 ]]; then
  echo "The curl command is failing, please make sure you entered a valid projectid ($projectid) and that your username and password are correct. You can try running \"cat $sessionfile\" to debug."
  exit 1
fi
echo -e "Done.\n"

for each in `sed 1d < $sessionfile`; do
  id=`echo $each | awk -F ',' '{print $1}'`
  label=`echo $each | awk -F ',' '{print $6}'`

  if [[ -n $sessions ]] && [[ -z $(echo $sessions | tr ' ' ',' | tr ',' '\n' | egrep ^$label$) ]]; then continue; fi

  #check for data locally (skip if already downloaded)
  if [[ -d $base/$label && $overwrite -eq 0 ]]; then
    echo -e "$label directory exists, assuming data downloaded previously.\n"
    continue
  fi

  #check for FS data on NUNDA
  if [[ -n $target ]]; then
    fsid=`awk -F',' -v id=$id -v targ=$target '$1 ~ id && $1 ~ targ {print $1}' $fsfile`
  else
    fsid=`awk -F',' -v id=$id '$1 ~ id {print $1}' $fsfile`
  fi
  if [[ -z $fsid ]]; then
    echo -ne "No FS data" 
    if [[ -n $target ]]; then
      echo -ne " matching $target"
    fi
    echo -e " for $label (ID=$id) on NUNDA.\n"
    continue
  fi
  if [[ `echo $fsid | tr -d [:space:]` != $fsid ]]; then 
    echo "More than one matching FS ID for $label: $fsid"
    echo "You may wish to add an argument to -t"
    continue
  fi

  #download FS from NUNDA
  echo -e "Downloading FS directories ($fsid) for $label:\n"
  mkdir -p $base/$label
  pushd $base/$label > /dev/null
  curl --cookie JSESSIONID=$jses -X GET "$host/data/experiments/$id/assessors/$fsid/resources/DATA/files?format=zip" > fs.zip
  zip -T fs.zip
  if [[ $? -ne 0 ]]; then
      login
      curl --cookie JSESSIONID=$jses -X GET "$host/data/experiments/$id/assessors/$fsid/resources/DATA/files?format=zip" > fs.zip
      zip -T fs.zip
      if [[ $? -ne 0 ]]; then
          echo "Issue downloading $fsid"
      fi
  fi
  echo -e "Done.\n"

  unzip fs.zip
  mv $fsid/out/resources/DATA/files/* .
  if [[ ! -e mri/orig.mgz ]]; then
    mv $fsid/resources/DATA/files/* .
  fi
  if [[ ! -e mri/orig.mgz ]]; then
    echo "The curl command is failing for $label. You can try running \"cat $base/$label/fs.zip\" to debug."
    exit 1
  else
    rm -rf $fsid
    rm fs.zip
    echo -e "Done.\n"
    echo -e "Finished downloading FS directories ($fsid) for $label.\n"
  fi
  popd > /dev/null
  if [[ $quickcheck -eq 1 ]]; then
    echo "Downloading quickcheck images"
    curl --cookie JSESSIONID=$jses -X GET "$host/data/experiments/$id/assessors/$fsid/resources/SNAPSHOTS/files?format=zip" > qc.zip
    unzip qc.zip -d $base/quickcheck
    rm -f qc.zip
    echo -e "Done.\n"
  fi
done

