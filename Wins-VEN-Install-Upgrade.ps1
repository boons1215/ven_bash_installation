#################################################################################################
#                                                                                               #
# The purpose of this script is to install or upgrade the latest version of the Illumio VEN on  #
# Windows   This script will do the following:                                                  #
#  1. Install or upgrades the VEN to location specified in the Modify These Variables section   #
#  2. Enables WFP Optimization on the VEN if needed                                             #
#  3. Pairs the VEN to the PCE                                                                  #
#  4. Allowed datadir path check                                                                #
#  5. Added certs installed                                                                     #
#  6. Upgraded to 19.3.4 tested                                                                 #                                                            #
#                                                                                               #
# NOTE:  This script MUST be ran as an administrator to be successful.                          #
# NOTE:  The default Install Folder and Data Folder are the default variables                   #
#                                                                                               #
#  Written by Greg DiRubbio - Illumio Professional Services, Illumio Inc.                       #
#  Updated by Siew Boon Siong - Illumio Professional Services, 06-Jan-2020                      #
#                                                                                               #
#################################################################################################


#################################################################################################
## ONLY Modify The variables below                                                             ##
## the VENAGent32 variable is for AUS deployments only and can be ignored when deploying to    ##
## only supported servers                                                                      ##
#################################################################################################

$hostname = hostname
$Illumio_MSI_Log = "C:\temp\illumio\IllumioMSI.log"
$DependencyLog = "C:\temp\illumio\Illumio-Dependencies-$hostname.log"
$WorkingDir = "C:\temp\illumio"

#$VENVersion="18.2.4-4528" # The VEN version that you going to use
#$VENVersion = "19.3.0-6104" # The VEN version that you going to use
$VENVersion = "19.3.4-6371"
$VENInstallFolder = "C:\Program Files\Illumio"

$dataPathDrive = "D:" # For data dir	
$altDataPathDrive = "E:" # For data dir	

$ActivationCode = "143a28dbbb9b364f8bccac650e4607ff5cd2ad906f36112ee1667cc39cb52215b0ea90de54bf6"
 
$ManagementServer = "mseg.sgp.com"
$PCEPort1 = "8443" #The port you pair your VENs to PCE
$PCEPort2 = "8444"
$rebootcheck = "NO"
## rebootcheck verifies if the workload has a pending reboot prior to the VEN being installed  ##

$PCECertcheck = "YES"
$MyPCERootCertThumbprint = "540db45eab09f3844325c61d15bb5b476134c7" #DBS Root Cert
$RootCert = "w01gimsmrca1a_-Root-CA.crt"
$MyPCERootCertThumbprint_2 = "30aad325c4bcc5828a0f0d762e90d4c444ca73" #DBS Int cert
$RootCert_2 = "Bank-Ent-SubCA.crt"
## If PCECertcheck is set to YES you must get the root cert thumprint                          ##
## To get the thumprint of your PCE root certificate on a machine you know has the root        ## 
## certificate installed, either run the following powershell command                          ##
## Get-ChildItem -Path Cert:\LocalMachine\root                                                 ##
## or look at the local computer certs in the MMC and look at the details of your PCE root     ##
## certificate and find the thumbprint value                                                   ## 

#################################################################################################
## DO NOT MODIFY ANYTHING BELOW THIS LINE                                                      ##
#################################################################################################

# Before 19.3.2
#$VENAgent64 = "C:\temp\illumio\VENInstaller-$VENVersion-x64.msi"
#$VENAgent32 = "C:\temp\illumio\VENInstaller-$VENVersion-x86.msi"

# After 19.3.2
$VENAgent64 = "C:\temp\illumio\illumio-ven-$VENVersion.win.x64.msi"
$VENAgent32 = "C:\temp\illumio\illumio-ven-$VENVersion.win.x86.msi"

#################################################################################################
## System Variables                                                                            ##
#################################################################################################

$ErrorActionPreference = 'SilentlyContinue'
$counter = 0
$upgrade_c = 0

#################################################################################################
## Build Title                                                                                 ##
#################################################################################################

$myProgrammTitle = "VEN Install or Upgrade"
$myProgramVersion = "3.8"
$myOutput = "  " + $myProgrammTitle + ", Version: " + $myProgramVersion + ", Illumio Inc. 2021  "
for ($i = 0 ; $i -lt ($myOutput.length); $i++) { $myOutPutUnderline += "-" }

