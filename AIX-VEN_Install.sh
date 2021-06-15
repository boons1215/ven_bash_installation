#!/usr/bin/ksh
# POC AIX install and pair v0.2

# Script name: aix_veninstall.sh
# Created by: Siew Boon Siong
# Updated: Jan-16-2020
#
# Nov-26 Added variable for VEN versions
# Nov-27 Updated disk check requirement

# Unattended install script for aix
# Rules are:
# - if any required package/dependencies missing, logs the info but not installing Illumio VEN
# - if the workload can't reaching the PCE or can't resolve PCE FQDN, logs the info but not installing Illumio VEN
# - it must be run as root and place under /var/var/tmp
# - Create 7 logs: _illumio_veninstall.log, _illumio_rpminstallresult.log, _illumio_rpmerrorinstall.log, _illumio_pairingerror.log,
# _illumio_certcheck.log, _illumio_8443check.log, _illumio_8444stderr.log
#
# When pairing failed, VEN software will be uninstalled, and generate illumio_ven_report.tgz which combining
# /opt/illumio_ven* and logs for analysis.

# Flexible variables adjust when needed
PCEFQDN='mseg.com'
PCEPORT='8443'
PCEPORT2='8444'
PCEIP='10.91.18.98'
PCEIP2='10.91.38.98'
# If only one DNS server, just fill the same IP into these 2 variables
DNS1='10.80.14.8'
DNS2='10.81.12.8'
ROOTCERT='w01gimsmrca1a_Bank-Root-CA.crt'

ActivationCode='1b42b71d7c37df25d4dcbde3970c2c08ac9d3ce12eab1bb2714e90be8efdee7f94f7ce484deae'

# For AIX VEN packages
VEN_VER='18.2.4.4520'

####################################################
######## DO NOT MODIFY ANYTHING BELOW ##############
####################################################
# Unchanged variables
AIXPackage="illumio-ven.${VEN_VER}.bff"
AIXbff='ipfl.5.3.0.5001.bff'
InstallPath='/opt'
WorkingDirectory='/var/tmp'
LogFile='/var/tmp/_illumio_veninstall.log'
VENdiskUsageInMB='20'
IllumioVENctl='/opt/illumio_ven/illumio-ven-ctl'
IllumioVENdir='/opt/illumio_ven'
IllumioVENdatadir='/opt/illumio_ven_data'
IllumioActCfg='/opt/illumio_ven_data/etc/agent_activation.cfg'

#
# tar /opt/illumio_ven* and 9 logs: _illumio_veninstall.log, _illumio_rpminstallresult.log, _illumio_rpmerrorinstall.log, _illumio_pairingerror.log,
# _illumio_opensslstdout.log, _illumio_opensslstderr.log, _illumio_8443stdout.log, _illumio_8443stderr.log, _illumio_8444stderr.log
# Then, remove bash shell script and VEN installer which copied over.
function TARLOGS_CLEANUP {
    date=$(date '+%Y-%m-%d')
    cd ${WorkingDirectory} && mkdir -p job
    cp -R ${IllumioVENdir} ${IllumioVENdatadir} ${WorkingDirectory}/_illumio_*.log /var/log/illumio*log ${WorkingDirectory}/job
    tar -cvf ${WorkingDirectory}/${date}_${HOSTNAME}_${OS}_illumioreport.tar job
    rm -rf ${WorkingDirectory}/_illumio_*.log
    rm -rf ${WorkingDirectory}/illumio-ven*.bff
    rm -rf ${WorkingDirectory}/AIX-VEN-Install_v1.3.sh
    rm -rf ${WorkingDirectory}/job
} >/dev/null

# Generic statements for workload info
function WORKLOAD_INFO_STATEMENT {
  echo "$(date) Workload Hostname: ${HOSTNAME}" | tee -a ${LogFile}
  echo "$(date) This workload is supported by VEN." | tee -a ${LogFile}
  echo "$(date) Workload OS: ${OSrelease}"  | tee -a ${LogFile}
  echo "$(date) Workload Architecture: ${OSkernel}"  | tee -a ${LogFile}
  echo "$(date) Workload Level: ${AIXTL}"  | tee -a ${LogFile}
}

