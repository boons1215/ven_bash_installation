#!/usr/bin/env bash

# Script name: linux_veninstall.sh
# Created by: Siew Boon Siong
# Updated: Oct-05-2019
#
# Unattended install script for Linux - RHEL, CentOS, Ubuntu, SLSE, Debian, Amazon AMI
# Rules are:
# - if any required package/dependencies missing, logs the info but not installing Illumio VEN
# - if the workload can't reaching the PCE or can't resolve PCE FQDN, logs the info but not installing Illumio VEN
# - it must be run as root and place under /var/tmp
# - Create 9 logs: illumio_veninstall.log, illumio_rpminstallresult.log, illumio_rpmerrorinstall.log, illumio_pairingerror.log,
# illumio_opensslstdout.log, illumio_opensslstderr.log, illumio_8443stdout.log, illumio_8443stderr.log, illumio_8444stdout.log
#
# When pairing failed, VEN software will be uninstalled, and generate illumio_ven_report.tgz which combining
# /opt/illumio_ven* and logs for analysis.

# Flexible variables adjust when needed
PCEFQDN='pce.illumioeval.com'
PCEPORT='8443'
PCEPORT2='8444'
PCEIP='172.16.2.10'
PCEIP2='172.16.2.11'
# If only one DNS server, just fill the same IP into these 2 variables
DNS1='172.16.3.95'
DNS2='172.16.3.95'
#RootCert='root.illumioeval.com.crt'
#IntermediateCert='intermediate.illumioeval.com.crt'
#DigiCert='DigiCertHighAssuranceEVRootCA.crt'
#VeriSignCert='vsign-universal-root.crt'
ActivationCode='1c8e6de82892b4736b905d536ca62886637ea53696bb043f50e9d6a2e60d2cbc84f559ccd79e89634'

## For Production
#PCEFQDN='mseg.sgp.com'
#PCEIP='10.67.23.198'
#PCEIP2='10.67.23.151'
#DNS1='10.67.1.58'
#DNS2='10.67.1.64'
#RootCert=
#IntermediateCert=

## For UAT environment
#PCEFQDN='mseg.uat.com'
#PCEIP='10.91.138.98'
#PCEIP2='10.91.138.98'
#DNS1='10.67.1.58'
#DNS2='10.67.1.64'
#RootCert=
#IntermediateCert=

# For RHEL/CentOS VEN packages, for AMI as well
C5_32VENPackage='illumio-ven-18.2.4-4520.c5.i686.rpm'
C5_64VENPackage='illumio-ven-18.2.4-4520.c5.x86_64.rpm'
C6_32VENPackage='illumio-ven-18.2.4-4520.c6.i686.rpm'
C6_64VENPackage='illumio-ven-18.2.4-4520.c6.x86_64.rpm'
C7_64VENPackage='illumio-ven-18.2.4-4520.c7.x86_64.rpm'
C8_64VENPackage='illumio-ven-18.2.4-4520.c8.x86_64.rpm'

# For Ubuntu VEN packages
U12_64VENPackage='illumio-ven-18.2.4-4520.u12.amd64.deb'
U12_32VENPackage='illumio-ven-18.2.4-4520.u12.i386.deb'
U14_64VENPackage='illumio-ven-18.2.4-4520.u14.amd64.deb'
U14_32VENPackage='illumio-ven-18.2.4-4520.u14.i386.deb'
U16_64VENPackage='illumio-ven-18.2.4-4520.u16.amd64.deb'
U16_32VENPackage='illumio-ven-18.2.4-4520.u16.i386.deb'

# For Debian VEN packages
D7_32VENPackage='illumio-ven-18.2.4-4520.d7.i386.deb'
D7_64VENPackage='illumio-ven-18.2.4-4520.d7.amd64.deb'

# For SLES VEN pacakges
S11_VENPackage='illumio-ven-18.2.4-4520.s11.x86_64.rpm'
S12_VENPackage='illumio-ven-18.2.4-4520.s12.x86_64.rpm'

# Unchanged variables
InstallPath='/opt'
WorkingDirectory='/var/tmp'
LogFile='/var/tmp/illumio_veninstall.log'
VENdiskUsageInMB='20'
IllumioVENctl='/opt/illumio_ven/illumio-ven-ctl'
IllumioVENdir='/opt/illumio_ven'
IllumioVENdatadir='/opt/illumio_ven_data'
IllumioActCfg='/opt/illumio_ven_data/etc/agent_activation.cfg'
Domain='illumioeval'

####################################################
######## DO NOT MODIFY ANYTHING BELOW ##############
####################################################
#
# tar /opt/illumio_ven* and 9 logs: illumio_veninstall.log, illumio_rpminstallresult.log, illumio_rpmerrorinstall.log, illumio_pairingerror.log,
# illumio_opensslstdout.log, illumio_opensslstderr.log, illumio_8443stdout.log, illumio_8443stderr.log, illumio_8444stderr.log
# Then, remove bash shell script and VEN installer which copied over.
function TARLOGS_CLEANUP {
  date=$(date '+%Y-%m-%d')
  if [[ "${fail}" == 0 ]]
  then
    tar czf ${WorkingDirectory}/${date}_${HOSTNAME}_${OS}_illumioreport_SUCCESS.tgz ${IllumioVENdir} ${IllumioVENdatadir} ${WorkingDirectory}/illumio_*.log
  else
    tar czf ${WorkingDirectory}/${date}_${HOSTNAME}_${OS}_illumioreport_FAILED.tgz ${IllumioVENdir} ${IllumioVENdatadir} ${WorkingDirectory}/illumio_*.log
  fi

#  find ${WorkingDirectory} -type f \( -name "linux_veninstall.sh" -o -name "*illumio-ven*" -o -name "*VEN*msi" -o -name "illumio_*.log" \) | xargs /bin/rm -f
} &> /dev/null

# Generic statements for workload info
function WORKLOAD_INFO_STATEMENT() {
  echo "$(date) Workload Hostname: ${HOSTNAME}" | tee -a ${LogFile}
  echo "$(date) This workload is supported by VEN." | tee -a ${LogFile}
  echo "$(date) Workload IP(s): ${IPAdd}" | tee -a ${LogFile}

  osVersion=('RedHat' 'CentOS' 'Ubuntu' 'Debian' 'Sles' 'Ami')
  for i in ${osVersion[*]}; do
    if [[ "${OS}" == "${i}"  ]]
    then
      echo "$(date) Workload OS: ${OSoutput}"  | tee -a ${LogFile}
    fi
  done

  if [[ "${OS}" =~ ^(Sles|Ami)$ ]]
  then
    arch=$(getconf LONG_BIT)
    echo "$(date) Workload Architecture: ${arch}"  | tee -a ${LogFile}
  elif [[ "${OS}" =~ ^(RedHat|CentOS|Ubuntu|Debian)$ ]]
  then
    echo "$(date) Workload Architecture: $(arch)"  | tee -a ${LogFile}
  fi
}

# RHEL & CENTOS OS check
function RHEL_CENTOS_OS_CHECK() {
  # Check if the OS supported. If it is not supported or out of the list, job exit.
  echo "$(date) Checking Operating System..." | tee -a ${LogFile}
  # The length of output of /etc/redhat-release differents in each OS , setting 2 variable and trying to catch all.
  OSrelease=NotFound
  OSrelease2=NotFound
  if [[ "${OSrelease}" == 'NotFound' ]] || [[ "${OSrelease2}" == 'NotFound' ]]
  then
    redHatRelease=/etc/redhat-release
    OSoutput=$(cat /etc/redhat-release)
    if test -f "${redHatRelease}"
    then
      if grep -q 'Red Hat' ${redHatRelease}
      then
        echo "$(date) RedHat Detected." | tee -a ${LogFile}
				OS='RedHat'
        OSrelease=$(cat ${redHatRelease} | awk '{print $7}' | cut -d$'.' -f1)
        OSrelease2=$(cat ${redHatRelease} | awk '{print $6}' | cut -d$'.' -f1)
        OSminor=$(cat ${redHatRelease} | awk '{print $7}' | cut -d$'.' -f2)
        Osminor2=$(cat ${redHatRelease} | awk '{print $6}' | cut -d$'.' -f2)
		  fi
		  if grep -q 'CentOS' ${redHatRelease}
      then
				echo "$(date) CentOS Detected." | tee -a ${LogFile}
				OS='CentOS'
				OSrelease=$(cat ${redHatRelease} | awk '{print $3}' | cut -d$'.' -f1)
				OSrelease2=$(cat ${redHatRelease} | awk '{print $4}' | cut -d$'.' -f1)
        OSminor=$(cat ${redHatRelease} | awk '{print $3}' | cut -d$'.' -f2)
				Osminor2=$(cat ${redHatRelease} | awk '{print $4}' | cut -d$'.' -f2)
		  fi
	  fi
  fi

  if [[ "${OSrelease}" == '5' || "${OSrelease2}" == '5' ]] && [[ "${OSminor}" =~ ^(5|6|7|8|9|10|11)$ || "${OSminor2}" =~ ^(5|6|7|8|9|10|11)$ ]]
  then
    IPAdd=$(/sbin/ip addr | grep inet | grep -v -E '127.0.0|inet6' | cut -d$'/' -f1 | awk '{print $2}' ORS=' ')
    WORKLOAD_INFO_STATEMENT
  elif [[ "${OSrelease}" == '6' || "${OSrelease2}" == '6' ]] && [[ "${OSminor}" =~ ^(2|3|4|5|6|7|8|9|10)$ || "${OSminor2}" =~ ^(2|3|4|5|6|7|8|9|10)$ ]]
  then
    IPAdd=$(hostname -I)
    WORKLOAD_INFO_STATEMENT
  elif [[ "${OSrelease}" == '7' || "${OSrelease2}" == '7' ]] && [[ "${OSminor}" -lt 7 || "${OSminor2}" -lt 7 ]]
  then
    IPAdd=$(hostname -I)
    WORKLOAD_INFO_STATEMENT
  elif [[ "${OSrelease}" == '8' || "${OSrelease2}" == '8' ]] && [[ "${OSminor}" == "" || "${OSminor2}" == "" ]]
  then
    IPAdd=$(hostname -I)
    WORKLOAD_INFO_STATEMENT
  elif [[ "${OSrelease}" == 'NotFound' ]] || [[ "${OSrelease2}" == 'NotFound' ]]
  then
    echo "$(date) ERROR: Could not determine the operating system, aborting..." | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
  else
    echo "$(date) ERROR: This workload is NOT supported by VEN (check the major and minor OS), aborting VEN installation." | tee -a ${LogFile}
    echo "$(date) Workload OS: ${OSoutput}"  | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
  fi
}

