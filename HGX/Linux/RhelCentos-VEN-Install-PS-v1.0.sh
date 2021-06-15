#!/usr/bin/env bash
#
# Copyright 2013-2020 Illumio, Inc. All Rights Reserved.
#
# Created by: Siew Boon Siong
# Email: boon.siew@illumioeval.com
# Updated: Mar-02-2020
# Version: 1.14
#
# 1. This script only for Red Hat and CentOS by using PCE-based pairing script only.
# 2. Copy this script together with Rootcert file together to the target workload and place under /tmp directory
# 3. Execute command step: "bash RhelCentos-VEN-Install-PS-v1.0.sh"
# 4. Whenever it complete, it will create a tgz file no matter the result is success or fail. Eg: ${date}_${HOSTNAME}_${OS}_illumioreport.tgz
# 5. Root cert and shell script will be deleted after the execution.
#
# Flexible variables adjust when needed
PCEFQDN='illumio.office.hgc.com.hk'
ROOTCERT='HGCCA.CER'

# If using front-end load balancer, put the same PCE VIP in these 2 variables. If using DNS load balancing, put both Core0 and Core1 IP accordingly
PCEIP='192.168.36.124'
PCEIP2='192.168.36.124'

# Pairing script for VEN version 19.x
PairingScript='rm -fr /opt/illumio_ven_data/tmp && umask 026 && mkdir -p /opt/illumio_ven_data/tmp && curl "https://illumio.office.hgc.com.hk:8443/api/v6/software/ven/image?pair_script=pair.sh&profile_id=3" -o /opt/illumio_ven_data/tmp/pair.sh && chmod +x /opt/illumio_ven_data/tmp/pair.sh && /opt/illumio_ven_data/tmp/pair.sh --management-server illumio.office.hgc.com.hk:8443 --activation-code 1f55928d848f7597ea2240e06b30ed9bf309e27bcddf9f05314b80d9a9adbb43c52ca23b68d6347f3'

# Pairing script for VEN version 18.2 for RHEL/CentOS 5
PairingScript182='rm -fr /opt/illumio_ven_data/tmp && umask 026 && mkdir -p /opt/illumio_ven_data/tmp && curl "https://illumio.office.hgc.com.hk:8443/api/v6/software/ven/image?pair_script=pair.sh&profile_id=4" -o /opt/illumio_ven_data/tmp/pair.sh && chmod +x /opt/illumio_ven_data/tmp/pair.sh && /opt/illumio_ven_data/tmp/pair.sh --management-server illumio.office.hgc.com.hk:8443 --activation-code 164854fd8d55bee81985d4390c9ca4d8fe9e7a50bd557074cf9df96194247be019e4e8b4e5b8b6634'

####################################################
######## DO NOT MODIFY ANYTHING BELOW ##############
####################################################
PCEPORT='8443'
PCEPORT2='8444'
PCEBasedPairing='YES'
InstallPath='/opt'
WorkingDirectory='/tmp'
LogFile='/tmp/_illumio_veninstall.log'
VENdiskUsageInMB='20'
IllumioVENctl='/opt/illumio_ven/illumio-ven-ctl'
IllumioVENdir='/opt/illumio_ven'
IllumioVENdatadir='/opt/illumio_ven_data'
IllumioAgentId='/opt/illumio_ven_data/etc/agent_id.cfg'

# Clean up when the job is completed
function TARLOGS_CLEANUP() {
    date=$(date '+%Y-%m-%d')
    cd ${WorkingDirectory} && mkdir -p job
    cp -R ${IllumioVENdir} ${IllumioVENdatadir} ${WorkingDirectory}/_illumio_*.log /var/log/illumio*log ${WorkingDirectory}/job
    tar -rf ${WorkingDirectory}/${date}_${HOSTNAME}_${OS}_illumioreport.tgz job
    rm -rf ${WorkingDirectory}/_illumio_*.log
    rm -rf ${WorkingDirectory}/RhelCentos-VEN-Install-PS-v1.0.sh
    rm -rf ${WorkingDirectory}/job
    rm -rf ${WorkingDirectory}/${ROOTCERT}
} &>/dev/null