# Write title to screen
Write-Host -ForegroundColor yellow -Backgroundcolor black $myOutPutUnderline
Write-Host -ForegroundColor white -Backgroundcolor black $myOutput
Write-Host -ForegroundColor yellow -Backgroundcolor black $myOutPutUnderline

#################################################################################################
## Verify All Pre-requisites                                                                   ##
#################################################################################################

cd $WorkingDir

#################################################################################################	
## Verify Data Path                                                        ##	
#################################################################################################	
function DataPathCheck {	
    $driveCheck = Test-Path -Path $dataPathDrive	
    if (-not ($driveCheck)) {	
        Write-Output "$dataPathDrive drive is not exist, switch to $altDataPathDrive drive and checking."	
        $driveCheck = Test-Path -Path $altDataPathDrive	
        if (-not ($driveCheck)) {	
            Write-Output "$altDataPathDrive drive is not exist either, Data folder is going to install in C: drive"	
            $global:VENDataFolder = "C:\ProgramData\Illumio\"	
        }	
        else {	
            Write-Output "Data folder is going to install in $altDataPathDrive drive"	
            $global:VENDataFolder = "$altDataPathDrive\ProgramData\Illumio\"	
        }	
    }	
    else {	
        $global:VENDataFolder = "$dataPathDrive\ProgramData\Illumio\"	
        Write-Output "Data folder is going to install in $dataPathDrive drive"	
    }
}

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
        
    
#################################################################################################
## Verify if this Windows is supported by VEN or not (not currently used in script)            ##
#################################################################################################

function OSCheck {
    $result = (Get-WmiObject Win32_OperatingSystem).caption | % { $_.Split(' ')[3]; }
    if ($result -eq "2012" -or $result -eq "2016" -or $result -eq "2019") {
        $global:oscheck = "YES"
    }
    elseif ($result -eq "2008") {
        $checksub = (Get-WmiObject Win32_OperatingSystem).caption | % { $_.Split(' ')[4]; }
        if ($checksub -eq "R2") {
            $global:oscheck = "YES"
        }
        else {
            $global:oscheck = "NO"
        }
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
            
        $global:rebootrequired = "YES" 
        
    }

    else {
        Write-Output "No pending reboot, install will continue" 
        $global:rebootrequired = "NO"   
    }
}

function verifyreboot {

    if ($rebootcheck -eq "YES") {
        Test-Pending-Reboot
    }

    else { 
        Write-Output "Pending Reboot Check skipped, continuing"
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

        Write-Host "Missing the following Root certificate: $cert1, reinstalling this root certificate and retry the install again" 
        "$(date) Missing the following certificate: $cert1, reinstalling this root certificate and retry the install again" | Out-file -FilePath $DependencyLog -Append
        certutil.exe -addstore -f "Root" $WorkingDir\DigiCertHighRootCA.cer
    }
        
    if (!$global:check2) {

        Write-Host "Missing the following Root certificate: $cert2, reinstalling this root certificate and retry the install again"
        "$(date) Missing the following certificate: $cert2, reinstalling this root certificate and retry the install again" | Out-file -FilePath $DependencyLog -Append
        certutil.exe -addstore -f "Root" $WorkingDir\VerisignUniversalRootCA.cer
    }
    

    $global:check1 = Get-ChildItem -Path Cert:\LocalMachine\root | Where-Object { $_.Subject -eq $global:cert1 } | Select-Object -Property subject
    $global:check2 = Get-ChildItem -Path Cert:\LocalMachine\root | Where-Object { $_.Subject -eq $global:cert2 } | Select-Object -Property subject

    if (!$global:Check1 -OR !$global:Check2) {
        
    
        $global:requiredCertsMissing = "YES"
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
    }
    else {
        $global:PCECertsMissing = "NO"
        $MissingRootCertCounter = 0
        Write-Host "PCE Root Cert exists, continuing"
    }
}

function PCERootCertVerify_2 {
    $global:PCERootCertCheck = Get-ChildItem -Path Cert:\LocalMachine\root | Where-Object { $_.Thumbprint -eq "$MyPCERootCertThumbprint_2" }

    if (!$global:PCERootCertCheck) { 
        $MissingRootCertCounter++
        RootCertInstall
    }
    else {
        $global:PCECertsMissing = "NO"
        $MissingRootCertCounter = 0
        Write-Host "PCE Root Cert exists, continuing"
    }
}

