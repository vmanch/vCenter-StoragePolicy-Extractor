#Powershell collector script for vSAN storage policy compliance
#v1.0 vMan.ch, 28.08.2017 - Initial Version
<#
    Run the command below to store user and pass in secure credential XML for each environment

        $cred = Get-Credential
        $cred | Export-Clixml -Path "HOME-VC.xml"
#>

param
(
    [String]$VC,
    [String]$creds,
    [String]$FileName
)

#Logging Function
Function Log([String]$message, [String]$LogType, [String]$LogFile){
    $date = Get-Date -UFormat '%m-%d-%Y %H:%M:%S'
    $message = $date + "`t" + $LogType + "`t" + $message
    $message >> $LogFile
}

$ScriptPath = (Get-Item -Path ".\" -Verbose).FullName
$mods = "$ScriptPath\Modules;"
$random = get-random
$RunDateTime = (Get-date)
$RunDateTime = $RunDateTime.tostring("yyyyMMddHHmmss")
$RunDateTime = $RunDateTime + '_'  + $random
$LogFileLoc = $ScriptPath + '\Log\Logfile.log'

if($creds -gt ""){

    $cred = Import-Clixml -Path "$ScriptPath\config\$creds.xml"

    }
    else
    {
    echo "Environment not selected, stop hammer time!"
    Exit
    }

Log -Message "Starting Script" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc

Log -Message "Connecting to $VC with credentials $creds" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc

Connect-VIServer -server $VC -Credential $cred -Force 

$DiskPolicyReport = @()

Log -Message "Getting VM List from vCenter" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc

$vms = Get-VM

Log -Message "Running loop for VM Home Directory and VMDK Policy" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc

foreach ($vm in $vms){

    $vmCluster = Get-Cluster -VM $vm
    $vmDatastore = Get-Datastore -VM $vm

    
    $VMHome = $vm | get-SpbmEntityConfiguration

        Foreach ($VMH in $VMHome){

            $DiskPolicyReport += New-Object PSObject -Property @{

            VM = $vm
            Cluster = $vmCluster
            Datastore = $vmDatastore
            Entity = 'VMHome'
            Policy = $VMH.StoragePolicy
            Status = $VMH.ComplianceStatus
            DateTime = $VMH.TimeOfCheck

            }
                Remove-Variable VMH -Force -ErrorAction SilentlyContinue
        }

    $VMDisks = $vm | get-harddisk

        Foreach ($disk in $VMDisks){

            $VMDisk = $disk | get-SpbmEntityConfiguration

            $DiskPolicyReport += New-Object PSObject -Property @{

            VM = $vm
            Cluster = $vmCluster
            Datastore = [regex]::match($disk.Filename,'\[(.*?)\]').Groups[1].Value
            Entity = $VMDisk.Entity
            Policy = $VMDisk.StoragePolicy
            Status = $VMDisk.ComplianceStatus
            DateTime = $VMDisk.TimeOfCheck

            }
                Remove-Variable disk -Force -ErrorAction SilentlyContinue
        }



}


Log -Message "Generating report $FileName" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc

$DiskPolicyReport | select VM,Cluster,Datastore,Entity,Policy,Status,DateTime | export-csv $FileName -NoTypeInformation

Log -Message "Disconnecting from $VC" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc

Disconnect-VIServer -server $VC -Confirm:$false

Log -Message "Script Finished" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc