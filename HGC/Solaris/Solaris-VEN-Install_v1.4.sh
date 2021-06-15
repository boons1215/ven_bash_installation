#!/usr/bin/env bash
#
# Copyright 2013-2020 Illumio, Inc. All Rights Reserved.
#
# Script name: solaris_veninstall.sh
# Created by: Siew Boon Siong
# Email: boon.siew@illumioeval.com
# Updated: Feb-04-2020
# Version: 1.4
#
# History:
# Oct-18-2019 Added support for 11.4 X86 with packetfilter
# Oct-19-2019 Added support for 19.3
# Nov-26-2019 Added variable for VEN versions
# Jan-16-2020 Added auto cert add function
# Feb-04-2020 Regrouped, and removed DNS check functions

# Flexible variables adjust when needed
PCEFQDN='illumio.office.hgc.com.hk'
PCEIP='192.168.36.124'
ROOTCERT='HGCCA.CER'
ActivationCode='1f55928d848f7597ea2240e06b30ed9bf309e27bcddf9f05314b80d9a9adbb43c52ca23b68d6347f3'

# Solaris 11.4 supported starting from 19.3 only
VEN_VER='19.3.0-6110'

####################################################
######## DO NOT MODIFY ANYTHING BELOW ##############
####################################################
S5_SPARCPackage="illumio-ven-${VEN_VER}.s5.sparcv9.pkg.tgz"
S5_X86Package="illumio-ven-${VEN_VER}.s5.x86_64.pkg.tgz"
PCEPORT='8443'
PCEPORT2='8444'
InstallPath='/opt'
WorkingDirectory='/tmp'
LogFile='/tmp/_illumio_veninstall.log'
VENdiskUsageInMB='20'
IllumioVENctl='/opt/illumio_ven/illumio-ven-ctl'
IllumioVENdir='/opt/illumio_ven'
IllumioVENdatadir='/opt/illumio_ven_data'
IllumioActCfg='/opt/illumio_ven_data/etc/agent_activation.cfg'
Domain='illumioeval'

# Clean up when the job is completed
function TARLOGS_CLEANUP() {
    date=$(date '+%Y-%m-%d')
    cd ${WorkingDirectory} && mkdir -p job
    cp -R ${IllumioVENdir} ${IllumioVENdatadir} ${WorkingDirectory}/_illumio_*.log /var/log/illumio*log ${WorkingDirectory}/job
    tar cvf - job |gzip -c >${WorkingDirectory}/${date}_${HOSTNAME}_${OS}_illumioreport.gz
    rm -rf ${WorkingDirectory}/_illumio_*.log
    rm -rf ${WorkingDirectory}/illumio-ven*s5*.tgz
    rm -rf ${WorkingDirectory}/Solaris-VEN-Install_v1.4.sh
    rm -rf ${WorkingDirectory}/job
    rm -rf ${WorkingDirectory}/${ROOTCERT}
} &>/dev/null

# Generic statements for workload info
function WORKLOAD_INFO_STATEMENT() {
  echo "$(date) Workload Hostname: ${HOSTNAME}" | tee -a ${LogFile}
  echo "$(date) This workload is supported by VEN." | tee -a ${LogFile}
  echo "$(date) Workload OS: ${OS}"  | tee -a ${LogFile}
  echo "$(date) Workload Architecture: ${sol_based}"  | tee -a ${LogFile}
  echo "$(date) Workload Type: ${sol_type}"  | tee -a ${LogFile}
}

# Check if the OS supported. If it is not supported or out of the list, job exit.
function SOLARIS_OS_CHECK() {
    VEN_COMPARE=`echo ${VEN_VER} | cut -d$'-' -f1 | awk -F. '{print $1""$2}'`
    # The length of output of /etc/redhat-release differents in each OS , setting 2 variable and trying to catch all.
    OSrelease=NotFound
    if [[ "${OSrelease}" == 'NotFound' ]]
    then
        solRelease=/etc/release
        OSoutput=$(cat /etc/release)
        if test -f "${solRelease}"
        then
            if grep 'Solaris' ${solRelease} | grep 'Oracle'
            then
                echo "$(date) Solaris Detected." | tee -a ${LogFile}
		        OS='Solaris'
                OSrelease=`grep "Oracle Solaris" ${solRelease} | awk '{print $3"."$4}'`
                sol_type=`grep "Oracle Solaris" ${solRelease} | awk 'NF>1{print $NF}'`
            elif grep 'Solaris 10' ${solRelease} # For Solaris 10u8 only
            then
                echo "$(date) Solaris Detected." | tee -a ${LogFile}
		        OS='Solaris'
                OSrelease=`grep "Solaris" ${solRelease} | awk '{print $2"."$3}'`
                sol_type=`grep "Solaris" ${solRelease} | awk 'NF>1{print $NF}'`
            fi
        fi
    fi

    if [[ "${OS}" == 'Solaris' ]] && [[ "${OSrelease}" =~ ^(11.4.X86)$ ]] && [[ "${VEN_COMPARE}" -lt 193 ]]
    then
        echo "$(date) ERROR: This workload is ONLY supported by VEN version 19.3 and above, aborting VEN installation." | tee -a ${LogFile}
        echo "$(date) Workload OS: ${OSoutput}"  | tee -a ${LogFile}
        TARLOGS_CLEANUP
        exit 1
    elif [[ "${OS}" == 'Solaris' ]] && [[ "${OSrelease}" =~ ^(11.4.X86|11.3.X86|11.2.X86|11.1.X86|10.1/13|10.8/11|10.9/10|10.10/09)$ ]]
    then
        WORKLOAD_INFO_STATEMENT
    elif [[ "${OSrelease}" == 'NotFound' ]] 
    then
        echo "$(date) ERROR: Could not determine the operating system, aborting..." | tee -a ${LogFile}
        TARLOGS_CLEANUP
        exit 1
    else
        echo "$(date) ERROR: This workload is NOT supported by VEN, aborting VEN installation." | tee -a ${LogFile}
        echo "$(date) Workload OS: ${OSoutput}"  | tee -a ${LogFile}
        TARLOGS_CLEANUP
        exit 1
    fi
}

# Set generic VEN path/directory check
function VEN_PATH_PRE_CHECK() {
    if [[ -f "${IllumioVENctl}" ]] > /dev/null 2>&1
    then
        PairStatus=`${IllumioVENctl} status | grep state 2>/dev/null | head -n 1 | cut -d$' ' -f3`
        VENVersion=`cat ${IllumioVENdir}/etc/agent_version 2>/dev/null | head -n 1 | cut -d$' ' -f3`
        PCEName=`cat ${IllumioVENdatadir}/etc/agent_activation.cfg 2>/dev/null | grep master | head -n 1 | cut -d$':' -f2`
    fi
}

# Check if workload has already paired. If no status found, proceed for next step, else job exit.
function VEN_CURRENT_STATUS_CHECK() {
    VEN_PATH_PRE_CHECK
    if [[ "${PairStatus}" == 'unpaired' ]]
    then
        echo "$(date) NOTIFY: VEN version ${VENVersion} is in unpaired mode, proceed for next step." | tee -a ${LogFile}
    fi

    venStatus=('illuminated' 'enforced' 'idle')
    for i in ${venStatus[*]}; do
        if [[ -f ${IllumioVENctl} ]] && [[ "${PairStatus}" == "${i}"  ]]
        then
        echo "$(date) NOTIFY: VEN version ${VENVersion} has already paired as ${i} mode with${PCEName}, aborting VEN installation." | tee -a ${LogFile}
        TARLOGS_CLEANUP
        exit 1
        fi
    done
}