function RootCertInstall {
    write-Host "$MissingRootCertCounter"
    if (($MissingRootCertCounter -eq "1") -and (Test-Path -path $WorkingDir\$RootCert)) {
        Write-Host "Trying to install the Root Cert and retry"
        certutil.exe -addstore -f "Root" $WorkingDir\$RootCert
        certutil.exe -addstore -f "Root" $WorkingDir\$RootCert_2
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
        PCERootCertVerify_2
    }

    else { 
        $global:PCECertceck = "Skipped"
        Write-Output "PCE Cert Root Verification Check skipped, continuing"
    }
}


################################################################################################# 
## Verify VEN Path Exists                                                                      ##
#################################################################################################

function VenPath {
    if (!(Test-Path -path $global:VEN)) {
        $global:VENexists = "NO" 
    }
}

#################################################################################################
## Check if workload can reach PCE ports                                                       ##
#################################################################################################

function TestPCEPort1 {
    $PCEPort1Test = New-Object System.Net.Sockets.TcpClient "$ManagementServer", $PCEPort1
    if ($PCEPort1Test.Connected) {
        $global:TestPCEPort1 = "YES"
    }
    else {
        $global:TestPCEPort1 = "NO"
    }
}
    
function TestPCEPort2 {
    $PCEPort2Test = New-Object System.Net.Sockets.TcpClient "$ManagementServer", $PCEPort2
    if ($PCEPort2Test.Connected) {
        $global:TestPCEPort2 = "YES"
    }
    else {
        $global:TestPCEPort2 = "NO"
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

    $installdrive = $global:VENDataFolder.SubString(0, 2)
    $Global:Disk = Get-WmiObject -Class Win32_logicaldisk -Filter "DeviceID = '$installdrive'" | Select-Object -Property DeviceID, 
    @{L = 'FreeSpaceGB'; E = { "{0:N2}" -f ($_.FreeSpace /1GB) } },
    @{L = "Capacity"; E = { "{0:N2}" -f ($_.Size/1GB) } }

}



################################################################################################# 
## Remove All Variables                                                                        ##
#################################################################################################
function RemoveVariables {

    Write-Host "Cleaning up all variables"

    Clear-Variable -Name hostname -scope Script
    Clear-Variable -Name Illumio_MSI_Log -scope Script
    Clear-Variable -Name DependencyLog -scope Script
    Clear-Variable -Name VENAgent64 -scope Script
    Clear-Variable -Name VENAgent32 -scope Script
    Clear-Variable -Name VENInstallFolder -scope Script
    Clear-Variable -Name VENDataFolder -scope Script
    Clear-Variable -Name ActivationCode -scope Script
    Clear-Variable -Name ManagementServer -scope Script
    Clear-Variable -Name PCEPort1 -scope Script
    Clear-Variable -Name PCEPort2 -scope Script
    Clear-Variable -Name rebootcheck -scope Script
    Clear-Variable -Name PCECertcheck -scope Script
    Clear-Variable -Name MyPCERootCertThumbprint -scope Script
    Clear-Variable -Name MyPCERootCertThumbprint_2 -scope Script
    Clear-Variable -name VEN -Scope Global
    Clear-Variable -name VEnVer -Scope Global
    Clear-Variable -name NewVenVer -Scope Global
    Clear-Variable -name VenReg -Scope Global
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
    Clear-Variable -name VENexists -Scope Global
    Clear-Variable -name TestPCEPort1 -scope Global
    Clear-Variable -name TestPCEPort2 -scope Global
    Clear-Variable -name upgrade_c -Scope Global
}  
################################################################################################# 
## Prequisite Check OutPut                                                                     ##
#################################################################################################


function ReqCheck {
    if ($global:PCECertsMissing -eq "YES") {

        Write-Host "ERROR: Missing the PCE Root certificate, Please install the PCE root certificate on this workload and retry the install again"
        "$(date) ERROR: Missing the PCE Root certificate, Please install the PCE root certificate on this workload and retry the install again" | Out-file -FilePath $DependencyLog -Append
        $counter++
    }
    if ($global:requiredCertsMissing -eq "YES") {
        Write-Host "ERROR: 1 or more certs missing, exiting"
        $counter++
    }
    if ($global:rebootrequired -eq "YES") {
        Write-Output "ERROR: Reboot required, reboot workload before installing and pairing the VEN"
        "$(date) ERROR: Reboot required, reboot workload before installing and pairing the VEN" | Out-file -FilePath $DependencyLog -Append
        $counter++
    }
    if ($global:adminUser -eq $false) {
        Write-Output "ERROR: Must be an Admin user to install the VEN"
        "$(date) ERROR: Must be an Admin user to install the VEN" | Out-file -FilePath $DependencyLog -Append
        $counter++
    }
    If ($Global:disk.FreeSpaceGB -lt 0.5) {
        Write-host "ERROR: You do not meet the required minumim free disk space of 500MB.  Recommened 1.5 GB - 2 GB of free disk space"
        "$(date) ERROR: You do not meet the required minumim free disk space of 500MB.  Recommened 1.5 GB - 2 GB of free disk space" | Out-file -FilePath $DependencyLog -Append
        $counter++
    }
    if ($global:VENexists -eq "NO") {
        Write-Output "ERROR: Path to VEN does not exist, please modify this script"
        "$(date) ERROR: Path to VEN does not exist, please modify this script" | Out-file -FilePath $DependencyLog -Append
        $counter++
    }
    if ($global:psversion -eq $false) {
        Write-Output "ERROR: Must be at least PowerShell version 2"
        "$(date) ERROR: Must be at least PowerShell version 2" | Out-file -FilePath $DependencyLog -Append
        $counter++
    }    
    if ($global:TestPCEPort1 -eq "NO") {
        Write-Host "ERROR: Workload cannot reaching PCE port $PCEPort1, you may need to contact your IT team to open it"
        "$(date) ERROR: Workload cannot reaching PCE port $PCEPort1, you may need to contact your IT team to open it" | Out-file -FilePath $DependencyLog -Append
        $counter++
    }
    if ($global:TestPCEPort2 -eq "NO") {
        Write-Host "ERROR: Workload cannot reaching PCE port $PCEPort2, you may need to contact your IT team to open it"
        "$(date) ERROR: Workload cannot reaching PCE port $PCEPort2, you may need to contact your IT team to open it" | Out-file -FilePath $DependencyLog -Append
        $counter++
    }
    if ($global:retvalue.TLSv1_2 -ne "True") {
        Write-host "ERROR: TLS v1.2 not enabled on the Workload"
        "$(date) ERROR: TLS v1.2 is not enabled on the Workload.  The VEN requires TLS 1.2 support to function.  
            See https://docs.microsoft.com/en-us/windows-server/security/tls/tls-registry-settings for more details" | Out-file -FilePath $DependencyLog -Append
        $counter++
    }
    if ($counter -gt 0) {
        Variablecleanup
        Write-host "ERROR: 1 or more pre-requisites missing, check the $DependencyLog file "
        RemoveVariables
        break
        exit
    }

    else {
        Write-Host "All pre-requistes exist continuing"
    }  
}      

################################################################################################# 
## Upgrade VEN Function                                                                        ##
#################################################################################################

function Upgrade {
    if ($global:NewVenVer -lt $global:VEnVer) {
        Write-Host "VEN Upgrade Version is less than $VenVer, nothing to upgrade, exiting"
        break
    }
    
    elseif ($global:NewVenVer -ge $global:VEnVer ) {

        Write-Host "Upgrading VEN to Version $global:NewVenVer"   
        #&cmd /c "msiexec /i `"$VEN`" INSTALLFOLDER=`"$VENInstallFolder`"  /qn /l*vx $Illumio_MSI_Log"
        #&cmd /c "msiexec /i `"$global:VEN`" INSTALLFOLDER=`"$VENInstallFolder`" DATAFOLDER=`"$global:VENDataFolder`" /qn /l*vx $Illumio_MSI_Log"
        &cmd /c "msiexec /i `"$global:VEN`" DATAFOLDER=`"$global:VENDataFolder`" /qn /l*vx $Illumio_MSI_Log"

        Write-host "Done"
        $upgrade_c++
    }
}

function Post_Upgrade {
    if ($upgrade_c -gt 0) {
        if ($global:VEnVer = $VENVersion ) {
            Write-host "Upgrade to $global:VEnVer Completed"
        }
        else {
            Write-host "Upgrade to $global:VEnVer not success"
        }
    }
}

#################################################################################################
## Detect if OS is 32-bit or 64-bit                                                            ##
#################################################################################################
function OSdetect {

    if ((gwmi win32_operatingsystem | select osarchitecture).osarchitecture -eq "64-bit") {
        
        $global:VEN = $VENAgent64
    }
    else {
        
        $global:VEN = $VENAgent32
    }
}
################################################################################################# 
## Get MSI Version Function                                                                    ##
#################################################################################################
function getMSIVersion {
    param(
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.IO.FileInfo]$Path,
    
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("ProductCode", "ProductVersion", "ProductName", "Manufacturer", "ProductLanguage", "FullVersion")]
        [string]$Property
    )
    Process {
        try {
            # Read property from MSI database
            $WindowsInstaller = New-Object -ComObject WindowsInstaller.Installer
            $MSIDatabase = $WindowsInstaller.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $WindowsInstaller, @($Path.FullName, 0))
            $Query = "SELECT Value FROM Property WHERE Property = '$($Property)'"
            $View = $MSIDatabase.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $MSIDatabase, ($Query))
            $View.GetType().InvokeMember("Execute", "InvokeMethod", $null, $View, $null)
            $Record = $View.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $View, $null)
            $Value = $Record.GetType().InvokeMember("StringData", "GetProperty", $null, $Record, 1)
    
            # Commit database and close view
            $MSIDatabase.GetType().InvokeMember("Commit", "InvokeMethod", $null, $MSIDatabase, $null)
            $View.GetType().InvokeMember("Close", "InvokeMethod", $null, $View, $null)           
            $MSIDatabase = $null
            $View = $null
    
            # Return the value
            return $Value
        } 
        catch {
            Write-Warning -Message $_.Exception.Message ; break
        }
    }
    End {
        # Run garbage collection and release ComObject
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($WindowsInstaller) | Out-Null
        [System.GC]::Collect()
    }
}

