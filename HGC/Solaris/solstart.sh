#!/bin/bash
#
# Copyright 2013-2020 Illumio, Inc. All Rights Reserved.
#
# Created by: Siew Boon Siong
# Email: boon.siew@illumioeval.com
# Updated: Mar-02-2020
# Version: 1.0
#
# This is the main script for starting the automation.
# Require "sshpass" and "expect" to be installed in the server that running this scripts.
# Tested in Red Hat 7

# Usage bash main.ssh <ssh user> <ssh password> <su password>
# eg. bash main.sh illumio illumio1 Illumio1

txtred=$(tput setaf 1)
txtgreen=$(tput setaf 2)
txtrst=$(tput sgr0)

helpFunction() {
    echo ""
    echo "Usage: bash $0 <ssh user> <ssh password> <su password>"
    exit 1 # Exit script after printing help
}

# Print helpFunction in case parameters are empty
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Some or all of the parameters are empty"
    helpFunction
fi

solservers="solservers.lst"

script=$(grep exarg1 config | cut -d$'"' -f2)
rootcert=$(grep exarg3 config | cut -d$'"' -f2)
agentfile=$(grep exarg2 config | cut -d$'"' -f2)
expectscript=$(grep exarg4 config | cut -d$'"' -f2)
sollog='sol_result'
soltmp='sol_tmp'
fail=0
touch ${sollog}
touch ${soltmp}

echo -e "Please wait..."
for ip in $(cat ${solservers}); do
    rm -rf ${soltmp}
    sshpass -p $2 scp -o StrictHostKeyChecking=no -o ConnectTimeout=5 ${rootcert} ${script} illumio-ven*s5*tgz $1@${ip}:/tmp 2>/dev/null
    exitA=$?
    if [[ "${exitA}" == '5' ]]; then
        echo -e "$ip : ${txtred}Access permission denied${txtrst}" | tee -a ${sollog}
        let fail++
    elif [[ "${exitA}" == '0' ]]; then
        expect ${expectscript} ${ip} $1 $2 root $3 &>${soltmp}
    else
        echo -e "$ip : ${txtred}Connection timed out or no route to host${txtrst}" | tee -a ${sollog}
        let fail++
    fi

    if [[ "${fail}" != 0 ]]; then
        fail=0
    else
        status1=$(grep agent_id ${soltmp} | head -n 2 | cut -d$' ' -f2)
        status2=$(grep -E "successfully with|already paired" ${soltmp})
        status3=$(grep ERROR ${soltmp} | grep aborting)
        if [[ "${status1}" == "cannot" ]]; then
            echo -e "$ip : ${txtred}Pairing failed${txtrst}, check logs" | tee -a ${sollog}
            sshpass -p $2 scp -o StrictHostKeyChecking=no $1@${ip}:/tmp/*_illumioreport.gz . 2>/dev/null
            exitB=$?
            if [[ "${exitB}" == '0' ]]; then
                echo -e "$ip : ${txtgreen}Installation logs copied${txtrst}" | tee -a ${sollog}
            else
                echo -e "$ip : ${txtgreen}Unable to copy the logs over${txtrst}" | tee -a ${sollog}
            fi
        elif [[ ! -z "${status2}" ]]; then
            echo -e "$ip : Pairing OK." | tee -a ${sollog}
        elif [[ ! -z "${status3}" ]]; then
            echo -e "$ip : ${txtred}Installation Aborted${txtrst}, check logs" | tee -a ${sollog}
            sshpass -p $2 scp -o StrictHostKeyChecking=no $1@${ip}:/tmp/*_illumioreport.gz . 2>/dev/null
            exitB=$?
            if [[ "${exitB}" == '0' ]]; then
                echo -e "$ip : ${txtgreen}Installation logs copied${txtrst}" | tee -a ${sollog}
            else
                echo -e "$ip : ${txtgreen}Unable to copy the logs over${txtrst}" | tee -a ${sollog}
            fi
        else
            echo -e "$ip : ${txtred}Other errors, check logs.${txtrst}" | tee -a ${sollog}
            sshpass -p $2 scp -o StrictHostKeyChecking=no $1@${ip}:/tmp/*_illumioreport.gz . 2>/dev/null
            exitB=$?
            if [[ "${exitB}" == '0' ]]; then
                echo -e "$ip : ${txtgreen}Installation logs copied${txtrst}" | tee -a ${sollog}
            else
                echo -e "$ip : ${txtgreen}Unable to copy the logs over${txtrst}" | tee -a ${sollog}
            fi
        fi
    fi
done

exit 0