# Check if workload has any leftover VEN directories
function VEN_DIR_PRE_CHECK() {
    VenDirPath=`ls -d "${IllumioVENdir}" 2>/dev/null | head -n 1 | cut -d$'/' -f3`
    VenDataDirPath=`ls -d "${IllumioVENdatadir}" 2>/dev/null | head -n 1 | cut -d$'/' -f3`

    if [[ -d "${IllumioVENdir}" ]] && [[ ! -d "${IllumioVENdatadir}" ]]
    then
        echo "$(date) ERROR: Found VEN config directory but VEN data directory is missing, aborting VEN installation." | tee -a ${LogFile}
        TARLOGS_CLEANUP
        exit 1
    elif [[ ! -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
    then
        depthDir=$(ls /opt/illumio_ven_data/ | wc -l)
        if [[ "${depthDir}" == '1' ]]; then
            rm -rf ${IllumioVENdatadir} 2>/dev/null
        else
            echo "$(date) ERROR: Found VEN data directory but VEN config directory is missing, aborting VEN installation." | tee -a ${LogFile}
            TARLOGS_CLEANUP
            exit 1
        fi
    fi
}

# Generic check on the disk space and prompt error if the disk space is less than 500MB
function DISK_SPACE_CHECK() {
    DiskFreeLine=`df -k ${InstallPath} | grep "%" | tail -1 | awk -F' ' '{print $4}'`
    let "kbToMb = ${DiskFreeLine} / 1024"
    let "DiskLeftAfterVENinstall = ${kbToMb} - ${VENdiskUsageInMB}"
    echo "$(date) Disk left After VEN install = ${DiskLeftAfterVENinstall}M" | tee -a ${LogFile}

    if [[ "${DiskLeftAfterVENinstall}" -lt 1500 ]]
    then
        echo "$(date) NOTIFY: Disk free after install is less than 1.5GB, please be aware! Proceed for next step." | tee -a ${LogFile}
    elif [[ "${DiskLeftAfterVENinstall}" -lt 500 ]]
    then
        echo "$(date) ERROR: Disk free after install is less than 500M as minimum requirement, aborting VEN installation." | tee -a ${LogFile}
        TARLOGS_CLEANUP
        exit 1
    fi
}

# Check if required packages exist for VEN
function SOLARIS_PACKAGES_CHECK() {
    if [[ "${OS}" == 'Solaris' ]] && [[ "${OSrelease}" =~ ^(11.4.X86)$ ]]
    then 
        rpmPackageCheck=('SUNWxcu4' 'SUNWbash')
        for package in ${rpmPackageCheck[*]}; do
            if ! pkgparam -v ${package} | grep PKGINST > /dev/null 2>&1
            then
                echo "$(date) ERROR: ${package} package is not installed." | tee -a ${LogFile}
                let fail++
            fi
        done
    fi

    if [[ "${OS}" == 'Solaris' ]] && [[ "${OSrelease}" =~ ^(11.3.X86|11.2.X86|11.1.X86|10.1/13|10.8/11|10.9/10|10.10/09)$ ]]
    then 
        rpmPackageCheck=('SUNWxcu4' 'SUNWipfu' 'SUNWipfr' 'SUNWbash')
        for package in ${rpmPackageCheck[*]}; do
            if !  pkgparam -v ${package} | grep PKGINST > /dev/null 2>&1
            then
                echo "$(date) ERROR: ${package} package is not installed." | tee -a ${LogFile}
                let fail++
            fi
        done
    fi
} 2>/dev/null

# Check if multi zones configured
function ZONES_CHECK() {
    zoneCheck=`zoneadm list -civ | grep shared | grep -v global | wc -l | tr -d " "`
    if [[ "$zoneCheck" != 0 ]]
    then
        echo "$(date) ERROR: Multi zones not supported by VEN." | tee -a ${LogFile}
        let fail++
    fi
} 2>/dev/null

# Check if the workload can reach the PCE FQDN via PING and the return IP matches or not. If it is not match, proceed for FQDN check via nslookup.
function PCE_FQDN_CHECK() {
    PCEFqdnResolve=`nslookup ${PCEFQDN} | grep ${PCEIP}| tail -1 | awk -F' ' '{print $2}'`
    ping ${PCEFQDN} >/dev/null
    if [[ "${?}" == 0 ]]; then
        resolve=`ping -s ${PCEFQDN} 64 1 | grep from | sed -e "s/).*//" | sed -e "s/.*(//"`
        hosttable=$(grep -i ${PCEFQDN} /etc/hosts | grep ${PCEIP} | awk -F' ' '{print $1}')
        if [[ "${resolve}" == "${PCEIP}" ]] || [[ "${hosttable}" == "${PCEIP}" ]]; then
            echo "$(date) Skip the FQDN check since workload can reaching PCE."
        else
            echo "$(date) ERROR: Unable to resolve ${PCEFQDN} FQDN as IP ${PCEIP}." | tee -a ${LogFile}
        fi
    elif [[ "${PCEFqdnResolve}" != "${PCEIP}" ]]; then
        echo "$(date) ERROR: Unable to resolve ${PCEFQDN} FQDN as IP ${PCEIP}." | tee -a ${LogFile}
        let fail++
    fi
} 2>/dev/null

# Check if ipf.conf file exist
function IPF_CHECK() {
    if [[ "${OSrelease}" =~ ^(11.3.X86|11.2.X86|11.1.X86|10.1/13|10.8/11|10.9/10|10.10/09)$ ]]
    then
        if [[ ! -f /etc/ipf/ipf.conf ]] > /dev/null 2>&1
        then
            echo "$(date) ERROR: IPF Config file is missing." | tee -a ${LogFile}
            let fail++
        fi
    fi
}

# Check if ipf.conf file exist only for 11.4 version
function PF_CHECK() {
    if [[ "${OSrelease}" =~ ^(11.4.X86)$ ]]
    then
        if [[ ! -f /etc/firewall/pf.conf ]] > /dev/null 2>&1
        then
        echo "$(date) ERROR: PF (packetfilter) Config file is missing." | tee -a ${LogFile}
        let fail++
        fi
    fi
}

# Check if ipfilter service is running. It will first try to enable it before the check
function IPFILTER_CHECK() {
    if [[ "${OSrelease}" != '11.4.X86' ]]
    then
        svcadm enable network/ipfilter
        svcadm refresh network/ipfilter
        sleep 6
        ipFilterCheck=`svcs -l ipfilter | grep state | head -n 1 | awk -F' ' '{print $2}'`
        if [[ "$ipFilterCheck" != 'online' ]]
        then
            echo "1" | tee -a ${LogFile}
            echo "$(date) ERROR: IPfilter service is not online." | tee -a ${LogFile}
            let fail++
        fi
    fi
}

# Check if firewall service is running. It will first try to enable it before the check. Only for 11.4 version
function PACKETFILTER_CHECK() {
    if [[ "${OSrelease}" =~ ^(11.4.X86)$ ]]
    then
        svcadm enable network/firewall
        svcadm refresh network/firewall
        sleep 6
        packetFilterCheck=`svcs -l firewall | grep state | head -n 1 | awk -F' ' '{print $2}'`
        if [[ "$packetFilterCheck" =~ ^!(online|degraded)$ ]]
        then
            echo "$(date) ERROR: packetfilter (firewall) service is not online." | tee -a ${LogFile}
            let fail++
        fi
    fi
}

# Check if there is existing rule in ipfilter, provides a notification if there is.
function IPFILTER_USAGE_CHECK() {
  if [[ "${OSrelease}" != '11.4.X86' ]]
  then
    ipfRuleCount=`ipfstat -io | wc | awk -F' ' '{print $1}'`
    ipfTable=0
    if [[ "${ipfRuleCount}" != 0 ]]
    then
      echo "$(date) NOTIFY: There is rule in ipfilter tables." | tee -a ${LogFile}
      let ipfTable++
    fi

    if [[ ${ipfTable} != 0 ]]
    then
      echo "$(date) NOTIFY: Backup existing ipfilter rules into log." | tee -a ${LogFile}
      ipfRules=${WorkingDirectory}/_illumio_ipfrules_backup.log
      cat /etc/ipf/ipf.conf >> ${ipfRules}
    fi
  fi
} 2>/dev/null

# Check if there is existing rule in packetfilter, provides a notification if there is.
function PACKETFILTER_USAGE_CHECK() {
  if [[ "${OSrelease}" =~ ^(11.4.X86)$ ]]
  then
    pfRuleCount=`pfctl -s rules | wc | awk -F' ' '{print $1}'`
    pfTable=0
    if [[ "${pfRuleCount}" != 0 ]]
    then
      echo "$(date) NOTIFY: There is rule in packetfilter tables." | tee -a ${LogFile}
      let pfTable++
    fi

    if [[ ${pfTable} != 0 ]]
    then
      echo "$(date) NOTIFY: Backup existing packetfilter rules into log." | tee -a ${LogFile}
      pfRules=${WorkingDirectory}/_illumio_pfrules_backup.log
      cat /etc/firewall/pf.conf >> ${pfRules}
    fi
  fi
} 2>/dev/null

# Check if the workload can resolve PCE SSL cert via wgets.
function PCE_CERTS_LOCAL_CHECK() {
    if [[ "${OS}" == 'Solaris' ]]; then
        # For root cert
        wget --tries=1 https://${PCEFQDN}:${PCEPORT} 2>${WorkingDirectory}/_illumio_certcheck.log >/dev/null
        if [[ "${?}" == 0 ]]; then
            echo "$(date) Workload can resolve ${PCEFQDN} cert." | tee -a ${LogFile}
        elif [[ "${?}" != 0 ]] && [[ "${certinstall}" == 1 ]]; then
            echo "$(date) ERROR: Workload cannot resolve ${PCEFQDN} cert, check \"_illumio_certcheck.log\"." | tee -a ${LogFile}
            let fail++
        else
            echo "$(date) ERROR: Workload cannot resolve ${PCEFQDN} cert." | tee -a ${LogFile}
            # echo "$(date) NOTIFY: Trying to install the SSL certs and retry." | tee -a ${LogFile}
            let certinstall++
            # CERT_INSTALL
        fi
    fi
}

# Auto cert install if it is missing then retry the test again.
function CERT_INSTALL() {
    if [[ "${certinstall}" == 1 ]] && [[ "${OSrelease}" =~ ^(11.4.X86|11.2.X86|11.3.X86|11.1.X86)$ ]]
    then
        if [[ -f "${WorkingDirectory}/${ROOTCERT}" ]] > /dev/null 2>&1
        then
            svcadm enable ca-certificates
            cp ${WorkingDirectory}/${ROOTCERT} /etc/certs/CA
            svcadm restart ca-certificates
            sleep 3
            PCE_CERTS_LOCAL_CHECK
        else
            echo "$(date) ERROR: ${ROOTCERT} is not in the directory." | tee -a ${LogFile}
        fi
    elif [[ "${certinstall}" == 1 ]] && [[ "${OSrelease}" =~ ^(10.1/13|10.8/11|10.9/10|10.10/09)$ ]]
    then
        if [[ -f "${WorkingDirectory}/${ROOTCERT}" ]] > /dev/null 2>&1
        then
            DEFAULT_CERTS="/etc/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt /etc/opt/csw/ssl/certs/ca-certificates.crt"
            for TVAL in ${DEFAULT_CERTS}; do
                if [ -f "$TVAL" ]
                then
                    CHOSEN_CERT="$TVAL"
                    break
                fi
            done
            echo "$(date) Copy the ${CHOSEN_CERT} to ${WorkingDirectory} as backup." | tee -a $
            cp ${CHOSEN_CERT} "${WorkingDirectory}/certsbackup-bak-$(date +"%Y%m%d_%H%M%S")"
            cat ${WorkingDirectory}/${ROOTCERT} >> ${CHOSEN_CERT}
            PCE_CERTS_LOCAL_CHECK
        else
            echo "$(date) ERROR: ${ROOTCERT} is not in the directory." | tee -a ${LogFile}
        fi
    else
        echo "$(date) ERROR: Unable to install the missing certs due to ca-certificates service is missing." | tee -a ${LogFile}
        PCE_CERTS_LOCAL_CHECK
    fi
}

# Check if workload can reaching PCE port 8443 via wget.
function PCE_8443_PORT_CHECK() {
    wget --tries=1 https://${PCEFQDN}:${PCEPORT} --no-check-certificate &>${WorkingDirectory}/_illumio_8443check.log
    grep connected ${WorkingDirectory}/_illumio_8443check.log >/dev/null
    if [[ "${?}" != 0 ]]
    then
        echo "$(date) ERROR: Workload cannot reaching ${PCEFQDN} management port ${PCEPORT}, check \"_illumio_8443check.log\"." | tee -a ${LogFile}
        let fail++
    fi
}

# Check if workload can reaching PCE port 8444 via wget.
function PCE_8444_PORT_CHECK() {
    wget --tries=1 https://${PCEFQDN}:${PCEPORT2} --no-check-certificate &>${WorkingDirectory}/_illumio_8444stdout.log
    grep connected ${WorkingDirectory}/_illumio_8444stdout.log >/dev/null
    if [[ "${?}" != 0 ]]
    then
      echo "$(date) ERROR: Workload cannot reaching ${PCEFQDN} port ${PCEPORT2}, check \"_illumio_8444stdout.log\"." | tee -a ${LogFile}
      let fail++
    fi
}

# If above jobs all pass and 'fail' bit is 0, proceed for install, else abort.
function SOLARIS_VEN_INSTALL() {
    rpmOutput=${WorkingDirectory}/_illumio_rpminstallresult.log
    rpmError=${WorkingDirectory}/_illumio_rpmerrorinstall.log

    if [[ "${fail}" == 0 ]] && [[ "${OS}" == 'Solaris' ]]
    then
        sleep 5
        echo "$(date) Proceed for VEN installation..." | tee -a ${LogFile}

        if [[ "${OS}" == 'Solaris' ]] && [[ "${sol_type}" =~ ^(X86|SPARC)$ ]]
        then
            rpmVENfile="S5_${sol_type}Package"
            if [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]] && [[ "${PairStatus}" == 'unpaired' ]]
            then
                currentVer=`/opt/illumio_ven/illumio-ven-ctl version` 
                echo "$(date) VEN ${currentVer} already installed." | tee -a ${LogFile}
                VEN_UPGRADE
            elif [[ ! -d "${IllumioVENdir}" ]] && [[ ! -d "${IllumioVENdatadir}" ]] 
            then
                cd ${WorkingDirectory}
                rm -rf illumio-ven
                gunzip -c ${WorkingDirectory}/${!rpmVENfile} | tar xvf - >$rpmOutput 2>$rpmError
                echo "y" | pkgadd -d . -a illumio-ven/root/opt/illumio_ven/etc/templates/admin -r illumio-ven/root/opt/illumio_ven/etc/templates/response all
                rpmState=${?}
                rm -rf illumio-ven
                if [[ ! -f "${WorkingDirectory}"/"${!rpmVENfile}" ]]
                then
                    echo "$(date) ERROR: VEN PACKAGE ${!rpmVENfile} package not found, aborting installation" | tee -a ${LogFile}
                    let fail++
                    TARLOGS_CLEANUP
                    exit 1
                elif [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
                then
                    echo "$(date) VEN PACKAGE ${!rpmVENfile} Installed Successfully." | tee -a ${LogFile}
                elif [[ "${rpmState}" != 0 ]] && [[ ! -d "${IllumioVENdir}" ]] && [[ ! -d "${IllumioVENdatadir}" ]]
                then
                    echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}
                    TARLOGS_CLEANUP
                    exit 1
                fi
            fi
        else
            echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}
            TARLOGS_CLEANUP
            exit 1
        fi
    else
        echo "$(date) ERROR: Aborting VEN installation. Please check '_illumio_veninstall.log', there are dependencies missing." | tee -a ${LogFile}
        TARLOGS_CLEANUP
        exit 1
    fi
}