# Generic statements for workload info
function WORKLOAD_INFO_STATEMENT() {
    echo "$(date) Workload Hostname: ${HOSTNAME}" | tee -a ${LogFile}
    echo "$(date) This workload is supported by VEN." | tee -a ${LogFile}
    echo "$(date) Workload IP(s): ${IPAdd}" | tee -a ${LogFile}

    osVersion=('RedHat' 'CentOS')
    for i in ${osVersion[*]}; do
        if [[ "${OS}" == "${i}" ]]; then
            echo "$(date) Workload OS: ${OSoutput}" | tee -a ${LogFile}
        fi
    done

    if [[ "${OS}" =~ ^(RedHat|CentOS)$ ]]; then
        echo "$(date) Workload Architecture: $(arch)" | tee -a ${LogFile}
    fi
}

# Check if the OS supported. If it is not supported or out of the list, job exit.
function RHEL_CENTOS_OS_CHECK() {
    echo "$(date) Checking Operating System..." | tee -a ${LogFile}
    # The length of output of /etc/redhat-release differents in each OS , setting the variable and trying to catch all.
    OSrelease=NotFound
    if [[ "${OSrelease}" == 'NotFound' ]]; then
        redHatRelease=/etc/redhat-release
        OSoutput=$(cat /etc/redhat-release)
        if test -f "${redHatRelease}"; then
            if grep -q 'Red Hat' ${redHatRelease}; then
                echo "$(date) RedHat Detected." | tee -a ${LogFile}
                OS='RedHat'
            fi
            if grep -q 'CentOS' ${redHatRelease}; then
                echo "$(date) CentOS Detected." | tee -a ${LogFile}
                OS='CentOS'
            fi
            OSrelease=$(cat ${redHatRelease} | rev | cut -d'(' -f 2 | rev | awk 'NF>1{print $NF}' | cut -d$'.' -f1)
            OSminor=$(cat ${redHatRelease} | rev | cut -d'(' -f 2 | rev | awk 'NF>1{print $NF}' | cut -d$'.' -f2)
        fi
    fi
    # If it is version 5, it will be pairing with 18.2 pairing scipt.
    if [[ "${OSrelease}" == '5' ]]; then
        let pairing182++
        IPAdd=$(/sbin/ip addr | grep inet | grep -v -E '127.0.0|inet6' | cut -d$'/' -f1 | awk '{print $2}' ORS=' ')
        WORKLOAD_INFO_STATEMENT
    # Other version, will be using 19.x pairing script.
    elif [[ "${OSrelease}" =~ ^(6|7|8)$ ]]; then
        IPAdd=$(hostname -I)
        WORKLOAD_INFO_STATEMENT
    elif [[ "${OSrelease}" == 'NotFound' ]]; then
        echo "$(date) ERROR: Could not determine the operating system, aborting..." | tee -a ${LogFile}
        TARLOGS_CLEANUP
        exit 1
    else
        echo "$(date) ERROR$: This workload is NOT supported by VEN ${VEN_VER} (check the major and minor OS), aborting VEN installation." | tee -a ${LogFile}
        echo "$(date) Workload OS: ${OSoutput}" | tee -a ${LogFile}
        TARLOGS_CLEANUP
        exit 1
    fi
}

# Set generic VEN path/directory check
function VEN_PATH_PRE_CHECK() {
    if [[ -f "${IllumioVENctl}" ]] >/dev/null 2>&1; then
        PairStatus=$(${IllumioVENctl} status | grep state 2>/dev/null | head -n 1 | cut -d$' ' -f3)
        VENVersion=$(cat ${IllumioVENdir}/etc/agent_version 2>/dev/null | head -n 1 | cut -d$' ' -f3)
        PCEName=$(cat ${IllumioVENdatadir}/etc/agent_activation.cfg 2>/dev/null | grep master | head -n 1 | cut -d$':' -f2)
    fi
}