# Check if the OS supported. If it is not supported or out of the list, job exit.
function AIX_OS_CHECK {
  VEN_COMPARE=`echo ${VEN_VER} | cut -d$'-' -f1 | awk -F. '{print $1""$2}'`
  echo "$(date) Checking Operating System..." | tee -a ${LogFile}
  OSrelease=NotFound
  if [[ "${OSrelease}" == 'NotFound' ]]
  then
    if [ "${OStype}" == 'AIX' ]
    then
      HOSTNAME=`hostname`
      AIXVERSION=$(oslevel -s)
      OSrelease=$(echo "scale=1; $(echo $AIXVERSION | cut -d'-' -f1)/1000" | bc)
      AIXTL=$(echo $AIXVERSION | cut -d'-' -f2 | bc)
      AIXSP=$(echo $AIXVERSION | cut -d'-' -f3 | bc)
      echo "$(date) AIX ${AIXVERSION} - Technology Level ${AIXTL} - Service Pack ${AIXSP}"

      case ${OSrelease} in
      6.1)
        case ${AIXTL} in
        9)
          WORKLOAD_INFO_STATEMENT
          ;;
        esac
        ;;
      7.1)
        case ${AIXTL} in
        4|5)
          WORKLOAD_INFO_STATEMENT
          ;;
        esac
        ;;
      7.2)
        case ${AIXTL} in
        1|2|3)
          WORKLOAD_INFO_STATEMENT
          ;;
        esac
        ;;
      NotFound)
        echo "$(date) ERROR: Could not determine the operating system, aborting..." | tee -a ${LogFile}
        TARLOGS_CLEANUP
        exit 1
        ;;
      *)
        echo "$(date) ERROR: This workload is NOT supported by VEN, aborting VEN installation." | tee -a ${LogFile}
        TARLOGS_CLEANUP
        exit 1
        ;;
      esac
    fi
  fi
}

# Set generic VEN path/directory check
function VEN_PATH_PRE_CHECK {
  if [[ -f "${IllumioVENctl}" ]] > /dev/null 2>&1
  then
    PairStatus=`${IllumioVENctl} status | grep state 2>/dev/null | head -n 1 | cut -d' ' -f3`
    VENVersion=`cat ${IllumioVENdir}/etc/agent_version 2>/dev/null | head -n 1 | cut -d' ' -f3`
    PCEName=`cat ${IllumioVENdatadir}/etc/agent_activation.cfg 2>/dev/null | grep master | head -n 1 | cut -d':' -f2`
  fi
}

#  Check if workload has already paired. If no status found, proceed for next step, else job exit.
function VEN_CURRENT_STATUS_CHECK {
  VEN_PATH_PRE_CHECK
  if [[ "${PairStatus}" == 'unpaired' ]]
  then
    echo "$(date) NOTIFY: VEN version ${VENVersion} is in unpaired mode, proceed for next step." | tee -a ${LogFile}
  fi

  for i in illuminated enforced idle; do
    if [[ -f ${IllumioVENctl} ]] && [[ "${PairStatus}" == "${i}"  ]]
    then
      echo "$(date) NOTIFY: VEN version ${VENVersion} has already paired as ${i} mode with${PCEName}, aborting VEN installation." | tee -a ${LogFile}
      TARLOGS_CLEANUP
      exit 1
    fi
  done
}

# Check if workload has VEN installed before, or VEN software remained due to incomplete uninstallation.
function VEN_DIR_PRE_CHECK {
  VenDirPath=`ls -d "${IllumioVENdir}" 2>/dev/null | head -n 1 | cut -d$'/' -f3`
  VenDataDirPath=`ls -d "${IllumioVENdatadir}" 2>/dev/null | head -n 1 | cut -d$'/' -f3`

  if [[ -d "${IllumioVENdir}" ]] && [[ ! -d "${IllumioVENdatadir}" ]]
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
    echo "$(date) No VEN directories found, proceed for next step." > /dev/null
  else
    echo "$(date) ERROR: Other error found, please check whether VEN directory exist, aborting VEN installation." | tee -a ${LogFile}
    TARLOGS_CLEANUP
    exit 1
  fi
}