function VERSION_COMPARE() {
    test "$(printf '%s\n' "$@" | sort | head -n 1)" != "$1"; 
}

# VEN Upgrade function
function VEN_UPGRADE() {
    echo "$(date) Checking if workload requires a VEN upgrade." | tee -a ${LogFile}
    currentVer=`/opt/illumio_ven/illumio-ven-ctl version`
    if [[ ${currentVer} != ${VEN_VER} ]]
    then
        if [[ "${OS}" =~ ^(Solaris)$ ]]
        then
            if [[ ${currentVer} != ${VEN_VER} ]]
            then
                if VERSION_COMPARE ${VEN_VER} ${currentVer}
                then
                    cd ${WorkingDirectory}
                    rm -rf illumio-ven
                    gunzip -c ${WorkingDirectory}/${!rpmVENfile} |tar xvf - >$rpmOutput 2>$rpmError
                    echo "y" | pkgadd -d . -a illumio-ven/root/opt/illumio_ven/etc/templates/admin -r illumio-ven/root/opt/illumio_ven/etc/templates/response all
                    rm -rf illumio-ven
                    currentVer=`/opt/illumio_ven/illumio-ven-ctl version`
                    if [[ ${currentVer} == ${VEN_VER} ]]
                    then
                        echo "$(date) VEN successfully upgraded to ${currentVer}." | tee -a ${LogFile}
                        VEN_PAIRING
                    fi
                else
                    echo "$(date) Current VEN ${currentVer} has not upgraded, either the current version is higher or check logs for detail." | tee -a ${LogFile}
                    VEN_PAIRING
                fi
            fi
        fi
    elif [[ ${currentVer} == ${VEN_VER} ]]
    then
        echo "$(date) Current VEN version is the same with the targetted version." | tee -a ${LogFile}
        VEN_PAIRING
    fi
}