# Check if workload has already paired. If no status found, proceed for next step, else job exit.
function VEN_CURRENT_STATUS_CHECK() {
    VEN_PATH_PRE_CHECK
    if [[ "${PairStatus}" == 'unpaired' ]]; then
        echo "$(date) NOTIFY: VEN version ${VENVersion} is in unpaired mode, proceed for next step." | tee -a ${LogFile}
    fi

    venStatus=('illuminated' 'enforced' 'idle')
    for i in ${venStatus[*]}; do
        if [[ -f ${IllumioVENctl} ]] && [[ "${PairStatus}" == "${i}" ]]; then
            echo "$(date) NOTIFY: VEN version ${VENVersion} has already paired as ${i} mode with${PCEName}, aborting VEN installation." | tee -a ${LogFile}
            TARLOGS_CLEANUP
            exit 1
        fi
    done
}

# Check if workload has any leftover VEN directories
function VEN_DIR_PRE_CHECK() {
    VenDirPath=$(ls -d "${IllumioVENdir}" 2>/dev/null | head -n 1 | cut -d$'/' -f3)
    VenDataDirPath=$(ls -d "${IllumioVENdatadir}" 2>/dev/null | head -n 1 | cut -d$'/' -f3)

    if [[ -d "${IllumioVENdir}" ]] && [[ ! -d "${IllumioVENdatadir}" ]]; then
        echo "$(date) ERROR: Found VEN config directory but VEN data directory is missing, aborting VEN installation." | tee -a ${LogFile}
        TARLOGS_CLEANUP
        exit 1
    elif [[ ! -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]; then
        depthDir=$(find /opt/illumio_ven_data/ -maxdepth 1 -empty | wc -l)
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
    DiskFreeLine=$(df -k ${InstallPath} -B M | grep "%" | tail -1 | awk -F'M ' '{print $3}')

    let "DiskLeftAfterVENinstall = ${DiskFreeLine} - ${VENdiskUsageInMB}"
    echo "$(date) Disk left After VEN install = ${DiskLeftAfterVENinstall}M" | tee -a ${LogFile}
    if [[ "${DiskLeftAfterVENinstall}" -lt 1500 ]]; then
        echo "$(date) NOTIFY: Disk free after install is less than 1.5GB, please be aware! Proceed for next step." | tee -a ${LogFile}
    elif [[ "${DiskLeftAfterVENinstall}" -lt 500 ]]; then
        echo "$(date) ERROR: Disk free after install is less than 500M as minimum requirement, aborting VEN installation." | tee -a ${LogFile}
        TARLOGS_CLEANUP
        exit 1
    fi
}

# Check if required packages exist for VEN.
function RHEL_CENTOS_PACKAGES_CHECK() {
    # for RHEL/CentOs 5,6,7,8 check on the package
    if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ "${OSrelease}" =~ ^(5|6|7|8)$ ]]; then
        rpmPackageCheck=('libcap' 'gmp' 'bind-utils' 'curl' 'sed')
        for package in ${rpmPackageCheck[*]}; do
            if ! rpm -q ${package} >/dev/null 2>&1; then
                echo "$(date) ERROR: ${package} package is not installed." | tee -a ${LogFile}
                let fail++
            fi
        done
    fi

    # for RHEL/CentOs 5,6,7 check on the package
    if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ "${OSrelease}" =~ ^(5|6|7)$ ]]; then
        rpmFileCheck=('iptables' 'ip6tables' 'ipset')
        for package in ${rpmFileCheck[*]}; do
            if [[ -f /usr/bin/${package} || -f /bin/${package} || -f /sbin/${package} || -f /usr/sbin/${package} ]]; then
                echo "$(date) ${package} package installed." >/dev/null
            else
                echo "$(date) ERROR: ${package} package is not installed." | tee -a ${LogFile}
                let fail++
            fi
        done
    fi

    # for RHEL/CentOs 8 check on the package. If the VEN version is 18.2.4, we just need iptables and ipset. If the version is 19.3 and above, we just need nft. This is for 19.3 only.
    if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ "${OSrelease}" =~ ^(8)$ ]]; then
        rpmFileCheck=('nft')
        for package in ${rpmFileCheck[*]}; do
            if [[ ! -f /sbin/${package} ]] >/dev/null 2>&1; then
                echo "$(date) ERROR: ${package} package is not installed." | tee -a ${LogFile}
                let fail++
            fi
        done
    fi

    # for RHEL/CentOs 6,7,8 check on the package
    if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ "${OSrelease}" =~ ^(6|7|8)$ ]]; then
        rpmPackageCheck=('net-tools' 'libnfnetlink' 'libmnl' 'ca-certificates')
        for package in ${rpmPackageCheck[*]}; do
            if ! rpm -q ${package} >/dev/null 2>&1; then
                echo "$(date) ERROR: ${package} package is not installed." | tee -a ${LogFile}
                let fail++
            fi
        done
    fi
}

# Check if the workload can reach the PCE FQDN via PING and the return IP matches or not. If it is not match, proceed for FQDN check via nslookup.
function PCE_FQDN_CHECK() {
    PCEFqdnResolve=$(nslookup ${PCEFQDN} | grep ${PCEIP} | tail -1 | cut -d$' ' -f2)
    PCEFqdnResolve2=$(nslookup ${PCEFQDN} | grep ${PCEIP2} | tail -1 | cut -d$' ' -f2)
    ping -q -c3 ${PCEFQDN} >/dev/null
    if [[ "${?}" == 0 ]]; then
        resolve=$(ping -q -c 1 -t 1 ${PCEFQDN} | grep PING | sed -e "s/).*//" | sed -e "s/.*(//")
        hosttable=$(grep -i ${PCEFQDN} /etc/hosts | grep ${PCEIP} | awk -F' ' '{print $1}')
        if [[ "${resolve}" == "${PCEIP}" ]] || [[ "${hosttable}" == "${PCEIP}" ]]; then
            echo "$(date) Skip the FQDN check since workload can reaching PCE."
        else
            echo "$(date) ERROR: Unable to resolve ${PCEFQDN} FQDN as IP ${PCEIP}." | tee -a ${LogFile}
            let fail++
        fi
    elif [[ "${PCEFqdnResolve}" != "${PCEIP}" ]] || [[ "${PCEFqdnResolve2}" != "${PCEIP2}" ]]; then
        echo "$(date) ERROR: Unable to resolve ${PCEFQDN} FQDN as IP ${PCEIP}." | tee -a ${LogFile}
        let fail++
    fi
} 2>/dev/null

