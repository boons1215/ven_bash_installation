#!/usr/bin/env bash

# Created by: Siew Boon Siong
# Updated: Jan-25-2021
#
# History:
# Oct-15-2019 Added NFT support
# Oct-18-2019 Added option to choose if pairing with PCE-based pairing script or standalone
# Oct-26-2019 Added VEN version into variable
# Jan-05-2020 Added cert installed function
# Jan-25-2021 Updated scripts to support 19.3.4VEN installation due to filename changed
#
# Unattended install script for Linux - RHEL, CentOS
# Rules are:
# - if any required package/dependencies missing, logs the info but not installing Illumio VEN
# - if the workload can't reaching the PCE or can't resolve PCE FQDN, logs the info but not installing Illumio VEN
# - it must be run as root and place under /var/tmp
# - Create 7 logs: _illumio_veninstall.log, _illumio_rpminstallresult.log, _illumio_rpmerrorinstall.log, _illumio_pairingerror.log,
# _illumio_certcheck.log, _illumio_8443check.log, _illumio_8444stderr.log
#
# When pairing failed, VEN software will be uninstalled, and generate illumio_ven_report.tgz which combining
# /opt/illumio_ven* and logs for analysis.

# Flexible variables adjust when needed
PCEFQDN='mseg.sgp.com'
PCEPORT='8443'
PCEPORT2='8444'
PCEIP='10.67.23.151'
PCEIP2='10.67.23.198'
# If only one DNS server, just fill the same IP into these 2 variables
DNS1='10.80.114.8'
DNS2='10.81.112.8'
ROOTCERT='ca-bundle.crt'

# Choose either using PCE-based pairing or standalone pairing
PCEBasedPairing='NO' # If using standalone pairing, turn 'YES' to 'NO'
PairingScript=''

# If using standalone pairing, please fill in the following. But if PCEBasedPairing variable = 'YES', these 2 lines will be ignored.
ActivationCode='143a28e37cdbbb9b364f8bccac650e4607ff5cd2ad906f36112ee1667cc39cb52215b0ea90de54bf6'
#VEN_VER='18.2.4-4528'
#VEN_VER='19.3.0-6104'
#VEN_VER='19.3.3-6328'
VEN_VER='19.3.4-6371'




####################################################
######## DO NOT MODIFY ANYTHING BELOW ##############
####################################################

InstallPath='/opt'
WorkingDirectory='/var/tmp/illumio'
LogFile='/var/tmp/illumio/_illumio_veninstall.log'
VENdiskUsageInMB='20'
IllumioVENctl='/opt/illumio_ven/illumio-ven-ctl'
IllumioVENdir='/opt/illumio_ven'
IllumioVENdatadir='/opt/illumio_ven_data'
IllumioActCfg='/opt/illumio_ven_data/etc/agent_activation.cfg'

txtred=$(tput setaf 1)
txtrst=$(tput sgr0)

# Unchanged variables
# For RHEL/CentOS VEN packages, for AMI as well
# RHEL/CentOS 5 not supported starting from 18.3 onwards
C5_32VENPackage="illumio-ven-${VEN_VER}.c5.i686.rpm"
C5_64VENPackage="illumio-ven-${VEN_VER}.c5.x86_64.rpm"
C6_32VENPackage="illumio-ven-${VEN_VER}.c6.i686.rpm"
C6_64VENPackage="illumio-ven-${VEN_VER}.c6.x86_64.rpm"
C7_64VENPackage="illumio-ven-${VEN_VER}.c7.x86_64.rpm"
C8_64VENPackage="illumio-ven-${VEN_VER}.c8.x86_64.rpm"

VenCurrentVer=`/opt/illumio_ven/illumio-ven-ctl version`
#
# tar /opt/illumio_ven* and 9 logs: _illumio_veninstall.log, _illumio_rpminstallresult.log, _illumio_rpmerrorinstall.log, _illumio_pairingerror.log,
# _illumio_opensslstdout.log, _illumio_opensslstderr.log, _illumio_8443stdout.log, _illumio_8443stderr.log, _illumio_8444stderr.log
# Then, remove bash shell script and VEN installer which copied over.

function TARLOGS_CLEANUP {
  date=$(date '+%Y-%m-%d')
cd ${WorkingDirectory} && mkdir -p job
  cp -R ${IllumioVENdir} ${IllumioVENdatadir} ${WorkingDirectory}/_illumio_*.log /var/log/illumio*log ${WorkingDirectory}/job
  tar -rf ${WorkingDirectory}/${date}_${HOSTNAME}_${OS}_illumioreport.tgz job
  # rm -rf ${WorkingDirectory}/_illumio_*.log
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
    if [[ "${OS}" == "${i}"  ]]
    then
      echo "$(date) Workload OS: ${OSoutput}"  | tee -a ${LogFile}
    fi
  done

  if [[ "${OS}" =~ ^(RedHat|CentOS)$ ]]
  then
    echo "$(date) Workload Architecture: $(arch)"  | tee -a ${LogFile}
  fi
}

# RHEL & CENTOS OS check
function RHEL_CENTOS_OS_CHECK() {
  # Check if the OS supported. If it is not supported or out of the list, job exit.
  # The length of output of /etc/redhat-release differents in each OS , setting 2 variable and trying to catch all.
  VEN_COMPARE=`echo ${VEN_VER} | cut -d$'-' -f1 | awk -F. '{print $1""$2}'`
  OSrelease=NotFound
  if [[ "${OSrelease}" == 'NotFound' ]]
  then
    redHatRelease=/etc/redhat-release
    OSoutput=$(cat /etc/redhat-release)
    if test -f "${redHatRelease}"
    then
      if grep -q 'Red Hat' ${redHatRelease}
      then
        echo "$(date) RedHat Detected." | tee -a ${LogFile}
        OS='RedHat'
        OSrelease=$(cat ${redHatRelease} | rev | cut -d'(' -f 2 | rev | awk 'NF>1{print $NF}' | cut -d$'.' -f1)
        OSminor=$(cat ${redHatRelease} | rev | cut -d'(' -f 2 | rev | awk 'NF>1{print $NF}' | cut -d$'.' -f2)
      fi
      if grep -q 'CentOS' ${redHatRelease}
      then
        echo "$(date) CentOS Detected." | tee -a ${LogFile}
        OS='CentOS'
        OSrelease=$(cat ${redHatRelease} | rev | cut -d'(' -f 2 | rev | awk 'NF>1{print $NF}' | cut -d$'.' -f1)
        OSminor=$(cat ${redHatRelease} | rev | cut -d'(' -f 2 | rev | awk 'NF>1{print $NF}' | cut -d$'.' -f2)
      fi
    fi
  fi
  if [[ "${OSrelease}" == '5' ]] && [[ "${OSminor}" =~ ^(5|6|7|8|9|10|11)$ ]] && [[ "${VEN_COMPARE}" -lt 183 ]]
  then
    IPAdd=$(/sbin/ip addr | grep inet | grep -v -E '127.0.0|inet6' | cut -d$'/' -f1 | awk '{print $2}' ORS=' ')
    WORKLOAD_INFO_STATEMENT
  elif [[ "${OSrelease}" == '6' ]] && [[ "${OSminor}" =~ ^(2|3|4|5|6|7|8|9|10)$ ]]
  then
    IPAdd=$(hostname -I)
    WORKLOAD_INFO_STATEMENT
  elif [[ "${OSrelease}" == '7' ]] && [[ "${OSminor}" -lt 10 ]]
  then
    IPAdd=$(hostname -I)
    WORKLOAD_INFO_STATEMENT
  elif [[ "${OSrelease}" == '8' ]] && [[ "${VEN_COMPARE}" -ge 182 ]]
  then
    IPAdd=$(hostname -I)
    WORKLOAD_INFO_STATEMENT
  elif [[ "${OSrelease}" == 'NotFound' ]]
  then
    echo "$(date) ERROR: Could not determine the operating system, aborting..." | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
  else
    echo "$(date) ERROR: This workload is NOT supported by VEN ${VEN_VER} (check the major and minor OS), aborting VEN installation." | tee -a ${LogFile}
    echo "$(date) Workload OS: ${OSoutput}"  | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
  fi
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

# Set generic VEN path/directory check
function VEN_PATH_PRE_CHECK() {
  if [[ -f "${IllumioVENctl}" ]] >/dev/null 2>&1; then
      PairStatus=$(${IllumioVENctl} status | grep state 2>/dev/null | head -n 1 | cut -d$' ' -f3)
      VENVersion=$(cat ${IllumioVENdir}/etc/agent_version 2>/dev/null | head -n 1 | cut -d$' ' -f3)
      PCEName=$(cat ${IllumioVENdatadir}/etc/agent_activation.cfg 2>/dev/null | grep master | head -n 1 | cut -d$':' -f2)
  fi
}

# Check if the workload has already paired or not
function VEN_CURRENT_STATUS_CHECK() {
VEN_PATH_PRE_CHECK
# Check if workload has already paired. If no status found, proceed for next step, else job exit.
if [[ "${PairStatus}" == 'unpaired' ]]
then
  echo "$(date) NOTIFY: VEN version ${VENVersion} is in unpaired mode, proceed for next step." | tee -a ${LogFile}
fi

venStatus=('illuminated' 'enforced' 'idle')
for i in ${venStatus[*]}; do
  if [[ -f ${IllumioVENctl} ]] && [[ "${PairStatus}" == "${i}"  ]]
  then
    echo "$(date) NOTIFY: VEN version ${VENVersion} has already paired as ${i} mode with${PCEName}, aborting VEN installation." | tee -a ${LogFile}
    if [[ ${VenCurrentVer} != ${VEN_VER} ]]
    then
      RHEL_CENTOS_VEN_INSTALL_STANDALONE
    else
      TARLOGS_CLEANUP
      exit 1
    fi
  fi
done
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

# Check if the workload has correct DNS server settings, DBS has 2 DNS servers
function DNS_SETTING_CHECK() {
  DNSServer1=$(grep name /etc/resolv.conf | grep ${DNS1} | cut -d$' ' -f2 | head -1)
  DNSServer2=$(grep name /etc/resolv.conf | grep ${DNS2} | cut -d$' ' -f2 | head -1)

  if [[ "${DNSServer1}" != "${DNS1}" ]]
  then
    echo "$(date) ERROR: Missing first ${DNS1} DNS settings in resolve file." | tee -a ${LogFile}
    let fail++
  else
    echo "$(date) First DNS settings for ${DNS1} checked." | tee -a ${LogFile}
  fi
  if [[ "${DNSServer2}" != "${DNS2}" ]]
  then
    echo "$(date) ERROR: Missing second ${DNS2} DNS settings in resolve file." | tee -a ${LogFile}
    let fail++
  else
    echo "$(date) Second DNS settings for ${DNS2} checked." | tee -a ${LogFile}
  fi
}

# Check if the workload can resolve PCE FQDN
function PCE_FQDN_CHECK() {
  PCEFqdnResolve=$(nslookup ${PCEFQDN} | grep ${PCEIP}| tail -1 | cut -d$' ' -f2)
  PCEFqdnResolve2=$(nslookup ${PCEFQDN} | grep ${PCEIP2}| tail -1 | cut -d$' ' -f2)

  if [[ "${PCEFqdnResolve}" != "${PCEIP}" ]]
  then
    if [[ "${PCEFqdnResolve2}" != "${PCEIP2}" ]]
    then
      echo "$(date) ERROR: Unable to resolve ${PCEFQDN} FQDN with IP." | tee -a ${LogFile}
      let fail++
    fi
  fi
}

# Check if required packages exist for VEN.
function RHEL_CENTOS_PACKAGES_CHECK() {
  # for RHEL/CentOs 5,6,7,8 check on the package
  if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ "${OSrelease}" =~ ^(5|6|7|8)$ ]]; then
      rpmPackageCheck=('libcap' 'gmp' 'bind-utils' 'curl' 'sed')
      for package in ${rpmPackageCheck[*]}; do
          if ! rpm -q ${package} >/dev/null 2>&1; then
            if [[ "${recheckPackage}" == 0 ]]; then
              rm -rf /var/run/yum.pid >/dev/null
              yum -y install ${package} &>/dev/null
              let packageMissing++
            else 
              echo "$(date) ERROR: ${package} package is missing and failed to install, please check repo." | tee -a ${LogFile}
              let fail++
            fi
          fi
      done
  fi

# for RHEL/CentOs 5,6,7 check on the package

  if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ "${OSrelease}" =~ ^(5|6|7)$ ]]; then
      rpmFileCheck=('iptables')
      for package in ${rpmFileCheck[*]}; do
          if [[ -f /usr/bin/${package} || -f /bin/${package} || -f /sbin/${package} || -f /usr/sbin/${package} ]]; then
              let checkIptableVer++
              echo "$(date) ${package} package installed." >/dev/null
          elif [[ "${recheckPackage}" == 0 ]]; then
              rm -rf /var/run/yum.pid >/dev/null
              yum -y install iptables &>/dev/null
              let packageMissing++
          else
              echo "$(date) ERROR: ${package} package is missing and failed to install, please check repo." | tee -a ${LogFile}
              let fail++
          fi
      done
  fi

  if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ "${OSrelease}" =~ ^(5|6|7)$ ]] && [[ "${checkIptableVer}" == 1 ]]; then
      iptablesVer=`iptables -V`
      currentver=`rpm -qa iptables | cut -d$'.' -f1-3 | awk -Fs- '{print $2}'`
      requiredver="1.4.7-16"
      if [ "$(printf '%s\n' "${requiredver}" "${currentver}" | sort -V | head -n1)" = "${requiredver}" ]; then 
          echo "$(date) iptables package installed." >/dev/null
      elif [[ "${recheckPackage}" == 0 ]]; then
          echo "$(date) Current iptables ${iptablesVer} version does not meet the minimum required version, updating..." | tee -a ${LogFile}
          rm -rf /var/run/yum.pid >/dev/null
          yum -y install iptables &>/dev/null
          let packageMissing++
      else
          echo "$(date) ERROR: iptables version still not meet the requirement after installed, please check repo." | tee -a ${LogFile}
          let fail++
      fi
  fi

  if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ "${OSrelease}" =~ ^(5|6|7)$ ]]; then
      rpmFileCheck=('ip6tables')
      for package in ${rpmFileCheck[*]}; do
          if [[ -f /usr/bin/${package} || -f /bin/${package} || -f /sbin/${package} || -f /usr/sbin/${package} ]]; then
              echo "$(date) ${package} package installed." >/dev/null
          elif [[ "${recheckPackage}" == 0 ]]; then
              rm -rf /var/run/yum.pid >/dev/null
              yum -y remove iptables &>/dev/null
              yum -y install iptables &>/dev/null
              let packageMissing++
          else
              echo "$(date) ERROR: ${package} package is missing and failed to install, please check repo." | tee -a ${LogFile}
              let fail++
          fi
      done
  fi

  if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ "${OSrelease}" =~ ^(6|7)$ ]]; then
      rpmFileCheck=('ipset')
      for package in ${rpmFileCheck[*]}; do
          if [[ -f /usr/bin/${package} || -f /bin/${package} || -f /sbin/${package} || -f /usr/sbin/${package} ]]; then
              let checkIpsetVer++
              echo "$(date) ${package} package installed." >/dev/null
          elif [[ "${recheckPackage}" == 0 ]]; then
              rm -rf /var/run/yum.pid >/dev/null
              yum -y install ipset &>/dev/null
              let packageMissing++
          else
              echo "$(date) ERROR: ${package} package is missing and failed to install, please check repo." | tee -a ${LogFile}
              let fail++
          fi
      done
  fi

  if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ "${OSrelease}" =~ ^(6|7)$ ]] && [[ "${checkIpsetVer}" == 1 ]]; then
      currentVer=`rpm -qa ipset | cut -d$'.' -f1-2 | awk -Ft- '{print $2}'`
      requiredVer="6.11-4"
      if [ "$(printf '%s\n' "${requiredVer}" "${currentVer}" | sort -V | head -n1)" = "${requiredVer}" ]; then 
          echo "$(date) ipset package installed." >/dev/null
      elif [[ "${recheckPackage}" == 0 ]]; then
          echo "$(date) Current ipset ${currentVer} version does not meet the minimum required version, reinstalling..." | tee -a ${LogFile}
          rm -rf /var/run/yum.pid >/dev/null
          yum -y remove ipset &>/dev/null
          yum -y install ipset &>/dev/null
          let packageMissing++
      else
          echo "$(date) ERROR: ipset version still not meet the requirement after installed, please check repo." | tee -a ${LogFile}
          let fail++
      fi
  fi

  # for RHEL/CentOs 8 check on the package. If the VEN version is 18.2.4, we just need iptables and ipset. If the version is 19.3 and above, we just need nft. This is for 19.3 only.
  if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ "${OSrelease}" =~ ^(8)$ ]]; then
      rpmFileCheck=('nft')
      for package in ${rpmFileCheck[*]}; do
          if [[ ! -f /sbin/${package} ]] >/dev/null 2>&1; then
              if [[ "${recheckPackage}" == 0 ]]; then
                rm -rf /var/run/yum.pid >/dev/null
                yum -y install ${package} &>/dev/null
                let packageMissing++
              else
                echo "$(date) ERROR: ${package} package is missing and failed to install, please check repo." | tee -a ${LogFile}
                let fail++
              fi
          fi
      done
  fi

  # for RHEL/CentOs 6,7,8 check on the package
  if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ "${OSrelease}" =~ ^(6|7|8)$ ]]; then
      rpmPackageCheck=('net-tools' 'libnfnetlink' 'libmnl' 'ca-certificates')
      for package in ${rpmPackageCheck[*]}; do
          if ! rpm -q ${package} >/dev/null 2>&1; then
              if [[ "${recheckPackage}" == 0 ]]; then
                rm -rf /var/run/yum.pid >/dev/null
                yum -y install ${package} &>/dev/null
                let packageMissing++
              else
                echo "$(date) ERROR: ${package} package is missing and failed to install, please check repo." | tee -a ${LogFile}
                let fail++
              fi
          fi
      done
  fi

  if [[ "${packageMissing}" != 0 ]] && [[ "${secondCheck}" == 0 ]] ; then
    packageMissing=0
    recheckPackage=1
    checkIptableVer=0
    checkIpsetVer=0
    RHEL_CENTOS_PACKAGES_CHECK
  fi
}

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

# RESERVED: Check if related root and intermediate certs exist or not by matching cert name.
# If missing, just copy the cert over.
function PCE_REACHABILITY_LOCAL_CHECK {
  if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ "${OSrelease}" =~ ^(6|7|8)$ ]]
  then
    # For root cert
    curl -I https://${PCEFQDN}:${PCEPORT} --max-time 30 2>${WorkingDirectory}/_illumio_certcheck.log >/dev/null
    if [[ "${?}" == 0 ]]
    then
      echo "$(date) Workload can resolve ${PCEFQDN} cert." | tee -a ${LogFile}
    elif [[ "${?}" != 0 ]] && [[ "${certinstall}" == 1 ]]
    then
      echo "$(date) ERROR: Workload cannot resolve ${PCEFQDN} cert, check \"_illumio_certcheck.log\"." | tee -a ${LogFile}
      let fail++
    else
      echo "$(date) NOTIFY: Workload cannot resolve ${PCEFQDN} cert." | tee -a ${LogFile}
      echo "$(date) NOTIFY: Trying to install the SSL certs and retry." | tee -a ${LogFile}
      let certinstall++
      CERT_INSTALL
    fi
  fi

  if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ "${OSrelease}" =~ ^(5)$ ]]
  then
    echo "$(date) Checking if OpenSSL version is sufficient for RHEL/CentOS 5..." | tee -a ${LogFile}
    # Verify RHEL/CentOS 5 OpenSSL version
    OpenSSLRequired='openssl-0.9.8e-40.el5_11'
    CheckOpenSSLVer=`rpm -qa | grep -i ^openssl-`
    if [[ "${CheckOpenSSLVer}" != "${OpenSSLRequired}" ]]
    then
      echo "$(date) ERROR: OpenSSL version for RHEL/CentOS 5 requires ${OpenSSLRequired}." | tee -a ${LogFile}
      echo "$(date) ERROR: The OpenSSL current version is insufficient, please refer KB: https://my.illumio.com/apex/article?name=Error-message-asn1-encoding-routines-when-pairing-on-CentOS5-5" | tee -a ${LogFile}
      let fail++
    elif [[ "${CheckOpenSSLVer}" == "${OpenSSLRequired}" ]]
    then
      echo "$(date) OpenSSL version is sufficient..." | tee -a ${LogFile}
      echo "$(date) Checking if workload can resolve PCE cert..." | tee -a ${LogFile}
      curl -I https://${PCEFQDN}:${PCEPORT} --max-time 30 2>${WorkingDirectory}/_illumio_certcheck.log >/dev/null
      if [[ "${?}" == 0 ]]
      then
        echo "$(date) Workload can resolve ${PCEFQDN} cert." | tee -a ${LogFile}
      elif [[ "${?}" != 0 ]] && [[ "${certinstall}" == 1 ]]
      then
        echo "$(date) ERROR: Workload cannot resolve ${PCEFQDN} cert, check \"_illumio_certcheck.log\"." | tee -a ${LogFile}
        let fail++
      else
        echo "$(date) NOTIFY: Workload cannot resolve ${PCEFQDN} cert." | tee -a ${LogFile}
        echo "$(date) NOTIFY: Trying to install the SSL certs and retry." | tee -a ${LogFile}
        let certinstall++
        CERT_INSTALL
      fi
    fi
  fi
}