# VEN Installation
function VEN_PAIRING() {
    # Pairing the VEN workload with PCE
    echo "$(date) Pairing VEN workload with PCE - ${PCEFQDN}..." | tee -a ${LogFile}
    ErrorPairingVEN=${WorkingDirectory}/_illumio_pairingerror.log
    sleep 5
    echo "$(date)" >> ${ErrorPairingVEN}
    cd "${IllumioVENdir}"
    ./illumio-ven-ctl activate --management-server ${PCEFQDN}:${PCEPORT} --activation-code ${ActivationCode} 1>>${ErrorPairingVEN} 2>>${ErrorPairingVEN}
    PairingState=${?}
    if [[ "${PairingState}" == 0 ]] && [[ -f "${IllumioActCfg}" ]]
    then
        echo "$(date) Pairing with PCE - ${PCEFQDN} successfully with VEN." | tee -a ${LogFile}
        sleep 5
        TARLOGS_CLEANUP
        exit 1
    else
        echo "$(date) ERROR: Pairing with PCE - ${PCEFQDN} failed, removing the VEN and reverting to previous ipfilter stage." | tee -a ${LogFile}
        echo "$(date) Search for NOTIFY and ERROR in the '_illumio_veninstall.log' for more info." | tee -a ${LogFile}
        echo "$(date)" >> ${ErrorPairingVEN}
        sleep 5
        ${IllumioVENctl} unpair saved 1>>${ErrorPairingVEN} 2>>${ErrorPairingVEN}
        echo "$(date)" >> ${ErrorPairingVEN}
        let fail++
        TARLOGS_CLEANUP
        exit 1
    fi
}