# Check if any rule exist in the iptables prior to VEN installation. Back it up before proceed.
function IPTABLES_USAGE_CHECK() {
    if [[ "${OS}" =~ ^(RedHat|CentOS)$ && "${OSrelease}" =~ ^(5|6|7|8)$ ]]; then
        FilterIPtable=$(/sbin/iptables -t filter -L | wc | awk -F' ' '{print $1}')
        RawIPtable=$(/sbin/iptables -t raw -L | wc | awk -F' ' '{print $1}')
        MangleIPtable=$(/sbin/iptables -t mangle -L | wc | awk -F' ' '{print $1}')
        NatIPtable=$(/sbin/iptables -t nat -L | wc | awk -F' ' '{print $1}')
        ipTables=0

        if [[ "${FilterIPtable}" -gt 8 ]]; then
            echo "$(date) NOTIFY: There is rule in Filter IPtables." | tee -a ${LogFile}
            let ipTables++
        fi

        if [[ "${RawIPtable}" -gt 5 ]]; then
            echo "$(date) NOTIFY: There is rule in Raw IPtables" | tee -a ${LogFile}
            let ipTables++
        fi

        if [[ "${MangleIPtable}" -gt 14 ]]; then
            echo "$(date) NOTIFY: There is rule in Mangle IPtables" | tee -a ${LogFile}
            let ipTables++
        fi

        # There is extra chain in RHEL/CentOS 7 than 5,6
        if [[ "${NatIPtable}" -gt 8 ]] && [[ "${OSrelease}" =~ ^(5|6)$ ]]; then
            echo "$(date) NOTIFY: There is rule in Nat IPtables" | tee -a ${LogFile}
            let ipTables++
        fi

        if [[ "${NatIPtable}" -gt 11 ]] && [[ "${OSrelease}" =~ ^(7|8)$ ]]; then
            echo "$(date) NOTIFY: There is rule in Nat IPtables" | tee -a ${LogFile}
            let ipTables++
        fi
    fi

    if [[ "${OS}" =~ ^(RedHat|CentOS)$ && "${OSrelease}" =~ ^(6|7|8)$ ]]; then
        SecurityIPtable=$(/sbin/iptables -t security -L | wc | awk -F' ' '{print $1}')
        if [[ "${SecurityIPtable}" -gt 8 ]]; then
            echo "$(date) NOTIFY: There is rule in Security IPtables" | tee -a ${LogFile}
            let ipTables++
        fi
    fi

    if [[ ${ipTables} != 0 ]] && [[ "${OS}" =~ ^(RedHat|CentOS)$ && "${OSrelease}" =~ ^(6|7|8)$ ]]; then
        echo "$(date) NOTIFY: Dump existing IPtables rules into ${WorkingDirectory}." | tee -a ${LogFile}
        iptablesRules=${WorkingDirectory}/_illumio_preiptablesrules.log
        iptablesTable=('filter' 'raw' 'mangle' 'security' 'nat')
        for i in ${iptablesTable[*]}; do
            echo " " >>${iptablesRules}
            echo "$(date) ${i} rules" >>${iptablesRules}
            /sbin/iptables -t ${i} -S >>${iptablesRules}
        done
    elif [[ ${ipTables} != 0 ]] && [[ "${OS}" =~ ^(RedHat|CentOS)$ ]] && [[ "${OSrelease}" == '5' ]]; then
        echo "$(date) NOTIFY: Dump existing IPtables rules into ${WorkingDirectory}." | tee -a ${LogFile}
        iptablesRules=${WorkingDirectory}/_illumio_preiptablesrules.log
        cat /etc/sysconfig/iptables >${iptablesRules}
    fi
} 2>/dev/null

# Only for RHEL/CentOS 8, check if any rule exist in nftable prior to VEN installation. Back it up before proceed.
function NFT_USAGE_CHECK() {
    if [[ "${OS}" =~ ^(RedHat|CentOS)$ ]] && [[ "${OSrelease}" == '8' ]]; then
        nftable=$(nft list ruleset | wc | awk -F' ' '{print $1}')

        if [[ "${nftable}" -gt 1 ]]; then
            echo "$(date) NOTIFY: There is rule in NFTables." | tee -a ${LogFile}
            echo "$(date) NOTIFY: Dump existing NFTables rules into log." | tee -a ${LogFile}
            nftRulesBack=${WorkingDirectory}/_illumio_prenftablesrules.log
            nft list ruleset >${nftRulesBack}
        fi
    fi
} 2>/dev/null

# Check if the workload can resolve PCE SSL cert via Curl.
function PCE_REACHABILITY_LOCAL_CHECK() {
    if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ "${OSrelease}" =~ ^(6|7|8)$ ]]; then
        # For root cert
        curl -I https://${PCEFQDN}:${PCEPORT} --max-time 30 2>${WorkingDirectory}/_illumio_certcheck.log >/dev/null
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

    if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ "${OSrelease}" =~ ^(5)$ ]]; then
        echo "$(date) Checking if OpenSSL version is sufficient for RHEL/CentOS 5..." | tee -a ${LogFile}
        # Verify RHEL/CentOS 5 OpenSSL version
        OpenSSLRequired='openssl-0.9.8e-40.el5_11'
        CheckOpenSSLVer=$(rpm -qa | grep -i ^openssl-)
        if [[ "${CheckOpenSSLVer}" != "${OpenSSLRequired}" ]]; then
            echo "$(date) ERROR: OpenSSL version for RHEL/CentOS 5 requires ${OpenSSLRequired}." | tee -a ${LogFile}
            echo "$(date) ERROR: Aborting, the OpenSSL current version is insufficient, please refer KB: https://my.illumio.com/apex/article?name=Error-message-asn1-encoding-routines-when-pairing-on-CentOS5-5" | tee -a ${LogFile}
            let fail++
        elif [[ "${CheckOpenSSLVer}" == "${OpenSSLRequired}" ]]; then
            echo "$(date) OpenSSL version is sufficient..." | tee -a ${LogFile}
            curl -I https://${PCEFQDN}:${PCEPORT} --max-time 30 2>${WorkingDirectory}/_illumio_certcheck.log >/dev/null
            if [[ "${?}" == 0 ]]; then
                echo "$(date) Workload can resolve ${PCEFQDN} cert." >/dev/null
            elif [[ "${?}" != 0 ]] && [[ "${certinstall}" == 1 ]]; then
                echo "$(date) ERROR: Workload cannot resolve ${PCEFQDN} cert, check \"_illumio_certcheck.log\"." | tee -a ${LogFile}
                let fail++
            else
                echo "$(date) ERROR: Workload cannot resolve ${PCEFQDN} cert." | tee -a ${LogFile}
                # echo "$(date) NOTIFY: Installing the SSL certs and retry." | tee -a ${LogFile}
                let certinstall++
                # CERT_INSTALL
            fi
        fi
    fi
}