# Ubuntu OS check
function UBUNTU_OS_CHECK() {
  # Check if the OS supported. If it is not supported or out of the list, job exit.
  echo "$(date) Checking Operating System..." | tee -a ${LogFile}
  # The length of output of /etc/os-release differents in each OS , setting 2 variable and trying to catch all.
  OSrelease=NotFound
  if [[ "${OSrelease}" == 'NotFound' ]]
  then
    UbuntuRelease=/etc/os-release
    OSoutput=$(cat /etc/os-release | grep PRETTY | cut -d$'"' -f2)
    if test -f "${UbuntuRelease}"
    then
      if grep -q -i 'Ubuntu' ${UbuntuRelease} | head -n 1  | cut -d$'"' -f2
      then
        echo "$(date) Ubuntu Detected." | tee -a ${LogFile}
				OS='Ubuntu'
        OSrelease=`cat ${UbuntuRelease} | grep VERSION_ID | head -n 1  | cut -d$'"' -f2`
		  fi
	  fi
  fi

  if [[ "${OSrelease}" =~ ^(12.04|14.04|16.04|18.04)$ ]]
  then
    IPAdd=`hostname -I`
    WORKLOAD_INFO_STATEMENT
  elif [[ "${OSrelease}" == 'NotFound' ]]
  then
    echo "$(date) ERROR: Could not determine the operating system, aborting..." | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
  else
    echo "$(date) ERROR: This workload is NOT supported by VEN, aborting VEN installation." | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
  fi
}

# Debian OS check function
function DEBIAN_OS_CHECK() {
  # Check if the OS supported. If it is not supported or out of the list, job exit.
  echo "$(date) Checking Operating System..." | tee -a ${LogFile}
  # The length of output of /etc/os-release differents in each OS , setting 2 variable and trying to catch all.
  OSrelease=NotFound
  if [[ "${OSrelease}" == 'NotFound' ]]
  then
    DebianRelease=/etc/os-release
    OSoutput=$(cat /etc/debian_version)
    if [[ -f "${DebianRelease}" ]]
    then
      if grep -q -i 'debian' ${DebianRelease} | grep -i id | head -n 1 | cut -d$'=' -f2
      then
        echo "$(date) Debian Detected." | tee -a ${LogFile}
				OS='Debian'
        OSrelease=`cat ${DebianRelease} | grep ID | head -n 1  | cut -d$'=' -f2 | cut -d$'"' -f2`
		  fi
	  fi
  fi

  if [[ "${OSrelease}" =~ ^(7|8|9)$ ]]
  then
    IPAdd=`hostname -I`
    WORKLOAD_INFO_STATEMENT
  elif [[ "${OSrelease}" == 'NotFound' ]]
  then
    echo "$(date) ERROR: Could not determine the operating system, aborting..." | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
  else
    echo "$(date) ERROR: This workload is NOT supported by VEN, aborting VEN installation." | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
  fi
}

# SLES OS check function
function SLES_OS_CHECK() {
  # Check if the OS supported. If it is not supported or out of the list, job exit.
  echo "$(date) Checking Operating System..." | tee -a ${LogFile}
  # The length of output of /etc/os-release differents in each OS , setting 2 variable and trying to catch all.
  OSrelease=NotFound
  if [[ "${OSrelease}" == 'NotFound' ]]
  then
    SlesRelease=/etc/os-release
    OSoutput=`cat /etc/os-release | grep -i id | head -n 1 | cut -d$'=' -f2`
    if test -f "${SlesRelease}"
    then
      if grep -q -i 'sles' ${SlesRelease} | head -n 1  | cut -d$'"' -f2
      then
        echo "$(date) SLES Detected." | tee -a ${LogFile}
				OS='Sles'
        OSrelease=`cat ${SlesRelease} | grep VERSION_ID | head -n 1  | cut -d$'"' -f2`
		  fi
	  fi
  fi

  if [[ "${OSrelease}" =~ ^(11.3|11.4|12.1|12.2|12.3|12.4)$ ]]
  then
    IPAdd=`/sbin/ip addr | grep inet | grep -v -E '127.0.0|inet6' | cut -d$'/' -f1 | awk '{print $2}' ORS=' '`
    WORKLOAD_INFO_STATEMENT
  elif [[ "${OSrelease}" == 'NotFound' ]]
  then
    echo "$(date) ERROR: Could not determine the operating system, aborting..." | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
  else
    echo "$(date) ERROR: This workload is NOT supported by VEN, aborting VEN installation." | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
  fi
}

# AMI OS check function
function AMI_OS_CHECK() {
  # Check if the OS supported. If it is not supported or out of the list, job exit.
  echo "$(date) Checking Operating System..." | tee -a ${LogFile}
  # The length of output of /etc/os-release differents in each OS , setting 2 variable and trying to catch all.
  OSrelease=NotFound
  if [[ "${OSrelease}" == 'NotFound' ]]
  then
    AmiRelease=/etc/os-release
    OSoutput=`cat /etc/os-release | grep -i version | head -n 1 | cut -d$'=' -f2`
    if test -f "${AmiRelease}"
    then
      if grep -q -i 'amazon' ${AmiRelease} | head -n 1  | cut -d$'"' -f2
      then
        echo "$(date) Amazon AMI Detected." | tee -a ${LogFile}
				OS='Ami'
        OSrelease=`cat ${AmiRelease} | grep VERSION_ID | head -n 1  | cut -d$'"' -f2`
		  fi
	  fi
  fi

  if [[ "${OSrelease}" =~ ^(2018.03|2017.03|2016.09|2016.03)$ ]]
  then
    IPAdd=`/sbin/ip addr | grep inet | grep -v -E '127.0.0|inet6' | cut -d$'/' -f1 | awk '{print $2}' ORS=' '`
    WORKLOAD_INFO_STATEMENT
  elif [[ "${OSrelease}" == 'NotFound' ]]
  then
    echo "$(date) ERROR: Could not determine the operating system, aborting..." | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
  else
    echo "$(date) ERROR: This workload is NOT supported by VEN, aborting VEN installation." | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
  fi
}