#############################################################################


# Job begin
# Check if the executer is root user or not before proceed
if [[ $EUID -ne 0 ]]
then
    echo "$(date) ERROR: The script must be run as root, aborting." | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
else
    cd $WorkDir
    touch ${LogFile} && chmod 644 ${LogFile}
    echo "$(date) VEN Installation task - Job begin..." | tee -a ${LogFile}
    # Define an initial fail bit, this decides whether the script installs the VEN or not in the later stage.
    fail=0
    certinstall=0
fi

# OS check
sol_based=$(isainfo -b)
if [[ "${sol_based}" != "64" ]]
then
    echo "Solaris 32 bit workload is NOT supported by VEN"  | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
else
    SOLARIS_OS_CHECK
fi

VEN_CURRENT_STATUS_CHECK
VEN_DIR_PRE_CHECK
DISK_SPACE_CHECK
SOLARIS_PACKAGES_CHECK
ZONES_CHECK
PCE_FQDN_CHECK
IPF_CHECK
PF_CHECK
IPFILTER_CHECK
PACKETFILTER_CHECK
IPFILTER_USAGE_CHECK
PACKETFILTER_USAGE_CHECK
PCE_CERTS_LOCAL_CHECK
PCE_8443_PORT_CHECK
PCE_8444_PORT_CHECK
SOLARIS_VEN_INSTALL
VEN_PAIRING

sleep 3
exit 0