# Auto cert install if it is missing then retry the test again.
function CERT_INSTALL() {
    if [[ "${certinstall}" == 1 ]] && [[ "${OSrelease}" =~ ^(6|7|8)$ ]]; then
        if rpm -q ca-certificates >/dev/null 2>&1; then
            if [[ -f "${WorkingDirectory}/${ROOTCERT}" ]] >/dev/null 2>&1; then
                # cert name
                cp ${WorkingDirectory}/${ROOTCERT} /etc/pki/ca-trust/source/anchors/
                update-ca-trust enable
                update-ca-trust extract force
                PCE_REACHABILITY_LOCAL_CHECK
            else
                echo "$(date) ERROR: ${ROOTCERT} is not in the directory." | tee -a ${LogFile}
            fi
        else
            echo "$(date) ERROR: Unable to install the missing certs due to ca-certificates package is missing." | tee -a ${LogFile}
            PCE_REACHABILITY_LOCAL_CHECK
        fi
    fi

    if [[ "${certinstall}" == 1 ]] && [[ "${OSrelease}" =~ ^(5)$ ]]; then
        if [[ -f /etc/pki/tls/certs/ca-bundle.crt ]] >/dev/null 2>&1; then
            if [[ -f "${WorkingDirectory}/${ROOTCERT}" ]] >/dev/null 2>&1; then
                # cert name
                echo "$(date) NOFITY: Backup existing ca-bundle.crt to ${WorkingDirectory} and installing cert." | tee -a ${LogFile}
                cp /etc/pki/tls/certs/ca-bundle.crt ${WorkingDirectory}/
                cat ${WorkingDirectory}/${ROOTCERT} >>/etc/pki/tls/certs/ca-bundle.crt
                PCE_REACHABILITY_LOCAL_CHECK
            else
                echo "$(date) ERROR: ${ROOTCERT} is not in the directory." | tee -a ${LogFile}
            fi
        else
            echo "$(date) ERROR$: Unable to install the missing certs due to ca-bundle directory is not exist." | tee -a ${LogFile}
            PCE_REACHABILITY_LOCAL_CHECK
        fi
    fi
}

# Check if workload can resolve port 8443, expect a HTTP 200 return.
function PCE_8443_PORT_CHECK() {
    curl -I https://${PCEFQDN}:${PCEPORT} -k --max-time 30 &>${WorkingDirectory}/_illumio_8443check.log
    grep -q '200 OK' ${WorkingDirectory}/_illumio_8443check.log
    if [[ "${?}" != 0 ]]; then
        echo "$(date) ERROR: Workload cannot reaching ${PCEFQDN} management port ${PCEPORT}, check \"_illumio_8443check.log\"." | tee -a ${LogFile}
        let fail++
    fi
}