# Check if workload has VEN installed before, or VEN software remained due to incomplete uninstallation.
function VEN_DIR_PRE_CHECK() {
  VenDirPath=$(ls -d "${IllumioVENdir}" 2>/dev/null | head -n 1 | cut -d$'/' -f3)
  VenDataDirPath=$(ls -d "${IllumioVENdatadir}" 2>/dev/null | head -n 1 | cut -d$'/' -f3)

  if [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
  then
    echo "$(date) NOTIFY: Both VEN directories exist, proceed for next step." | tee -a ${LogFile}
  elif [[ -d "${IllumioVENdir}" ]] && [[ ! -d "${IllumioVENdatadir}" ]]
  then
    echo "$(date) ERROR: Found VEN config directory but VEN data directory is missing, aborting VEN installation." | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
  elif [[ ! -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
  then
    echo "$(date) ERROR: Found VEN data directory but VEN config directory is missing, aborting VEN installation." | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
  elif [[ ! -d "${IllumioVENdir}" ]] && [[ ! -d "${IllumioVENdatadir}" ]]
  then
    echo "$(date) No VEN directories found, proceed for next step." | tee -a ${LogFile}
  else
    echo "$(date) ERROR: Other error found, please check whether VEN directory exist, aborting VEN installation." | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
  fi
}

# Set generic VEN path/directory check
function VEN_PATH_PRE_CHECK() {
  if [[ -f "${IllumioVENctl}" ]] > /dev/null 2>&1
  then
    PairStatus=$(${IllumioVENctl} status | grep state 2>/dev/null | head -n 1 | cut -d$' ' -f3)
    VENVersion=$(cat ${IllumioVENdir}/etc/agent_version 2>/dev/null | head -n 1 | cut -d$' ' -f3)
    PCEName=$(cat ${IllumioVENdatadir}/etc/agent_activation.cfg 2>/dev/null | grep master | head -n 1 | cut -d$':' -f2)
  else
    echo "$(date) No VEN status found, proceed for next check." | tee -a ${LogFile}
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
      TARLOGS_CLEANUP
      exit 1
    fi
  done
}

# Check if the workload has minimal 500MB disk space free after VEN installation
function DISK_SPACE_CHECK() {
  echo "$(date) Checking Disk Space..." | tee -a ${LogFile}
  DiskFreeLine=$(df -k ${InstallPath} -B M | grep "%" | tail -1 | awk -F'M ' '{print $3}')
  echo "$(date) VEN disk usage in MB minimum requirement = ${VENdiskUsageInMB}M" | tee -a ${LogFile}
  echo "$(date) Free disk space before install VEN = ${DiskFreeLine}M" | tee -a ${LogFile}

  let "DiskLeftAfterVENinstall = ${DiskFreeLine} - ${VENdiskUsageInMB}"
  echo "$(date) Disk left After VEN install = ${DiskLeftAfterVENinstall}M" | tee -a ${LogFile}

  if [[ "${DiskLeftAfterVENinstall}" -lt 1000 ]]
  then
    echo "$(date) NOTIFY: Disk free after install is less than 1GB, please be aware! Proceed for next step." | tee -a ${LogFile}
  elif [[ "${DiskLeftAfterVENinstall}" -lt 500 ]]
  then
    echo "$(date) ERROR: Disk free after install is less than 500M, aborting VEN installation." | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
  else
    echo "$(date) Proceed for next step." | tee -a ${LogFile}
  fi
}

# Check if the workload has correct DNS server settings, DBS has 2 DNS servers
function DNS_SETTING_CHECK() {
  echo "$(date) Checking DNS settings..." | tee -a ${LogFile}
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
  echo "$(date) Checking if workload can resolve PCE FQDN..." | tee -a ${LogFile}
  PCEFqdnResolve=$(nslookup ${PCEFQDN} | grep ${PCEIP}| tail -1 | cut -d$' ' -f2)
  PCEFqdnResolve2=$(nslookup ${PCEFQDN} | grep ${PCEIP2}| tail -1 | cut -d$' ' -f2)

  if [[ "${PCEFqdnResolve}" != "${PCEIP}" ]] && [[ "${PCEFqdnResolve2}" != "${PCEIP2}" ]]
  then
    echo "$(date) ERROR: Unable to resolve ${PCEFQDN} FQDN with both IP ${PCEIP} & ${PCEIP2}." | tee -a ${LogFile}
    let fail++
  elif [[ "${PCEFqdnResolve}" != "${PCEIP}" ]]
  then
    echo "$(date) ERROR: Unable to resolve ${PCEFQDN} FQDN with first IP ${PCEIP}." | tee -a ${LogFile}
    let fail++
  elif [[ "${PCEFqdnResolve2}" != "${PCEIP2}" ]]
  then
    echo "$(date) ERROR: Unable to resolve ${PCEFQDN} FQDN with second IP ${PCEIP2}." | tee -a ${LogFile}
    let fail++
  else
    echo "$(date) PCE FQDN - ${PCEFQDN} checked." | tee -a ${LogFile}
  fi
}

# Package check for RHEL / CentOS
function RHEL_CENTOS_PACKAGES_CHECK() {
  echo "$(date) Checking VEN required packages and dependencies..." | tee -a ${LogFile}
  if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ "${OSrelease}" =~ ^(5|6|7|8)$ || "${OSrelease2}" =~ ^(5|6|7|8)$ ]]
  then
    rpmPackageCheck=('libcap' 'gmp' 'bind-utils' 'ipset')
    for package in ${rpmPackageCheck[*]}; do
      if rpm -q ${package} > /dev/null 2>&1
      then
        echo "$(date) ${package} package installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: ${package} package is not installed." | tee -a ${LogFile}
        let fail++
      fi
    done

    rpmFileCheck=('curl' 'sed' 'iptables' 'ip6tables')
    for package in ${rpmFileCheck[*]}; do
      if [[ -f /usr/bin/${package} ||  -f /bin/${package} || -f /sbin/${package} ]] > /dev/null 2>&1
      then
        echo "$(date) ${package} package installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: ${package} package is not installed." | tee -a ${LogFile}
        let fail++
      fi
    done
  fi

  if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ "${OSrelease}" =~ ^(6|7|8)$ || "${OSrelease2}" =~ ^(6|7|8)$ ]]
  then
    rpmPackageCheck=('net-tools' 'libnfnetlink' 'libmnl' 'ca-certificates')
    for package in ${rpmPackageCheck[*]}; do
      if rpm -q ${package} > /dev/null 2>&1
      then
        echo "$(date) ${package} package installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: ${package} package is not installed." | tee -a ${LogFile}
        let fail++
      fi
    done
  fi
}

# Package check for Ubuntu
function UBUNTU_PACKAGES_CHECK() {
  echo "$(date) Checking VEN required packages and dependencies..." | tee -a ${LogFile}
  if [[ "${OS}" == 'Ubuntu' ]] && [[ "${OSrelease}" =~ ^(12.04|14.04|16.04|18.04)$ ]]
  then
    dpkgPackageCheck=('curl' 'net-tools' 'dnsutils' 'uuid-runtime' 'ipset' 'libnfnetlink0' 'libmnl0' 'libcap2' 'libgmp10' 'sed' 'iptables' 'ca-certificates')
    for package in ${dpkgPackageCheck[*]}; do
      if dpkg -l ${package} > /dev/null 2>&1
      then
        echo "$(date) ${package} package installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: ${package} package is not installed." | tee -a ${LogFile}
        let fail++
      fi
    done
  fi
}

# Package check for Debian
function DEBIAN_PACKAGES_CHECK() {
  echo "$(date) Checking VEN required packages and dependencies..." | tee -a ${LogFile}
  if [[ "${OS}" == 'Debian' ]] && [[ "${OSrelease}" =~ ^(7|8|9)$ ]]
  then
    dpkgPackageCheck=('apt-transport-https' 'curl' 'net-tools' 'dnsutils' 'uuid-runtime' 'ipset' 'libnfnetlink0' 'libmnl0' 'libcap2' 'libgmp10' 'sed' 'iptables' 'ca-certificates')
    for package in ${dpkgPackageCheck[*]}; do
      if dpkg -l ${package} > /dev/null 2>&1
      then
        echo "$(date) ${package} package installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: ${package} package is not installed." | tee -a ${LogFile}
        let fail++
      fi
    done
  fi
}

# Package check for SLES
function SLES_PACKAGES_CHECK() {
  echo "$(date) Checking VEN required packages and dependencies..." | tee -a ${LogFile}
  if [[ "${OS}" == 'Sles' ]] && [[ "${OSrelease}" =~ ^(11.3|11.4|12.1|12.2|12.3|12.4)$ ]]
  then
    rpmPackageCheck=('net-tools' 'bind-utils' 'ipset' 'libnfnetlink0' 'libmnl0' 'libcap2' 'iptables')
    for package in ${rpmPackageCheck[*]}; do
      if rpm -q ${package} > /dev/null 2>&1
      then
        echo "$(date) ${package} package installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: ${package} package is not installed." | tee -a ${LogFile}
        let fail++
      fi
    done

    rpmFileCheck=('openssl-certs' 'curl' 'sed' 'ca-certificates')
    for package in ${rpmFileCheck[*]}; do
      if [[ -f /usr/bin/${package} ||  -f /bin/${package} || -f /sbin/${package} ]] > /dev/null 2>&1
      then
        echo "$(date) ${package} package installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: ${package} package is not installed." | tee -a ${LogFile}
        let fail++
      fi
    done

    # Check if gmp package exist
    echo "$(date) Checking if gmp package exist..." | tee -a ${LogFile}
    if rpm -qa | grep ^gmp
    then
      echo "$(date) gmp package installed." | tee -a ${LogFile}
    else
      echo "$(date) ERROR: gmp package is not installed." | tee -a ${LogFile}
      let fail++
    fi
  fi
}

# Package check for AMI
function AMI_PACKAGES_CHECK() {
  echo "$(date) Checking VEN required packages and dependencies..." | tee -a ${LogFile}
  if [[ "${OS}" == 'Ami' ]] && [[ "${OSrelease}" =~ ^(2018.03|2017.03|2016.09|2016.03)$ ]]
  then
    rpmPackageCheck=('net-tools' 'bind-utils' 'ipset' 'libnfnetlink' 'libcap' 'iptables' 'gmp')
    for package in ${rpmPackageCheck[*]}; do
      if rpm -q ${package} > /dev/null 2>&1
      then
        echo "$(date) ${package} package installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: ${package} package is not installed." | tee -a ${LogFile}
        let fail++
      fi
    done

    rpmFileCheck=('openssl' 'curl' 'sed' 'ca-certificates')
    for package in ${rpmFileCheck[*]}; do
      if [[ -f /usr/bin/${package} ||  -f /bin/${package} || -f /sbin/${package} ]] > /dev/null 2>&1
      then
        echo "$(date) ${package} package installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: ${package} package is not installed." | tee -a ${LogFile}
        let fail++
      fi
    done
  fi
}