function CERT_INSTALL(){
  if [[ "${certinstall}" == 1 ]] && [[ "${OSrelease}" =~ ^(6|7|8)$ ]]
  then
    if rpm -q ca-certificates > /dev/null 2>&1
    then
      if [[ -f "${WorkingDirectory}/${ROOTCERT}" ]] > /dev/null 2>&1
      then
        # cert name
        cp ${WorkingDirectory}/${ROOTCERT} /etc/pki/ca-trust/source/anchors/
        #cp ${WorkingDirectory}/w01*DBSBank*CA.crt /etc/pki/ca-trust/source/anchors/
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

  if [[ "${certinstall}" == 1 ]] && [[ "${OSrelease}" =~ ^(5)$ ]]
  then
    if [[ -f /etc/pki/tls/certs/ca-bundle.crt ]] > /dev/null 2>&1
    then
      if [[ -f "${WorkingDirectory}/${ROOTCERT}" ]] > /dev/null 2>&1
      then
        # cert name
        echo "$(date) NOFITY: Backup existing ca-bundle.crt to ${WorkingDirectory}." | tee -a ${LogFile}
        cp /etc/pki/tls/certs/ca-bundle.crt ${WorkingDirectory}/
        cat ${WorkingDirectory}/${ROOTCERT} >> /etc/pki/tls/certs/ca-bundle.crt
        #cat ${WorkingDirectory}/w01*DBSBank*CA.crt >> /etc/pki/tls/certs/ca-bundle.crt
        PCE_REACHABILITY_LOCAL_CHECK
      else
        echo "$(date) ERROR: ${ROOTCERT} is not in the directory." | tee -a ${LogFile}
      fi
    else
      echo "$(date) ERROR: Unable to install the missing certs due to ca-bundle directory is not exist." | tee -a ${LogFile}
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


# If above jobs all pass and 'fail' bit is 0, proceed for install, else abort.
    # If choose for standalone installation version, here's the condition:
    # - if workload has already installed VEN, but unpaired, it will check if it is eligible for upgrade
    #     - if the existing version is older then the one that going to install, script tries to upgrade it
    #     - if the existing version is newer, script abort the upgrade step
    #     - if upgrade file, check logs
    # - if workload has not VEN installed
    #     - check if target VEN installer file found, if not, abort.
    # - once workload has installed the VEN, check if the installation success or not.
function RHEL_CENTOS_VEN_INSTALL_STANDALONE() {
  rpmOutput=${WorkingDirectory}/_illumio_rpminstallresult.log
  rpmError=${WorkingDirectory}/_illumio_rpmerrorinstall.log
  if [[ "${fail}" == 0 ]] && [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ ${PCEBasedPairing} == 'NO' ]]
  then
    sleep 5
    echo "$(date) Proceed for VEN installation..." | tee -a ${LogFile}
    if [[ "${OSrelease}" =~ ^(5|6)$ ]] && [[ "$(arch)" == 'i686' ]]
    then
      rpmVENfile="C${OSrelease}_32VENPackage"
      if [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]] && [[ "${PairStatus}" == 'unpaired' ]]
      then
        currentVer=`/opt/illumio_ven/illumio-ven-ctl version`
        echo "$(date) VEN ${currentVer} already installed." | tee -a ${LogFile}
      elif [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]] && [[ "${PairStatus}" != 'unpaired' ]]
      then
        currentVer=`/opt/illumio_ven/illumio-ven-ctl version`
        echo "$(date) VEN ${currentVer} already installed, looking for upgrade whenever possible." | tee -a ${LogFile}
        VEN_UPGRADE
      elif [[ ! -d "${IllumioVENdir}" ]] && [[ ! -d "${IllumioVENdatadir}" ]]
      then
        rpm -ivh ${WorkingDirectory}/${!rpmVENfile} >$rpmOutput 2>$rpmError
        rpmState=${?}
        PAIRING_STATUS_CHECK
      fi
    fi

    if [[ "${OSrelease}" =~ ^(5|6|7|8)$ ]] && [[ "$(arch)" == 'x86_64' ]]
    then
      rpmVENfile="C${OSrelease}_64VENPackage"
      if [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]] && [[ "${PairStatus}" == 'unpaired' ]]
      then
        currentVer=`/opt/illumio_ven/illumio-ven-ctl version`
        echo "$(date) VEN ${currentVer} already installed." | tee -a ${LogFile}
      elif [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]] && [[ "${PairStatus}" != 'unpaired' ]]
      then
        currentVer=`/opt/illumio_ven/illumio-ven-ctl version`
        echo "$(date) VEN ${currentVer} already installed, looking for upgrade whenever possible." | tee -a ${LogFile}
        VEN_UPGRADE
      elif [[ ! -d "${IllumioVENdir}" ]] && [[ ! -d "${IllumioVENdatadir}" ]]
      then
        rpm -ivh ${WorkingDirectory}/${!rpmVENfile} >$rpmOutput 2>$rpmError
        rpmState=${?}
        PAIRING_STATUS_CHECK
      fi
    fi
  else
    echo "$(date) ERROR: Aborting VEN installation. Please check '_illumio_veninstall.log', there are dependencies missing." | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
  fi
}

function PAIRING_STATUS_CHECK() {
  if [[ ! -f "${WorkingDirectory}"/"${!rpmVENfile}" ]] && [[ ${PCEBasedPairing} == 'NO' ]]
  then
    echo "$(date) ERROR: VEN PACKAGE ${!rpmVENfile} package not found, aborting installation." | tee -a ${LogFile}
    let fail++
    TARLOGS_CLEANUP
    exit 1
  elif [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
  then
  currentVer=`/opt/illumio_ven/illumio-ven-ctl version`
  echo "$(date) VEN PACKAGE ${currentVer} Installed Successfully." | tee -a ${LogFile}
  elif [[ "${rpmState}" != 0 ]] && [[ ! -d "${IllumioVENdir}" ]]
  then
    echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
  else
    echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}
    TARLOGS_CLEANUP
  exit 1
  fi
}

# If above jobs all pass and 'fail' bit is 0, proceed for install, else abort.
    # If choose for PCE-based pairing installation version, here's the condition:
    # - if workload has already installed VEN, but unpaired:
    #     - script will remove the existing one then reinstall the target
    # - if workload has already paired with PCE,
    #     - either it is older or newer version, script won't do anything but notify.
    # - if workload has not VEN installed, install.
    # - once workload has installed the VEN, check if the installation success or not.