# Check if workload can resolve port 8444, expect a curl 52 response as empty reply from PCE.
function PCE_8444_PORT_CHECK() {
    curl -I https://${PCEFQDN}:${PCEPORT2} -k --max-time 30 &>${WorkingDirectory}/_illumio_8444stdout.log
    awk -F 'curl' '{print $2}' ${WorkingDirectory}/_illumio_8444stdout.log | grep 52 >/dev/null
    if [[ "${?}" != 0 ]]; then
        echo "$(date) ERROR: Workload cannot reaching ${PCEFQDN} port ${PCEPORT2}, check \"_illumio_8444stdout.log\"." | tee -a ${LogFile}
        let fail++
    fi
}

# PCE pairing job only for pairing script.
function RHEL_CENTOS_VEN_INSTALL_PCEBASEDPAIRING() {
    rpmOutput=${WorkingDirectory}/_illumio_rpminstallresult.log
    rpmError=${WorkingDirectory}/_illumio_rpmerrorinstall.log
    if [[ "${fail}" == 0 ]]; then
        sleep 5
        echo "$(date) Proceed for VEN installation..." | tee -a ${LogFile}
        if [[ "${PairStatus}" == 'unpaired' ]]; then
            currentVer=$(/opt/illumio_ven/illumio-ven-ctl version)
            echo "$(date) VEN ${currentVer} already installed but it is unpaired." | tee -a ${LogFile}
            echo "$(date) Proceed for removing the VEN and installing with the targeted VEN version." | tee -a ${LogFile}
            /opt/illumio_ven/illumio-ven-ctl unpair open >$rpmOutput 2>$rpmError
            eval ${PairingScript} >$rpmOutput 2>$rpmError
            rpmState=${?}
            PAIRING_STATUS_CHECK
        elif [[ "${pairing182}" != 0 ]]; then
            echo "$(date) This workload only supported by VEN version 18.2, installing..." | tee -a ${LogFile}
            eval ${PairingScript182} >$rpmOutput 2>$rpmError
            rpmState=${?}
            PAIRING_STATUS_CHECK
        else
            eval ${PairingScript} >$rpmOutput 2>$rpmError
            rpmState=${?}
            PAIRING_STATUS_CHECK
        fi
    else
        echo "$(date) ERROR: Aborting VEN installation. Please check '_illumio_veninstall.log', there are dependencies missing." | tee -a ${LogFile}
        TARLOGS_CLEANUP
        exit 1
    fi
}

# Status check after pairing.
function PAIRING_STATUS_CHECK() {
    if [[ -f "${IllumioAgentId}" ]] && [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]; then
        currentVer=$(/opt/illumio_ven/illumio-ven-ctl version)
        echo "$(date) VEN PACKAGE ${currentVer} Installed Successfully." | tee -a ${LogFile}
        TARLOGS_CLEANUP
        exit 1
    else
        echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}
        TARLOGS_CLEANUP
        exit 1
    fi
}

#############################################################################

# Job begin
# Check if the executer is root user or not before proceed
if [[ "$(id -u)" != "0" ]]; then
    echo "$(date) ERROR: The script must be run as root, aborting." | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
else
    cd $WorkingDirectory
    touch ${LogFile} && chmod 644 ${LogFile}
    echo "$(date) VEN Installation task - Job begin..." | tee -a ${LogFile}
    # Define an initial fail bit, this decides whether the script installs the VEN or not in the later stage.
    fail=0
    certinstall=0
    pairing182=0
fi

if [[ -f "/etc/redhat-release" ]]; then
    RHEL_CENTOS_OS_CHECK
fi

VEN_CURRENT_STATUS_CHECK
VEN_DIR_PRE_CHECK
DISK_SPACE_CHECK
RHEL_CENTOS_PACKAGES_CHECK
PCE_FQDN_CHECK
IPTABLES_USAGE_CHECK
NFT_USAGE_CHECK
PCE_REACHABILITY_LOCAL_CHECK
PCE_8443_PORT_CHECK
PCE_8444_PORT_CHECK

if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ ${PCEBasedPairing} == 'YES' ]]; then
    RHEL_CENTOS_VEN_INSTALL_PCEBASEDPAIRING
fi

exit 0