# Check if there is existing rule in iptables, provides a notification if there is.
function IPTABLES_USAGE_CHECK() {
  echo "$(date) Checking if there is rule in iptables..." | tee -a ${LogFile}
  FilterIPtable=$(iptables -t filter -L | wc | awk -F' ' '{print $1}')
  RawIPtable=$(iptables -t raw -L | wc | awk -F' ' '{print $1}')
  SecurityIPtable=$(iptables -t security -L | wc | awk -F' ' '{print $1}')
  MangleIPtable=$(iptables -t mangle -L | wc | awk -F' ' '{print $1}')
  NatIPtable=$(iptables -t nat -L | wc | awk -F' ' '{print $1}')
  ipTables=0
  if [[ "${OS}" =~ ^(Sles|Ami|RedHat|CentOS|Ubuntu|Debian)$ ]]
  then
    if [[ "${FilterIPtable}" -gt 8 ]]
    then
      echo "$(date) NOTIFY: There is rule in Filter IPtables." | tee -a ${LogFile}
      let ipTables++
    fi

    if [[ "${RawIPtable}" -gt 5 ]]
    then
      echo "$(date) NOTIFY: There is rule in Raw IPtables" | tee -a ${LogFile}
      let ipTables++
    fi

    if [[ "${SecurityIPtable}" -gt 8 ]]
    then
      echo "$(date) NOTIFY: There is rule in Security IPtables" | tee -a ${LogFile}
      let ipTables++
    fi

    if [[ "${MangleIPtable}" -gt 14 ]]
    then
      echo "$(date) NOTIFY: There is rule in Mangle IPtables" | tee -a ${LogFile}
      let ipTables++
    fi

    # There is extra chain in RHEL/CentOS 7 than 6
    if [[ "${NatIPtable}" -gt 8 ]] && [[ "${OSrelease}" == '6' ]]
    then
      echo "$(date) NOTIFY: There is rule in Nat IPtables" | tee -a ${LogFile}
      let ipTables++
    fi

    if [[ "${NatIPtable}" -gt 11 ]] && [[ "${OSrelease}" == '7' || "${OSrelease2}" == '7' ]] && [[ "${OS}" =~ ^(RedHat|CentOS)$ ]]
    then
      echo "$(date) NOTIFY: There is rule in Nat IPtables" | tee -a ${LogFile}
      let ipTables++
    fi

    if [[ "${NatIPtable}" -gt 11 ]] && [[ "${OS}" == 'Ubuntu' ]]
    then
      echo "$(date) NOTIFY: There is rule in Nat IPtables" | tee -a ${LogFile}
      let ipTables++
    fi

    if [[ ${ipTables} != 0 ]]
    then
      echo "$(date) NOTIFY: Dump existing Iptables rules into log." | tee -a ${LogFile}
      iptablesRules=${WorkingDirectory}/illumio_preiptablesrules.log
      iptablesTable=('filter' 'raw' 'mangle' 'security' 'nat')
      for i in ${iptablesTable[*]}; do
        echo " " >> ${iptablesRules}
        echo "$(date) ${i} rules" >> ${iptablesRules}
        iptables -t ${i} -S >> ${iptablesRules}
      done
    else
      echo "$(date) No pre-existing IPtables rule found." | tee -a ${LogFile}
    fi
  fi
}

# RESERVED: Check if related root and intermediate certs exist or not by matching cert name.
# If missing, just copy the cert over.
function PCE_CERTS_LOCAL_CHECK {
  if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ "${OSrelease}" =~ ^(6|7|8)$ || "${OSrelease2}" =~ ^(6|7|8)$ ]]
  then
    # For root cert
    echo "$(date) Checking if root cert for PCE exist..." | tee -a ${LogFile}
    if [[ -f /etc/pki/ca-trust/source/anchors/${RootCert} ]] > /dev/null 2>&1
    then
      echo "$(date) ${RootCert} - root cert exist." | tee -a ${LogFile}
    else
      echo "$(date) NOTIFY: root cert is not exist, copying the cert to workload" | tee -a ${LogFile}
      echo yes | cp ${WorkingDirectory}/${RootCert} /etc/pki/ca-trust/source/anchors/
      update-ca-trust enable
      update-ca-trust extract
    fi

    # For intermediate cert
    echo "$(date) Checking if intermediate cert for PCE exist..." | tee -a ${LogFile}
    if [[ -f /etc/pki/ca-trust/source/anchors/${IntermediateCert} ]] > /dev/null 2>&1
    then
      echo "$(date) ${IntermediateCert} - intermediate cert exist." | tee -a ${LogFile}
    else
      echo "$(date) NOTIFY: intermediate cert is not exist, copying the cert to workload" | tee -a ${LogFile}
      echo yes | cp ${WorkingDirectory}/${IntermediateCert} /etc/pki/ca-trust/source/anchors/
      update-ca-trust enable
      update-ca-trust extract
    fi
  fi

  if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]] && [[ "${OSrelease}" =~ ^(5)$ || "${OSrelease2}" =~ ^(5)$ ]]
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
      echo "$(date) Checking if root/intermediate cert for PCE exist..." | tee -a ${LogFile}
      CheckCertCN=`grep -q -i ${Domain} /etc/pki/tls/certs/ca-bundle.crt`
      if [[ "${?}" == '1' ]]
      then
        echo "$(date) Cert cannot be found, importing the cert into the bundle." | tee -a ${LogFile}
        echo "$(date) Backup the existing cert bundle." | tee -a ${LogFile}
        cp /etc/pki/tls/certs/ca-bundle.crt /etc/pki/tls/certs/ca-bundle.crt.bak
        cat ${WorkingDirectory}/${RootCert} >> /etc/pki/tls/certs/ca-bundle.crt
        cat ${WorkingDirectory}/${IntermediateCert} >> /etc/pki/tls/certs/ca-bundle.crt
      else
        echo "$(date) Certs found." | tee -a ${LogFile}
      fi
    fi
  fi

  if [[ "${OS}" == 'Ubuntu' ]] && [[ "${OSrelease}" =~ ^(12.04|14.04|16.04|18.04)$ ]]
  then
    echo "$(date) Checking if certs exist..." | tee -a ${LogFile}
    ls /etc/ssl/certs | grep -i ${Domain}
    if [[ "${?}" == 1 ]]
    then
      echo "$(date) Certs not found." | tee -a ${LogFile}
      mkdir /usr/share/ca-certificates/${Domain}
      cp ${WorkingDirectory}/${RootCert} /usr/share/ca-certificates/${Domain}/${RootCert}
      cp ${WorkingDirectory}/${IntermediateCert} /usr/share/ca-certificates/${Domain}/${IntermediateCert}
      update-ca-certificates
      echo "$(date) Certs updated." | tee -a ${LogFile}
    else
      echo "$(date) Certs found." | tee -a ${LogFile}
    fi
  fi

  if [[ "${OS}" == 'Debian' ]] && [[ "${OSrelease}" =~ ^(7|8|9)$ ]]
  then
    echo "$(date) Checking if certs exist..." | tee -a ${LogFile}
    ls /etc/ssl/certs | grep -i ${Domain}
    if [[ "${?}" == 1 ]]
    then
      echo "$(date) Certs not found." | tee -a ${LogFile}
      mkdir /usr/local/share/ca-certificates/${Domain}
      cp ${WorkingDirectory}/${RootCert} /usr/local/share/ca-certificates/${Domain}/${RootCert}
      cp ${WorkingDirectory}/${IntermediateCert} /usr/local/share/ca-certificates/${Domain}/${IntermediateCert}
      update-ca-certificates
      echo "$(date) Certs updated." | tee -a ${LogFile}
    else
      echo "$(date) Certs found." | tee -a ${LogFile}
    fi
  fi

  if [[ "${OS}" == 'Sles' ]] && [[ "${OSrelease}" =~ ^(12.1|12.2|12.3|12.4)$ ]]
  then
    # For root cert
    echo "$(date) Checking if root cert for PCE exist..." | tee -a ${LogFile}
    if [[ -f /etc/pki/trust/anchors/${RootCert} ]] > /dev/null 2>&1
    then
      echo "$(date) ${RootCert} - root cert exist." | tee -a ${LogFile}
    else
      echo "$(date) NOTIFY: root cert is not exist, copying the cert to workload" | tee -a ${LogFile}
      echo yes | cp ${WorkingDirectory}/${RootCert} /etc/pki/trust/anchors/
      update-ca-certificates
    fi
    # For intermediate cert
    echo "$(date) Checking if intermediate cert for PCE exist..." | tee -a ${LogFile}
    if [[ -f /etc/pki/trust/anchors/${IntermediateCert} ]] > /dev/null 2>&1
    then
      echo "$(date) ${IntermediateCert} - intermediate cert exist." | tee -a ${LogFile}
    else
      echo "$(date) NOTIFY: intermediate cert is not exist, copying the cert to workload" | tee -a ${LogFile}
      echo yes | cp ${WorkingDirectory}/${IntermediateCert} /etc/pki/trust/anchors/
      update-ca-certificates
    fi
  fi

  if [[ "${OS}" == 'Sles' ]] && [[ "${OSrelease}" =~ ^(11.3|11.4)$ ]]
  then
    echo "$(date) Checking if certs exist..." | tee -a ${LogFile}
    ls /etc/ssl/certs | grep -i ${Domain}
    if [[ "${?}" == 1 ]]
    then
      echo "$(date) Certs not found." | tee -a ${LogFile}
      cp ${WorkingDirectory}/${RootCert} /etc/ssl/certs${RootCert}
      cp ${WorkingDirectory}/${IntermediateCert} /etc/ssl/certs${IntermediateCert}
      echo "$(date) Certs updated." | tee -a ${LogFile}
    else
      echo "$(date) Certs found." | tee -a ${LogFile}
    fi
  fi

  if [[ "${OS}" == 'Ami' ]] && [[ "${OSrelease}" =~ ^(2018.03|2017.03|2016.09|2016.03)$ ]]
  then
    # For root cert
    echo "$(date) Checking if root cert for PCE exist..." | tee -a ${LogFile}
    if [[ -f /etc/pki/ca-trust/source/anchors/${RootCert} ]] > /dev/null 2>&1
    then
      echo "$(date) ${RootCert} - root cert exist." | tee -a ${LogFile}
    else
      echo "$(date) NOTIFY: root cert is not exist, copying the cert to workload" | tee -a ${LogFile}
      echo yes | cp ${WorkingDirectory}/${RootCert} /etc/pki/ca-trust/source/anchors/
      update-ca-trust enable
      update-ca-trust extract
    fi

    # For intermediate cert
    echo "$(date) Checking if intermediate cert for PCE exist..." | tee -a ${LogFile}
    if [[ -f /etc/pki/ca-trust/source/anchors/${IntermediateCert} ]] > /dev/null 2>&1
    then
      echo "$(date) ${IntermediateCert} - intermediate cert exist." | tee -a ${LogFile}
    else
      echo "$(date) NOTIFY: intermediate cert is not exist, copying the cert to workload" | tee -a ${LogFile}
      echo yes | cp ${WorkingDirectory}/${IntermediateCert} /etc/pki/ca-trust/source/anchors/
      update-ca-trust enable
      update-ca-trust extract
    fi
  fi
}

