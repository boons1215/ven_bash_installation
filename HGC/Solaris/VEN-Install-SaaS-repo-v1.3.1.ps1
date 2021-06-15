#################################################################################################
#                                                                                               #
# Copyright 2013-2020 Illumio, Inc. All Rights Reserved.                                        #
#                                                                                               #
# The purpose of this script is to install the Illumio VEN on from a SaaS or onPrem Repo on     #
# Windows   This script will do the following:                                                  #
#  1. Verifies all pre-requisites exist for VEN installation                                    #
#  2. Installs the VEN from the Repo and pairs to the PCE                                       #
#                                                                                               #
# NOTE:  This script MUST be ran as an administrator to be successful.                          #
# The TLS 1.2 Check and PCE Connectivity check requires Powershell v3 or greater. The Script    #
# will skip those checks if only powershell v2 detected and log it in the dependency log.       #                                                                                          #
#                                                                                               #
#                                                                                               #
#  Written by Greg DiRubbio - Illumio Professional Services, Illumio Inc.                       #
#  Updated by Siew Boon Siong - Illumio Professional Services, 06-Jan-2020                      #   
#                                                                                               #
#################################################################################################


#################################################################################################
## ONLY Modify The variables below                                                             ##
#################################################################################################

$hostname = hostname
$LogPath = "c:\windows\system32"
$DependencyLog = "Illumio-Dependencies-$hostname.log"
$WorkingDir = "C:\temp"

### When copying the pairing script from your PCE, paste it in the $pairingscript variable below betweem the @' and '@ .  

$pairingscript = @'
PowerShell -Command "& {Set-ExecutionPolicy -Scope process remotesigned -Force; Start-Sleep -s 3; Set-Variable -Name ErrorActionPreference -Value SilentlyContinue; [System.Net.ServicePointManager]::SecurityProtocol=[Enum]::ToObject([System.Net.SecurityProtocolType], 3072); Set-Variable -Name ErrorActionPreference -Value Continue; (New-Object System.Net.WebClient).DownloadFile('https://illumio.office.hgc.com.hk:8443/api/v6/software/ven/image?pair_script=pair.ps1&profile_id=3', '.\Pair.ps1'); .\Pair.ps1 -management-server illumio.office.hgc.com.hk:8443 -activation-code 15b0b2a4c1103aec7603b2b6316f6e98351ed014e253f0fc4bb452fd7337236ee026214f74a26a635;}"
'@

$rebootcheck = "NO" 
## rebootcheck verifies if the workload has a pending reboot prior to the VEN being installed  ##

$PCECertcheck = "YES"
$MyPCERootCertThumbprint = "522caad37d86d3b72b0947a6595e0842eb9496bd"

## If PCECertcheck is set to YES you must get the root cert thumprint                          ##
## To get the thumprint of your PCE root certificate on a machine you know has the root        ## 
## certificate installed, either run the following powershell command                          ##
## Get-ChildItem -Path Cert:\LocalMachine\root                                                 ##
## or look at the local computer certs in the MMC and look at the details of your PCE root     ##
## certificate and find the thumbprint value                                                   ## 
#################################################################################################
## DO NOT MODIFY ANYTHING BELOW THIS LINE                                                      ##
#################################################################################################

#################################################################################################
## System Variables                                                                            ##
#################################################################################################
$ErrorActionPreference = 'SilentlyContinue'
$counter = 0
$pairingscript -match '({).*?(})'
$installscript = $matches[0] 

#################################################################################################
## Build Title                                                                                 ##
#################################################################################################

$myProgrammTitle = "VEN Install SaaS or Repo"
$myProgramVersion = "1.3.0"
$myOutput = "  " + $myProgrammTitle + ", Version: " + $myProgramVersion + ", Illumio Inc. 2019  "
for ($i = 0 ; $i -lt ($myOutput.length); $i++) { $myOutPutUnderline += "-" }

# Write title to screen
Write-Host -ForegroundColor yellow -Backgroundcolor black $myOutPutUnderline
Write-Host -ForegroundColor white -Backgroundcolor black $myOutput
Write-Host -ForegroundColor yellow -Backgroundcolor black $myOutPutUnderline

#################################################################################################
## Verify All Pre-requisites                                                                   ##
#################################################################################################

#################################################################################################
## Verify Admin and Powershell Version                                                         ##
#################################################################################################