################################################################################################# 
## Determine if VEN is installed and what the new VEN version is                               ##
#################################################################################################

function VENVer {

    $global:VenReg = (Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall") |
    Where-Object { $_.GetValue( "DisplayName" ) -like "*Illumio VEN*" } 

    if ($global:VenReg -ne $null) {

        $global:VEnVer = (Get-ItemProperty Registry::$global:Venreg -name DisplayVersion).DisplayVersion | Out-String
    }


    $global:NewVenVer = getmsiversion -path $global:VEN -Property ProductVersion | Out-String 

}


################################################################################################# 
## Install the VEN agent                                                                       ##
#################################################################################################

function installMSI {
    
    &cmd /c "msiexec /i `"$global:VEN`" INSTALLFOLDER=`"$VENInstallFolder`" DATAFOLDER=`"$global:VENDataFolder`" /qn /l*vx $Illumio_MSI_Log"

}
    
function InstallLogic {

    if ($global:NewVenVer -le "17.4") {
            
        Write-Output "VEN version not supported with this script, please use older install script v2.5 or use a newer VEN version 18.x or newer"
        break
            
    }

    elseif ($global:NewVenVer -gt "18.0") {
            
        installMSI
        #Start-Sleep -s 20
        pair
    }
}



    
################################################################################################# 
## Pairs the VEN with the PCE                                                                  ##  
#################################################################################################

function Pair {
    if ($upgrade_c -gt 0) {
        Write-Output "Paired."
    }
    else {
        cd "$VENInstallFolder"
        .\illumio-ven-ctl.ps1 activate -activation-code $ActivationCode -management-server $ManagementServer":"$PCEPort1
        Write-Output "Done"
    }
}

################################################################################################# 
## Determine Upgrade or Install of VEN                                                         ##
#################################################################################################
                
OSdetect
VerifyAdmin
PSVers
DataPathCheck
TestPCEPort1
TestPCEPort2
verify-tls
verifyreboot
PCErootVerify
VENCertCheck
DiskSpaceCheck
VenPath
ReqCheck
VENVer
                
        
if ($global:VENver -ne $null) {
    Write-Output "VEN Already installed ......"
    #Write-Output "VEN Already installed, attempting upgrade ......"
    Upgrade
    Post_Upgrade
    Pair
    RemoveVariables
            
}
else {
            
    Write-Output "VEN not installed, attempting to install and pair ......"
    InstallLogic
    RemoveVariables

}


################################################################################################# 
## Script end                                                                                  ##
#################################################################################################