# Check workload can resolve PCE SSL cert. STDERR would catch the "verify error" output error.
function PCE_SSL_REACHABILITY_CHECK() {
  echo "$(date) Checking if workload can resolve PCE SSL certs..." | tee -a ${LogFile}
  SslStdOut=${WorkingDirectory}/illumio_opensslstdout.log
  SslStdErr=${WorkingDirectory}/illumio_opensslstderr.log
  if [[ "${PCEFqdnResolve}" == "${PCEIP}" ]] && [[ "${PCEFqdnResolve2}" == "${PCEIP2}" ]]
  then
    echo | openssl s_client -connect ${PCEFQDN}:${PCEPORT} 1>${SslStdOut} 2>${SslStdErr}
    SslErrLog=$(grep -r -i -E 'error|errno' ${SslStdErr})
    if [[ "${?}" == 1 ]]
    then
      echo "$(date) Workload can resolve ${PCEFQDN} SSL certs." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: Workload cannot resolve ${PCEFQDN} SSL certs." | tee -a ${LogFile}
        echo "$(date) ERROR: ${SslErrLog}." | tee -a ${LogFile}
        let fail++
    fi
  fi

  if [[ "${PCEFqdnResolve}" != "${PCEIP}" ]] || [[ "${PCEFqdnResolve2}" != "${PCEIP2}" ]]
  then
    echo "$(date) ERROR: Workload cannot resolve ${PCEFQDN} SSL certs." | tee -a ${LogFile}
    echo "$(date) NOTIFY: Testing PCE SSL by using IP since workload cannot resolve the PCE FQDN." | tee -a ${LogFile}
    if [[ "${PCEFqdnResolve}" != "${PCEIP}" ]]
    then
      echo | openssl s_client -connect ${PCEIP}:${PCEPORT} 1>${SslStdOut} 2>${SslStdErr}
      SslErrLog=$(grep -r -i -E 'error|errno' ${SslStdErr})
      if [[ "${?}" == 1 ]]
      then
        echo "$(date) ERROR: Workload can resolve ${PCEFQDN} SSL certs by using PCE first IP ${PCEIP}, but not with FQDN." | tee -a ${LogFile}
        let fail++
      else
        echo "$(date) ERROR: Workload cannot resolve ${PCEFQDN} SSL certs by using PCE first IP ${PCEIP}." | tee -a ${LogFile}
        echo "$(date) ERROR: ${SslErrLog}." | tee -a ${LogFile}
        let fail++
      fi
    fi
    if [[ "${PCEFqdnResolve2}" != "${PCEIP2}" ]]
    then
      echo | openssl s_client -connect ${PCEIP2}:${PCEPORT} 1>${SslStdOut} 2>${SslStdErr}
      SslErrLog=$(grep -r -i -E 'error|errno' ${SslStdErr})
      if [[ "${?}" == 1 ]]
      then
        echo "$(date) ERROR: Workload can resolve ${PCEFQDN} SSL certs by using PCE second IP ${PCEIP2}, but not with FQDN." | tee -a ${LogFile}
        let fail++
      else
        echo "$(date) ERROR: Workload cannot resolve ${PCEFQDN} SSL certs by using PCE second IP ${PCEIP2}." | tee -a ${LogFile}
        echo "$(date) ERROR: ${SslErrLog}." | tee -a ${LogFile}
        let fail++
      fi
    fi
  fi
}

# Check if workload can reaching PCE port 8443 via CURL and expecting a HTTP 200 return.
function PCE_8443_PORT_CHECK() {
  echo "$(date) Checking if workload can reaching PCE port ${PCEPORT}..." | tee -a ${LogFile}
  if [[ "${PCEFqdnResolve}" == "${PCEIP}" ]] && [[ "${PCEFqdnResolve2}" == "${PCEIP2}" ]]
  then
    curl -I https://${PCEFQDN}:${PCEPORT} -k --max-time 3 1>${WorkingDirectory}/illumio_8443stdout.log 2>${WorkingDirectory}/illumio_8443stderr.log
    grep -r -i 200 ${WorkingDirectory}/illumio_8443stdout.log
    if [[ "${?}" == 0 ]]
    then
      echo "$(date) Workload can reaching ${PCEFQDN} management port ${PCEPORT}." | tee -a ${LogFile}
    else
      8443Errmsg=`awk -F 'curl' '{print $2}' ${WorkingDirectory}/illumio_8443stderr.log`
      echo "$(date) ERROR: Workload cannot reaching ${PCEFQDN} management port ${PCEPORT}." | tee -a ${LogFile}
      echo "$(date) ERROR: curl ${8443Errmsg}." | tee -a ${LogFile}
      let fail++
    fi
  elif [[ "${PCEFqdnResolve}" != "${PCEIP}" ]] || [[ "${PCEFqdnResolve2}" != "${PCEIP2}" ]]
  then
    echo "$(date) NOTIFY: Testing PCE Port 8443 by using IP since workload cannot resolve the PCE FQDN." | tee -a ${LogFile}
    if [[ "${PCEFqdnResolve}" != "${PCEIP}" ]]
    then
      curl -I https://${PCEIP}:${PCEPORT} -k --max-time 3 1>${WorkingDirectory}/illumio_8443stdout.log 2>${WorkingDirectory}/illumio_8443stderr.log
      grep -r -i 200 ${WorkingDirectory}/illumio_8443stdout.log
      if [[ "${?}" == 0 ]]
      then
        echo "$(date) ERROR: Workload can reaching PCE first ${PCEIP} management port ${PCEPORT} but not with FQDN." | tee -a ${LogFile}
        let fail++
      else
        8443Errmsg=`awk -F 'curl' '{print $2}' ${WorkingDirectory}/illumio_8443stderr.log`
        echo "$(date) ERROR: Workload cannot reaching PCE first ${PCEIP} management port ${PCEPORT}." | tee -a ${LogFile}
        echo "$(date) ERROR: curl ${8443Errmsg}." | tee -a ${LogFile}
        let fail++
      fi
    fi
    if [[ "${PCEFqdnResolve2}" != "${PCEIP2}" ]]
    then
      curl -I https://${PCEIP2}:${PCEPORT} -k --max-time 3 1>${WorkingDirectory}/illumio_8443stdout.log 2>${WorkingDirectory}/illumio_8443stderr.log
      grep -r -i 200 ${WorkingDirectory}/illumio_8443stdout.log
      if [[ "${?}" == 0 ]]
      then
        echo "$(date) ERROR: Workload can reaching PCE second ${PCEIP2} management port ${PCEPORT} but not with FQDN." | tee -a ${LogFile}
        let fail++
      else
        8443Errmsg=`awk -F 'curl' '{print $2}' ${WorkingDirectory}/illumio_8443stderr.log`
        echo "$(date) ERROR: Workload cannot reaching PCE second ${PCEIP2} management port ${PCEPORT}." | tee -a ${LogFile}
        echo "$(date) ERROR: curl ${8443Errmsg}." | tee -a ${LogFile}
        let fail++
      fi
    fi
  let fail++
  fi
}