function RHEL_CENTOS_VEN_INSTALL_PCEBASEDPAIRING() {
  rpmOutput=${WorkingDirectory}/_illumio_rpminstallresult.log
  rpmError=${WorkingDirectory}/_illumio_rpmerrorinstall.log
  if [[ "${fail}" == 0 ]] && [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ ${PCEBasedPairing} == 'YES' ]]
  then
    sleep 5
    echo "$(date) Proceed for VEN installation..." | tee -a ${LogFile}
    if [[ ! -d "${IllumioVENdir}" ]] && [[ ! -d "${IllumioVENdatadir}" ]]
    then
      eval ${PairingScript} >$rpmOutput 2>$rpmError
      rpmState=${?}
      PAIRING_STATUS_CHECK
    elif [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]] && [[ "${PairStatus}" == 'unpaired' ]]
    then
      currentVer=`/opt/illumio_ven/illumio-ven-ctl version`
      echo "$(date) VEN ${currentVer} already installed but it is unpaired." | tee -a ${LogFile}
      echo "$(date) Proceed for removing the VEN and installing with the targeted VEN version." | tee -a ${LogFile}
      /opt/illumio_ven/illumio-ven-ctl unpair open  >$rpmOutput 2>$rpmError
      eval ${PairingScript} >$rpmOutput 2>$rpmError
      rpmState=${?}
      PAIRING_STATUS_CHECK
    elif [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]] && [[ -f "${IllumioActCfg}" ]]
    then
      currentVer=`/opt/illumio_ven/illumio-ven-ctl version`
      echo "$(date) VEN ${currentVer} already installed and it is paired." | tee -a ${LogFile}
      echo "$(date) Abort the script." | tee -a ${LogFile}
      TARLOGS_CLEANUP
      exit 1
    fi
  else
    echo "$(date) ERROR: Aborting VEN installation. Please check '_illumio_veninstall.log', there are dependencies missing." | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
  fi
}

