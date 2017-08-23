#!/bin/bash


usage()
{
cat << EOF

This script downloads reconstruction files from NUNDA.

USAGE: 
$0 [OPTIONS] [-d output directory] [-i projecct ID on NUNDA] [-r recon base string, which is the name of the reconstruction without the session id (e.g., RobustfMRI)]

OPTIONS:
-x    overwrite directories if they exist already (default is to skip the session if a directory by that name already exists)
[-s session label(s)]  If you don't specify a session label, all sessions will be downloaded (comma- or space- separated if multiple, if you use spaces, be sure to quote your argument e.g., -s "sub1 sub2 sub3")
[-u username]       If you don't enter username and password as arguments to the script, you will be prompted to enter them interactively.
[-p password]       If you don't enter username and password as arguments to the script, you will be prompted to enter them interactively.
[-t target string]  String to look for in the resource name within the reconstruction (e.g., fmri). If you wish to select multiple, use a space-separated list (be sure to quote your argument e.g., -t "smri fmri")

NOTE:
If you don't enter username and password as arguments to the script, you will be prompted to enter them interactively.
If you don't specify a session label, all sessions will be downloaded

EXAMPLES:
$0 -d my_project -i my_project_id -u some_user -p users_passwd -r ASL -x 
$0 -d my_project -i my_project_id -u some_user -p users_passwd -r RobustfMRI -t smri  
$0 -d my_project -i my_project_id -u some_user -p users_passwd -r RobustfMRI -t "VBM test"  
$0 -d my_project -i my_project_id -u some_user -p users_passwd -r ASL -s 001,002,003 

To see this message, enter $0 -h 

EOF
}

overwrite=0
while getopts d:u:p:i:r:s:t:xh opt
do
  case "$opt" in
    p)  pass="$OPTARG";;
    u)  uname="$OPTARG";;
    d)  base="$OPTARG";;
    i)  projectid="$OPTARG";;
    s)  sessions="$OPTARG";;
    x)  overwrite=1;;
    r)  recon="$OPTARG";;
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
  echo -e "\nPlease specify a NUNDA project ID to the -i flag.\n"
  exit 1
fi

if [[ -z $recon ]]; then
  usage
  echo -e "\nPlease specify a reconstruction base string to the -r flag.\n"
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

login(){
    jses=`curl -u $uname:$pass -X POST $host/data/JSESSION 2> /dev/null`
}
login

echo -e "\nRetrieving all sessions for project $projectid...\n"
sessionfile=$base/NUNDA_metadata/mrsessions_`date +\%Y\%m\%d`.csv
curl --cookie JSESSIONID=$jses -X GET "$host/data/projects/$projectid/experiments?xsiType=xnat:mrSessionData&format=csv" | tr -d '[:blank:]' | tr -d \" > $sessionfile 2>/dev/null

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
  if [[ -d $base/$label/${recon}_$id && $overwrite -eq 0 ]]; then
    echo -e "$label/${recon}_$id directory exists, assuming data downloaded previously.\n"
    continue
  fi

  if [[ -z $target ]]; then
    #check for recon data on NUNDA
    nfile=`curl --cookie JSESSIONID=$jses -X GET "$host/data/experiments/$id/reconstructions/${recon}_$id/files?format=csv" 2>/dev/null | wc -l`
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
      login
      nfile=`curl --cookie JSESSIONID=$jses -X GET "$host/data/experiments/$id/reconstructions/${recon}_$id/files?format=csv" 2>/dev/null | wc -l`
      if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
          echo "Issue gathering reconstruction info for $label"
      fi
    fi
    if [[ $nfile -le 1 ]]; then
        echo -e "No $recon data for $label (ID=$id) on NUNDA.\n"
        continue
    fi
    #download reconstruction from NUNDA
    echo -e "Downloading reconstruction (${recon}_$id) for $label:\n"
    mkdir -p $base/$label
    pushd $base/$label > /dev/null
    curl --cookie JSESSIONID=$jses -X GET "$host/data/experiments/$id/reconstructions/${recon}_$id/files?format=zip&structure=legacy" > recon.zip
    zip -T recon.zip
    if [[ $? -ne 0 ]]; then
      login
      curl --cookie JSESSIONID=$jses -X GET "$host/data/experiments/$id/reconstructions/${recon}_$id/files?format=zip&structure=legacy" > recon.zip
      zip -T recon.zip
      if [[ $? -ne 0 ]]; then
          echo "Issue downloading ${recon}_$id"
      fi
    fi
    echo -e "Done.\n"
    unzip recon.zip
    if [[ $? -ne 0 ]]; then
        echo "The curl command is failing for $label. You can try running \"cat $base/$label/$recon/recon.zip\" to debug."
        exit 1
    else
        rm recon.zip
        echo -e "Done.\n"
        echo -e "Finished downloading reconstruction directories (${recon}_$id) for $label.\n"
    fi
    popd > /dev/null
  else
    curl --cookie JSESSIONID=$jses -X GET "$host/data/experiments/$id/reconstructions/${recon}_$id/resources?format=csv" 2>/dev/null | tr -d '[:blank:]' | tr -d \" > $base/NUNDA_metadata/tmp.csv
    resources=()
    for t in $target; do
        resources=( ${resources[@]} `awk -F',' -v targ=$t '$2 ~ targ {print $2}' $base/NUNDA_metadata/tmp.csv` )
    done
    rm -f $base/NUNDA_metadata/tmp.csv
    if [[ ${#resources[@]} -eq 0 ]]; then
        echo -e "No resource within ${recon}_$id matching $target (label=$label)\n" 
        continue
    fi
    #download reconstruction from NUNDA
    for res in ${resources[@]}; do
        echo -e "Downloading reconstruction (${recon}_$id/$res) for $label:\n"
        mkdir -p $base/$label
        pushd $base/$label > /dev/null
        curl --cookie JSESSIONID=$jses -X GET "$host/data/experiments/$id/reconstructions/${recon}_$id/resources/$res/files?format=zip&structure=legacy" > recon.zip
        zip -T recon.zip
        if [[ $? -ne 0 ]]; then
            login
            curl --cookie JSESSIONID=$jses -X GET "$host/data/experiments/$id/reconstructions/${recon}_$id/resources/$res/files?format=zip&structure=legacy" > recon.zip
            zip -T recon.zip
            if [[ $? -ne 0 ]]; then
                echo "Issue downloading ${recon}_$id/$res"
            fi
        fi
        unzip recon.zip
        if [[ $? -ne 0 ]]; then
            echo "The curl command is failing for $label. You can try running \"cat $base/$label/$recon/recon.zip\" to debug."
            exit 1
        else
            rm recon.zip
            echo -e "Done.\n"
            echo -e "Finished downloading reconstruction directory (${recon}_$id/$res) for $label.\n"
        fi
        popd > /dev/null
    done
    echo -e "Done.\n"
  fi
done