# Check if workload can reaching PCE port 8444 via curl, expecting a "left intact" output which
# indicating the port 8444 is active but not responding as expected. If 8444 is not success,
# we are getting "Connection Refused" instead.
function PCE_8444_PORT_CHECK() {
  if [[ "${PCEFqdnResolve}" == "${PCEIP}" ]] && [[ "${PCEFqdnResolve2}" == "${PCEIP2}" ]]
  then
    echo "$(date) Checking if workload can reaching PCE port 8444..." | tee -a ${LogFile}
    curl -I https://${PCEFQDN}:${PCEPORT2} -k --max-time 3 &>${WorkingDirectory}/illumio_8444stdout.log
    awk -F 'curl' '{print $2}' ${WorkingDirectory}/illumio_8444stdout.log | grep 52
    if [[ "${?}" == 0 ]]
    then
      echo "$(date) Workload can reaching ${PCEFQDN} port ${PCEPORT2}." | tee -a ${LogFile}
    else
      8444Errmsg=`awk -F 'curl' '{print $2}' ${WorkingDirectory}/illumio_8444stdout.log`
      echo "$(date) ERROR: Workload cannot reaching ${PCEFQDN} port ${PCEPORT2}." | tee -a ${LogFile}
      echo "$(date) ERROR: curl ${8444Errmsg}." | tee -a ${LogFile}
      let fail++
    fi
  elif [[ "${PCEFqdnResolve}" != "${PCEIP}" ]] || [[ "${PCEFqdnResolve2}" != "${PCEIP2}" ]]
  then
    echo "$(date) NOTIFY: Testing PCE Port ${PCEPORT2} by using IP since workload cannot resolve the PCE FQDN." | tee -a ${LogFile}
    if [[ "${PCEFqdnResolve}" != "${PCEIP}" ]]
    then
      curl -I https://${PCEIP}:${PCEPORT2} -k --max-time 3 &>${WorkingDirectory}/illumio_8444stdout.log
      awk -F 'curl' '{print $2}' ${WorkingDirectory}/illumio_8444stdout.log | grep 52
      if [[ "${?}" == 0 ]]
      then
        echo "$(date) ERROR: Workload can reaching PCE first ${PCEIP} port ${PCEPORT2} but not with FQDN." | tee -a ${LogFile}
        let fail++
      else
        8444Errmsg=`awk -F 'curl' '{print $2}' ${WorkingDirectory}/illumio_8444stdout.log`
        echo "$(date) ERROR: Workload cannot reaching PCE first ${PCEIP} port ${PCEPORT2}." | tee -a ${LogFile}
        echo "$(date) ERROR: curl ${8444Errmsg}." | tee -a ${LogFile}
        let fail++
      fi
    fi
    if [[ "${PCEFqdnResolve2}" != "${PCEIP2}" ]]
    then
      curl -I https://${PCEIP2}:${PCEPORT2} -k --max-time 3 &>${WorkingDirectory}/illumio_8444stdout.log
      awk -F 'curl' '{print $2}' ${WorkingDirectory}/illumio_8444stdout.log | grep 52
      if [[ "${?}" == 0 ]]
      then
        echo "$(date) ERROR: Workload can reaching PCE second ${PCEIP2} port ${PCEPORT2} but not with FQDN." | tee -a ${LogFile}
        let fail++
      else
        8444Errmsg=`awk -F 'curl' '{print $2}' ${WorkingDirectory}/illumio_8444stdout.log`
        echo "$(date) ERROR: Workload cannot reaching PCE second ${PCEIP2} port ${PCEPORT2}." | tee -a ${LogFile}
        echo "$(date) ERROR: curl ${8444Errmsg}." | tee -a ${LogFile}
        let fail++
      fi
    fi
  let fail++
  fi
}