# VEN upgrade, only applicable for standalone type of installation for unpaired mode only
function VEN_UPGRADE() {
  echo "$(date) Checking if workload requires a VEN upgrade." | tee -a ${LogFile}
  currentVer=`/opt/illumio_ven/illumio-ven-ctl version`
  if [[ ${currentVer} != ${VEN_VER} ]]
  then
    rpm -Uvh ${WorkingDirectory}/${!rpmVENfile} >$rpmOutput 2>$rpmError
    currentVer=`/opt/illumio_ven/illumio-ven-ctl version`
    if [[ ${currentVer} == ${VEN_VER} ]]
    then
      echo "$(date) VEN successfully upgraded to ${currentVer}." | tee -a ${LogFile}
    else
      echo "$(date) Current VEN ${currentVer} has not upgraded, either the current version is higher or check logs for detail." | tee -a ${LogFile}
    fi
  fi
}

# VEN Installation
function VEN_PAIRING() {
  # Pairing the VEN workload with PCE
  if [[ ${PCEBasedPairing} == 'YES' ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]] && [[ -f "${IllumioActCfg}" ]]
  then
    currentVer=`/opt/illumio_ven/illumio-ven-ctl version`
    echo "$(date) VEN ${currentVer} already installed and it is paired" | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
  elif [[ ${PCEBasedPairing} == 'NO' ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
  then
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
      echo "$(date) ERROR: Pairing with PCE - ${PCEFQDN} failed, removing the VEN and reverting to previous iptables stage." | tee -a ${LogFile}
      echo "$(date) Search for NOTIFY and ERROR in the '_illumio_veninstall.log' for more info." | tee -a ${LogFile}
      echo "$(date)" >> ${ErrorPairingVEN}
      sleep 5
      ${IllumioVENctl} unpair saved 1>>${ErrorPairingVEN} 2>>${ErrorPairingVEN}
      echo "$(date)" >> ${ErrorPairingVEN}
      let fail++
      rpm -e illumio-ven 1>>${ErrorPairingVEN} 2>>${ErrorPairingVEN}
      TARLOGS_CLEANUP
      exit 1
    fi
  fi
}


#############################################################################


# Job begin
# Check if the executer is root user or not before proceed
if [[ "$(id -u)" != "0"  ]]
then
  echo "$(date) ERROR: The script must be run as root, aborting." | tee -a ${LogFile}
  TARLOGS_CLEANUP
  exit 1
else
mkdir -p $WorkingDirectory
  cd $WorkingDirectory
  touch ${LogFile} && chmod 644 ${LogFile}
  echo "$(date) VEN Installation task - Job begin..." | tee -a ${LogFile}
  # Define an initial fail bit, this decides whether the script installs the VEN or not in the later stage.
  fail=0
  certinstall=0
fi

# OS check
if [[ -f "/etc/redhat-release" ]]
then
  RHEL_CENTOS_OS_CHECK
fi

VEN_CURRENT_STATUS_CHECK
VEN_DIR_PRE_CHECK
DISK_SPACE_CHECK
# DNS_SETTING_CHECK
# PCE_FQDN_CHECK

if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]]
then
  packageMissing=0
  recheckPackage=0
  secondCheck=0
  checkIptableVer=0
  checkIpsetVer=0
  RHEL_CENTOS_PACKAGES_CHECK
fi

IPTABLES_USAGE_CHECK
NFT_USAGE_CHECK
PCE_REACHABILITY_LOCAL_CHECK
PCE_8443_PORT_CHECK
PCE_8444_PORT_CHECK

if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ ${PCEBasedPairing} == 'NO' ]]
then
  RHEL_CENTOS_VEN_INSTALL_STANDALONE
elif [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ ${PCEBasedPairing} == 'YES' ]]
then
  RHEL_CENTOS_VEN_INSTALL_PCEBASEDPAIRING
fi

VEN_PAIRING
exit 0
