#                                                                                               #
# Copyright 2013-2020 Illumio, Inc. All Rights Reserved.                                        #
#
# Created by: Siew Boon Siong
# Email: boon.siew@illumioeval.com
# Updated: Feb-04-2020
# Version: 1.0
#
# To transfer files to remote host and run its
#

$Username = Read-Host "Enter Admin User"
$Password = Read-Host -assecurestring "Enter Password"
$pass = ConvertTo-SecureString -AsPlainText $Password -Force
$Cred = New-Object System.Management.Automation.PSCredential -ArgumentList $Username, $pass
$InputFile = 'C:\Temp\windowservers.txt'
$ScriptFile = 'VEN-Install-SaaS-repo-v1.3.1.ps1'
$addresses = get-content $InputFile
$reader = New-Object IO.StreamReader $InputFile
while ($reader.ReadLine() -ne $null) { $TotalIPs++ }
$installStatusLog = "C:\Temp\Illumio-VEN-Install.log"
$dnsResolver = "C:\Temp\dnsResolver.log"
write-host    ""
write-Host "Pinging each address..."
foreach ($address in $addresses) {
    $counter = 0
    ## Progress bar
    $j++
    $percentdone2 = (($j / $TotalIPs) * 100)
    $percentdonerounded2 = "{0:N0}" -f $percentdone2
    $Session = New-PSSession -Name $address -ComputerName $address -Credential $Cred 2>&1
    Write-Progress -Activity "Performing pings" -CurrentOperation "Pinging IP: $address (IP $j of $TotalIPs)" -Status "$percentdonerounded2% complete" -PercentComplete $percentdone2
    ## End progress bar
    if (!(test-Connection -ComputerName $address -Count 2 -Quiet )) {
        Write-Warning "$address does not respond to pings"
        "$address, no response to ping" | Out-file -FilePath $installStatusLog -Append
    }
    else {
        write-host    ""
        write-Host "##############################################" -ForegroundColor Red
        write-Host "Check $address" -ForegroundColor Green
        write-Host "$address ping responded" -ForegroundColor Green
        write-host    ""
        Try {
            if ($counter -eq 0) {
                $tmpPath = "C:\temp\"
                $testTmpPath = Invoke-Command -ScriptBlock { test-path C:\temp } -ComputerName $address -Credential $Cred
                If (!($testTmpPath)) {
                    Invoke-Command -ScriptBlock { mkdir C:\temp } -ComputerName $address -Credential $Cred
                }
                Copy-Item -Path C:\Temp\$ScriptFile -Destination C:\Temp\$ScriptFile -ToSession $Session
                Copy-Item -Path C:\Temp\*crt -Destination C:\Temp\ -ToSession $Session
                Invoke-Command -FilePath C:\Temp\$ScriptFile -ComputerName $address -Credential $Cred
                $testActPath = Invoke-Command -ScriptBlock { test-path C:\ProgramData\Illumio\etc\agent_activation.cfg } -ComputerName $address -Credential $Cred
                if ($testActPath) {
                    "$address, Activated" | Out-file -FilePath $installStatusLog -Append
                    Invoke-Command -ScriptBlock { Remove-Item C:\Temp\VEN-Install-SaaS-repo-v1* } -ComputerName $address -Credential $Cred
                }
                else {
                    If (!(test-path C:\temp\$address-failed)) {
                        $tempFile = "C:\temp\$address-failed"
                        mkdir $tempFile
                    }
                    "$address, Activate failed, check out $tempFile for detail" | Out-file -FilePath $installStatusLog -Append
                    Try {
                        Copy-Item -Path C:\Windows\temp\VENInstaller.log -FromSession $Session -Destination $tempFile
                        Copy-Item -Path C:\Windows\temp\illumio.log -FromSession $Session -Destination $tempFile
                        Copy-Item -Path C:\Windows\system32\Illumio-Dependencies-*.log -FromSession $Session -Destination $tempFile
                        Invoke-Command -ScriptBlock { Remove-Item C:\Temp\VEN-Install-SaaS-repo-v1* } -ComputerName $address -Credential $Cred
                    }
                    Catch {
                        Write-Warning "File probably not exist"
                    }
                }
                Get-PSSession | Remove-PSSession
                Start-sleep 5
            } 
        }
        Catch {
            Write-Warning "Access is denied"
            "$address, Access is denied" | Out-file -FilePath $installStatusLog -Append
        }
    }
}
write-host    ""
Start-sleep 10
write-Host "Resolving domain name on each address..."
foreach ($address in $addresses) {
    ## Progress bar
    $i++
    $percentdone = (($i / $TotalIPs) * 100)
    $percentdonerounded = "{0:N0}" -f $percentdone
    Write-Progress -Activity "Performing nslookups" -CurrentOperation "Working on IP: $address (IP $i of $TotalIPs)" -Status "$percentdonerounded% complete" -PercentComplete $percentdone
    ## End progress bar
    try {
        [system.net.dns]::resolve($address) | Select HostName, AddressList | Out-file -FilePath $dnsResolver -Append
    }
    catch {
        Write-host "$address was not found. $_" -ForegroundColor Green
    }
}
write-host    ""
exit