function VerifyAdmin {
    if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
                [Security.Principal.WindowsBuiltInRole] "Administrator")) {
        $global:adminUser = $true
        #Write-Output "You are an Admin equivalent user"
    }

    else {
        
        $global:adminUser = $false
    }
}

function PSVers {
    if ($PSVersionTable.PSVersion.Major -gt 1) {
        $global:psversion = $true
        
    }
    else {
        $global:psversion = $false
    }

}

function PSv3Check {
    if ($PSVersionTable.PSVersion.Major -gt 2) {
        $global:psv3 = $true
    }
    else {
        $global:psv3 = $false
    }
    
}  


################################################################################################# 
## Verify Paths Exist                                                                         ##
#################################################################################################

function LogPathCheck {
    if (!(Test-Path -path $LogPath)) {
        $global:LogPathexists = $false 
        Write-Host -ForegroundColor yellow -Backgroundcolor black "The Log Directory Path does not exist and no logs will be written, please modify the variable LogPath at top of this script"
    }
    else {
        $global:LogPathexists = $true
        Write-Host "Log Path exists"
    }
}
#################################################################################################
## get FQDN and Port from pairing script                                                      ##
#################################################################################################
function getFQDN {

    if ($pairingscript -match '-management-server (\w+).(\w+).(\w+):(\d+)' -eq $true ) {
        $ManagementServer = $matches[1] + "." + $matches[2] + "." + $matches[3]
        $PCEPort1 = $matches[4] 
        $pairingscriptgood = $true
    }   
    elseif ($pairingscript -match '-management-server (\w+).(\w+).(\w+).(\w+):(\d+)' -eq $true ) {
        $ManagementServer = $matches[1] + "." + $matches[2] + "." + $matches[3] + "." + $matches[4]
        $PCEPort1 = $matches[5] 
        $pairingscriptgood = $true
    }
    elseif ($pairingscript -match '-management-server (\w+).(\w+).(\w+).(\w+).(\w+):(\d+)' -eq $true ) {
        $ManagementServer = $matches[1] + "." + $matches[2] + "." + $matches[3] + "." + $matches[4] + "." + $matches[5]
        $PCEPort1 = $matches[6] 
        $pairingscriptgood = $true
    }
    else {
        $pairingscriptgood = $false
    }
}
#################################################################################################
## Verify if any Pending reboots exist before VEN install                                      ##
#################################################################################################

function PendingRebootCheck {
    if (Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -EA Ignore) { return $true } 
    if (Get-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -EA Ignore) { return $true }
    if (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -EA Ignore) { return $true }
    try { 
        $util = [wmiclass]"\\.\root\ccm\clientsdk:CCM_ClientUtilities"
        $status = $util.DetermineIfRebootPending()
        if (($status -ne $null) -and $status.RebootPending) {
            return $true
        }
    }
    catch { }
 
    return $false
}


function Test-Pending-Reboot {
    if (PendingRebootCheck = $True) { 
        
        $global:rebootrequired = $true 
    
    }

    else {
        Write-Host "No pending reboot exists, the install will continue" 
        $global:rebootrequired = $false   
    }
}

function verifyreboot {

    if ($rebootcheck -eq "YES") {
        Test-Pending-Reboot
    }

    else { 
        Write-Host "Pending Reboot Check skipped, continuing"
        $global:rebootrequired = "Skipped"
    }
}

################################################################################################# 
## Verify required certificates exist                                                          ##
#################################################################################################