# Check if the workload has minimal 500MB disk space free after VEN installation
function DISK_SPACE_CHECK {
  DiskFreeLine=`df -m /opt | tail -1 | awk -F' ' '{print $3}' | cut -d'.' -f1`
  let "DiskLeftAfterVENinstall = ${DiskFreeLine} - ${VENdiskUsageInMB}"
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

# Check if the workload has correct DNS server settings, DBS has 2 DNS servers
function DNS_SETTING_CHECK {
  DNSServer1=`grep name /etc/resolv.conf | grep ${DNS1} | awk -F' ' '{print $2}'` 
  DNSServer2=`grep name /etc/resolv.conf | grep ${DNS2} | awk -F' ' '{print $2}'`

  if [[ "${DNSServer1}" != "${DNS1}" ]]
  then
    echo "$(date) ERROR: Missing first ${DNS1} DNS settings in resolve file." | tee -a ${LogFile}
    let fail=+1
  else
    echo "$(date) First DNS settings for ${DNS1} checked." | tee -a ${LogFile}
  fi
  if [[ "${DNSServer2}" != "${DNS2}" ]]
  then
    echo "$(date) ERROR: Missing second ${DNS2} DNS settings in resolve file." | tee -a ${LogFile}
    let fail=+1
  else
    echo "$(date) Second DNS settings for ${DNS2} checked." | tee -a ${LogFile}
  fi
}

# Check if the workload can resolve PCE FQDN
function PCE_FQDN_CHECK {
  PCEFqdnResolve=`nslookup ${PCEFQDN} | grep ${PCEIP}| tail -1 | cut -d' ' -f2`
  PCEFqdnResolve2=`nslookup ${PCEFQDN} | grep ${PCEIP2}| tail -1 | cut -d' ' -f2`

  if [[ "${PCEFqdnResolve}" != "${PCEIP}" ]]
  then
    if [[ "${PCEFqdnResolve2}" != "${PCEIP2}" ]]
    then
      echo "$(date) ERROR: Unable to resolve ${PCEFQDN} FQDN with IP." | tee -a ${LogFile}
      let fail=+1
    fi
  fi
}

function LPAR_WPAR_CHECK {
  lparwparCheck=`uname -W`
  if [[ "${lparwparCheck}" != 0 ]]
  then
    echo "$(date) ERROR: WPAR is not supported by VEN, WPAR number ${lparwparCheck}." | tee -a ${LogFile}
    let fail=+1
  fi
}

function PCE_CERTS_REACHBILITY_CHECK {
  echo "$(date) Checking if workload can resolve PCE cert..." | tee -a ${LogFile}
  if [[ "${OStype}" == 'AIX'  ]] && [[ -f "/usr/bin/curl" ]]
  then
    # For root cert
    curl -I https://${PCEFQDN}:${PCEPORT} --max-time 30 2>${WorkingDirectory}/_illumio_certcheck.log >/dev/null
    if [[ "${?}" == 0 ]]
    then
      echo "$(date) Workload can resolve ${PCEFQDN} cert." | tee -a ${LogFile}
    else
      echo "$(date) ERROR: Workload cannot resolve ${PCEFQDN} cert, check \"_illumio_certcheck.log\"." | tee -a ${LogFile}
      let fail=+1
    fi
   else
     echo "$(date) cURL package is not exist, skipping the check." | tee -a ${LogFile}
  fi
}

# Check if workload can reaching PCE port 8443 via CURL and expecting a HTTP 200 return.
function PCE_8443_PORT_CHECK {
  echo "$(date) Checking if workload can reaching PCE port ${PCEPORT}..." | tee -a ${LogFile}
    PortCheck=`ssh -o BatchMode=yes -o ConnectTimeout=1 -p ${PCEPORT} ${PCEFQDN} 2>&1 | cut -d'_' -f2`
    if [[ "${PortCheck}" == 'exchange' ]]
    then
      echo "$(date) Workload can reaching ${PCEFQDN} management port ${PCEPORT}." | tee -a ${LogFile}
    else
      echo "$(date) ERROR: Workload cannot reaching ${PCEFQDN} management port ${PCEPORT}, check \"_illumio_8443check.log\"." | tee -a ${LogFile}
      let fail=+1
    fi
}

# If above jobs all pass and 'fail' bit is 0, proceed for install, else abort.
function AIX_VEN_INSTALL {
  rpmOutput=${WorkingDirectory}/_illumio_rpminstallresult.log
  rpmError=${WorkingDirectory}/_illumio_rpmerrorinstall.log
  if [[ "${fail}" == 0 ]]
  then
    sleep 5
    echo "$(date) Proceed for VEN installation..." | tee -a ${LogFile}
      if [[ ! -f "${WorkingDirectory}"/"${AIXbff}" ]] ||  [[ ! -f "${WorkingDirectory}"/"${AIXPackage}" ]]
      then
          echo "${AIXPackage}" | tee -a ${LogFile}
          echo "${WorkingDirectory}" | tee -a ${LogFile}
          echo "$(date) ERROR: VEN AIX installer package not found, aborting installation" | tee -a ${LogFile}
          let fail=+1
          TARLOGS_CLEANUP
          exit 1
      fi
      currentVer=`/opt/illumio_ven/illumio-ven-ctl version 2>/dev/null`
      currentBFF=`lslpp -l | grep ipfl | tail -1  | awk -F' ' '{print $2}' 2>/dev/null`
      targetBFF=`echo ${AIXbff} | awk -F'.bff' '{print $1}' | cut -c 6-`
      if [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]] && [[ "${PairStatus}" == 'unpaired' ]]
      then
        echo "$(date) VEN ${currentVer} already installed." | tee -a ${LogFile}
        VEN_UPGRADE
      elif [[ ! -d "${IllumioVENdir}" ]] && [[ ! -d "${IllumioVENdatadir}" ]]
      then 
        cd ${WorkingDirectory}
        installp -acXYgd ${AIXbff} ipfl
        currentBFF=`lslpp -l | grep ipfl | tail -1  | awk -F' ' '{print $2}' 2>/dev/null`
        if [[ "${currentBFF}" == "${targetBFF}" ]]
        then
          echo "$(date) BFF ${currentBFF} has installed." | tee -a ${LogFile}
        else
          echo "$(date) BFF ${targetBFF} is not installed." | tee -a ${LogFile}
          let fail=+1
        fi

        installp -acXYgd ${AIXPackage} illumio-ven
        rpmState=${?}
        if [[ "${rpmState}" == 0 ]] && [[ -d "${IllumioVENdir}" ]] && [[ -d "${IllumioVENdatadir}" ]]
        then
          echo "$(date) VEN PACKAGE ${AIXPackage} Installed Successfully." | tee -a ${LogFile}
        elif [[ "${rpmState}" != 0 ]] && [[ ! -d "${IllumioVENdir}" ]] && [[ ! -d "${IllumioVENdatadir}" ]]
        then
          echo "$(date) ERROR: VEN Installation failed." | tee -a ${LogFile}
          TARLOGS_CLEANUP
          exit 1
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

function VERSION_COMPARE {
  test "$(printf '%s\n' "$@" | sort | head -n 1)" != "$1"; 
}

# VEN Upgrade function
function VEN_UPGRADE {
  echo "$(date) Checking if workload requires a VEN upgrade." | tee -a ${LogFile}
  currentVer=`/opt/illumio_ven/illumio-ven-ctl version`
  if [[ ${currentVer} == ${VEN_VER} ]]
  then
    echo "$(date) Current VEN version is the same with the targetted version." | tee -a ${LogFile}
    VEN_PAIRING
  elif [[ ${currentVer} != ${VEN_VER} ]]
  then
    if VERSION_COMPARE ${VEN_VER} ${currentVer}
    then
          cd ${WorkingDirectory}
          currentBFF=`lslpp -l | grep ipfl | tail -1  | awk -F' ' '{print $2}' 2>/dev/null`
          if [[ "${currentBFF}" == "${targetBFF}" ]]
          then
            echo "$(date) BFF ${currentBFF} has installed." | tee -a ${LogFile}
          else
            installp -acXYgd ${AIXbff} ipfl
            currentBFF=`lslpp -l | grep ipfl | tail -1  | awk -F' ' '{print $2}' 2>/dev/null`
            if [[ "${currentBFF}" == "${targetBFF}" ]]
            then
              echo "$(date) BFF ${currentBFF} has installed." | tee -a ${LogFile}
            else
              echo "$(date) BFF ${currentBFF} has not installed." | tee -a ${LogFile}
              let fail=+1
            fi
          fi
          installp -acXYgd ${AIXPackage} illumio-ven
          currentVer=`/opt/illumio_ven/illumio-ven-ctl version 2>/dev/null`
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
}

# VEN Installation
function VEN_PAIRING {
  # Pairing the VEN workload with PCE
  if [[ "${fail}" == 0 ]]
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
      echo "$(date) ERROR: Pairing with PCE - ${PCEFQDN} failed, removing the VEN." | tee -a ${LogFile}
      echo "$(date) Search for NOTIFY and ERROR in the '_illumio_veninstall.log' for more info." | tee -a ${LogFile}
      echo "$(date)" >> ${ErrorPairingVEN}
      sleep 5
      ${IllumioVENctl} unpair saved 1>>${ErrorPairingVEN} 2>>${ErrorPairingVEN}
      echo "$(date)" >> ${ErrorPairingVEN}
      let fail=+1
      TARLOGS_CLEANUP
      exit 1
    fi
  fi
}

#############################################################################


# Job begin
# Must be superuser
if [ `id -u` -ne 0 ]
then
  echo "\n$0: Must be superuser (root) to invoke script\n" | tee -a ${LogFile}
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
OStype=`uname -s`
OSkernel=$(getconf KERNEL_BITMODE)
if [ "${OStype}" == 'AIX' ] && [[ "${OSkernel}" == '32' ]]
then
  echo "$(date) AIX 32bit Kernel is not supported by VEN." | tee -a ${LogFile}
  TARLOGS_CLEANUP
  exit 1
elif [ "${OStype}" == 'AIX' ] && [[ "${OSkernel}" == '64' ]]
then
  AIX_OS_CHECK
fi

VEN_CURRENT_STATUS_CHECK
VEN_DIR_PRE_CHECK
DISK_SPACE_CHECK
#DNS_SETTING_CHECK
PCE_FQDN_CHECK
LPAR_WPAR_CHECK
PCE_CERTS_REACHBILITY_CHECK
PCE_8443_PORT_CHECK
AIX_VEN_INSTALL

unset LIBPATH
VEN_PAIRING
set -o allexport
exit 0
