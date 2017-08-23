#!/bin/bash


usage()
{
cat << EOF

This script downloads a single reconstruction file from a given reconstruction for each session in a NUNDA project.

USAGE: 
$0 [OPTIONS] [-d output directory] [-i projecct ID on NUNDA] [-r recon base string, which is the name of the reconstruction without the session id (e.g., RobustfMRI)] [-f full filename]

OPTIONS:
[-s session label(s)]  If you don't specify a session label, all sessions will be downloaded (comma- or space- separated if multiple, if you use spaces, be sure to quote your argument e.g., -s "sub1 sub2 sub3")
[-u username]       If you don't enter username and password as arguments to the script, you will be prompted to enter them interactively.
[-p password]       If you don't enter username and password as arguments to the script, you will be prompted to enter them interactively.

NOTE:
If you don't enter username and password as arguments to the script, you will be prompted to enter them interactively.
If you don't specify a session label, all sessions will be downloaded

EXAMPLES:
$0 -d my_project -i my_project_id -u some_user -p users_passwd -r QA_EPI_Human -f fd.txt

To see this message, enter $0 -h 

EOF
}

while getopts d:u:p:i:r:s:f:h opt
do
  case "$opt" in
    p)  pass="$OPTARG";;
    u)  uname="$OPTARG";;
    d)  base="$OPTARG";;
    i)  projectid="$OPTARG";;
    s)  sessions="$OPTARG";;
    r)  recon="$OPTARG";;
    f)  filen="$OPTARG";;
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
  echo -e "\nPlease specify a NUNDA project ID to the -i flag.\n"
  exit 1
fi

if [[ -z $recon ]]; then
  usage
  echo -e "\nPlease specify a reconstruction base string to the -r flag.\n"
  exit 1
fi

if [[ -z $filen ]]; then
  usage
  echo -e "\nPlease specify a filename to the -f flag.\n"
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
metadata=$base/NUNDA_metadata
cd $base
mkdir -p $metadata

login(){
jses=`curl -u $uname:$pass -X POST $host/data/JSESSION 2> /dev/null`
}
login

echo -ne "\nRetrieving all sessions for project $projectid..."
sessionfile=$metadata/mrsessions_`date +\%Y\%m\%d`.csv
curl --cookie JSESSIONID=$jses -X GET "$host/data/projects/$projectid/experiments?xsiType=xnat:mrSessionData&format=csv" 2>/dev/null | tr -d '[:blank:]' | tr -d \" > $sessionfile 2>/dev/null

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

    #check for recon data on NUNDA
    curl --cookie JSESSIONID=$jses -X GET "$host/data/experiments/$id/reconstructions/${recon}_$id/files?format=csv" 2>/dev/null | awk -F',' -v filen=$filen '$1 ~ filen {print}'> $metadata/$id.files.txt
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        login
        curl --cookie JSESSIONID=$jses -X GET "$host/data/experiments/$id/reconstructions/${recon}_$id/files?format=csv" 2>/dev/null | awk -F',' -v filen=$filen '$1 ~ filen {print}' > $metadata/$id.files.txt
        if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
            echo "Issue gathering reconstruction info for $label"
            continue
        fi
    fi
    if [[ `cat $metadata/$id.files.txt | wc -l` -eq 0 ]]; then
        echo -e "No $filen files in $recon recon for $label (ID=$id) on NUNDA.\n"
        continue
    fi
    old_IFS=$IFS
    IFS=$'\n'
    for line in `cat $metadata/$id.files.txt`; do
        ffull=`echo $line | awk -F',' '{print $1}'`
        uri=`echo $line | awk -F',' '{print $3}'`
        res=`echo $line | awk -F',' '{print $4}'`
        mkdir -p $base/$label/${recon}_$id/$res
        echo -n Downloading $label/${recon}_$id/$res/$ffull...
        curl --cookie JSESSIONID=$jses -X GET "$host$uri" 2>/dev/null > $base/$label/${recon}_$id/$res/$ffull
        if [[ $? -ne 0 ]]; then
            login
            curl --cookie JSESSIONID=$jses -X GET "$host$uri" 2>/dev/null > $base/$label/${recon}_$id/$res/$ffull
            if [[ $? -ne 0 ]]; then
                echo "The curl command is failing for ${recon}_$id/$res/$ffull. You can try running \"cat $base/$label/${recon}_$id/$res/$ffull\" to debug."
                continue
            fi
        fi
        echo -e "Done\n"
    done
    IFS=$old_IFS
    rm -f  $metadata/$id.files.txt
done
curl --cookie JSESSIONID=$jses -X DELETE "$host/data/JSESSION 2>/dev/null"