# If above jobs all pass and 'fail' bit is 0, proceed for install, else abort.
function RHEL_CENTOS_VEN_INSTALL() {
  rpmOutput=${WorkingDirectory}/illumio_rpminstallresult.log
  rpmError=${WorkingDirectory}/illumio_rpmerrorinstall.log
  if [[ "${fail}" == 0 ]] && [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]]
  then
    sleep 5
    echo "$(date) Proceed for VEN installation..." | tee -a ${LogFile}
    if [[ "${OSrelease}" == '5' || "${OSrelease2}" == '5' ]] && [[ "$(arch)" == 'i686' ]]
    then
      rpm -ivh ${WorkingDirectory}/${C5_32VENPackage} >$rpmOutput 2>$rpmError
      rpmState=${?}
      if [[ ! -f "${WorkingDirectory}"/"${C5_32VENPackage}" ]]
      then
        echo "$(date) ERROR: VEN PACKAGE ${C5_32VENPackage} package not found, aborting installation" | tee -a ${LogFile}
        let fail++
        TARLOGS_CLEANUP
        exit 1
      elif [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${C5_32VENPackage} Installed Successfully." | tee -a ${LogFile}
      elif [[ "${rpmState}" != 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${C5_32VENPackage} already installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}

        TARLOGS_CLEANUP
        exit 1
      fi
    fi
    if [[ "${OSrelease}" == '5' || "${OSrelease2}" == '5' ]] && [[ "$(arch)" == 'x86_64' ]]
    then
      rpm -ivh ${WorkingDirectory}/${C5_64VENPackage} >$rpmOutput 2>$rpmError
      rpmState=${?}
      if [[ ! -f "${WorkingDirectory}"/"${C5_64VENPackage}" ]]
      then
        echo "$(date) ERROR: VEN PACKAGE ${C5_64VENPackage} package not found, aborting installation" | tee -a ${LogFile}
        let fail++
        TARLOGS_CLEANUP
        exit 1
      elif [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${C5_64VENPackage} Installed Successfully." | tee -a ${LogFile}
      elif [[ "${rpmState}" != 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${C5_64VENPackage} already installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}

        TARLOGS_CLEANUP
        exit 1
      fi
    fi
    if [[ "${OSrelease}" == '6' || "${OSrelease2}" == '6' ]] && [[ "$(arch)" == 'i686' ]]
    then
      rpm -ivh ${WorkingDirectory}/${C6_32VENPackage} >$rpmOutput 2>$rpmError
      rpmState=${?}
      if [[ ! -f "${WorkingDirectory}"/"${C6_32VENPackage}" ]]
      then
        echo "$(date) ERROR: VEN PACKAGE ${C6_32VENPackage} package not found, aborting installation" | tee -a ${LogFile}
        let fail++
        TARLOGS_CLEANUP
        exit 1
      elif [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${C6_32VENPackage} Installed Successfully." | tee -a ${LogFile}
      elif [[ "${rpmState}" != 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${C6_32VENPackage} already installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}

        TARLOGS_CLEANUP
        exit 1
      fi
    fi
    if [[ "${OSrelease}" == '6' || "${OSrelease2}" == '6' ]] && [[ "$(arch)" == 'x86_64' ]]
    then
      rpm -ivh ${WorkingDirectory}/${C6_64VENPackage} >$rpmOutput 2>$rpmError
      rpmState=${?}
      if [[ ! -f "${WorkingDirectory}"/"${C6_64VENPackage}" ]]
      then
        echo "$(date) ERROR: VEN PACKAGE ${C6_64VENPackage} package not found, aborting installation" | tee -a ${LogFile}
        let fail++
        TARLOGS_CLEANUP
        exit 1
      elif [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${C6_64VENPackage} Installed Successfully." | tee -a ${LogFile}
      elif [[ "${rpmState}" != 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${C6_64VENPackage} already installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}

        TARLOGS_CLEANUP
        exit 1
      fi
    fi
    if [[ "${OSrelease}" == '7' || "${OSrelease2}" == '7' ]] && [[ "$(arch)" == 'x86_64' ]]
    then
      rpm -ivh ${WorkingDirectory}/${C7_64VENPackage} >$rpmOutput 2>$rpmError
      rpmState=${?}
      if [[ ! -f "${WorkingDirectory}"/"${C7_64VENPackage}" ]]
      then
        echo "$(date) ERROR: VEN PACKAGE ${C7_64VENPackage} package not found, aborting installation" | tee -a ${LogFile}
        let fail++
        TARLOGS_CLEANUP
        exit 1
      elif [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${C7_64VENPackage} Installed Successfully." | tee -a ${LogFile}
      elif [[ "${rpmState}" != 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${C7_64VENPackage} already installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}

        TARLOGS_CLEANUP
        exit 1
      fi
    fi
    if [[ "${OSrelease}" == '8' || "${OSrelease2}" == '8' ]] && [[ "$(arch)" == 'x86_64' ]]
    then
      rpm -ivh ${WorkingDirectory}/${C8_64VENPackage} >$rpmOutput 2>$rpmError
      rpmState=${?}
      if [[ ! -f "${WorkingDirectory}"/"${C8_64VENPackage}" ]]
      then
        echo "$(date) ERROR: VEN PACKAGE ${C8_64VENPackage} package not found, aborting installation" | tee -a ${LogFile}
        let fail++
        TARLOGS_CLEANUP
        exit 1
      elif [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${C8_64VENPackage} Installed Successfully." | tee -a ${LogFile}
      elif [[ "${rpmState}" != 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${C8_64VENPackage} already installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}

        TARLOGS_CLEANUP
        exit 1
      fi
    fi
  else
    echo "$(date) ERROR: Aborting VEN installation. Please check 'illumio_veninstall.log', there are dependencies missing." | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
  fi
}

# If above jobs all pass and 'fail' bit is 0, proceed for install, else abort.
function UBUNTU_VEN_INSTALL() {
  rpmOutput=${WorkingDirectory}/illumio_rpminstallresult.log
  rpmError=${WorkingDirectory}/illumio_rpmerrorinstall.log
  if [[ "${fail}" == 0 ]] && [[ "${OS}" == 'Ubuntu' ]]
  then
    sleep 5
    echo "$(date) Proceed for VEN installation..." | tee -a ${LogFile}
    if [[ "${OS}" == 'Ubuntu' ]] && [[ "$(arch)" == 'i686' ]] && [[ "${OSrelease}" =~ ^(16.04|18.04)$ ]]
    then
      dpkg -i ${WorkingDirectory}/${U16_32VENPackage} >$rpmOutput 2>$rpmError
      rpmState=${?}
      if [[ ! -f "${WorkingDirectory}"/"${U16_32VENPackage}" ]]
      then
        echo "$(date) ERROR: VEN PACKAGE ${U16_32VENPackage} package not found, aborting installation" | tee -a ${LogFile}
        let fail++
        TARLOGS_CLEANUP
        exit 1
      elif [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${U16_32VENPackage} Installed Successfully." | tee -a ${LogFile}
      elif [[ "${rpmState}" != 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${U16_32VENPackage} already installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}

        TARLOGS_CLEANUP
        exit 1
      fi
    fi
    if [[ "${OS}" == 'Ubuntu' ]] && [[ "$(arch)" == 'x86_64' ]] && [[ "${OSrelease}" =~ ^(16.04|18.04)$ ]]
    then
      dpkg -i ${WorkingDirectory}/${U16_64VENPackage} >$rpmOutput 2>$rpmError
      rpmState=${?}
      if [[ ! -f "${WorkingDirectory}"/"${U16_64VENPackage}" ]]
      then
        echo "$(date) ERROR: VEN PACKAGE ${U16_64VENPackage} package not found, aborting installation" | tee -a ${LogFile}
        let fail++
        TARLOGS_CLEANUP
        exit 1
      elif [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${U16_64VENPackage} Installed Successfully." | tee -a ${LogFile}
      elif [[ "${rpmState}" != 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${U16_64VENPackage} already installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}

        TARLOGS_CLEANUP
        exit 1
      fi
    fi
    if [[ "${OS}" == 'Ubuntu' ]] && [[ "$(arch)" == 'i686' ]] && [[ "${OSrelease}" == '14.04' ]]
    then
      dpkg -i ${WorkingDirectory}/${U14_32VENPackage} >$rpmOutput 2>$rpmError
      rpmState=${?}
      if [[ ! -f "${WorkingDirectory}"/"${U14_32VENPackage}" ]]
      then
        echo "$(date) ERROR: VEN PACKAGE ${U14_32VENPackage} package not found, aborting installation" | tee -a ${LogFile}
        let fail++
        TARLOGS_CLEANUP
        exit 1
      elif [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${U14_32VENPackage} Installed Successfully." | tee -a ${LogFile}
      elif [[ "${rpmState}" != 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${U14_32VENPackage} already installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}

        TARLOGS_CLEANUP
        exit 1
      fi
    fi
    if [[ "${OS}" == 'Ubuntu' ]] && [[ "$(arch)" == 'x86_64' ]] && [[ "${OSrelease}" == '14.04' ]]
    then
      dpkg -i ${WorkingDirectory}/${U14_64VENPackage} >$rpmOutput 2>$rpmError
      rpmState=${?}
      if [[ ! -f "${WorkingDirectory}"/"${U14_64VENPackage}" ]]
      then
        echo "$(date) ERROR: VEN PACKAGE ${U14_64VENPackage} package not found, aborting installation" | tee -a ${LogFile}
        let fail++
        TARLOGS_CLEANUP
        exit 1
      elif [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${U14_64VENPackage} Installed Successfully." | tee -a ${LogFile}
      elif [[ "${rpmState}" != 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${U14_64VENPackage} already installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}

        TARLOGS_CLEANUP
        exit 1
      fi
    fi
    if [[ "${OS}" == 'Ubuntu' ]] && [[ "$(arch)" == 'i686' ]] && [[ "${OSrelease}" == '12.04' ]]
    then
      dpkg -i ${WorkingDirectory}/${U12_32VENPackage} >$rpmOutput 2>$rpmError
      rpmState=${?}
      if [[ ! -f "${WorkingDirectory}"/"${U12_32VENPackage}" ]]
      then
        echo "$(date) ERROR: VEN PACKAGE ${U12_32VENPackage} package not found, aborting installation" | tee -a ${LogFile}
        let fail++
        TARLOGS_CLEANUP
        exit 1
      elif [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${U12_32VENPackage} Installed Successfully." | tee -a ${LogFile}
      elif [[ "${rpmState}" != 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${U12_32VENPackage} already installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}

        TARLOGS_CLEANUP
        exit 1
      fi
    fi
    if [[ "${OS}" == 'Ubuntu' ]] && [[ "$(arch)" == 'x86_64' ]] && [[ "${OSrelease}" == '12.04' ]]
    then
      dpkg -i ${WorkingDirectory}/${U12_64VENPackage} >$rpmOutput 2>$rpmError
      rpmState=${?}
      if [[ ! -f "${WorkingDirectory}"/"${U12_64VENPackage}" ]]
      then
        echo "$(date) ERROR: VEN PACKAGE ${U12_64VENPackage} package not found, aborting installation" | tee -a ${LogFile}
        let fail++
        TARLOGS_CLEANUP
        exit 1
      elif [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${U12_64VENPackage} Installed Successfully." | tee -a ${LogFile}
      elif [[ "${rpmState}" != 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${U12_64VENPackage} already installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}

        TARLOGS_CLEANUP
        exit 1
      fi
    fi
  else
    echo "$(date) ERROR: Aborting VEN installation. Please check 'illumio_veninstall.log', there are dependencies missing." | tee -a ${LogFile}

    TARLOGS_CLEANUP
    exit 1
  fi
}

# If above jobs all pass and 'fail' bit is 0, proceed for install, else abort.
function DEBIAN_VEN_INSTALL() {
  rpmOutput=${WorkingDirectory}/illumio_rpminstallresult.log
  rpmError=${WorkingDirectory}/illumio_rpmerrorinstall.log
  if [[ "${fail}" == 0 ]] && [[ "${OS}" == 'Debian' ]]
  then
    sleep 5
    echo "$(date) Proceed for VEN installation..." | tee -a ${LogFile}
    if [[ "${OS}" == 'Debian' ]] && [[ "$(arch)" == 'i686' ]] && [[ "${OSrelease}" =~ ^(7)$ ]]
    then
      dpkg -i ${WorkingDirectory}/${D7_32VENPackage} >$rpmOutput 2>$rpmError
      rpmState=${?}
      if [[ ! -f "${WorkingDirectory}"/"${D7_32VENPackage}" ]]
      then
        echo "$(date) ERROR: VEN PACKAGE ${D7_32VENPackage} package not found, aborting installation" | tee -a ${LogFile}
        let fail++
        TARLOGS_CLEANUP
        exit 1
      elif [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${D7_32VENPackage} Installed Successfully." | tee -a ${LogFile}
      elif [[ "${rpmState}" != 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${D7_32VENPackage} already installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}

        TARLOGS_CLEANUP
        exit 1
      fi
    fi
    if [[ "${OS}" == 'Debian' ]] && [[ "$(arch)" == 'x86_64' ]] && [[ "${OSrelease}" =~ ^(7)$ ]]
    then
      dpkg -i ${WorkingDirectory}/${D7_64VENPackage} >$rpmOutput 2>$rpmError
      rpmState=${?}
      if [[ ! -f "${WorkingDirectory}"/"${D7_64VENPackage}" ]]
      then
        echo "$(date) ERROR: VEN PACKAGE ${D7_64VENPackage} package not found, aborting installation" | tee -a ${LogFile}
        let fail++
        TARLOGS_CLEANUP
        exit 1
      elif [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${D7_64VENPackage} Installed Successfully." | tee -a ${LogFile}
      elif [[ "${rpmState}" != 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${D7_64VENPackage} already installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}

        TARLOGS_CLEANUP
        exit 1
      fi
    fi
    if [[ "${OS}" == 'Debian' ]] && [[ "$(arch)" == 'i686' ]] && [[ "${OSrelease}" =~ ^(8)$ ]]
    then
      dpkg -i ${WorkingDirectory}/${D7_32VENPackage} >$rpmOutput 2>$rpmError
      rpmState=${?}
      if [[ ! -f "${WorkingDirectory}"/"${D7_32VENPackage}" ]]
      then
        echo "$(date) ERROR: VEN PACKAGE ${D7_32VENPackage} package not found, aborting installation" | tee -a ${LogFile}
        let fail++
        TARLOGS_CLEANUP
        exit 1
      elif [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${D7_32VENPackage} Installed Successfully." | tee -a ${LogFile}
      elif [[ "${rpmState}" != 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${D7_32VENPackage} already installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}

        TARLOGS_CLEANUP
        exit 1
      fi
    fi
    if [[ "${OS}" == 'Debian' ]] && [[ "$(arch)" == 'x86_64' ]] && [[ "${OSrelease}" =~ ^(8)$ ]]
    then
      dpkg -i ${WorkingDirectory}/${D7_64VENPackage} >$rpmOutput 2>$rpmError
      rpmState=${?}
      if [[ ! -f "${WorkingDirectory}"/"${D7_64VENPackage}" ]]
      then
        echo "$(date) ERROR: VEN PACKAGE ${D7_64VENPackage} package not found, aborting installation" | tee -a ${LogFile}
        let fail++
        TARLOGS_CLEANUP
        exit 1
      elif [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${D7_64VENPackage} Installed Successfully." | tee -a ${LogFile}
      elif [[ "${rpmState}" != 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${D7_64VENPackage} already installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}

        TARLOGS_CLEANUP
        exit 1
      fi
    fi
    if [[ "${OS}" == 'Debian' ]] && [[ "$(arch)" == 'i686' ]] && [[ "${OSrelease}" =~ ^(9)$ ]]
    then
      dpkg -i ${WorkingDirectory}/${D7_32VENPackage} >$rpmOutput 2>$rpmError
      rpmState=${?}
      if [[ ! -f "${WorkingDirectory}"/"${D7_32VENPackage}" ]]
      then
        echo "$(date) ERROR: VEN PACKAGE ${D7_32VENPackage} package not found, aborting installation" | tee -a ${LogFile}
        let fail++
        TARLOGS_CLEANUP
        exit 1
      elif [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${D7_32VENPackage} Installed Successfully." | tee -a ${LogFile}
      elif [[ "${rpmState}" != 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${D7_32VENPackage} already installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}

        TARLOGS_CLEANUP
        exit 1
      fi
    fi
    if [[ "${OS}" == 'Debian' ]] && [[ "$(arch)" == 'x86_64' ]] && [[ "${OSrelease}" =~ ^(9)$ ]]
    then
      dpkg -i ${WorkingDirectory}/${D7_64VENPackage} >$rpmOutput 2>$rpmError
      rpmState=${?}
      if [[ ! -f "${WorkingDirectory}"/"${D7_64VENPackage}" ]]
      then
        echo "$(date) ERROR: VEN PACKAGE ${D7_64VENPackage} package not found, aborting installation" | tee -a ${LogFile}
        let fail++
        TARLOGS_CLEANUP
        exit 1
      elif [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${D7_64VENPackage} Installed Successfully." | tee -a ${LogFile}
      elif [[ "${rpmState}" != 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${D7_64VENPackage} already installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}

        TARLOGS_CLEANUP
        exit 1
      fi
    fi
  else
    echo "$(date) ERROR: Aborting VEN installation. Please check 'illumio_veninstall.log', there are dependencies missing." | tee -a ${LogFile}

    TARLOGS_CLEANUP
    exit 1
  fi
}

# If above jobs all pass and 'fail' bit is 0, proceed for install, else abort.
function SLES_VEN_INSTALL() {
  rpmOutput=${WorkingDirectory}/illumio_rpminstallresult.log
  rpmError=${WorkingDirectory}/illumio_rpmerrorinstall.log
  if [[ "${fail}" == 0 ]] && [[ "${OS}" == 'Sles' ]]
  then
    sleep 5
    echo "$(date) Proceed for VEN installation..." | tee -a ${LogFile}
    if [[ "${OS}" == 'Sles' ]] && [[ "${OSrelease}" =~ ^(11.3|11.4)$ ]]
    then
      rpm -ivh ${WorkingDirectory}/${S11_VENPackage} >$rpmOutput 2>$rpmError
      rpmState=${?}
      if [[ ! -f "${WorkingDirectory}"/"${S11_VENPackage}" ]]
      then
        echo "$(date) ERROR: VEN PACKAGE ${S11_VENPackage} package not found, aborting installation" | tee -a ${LogFile}
        let fail++
        TARLOGS_CLEANUP
        exit 1
      elif [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${S11_VENPackage} Installed Successfully." | tee -a ${LogFile}
      elif [[ "${rpmState}" != 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${S11_VENPackage} already installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}

        TARLOGS_CLEANUP
        exit 1
      fi
    fi
    if [[ "${OS}" == 'Sles' ]] && [[ "${OSrelease}" =~ ^(12.1|12.2|12.3|12.4)$ ]]
    then
      rpm -ivh ${WorkingDirectory}/${S12_VENPackage} >$rpmOutput 2>$rpmError
      rpmState=${?}
      if [[ ! -f "${WorkingDirectory}"/"${S12_VENPackage}" ]]
      then
        echo "$(date) ERROR: VEN PACKAGE ${S12_VENPackage} package not found, aborting installation" | tee -a ${LogFile}
        let fail++
        TARLOGS_CLEANUP
        exit 1
      elif [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${S12_VENPackage} Installed Successfully." | tee -a ${LogFile}
      elif [[ "${rpmState}" != 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${S12_VENPackage} already installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}

        TARLOGS_CLEANUP
        exit 1
      fi
    fi
  else
    echo "$(date) ERROR: Aborting VEN installation. Please check 'illumio_veninstall.log', there are dependencies missing." | tee -a ${LogFile}

    TARLOGS_CLEANUP
    exit 1
  fi
}

# If above jobs all pass and 'fail' bit is 0, proceed for install, else abort.
function AMI_VEN_INSTALL() {
  rpmOutput=${WorkingDirectory}/illumio_rpminstallresult.log
  rpmError=${WorkingDirectory}/illumio_rpmerrorinstall.log
  if [[ "${fail}" == 0 ]] && [[ "${OS}" == 'Ami' ]]
  then
    sleep 5
    echo "$(date) Proceed for VEN installation..." | tee -a ${LogFile}
    if [[ "${OS}" == 'Ami' ]] && [[ "${OSrelease}" =~ ^(2018.03|2017.03|2016.09|2016.03)$ ]] && [[ "${Amiarch}" == '32' ]]
    then
      rpm -ivh ${WorkingDirectory}/${C6_32VENPackage} >$rpmOutput 2>$rpmError
      rpmState=${?}
      if [[ ! -f "${WorkingDirectory}"/"${C6_32VENPackage}" ]]
      then
        echo "$(date) ERROR: VEN PACKAGE ${C6_32VENPackage} package not found, aborting installation" | tee -a ${LogFile}
        let fail++
        TARLOGS_CLEANUP
        exit 1
      elif [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${C6_32VENPackage} Installed Successfully." | tee -a ${LogFile}
      elif [[ "${rpmState}" != 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${C6_32VENPackage} already installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}

        TARLOGS_CLEANUP
        exit 1
      fi
    fi
    if [[ "${OS}" == 'Ami' ]] && [[ "${OSrelease}" =~ ^(2018.03|2017.03|2016.09|2016.03)$ ]] && [[ "${Amiarch}" == '64' ]]
    then
      rpm -ivh ${WorkingDirectory}/${C6_64VENPackage} >$rpmOutput 2>$rpmError
      rpmState=${?}
      if [[ ! -f "${WorkingDirectory}"/"${C6_64VENPackage}" ]]
      then
        echo "$(date) ERROR: VEN PACKAGE ${C6_64VENPackage} package not found, aborting installation" | tee -a ${LogFile}
        let fail++
        TARLOGS_CLEANUP
        exit 1
      elif [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${C6_64VENPackage} Installed Successfully." | tee -a ${LogFile}
      elif [[ "${rpmState}" != 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
      then
        echo "$(date) VEN PACKAGE ${C6_64VENPackage} already installed." | tee -a ${LogFile}
      else
        echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}

        TARLOGS_CLEANUP
        exit 1
      fi
    fi
  else
    echo "$(date) ERROR: Aborting VEN installation. Please check 'illumio_veninstall.log', there are dependencies missing." | tee -a ${LogFile}

    TARLOGS_CLEANUP
    exit 1
  fi
}

# VEN Installation
function VEN_PAIRING() {
  # Pairing the VEN workload with PCE
  echo "$(date) Pairing VEN workload with PCE - ${PCEFQDN}..." | tee -a ${LogFile}
  ErrorPairingVEN=${WorkingDirectory}/illumio_pairingerror.log
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
    echo "$(date) Search for NOTIFY and ERROR in the 'illumio_veninstall.log' for more info." | tee -a ${LogFile}
    echo "$(date)" >> ${ErrorPairingVEN}
    sleep 5
    ${IllumioVENctl} unpair saved 1>>${ErrorPairingVEN} 2>>${ErrorPairingVEN}
    echo "$(date)" >> ${ErrorPairingVEN}
    let fail++
    rpm -e illumio-ven 1>>${ErrorPairingVEN} 2>>${ErrorPairingVEN}
    TARLOGS_CLEANUP
    exit 1
  fi
}



#####################
###################################
########################################################
#############################################################################
########################################################
###################################
#####################



# Job begin
# Check if the executer is root user or not before proceed
if [[ "$(id -u)" != "0"  ]]
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
fi

# OS check
if [[ -f "/etc/redhat-release" ]]
then
  RHEL_CENTOS_OS_CHECK
elif grep -q -i ubuntu "/etc/os-release"
then
  UBUNTU_OS_CHECK
elif grep -q -i debian "/etc/os-release"
then
  DEBIAN_OS_CHECK
elif grep -q -i sles "/etc/os-release"
then
  SLES_OS_CHECK
elif grep -q -i amazon "/etc/os-release"
then
  AMI_OS_CHECK
fi

VEN_CURRENT_STATUS_CHECK
VEN_DIR_PRE_CHECK
DISK_SPACE_CHECK
DNS_SETTING_CHECK
PCE_FQDN_CHECK

if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]]
then
  RHEL_CENTOS_PACKAGES_CHECK
elif [[ "${OS}" == 'Ubuntu' ]]
then
  UBUNTU_PACKAGES_CHECK
elif [[ "${OS}" == 'Debian' ]]
then
  DEBIAN_PACKAGES_CHECK
elif [[ "${OS}" == 'Sles' ]]
then
  SLES_PACKAGES_CHECK
elif [[ "${OS}" == 'Ami' ]]
then
  AMI_PACKAGES_CHECK
fi

IPTABLES_USAGE_CHECK

# Comment out this function for future adjustment.
# PCE_CERTS_LOCAL_CHECK

PCE_SSL_REACHABILITY_CHECK
PCE_8443_PORT_CHECK
PCE_8444_PORT_CHECK

if [[ "${OS}" == 'RedHat' || "${OS}" == 'CentOS' ]]
then
  RHEL_CENTOS_VEN_INSTALL
elif [[ "${OS}" == 'Ubuntu' ]]
then
  UBUNTU_VEN_INSTALL
elif [[ "${OS}" == 'Debian' ]]
then
  DEBIAN_VEN_INSTALL
elif [[ "${OS}" == 'Sles' ]]
then
  SLES_VEN_INSTALL
elif [[ "${OS}" == 'Ami' ]]
then
  AMI_VEN_INSTALL
fi

VEN_PAIRING
exit 1