function VENcertCheck {

    $global:cert1 = 'CN=DigiCert High Assurance EV Root CA, OU=www.digicert.com, O=DigiCert Inc, C=US'
    $global:cert2 = 'CN=VeriSign Universal Root Certification Authority, OU="(c) 2008 VeriSign, Inc. - For authorized use only", OU=VeriSign Trust Network, O="VeriSign, Inc.", C=US'
    
    
    $global:check1 = Get-ChildItem -Path Cert:\LocalMachine\root | Where-Object { $_.Subject -eq $global:cert1 } | Select-Object -Property subject
    $global:check2 = Get-ChildItem -Path Cert:\LocalMachine\root | Where-Object { $_.Subject -eq $global:cert2 } | Select-Object -Property subject
    
    if (!$global:check1) { 
    
        Write-Host -ForegroundColor yellow -Backgroundcolor black "Missing the following Root certificate: $cert1, reinstalling root certificate and retry the install again" 
        "$(date) Missing the following certificate: $cert1, reinstalling root certificate and retry the install again" | Out-file -FilePath $Logpath\$DependencyLog -Append
        certutil.exe -addstore -f "Root" $WorkingDir\DigiCertHighAssuranceEVRootCA.crt
    }
           
    if (!$global:check2) {
    
        Write-Host -ForegroundColor yellow -Backgroundcolor black "Missing the following Root certificate: $cert2, reinstalling root certificate and retry the install again"
        "$(date) Missing the following certificate: $cert2, reinstalling root certificate and retry the install again" | Out-file -FilePath $Logpath\$DependencyLog -Append
        certutil.exe -addstore -f "Root" $WorkingDir\vsign-universal-root.crt
    }
       
    $global:check1 = Get-ChildItem -Path Cert:\LocalMachine\root | Where-Object { $_.Subject -eq $global:cert1 } | Select-Object -Property subject
    $global:check2 = Get-ChildItem -Path Cert:\LocalMachine\root | Where-Object { $_.Subject -eq $global:cert2 } | Select-Object -Property subject
    
    
    if (!$global:Check1 -OR !$global:Check2) {
        
        $global:requiredCertsMissing = $true
    }
    
    else {
        Write-Host "Required DigiCert and Verisign certs exist, continuing"
        
        
    }
}
    
################################################################################################# 
## Verify PCE root certificate exists                                                          ##
#################################################################################################

$MissingRootCertCounter = 0
function PCERootCertVerify {
    $global:PCERootCertCheck = Get-ChildItem -Path Cert:\LocalMachine\root | Where-Object { $_.Thumbprint -eq "$MyPCERootCertThumbprint" }
    
    if (!$global:PCERootCertCheck) { 
        $MissingRootCertCounter++
        RootCertInstall
        # $global:PCECertsMissing = $true
    }
    else {
        $global:PCECertsMissing = "NO"
        $MissingRootCertCounter = 0
        Write-Host "PCE Root Cert exists, continuing"
         
    }
}
    
function RootCertInstall {
    write-Host "$MissingRootCertCounter"
    if (($MissingRootCertCounter -eq "1") -and (Test-Path -path $WorkingDir\HGCCA.CER)) {
        Write-Host "Trying to install the Root Cert and retry"
        certutil.exe -addstore -f "Root" $WorkingDir\HGCCA.CER
        # $global:PCECertsMissing ="NO"
        $MissingRootCertCounter++
        PCERootCertVerify
    }
    else {
        write-Host "Root cert is missing in the directory"
        $global:PCECertsMissing = "YES"
    }
}

function PCErootVerify {
    
    if ($PCECertcheck -eq "YES") {
        PCERootCertVerify
    }
    
    else { 
        $global:PCECertceck = "Skipped"
        Write-Output "PCE Cert Root Verification Check skipped, continuing"
    }
}
    

#################################################################################################
## Check if workload can reach PCE ports                                                       ##
#################################################################################################

function TestPCEPort1 {
    $PCEPort1Test = New-Object System.Net.Sockets.TcpClient "$ManagementServer", $PCEPort1
    if ($PCEPort1Test.Connected) {
        $global:TestPCEPort1 = $true
        Write-host "This workload is able to communicate to PCE on port $PCEPort1"

    }
    else {
        $global:TestPCEPort1 = $false
    }
}
  

################################################################################################# 
## TLS Check                                                                                   ##
#################################################################################################

function Test-ServerSSLSupport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$HostName,
        [UInt16]$Port = $PCEPort1
    )
    process {
        $global:retvalue = New-Object psobject -Property @{
            Host    = $HostName
            Port    = $Port
            TLSv1_2 = $false
        }
        "tls10", "tls11", "tls12" | % {
            $TcpClient = New-Object Net.Sockets.TcpClient
            $TcpClient.Connect($global:retvalue.Host, $global:retvalue.Port)
            $SslStream = New-Object Net.Security.SslStream $TcpClient.GetStream(),
            $true,
            ([System.Net.Security.RemoteCertificateValidationCallback] { $true })
            $SslStream.ReadTimeout = 15000
            $SslStream.WriteTimeout = 15000
            try {
                $SslStream.AuthenticateAsClient($global:retvalue.Host, $null, $_, $false)
                $status = $true
            }
            catch {
                $status = $false
            }
            switch ($_) {
             
                "tls12" { $global:retvalue.TLSv1_2 = $status }
            }
            # dispose objects to prevent memory leaks
            $TcpClient.Dispose()
            $SslStream.Dispose()
        }

    }
}

function verify-tls {
    Test-ServerSSLSupport $ManagementServer
}

################################################################################################# 
## Free Disk Space Check                                                                       ##
#################################################################################################
Function DiskSpaceCheck {

    $Global:Disk = Get-WmiObject -Class Win32_logicaldisk -Filter "DeviceID = 'c:'" | Select-Object -Property DeviceID, 
    @{L = 'FreeSpaceGB'; E = { "{0:N2}" -f ($_.FreeSpace /1GB) } },
    @{L = "Capacity"; E = { "{0:N2}" -f ($_.Size/1GB) } }
    
    $global:diskfree = $Global:disk.FreeSpaceGB
    
    If ($Global:disk.FreeSpaceGB -lt 0.5) {
        $global:diskspace = $false
    }
    
    
    else {
        Write-host "You have met or exceeded the minimum required disk space of 500MB, Recommended free disk space is 1.5 GB - 2 GB, you have $global:diskfree GB of free disk space on the c: Drive"
    }
} 

################################################################################################# 
## Determine if VEN is installed and what the new VEN version is                               ##
#################################################################################################

function VENVer {

    $global:VenReg = (Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall") |
    Where-Object { $_.GetValue( "DisplayName" ) -like "*Illumio VEN*" } 
    
    if ($global:VenReg -ne $null) {
    
        $global:VEnVer = ((Get-ItemProperty Registry::$global:Venreg -name DisplayVersion).DisplayVersion | Out-String).Trim()

    }
    if ($global:VenReg -ne $null) {
        Write-Host -ForegroundColor yellow -Backgroundcolor black "VEN version $global:VEnVer is already installed" 
        "$(date) VEN version $global:VEnVer is already installed" | Out-file -FilePath $Logpath\$DependencyLog -Append
        break   
    }
}
    
################################################################################################# 
## Powershell v3+ compatible checks                                                            ##  
#################################################################################################
function PSv3Dependencies {
    if ($global:psv3 -ne $true) {
        Write-Host -ForegroundColor yellow -Backgroundcolor black "Powershell Version 3 or greater not detected skipping the TLS 1.2 Check and PCE Connectivity Checks, the VEN could fail to pair if the workload is not running TLS 1.2 or cannot reach the PCE"
        "$(date) Powershell Version 3 or greater not detected skipping the TLS 1.2 Check and PCE Connectivity Checks, the VEN could fail to pair if the workload is not running TLS 1.2 or cannot reach the PCE" | Out-file -FilePath $Logpath\$DependencyLog -Append
    }
    else {
        TestPCEPort1
        TestPCEPort2
        verify-tls
    }
}
    
################################################################################################# 
## Remove All Variables                                                                        ##
#################################################################################################
function RemoveVariables {

    Write-Host "Cleaning up all variables"

    Clear-Variable -Name hostname -scope Script
    Clear-Variable -Name Illumio_MSI_Log -scope Script
    Clear-Variable -Name DependencyLog -scope Script
    Clear-Variable -Name ManagementServer -scope Script
    Clear-Variable -Name PCEPort1 -scope Script
    Clear-Variable -Name rebootcheck -scope Script
    Clear-Variable -Name PCECertcheck -scope Script
    Clear-Variable -Name MyPCERootCertThumbprint -scope Script
    Clear-Variable -Name pairingscript -scope Script
    Clear-Variable -Name installscript -scope Script
    Clear-Variable -name VEN -Scope Global
    Clear-Variable -name VEnVer -Scope Global
    Clear-Variable -name PCECertsMissing -Scope Global
    Clear-Variable -name requiredCertsMissing -Scope Global
    Clear-Variable -name adminUser -Scope Global
    Clear-Variable -name rebootrequired -Scope Global
    Clear-Variable -name check1 -Scope Global
    Clear-Variable -name check2 -Scope Global
    Clear-Variable -name cert1 -Scope Global
    Clear-Variable -name cert2 -Scope Global
    Clear-Variable -name PCERootCertCheck -Scope Global
    Clear-Variable -name PCECertceck -Scope Global
    Clear-Variable -name TestPCEPort1 -scope Global
    Clear-Variable -name diskpace -scope Global
    Clear-Variable -name diskfree -scope Global
    Clear-Variable -name disk -scope Global
}  
################################################################################################# 
## Prequisite Check OutPut                                                                     ##
#################################################################################################


function ReqCheck {
    if ($global:PCECertsMissing -eq $true) {
        Write-Host -ForegroundColor yellow -Backgroundcolor black "Missing the PCE Root certificate, Please install the PCE root certificate on this workload and retry the install again"
        "$(date) Missing the PCE Root certificate, Please install the PCE root certificate on this workload and retry the install again" | Out-file -FilePath $Logpath\$DependencyLog -Append
        $counter++
    }
    if ($global:requiredCertsMissing -eq $true) {
        Write-Host -ForegroundColor yellow -Backgroundcolor black "1 or more certs missing, exiting"
        $counter++
    }
    If ($global:diskspace -eq $false ) {
        Write-Host -ForegroundColor yellow -Backgroundcolor black "You do not meet the required minimum free disk space of 500MB.  Recommended is 1.5 GB - 2 GB of free disk space, you have $global:diskfree GB of free disk space on the C: Drive"
        "$(date) You do not meet the required minimum free disk space of 500MB.  Recommended is 1.5 GB - 2 GB of free disk space, you have $global:diskfree GB of free disk space on the C: Drive" | Out-file -FilePath $Logpath\$DependencyLog -Append
        $counter++
    } 
    if ($global:rebootrequired -eq $true) {
        Write-Host -ForegroundColor yellow -Backgroundcolor black "Reboot required, reboot workload before installing and pairing the VEN"
        "$(date) Reboot required, reboot workload before installing and pairing the VEN" | Out-file -FilePath $Logpath\$DependencyLog -Append
        $counter++
    }
    if ($global:adminUser -eq $false) {
        Write-Host -ForegroundColor yellow -Backgroundcolor black "Must be an Admin user to install the VEN"
        "$(date) Must be an Admin user to install the VEN" | Out-file -FilePath $Logpath\$DependencyLog -Append
        $counter++
    }
    if ($global:psversion -eq $false) {
        Write-Host -ForegroundColor yellow -Backgroundcolor black "Must be at least PowerShell version 3"
        "$(date) Must be at least PowerShell version 3" | Out-file -FilePath $Logpath\$DependencyLog -Append
        $counter++
    }    
    if ($global:TestPCEPort1 -eq $false) {
        Write-Host -ForegroundColor yellow -Backgroundcolor black "Workload cannot reaching PCE port $PCEPort1, you may need to contact your IT team to open it"
        "$(date) Workload cannot reaching PCE port $PCEPort1, you may need to contact your IT team to open it" | Out-file -FilePath $Logpath\$DependencyLog -Append
        $counter++
    }
    if ($global:retvalue.TLSv1_2 -eq $false) {
        Write-Host -ForegroundColor yellow -Backgroundcolor black "TLS v1.2 not enabled on the Workload or workload cannot reach PCE"
        "$(date) TLS v1.2 is not enabled on the Workload or workload cannot reach PCE.  The VEN requires TLS 1.2 support to function.  
         See https://docs.microsoft.com/en-us/windows-server/security/tls/tls-registry-settings for more details" | Out-file -FilePath $$Logpath\$DependencyLog -Append
        $counter++
    }
    if ($pairingscriptgood -eq $false) {
        Write-Host -ForegroundColor yellow -Backgroundcolor black "Please check that you pasted the Pairing Script properly in the variable" 
        "$(date) Please check that you pasted the Pairing Script properly in the pairingscript variable at top of script." | Out-file -FilePath $Logpath\$DependencyLog -Append
        $counter++
    }
    if ($counter -gt 0) {
        Variablecleanup
        Write-Host -ForegroundColor yellow -Backgroundcolor black "1 or more pre-requisites missing, check the $Logpath\$DependencyLog file "
        break
        exit
    }

    else {
        Write-Host "All pre-requistes exist continuing"
    }  
}      


################################################################################################# 
## Install the VEN agent                                                                       ##
#################################################################################################
function VENInstall {

 
    PowerShell -Command "& $installscript"
       
}


################################################################################################# 
## Install of VEN                                                                              ##
#################################################################################################
            
VerifyAdmin
PSVers
LogPathCheck
VENVer
getFQDN
PSv3Dependencies
verifyreboot
VENCertCheck
PCErootVerify
ReqCheck
VENInstall
RemoveVariables


################################################################################################# 
## Script end                                                                                  ##
#################################################################################################