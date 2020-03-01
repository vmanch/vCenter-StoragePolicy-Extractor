#Powershell collector script for vSAN storage policy compliance
#v1.0 vMan.ch, 28.08.2017 - Initial Version
#v1.1 vMan.ch, 06.11.2019 - Push Storage policy data to vRops
<#
    Run the command below to store user and pass in secure credential XML for each environment

        $cred = Get-Credential
        $cred | Export-Clixml -Path "HOME-VC.xml"
#>

param
(
    [String]$VC,
    [String]$creds,
	[String]$vRopsAddress,
	[String]$vRopsCreds,
    [String]$FileName,
	[String]$ImportType
)

#Logging Function
Function Log([String]$message, [String]$LogType, [String]$LogFile){
    $date = Get-Date -UFormat '%m-%d-%Y %H:%M:%S'
    $message = $date + "`t" + $LogType + "`t" + $message
    $message >> $LogFile
}


#Log rotation function
function Reset-Log 
{ 
    #function checks to see if file in question is larger than the paramater specified if it is it will roll a log and delete the oldes log if there are more than x logs. 
    param([string]$fileName, [int64]$filesize = 1mb , [int] $logcount = 5) 
     
    $logRollStatus = $true 
    if(test-path $filename) 
    { 
        $file = Get-ChildItem $filename 
        if((($file).length) -ige $filesize) #this starts the log roll 
        { 
            $fileDir = $file.Directory 
            $fn = $file.name #this gets the name of the file we started with 
            $files = Get-ChildItem $filedir | ?{$_.name -like "$fn*"} | Sort-Object lastwritetime 
            $filefullname = $file.fullname #this gets the fullname of the file we started with 
            #$logcount +=1 #add one to the count as the base file is one more than the count 
            for ($i = ($files.count); $i -gt 0; $i--) 
            {  
                #[int]$fileNumber = ($f).name.Trim($file.name) #gets the current number of the file we are on 
                $files = Get-ChildItem $filedir | ?{$_.name -like "$fn*"} | Sort-Object lastwritetime 
                $operatingFile = $files | ?{($_.name).trim($fn) -eq $i} 
                if ($operatingfile) 
                 {$operatingFilenumber = ($files | ?{($_.name).trim($fn) -eq $i}).name.trim($fn)} 
                else 
                {$operatingFilenumber = $null} 
 
                if(($operatingFilenumber -eq $null) -and ($i -ne 1) -and ($i -lt $logcount)) 
                { 
                    $operatingFilenumber = $i 
                    $newfilename = "$filefullname.$operatingFilenumber" 
                    $operatingFile = $files | ?{($_.name).trim($fn) -eq ($i-1)} 
                    write-host "moving to $newfilename" 
                    move-item ($operatingFile.FullName) -Destination $newfilename -Force 
                } 
                elseif($i -ge $logcount) 
                { 
                    if($operatingFilenumber -eq $null) 
                    {  
                        $operatingFilenumber = $i - 1 
                        $operatingFile = $files | ?{($_.name).trim($fn) -eq $operatingFilenumber} 
                        
                    } 
                    write-host "deleting " ($operatingFile.FullName) 
                    remove-item ($operatingFile.FullName) -Force 
                } 
                elseif($i -eq 1) 
                { 
                    $operatingFilenumber = 1 
                    $newfilename = "$filefullname.$operatingFilenumber" 
                    write-host "moving to $newfilename" 
                    move-item $filefullname -Destination $newfilename -Force 
                } 
                else 
                { 
                    $operatingFilenumber = $i +1  
                    $newfilename = "$filefullname.$operatingFilenumber" 
                    $operatingFile = $files | ?{($_.name).trim($fn) -eq ($i-1)} 
                    write-host "moving to $newfilename" 
                    move-item ($operatingFile.FullName) -Destination $newfilename -Force    
                } 
                     
            } 
 
                     
          } 
         else 
         { $logRollStatus = $false} 
    } 
    else 
    { 
        $logrollStatus = $false 
    } 
    $LogRollStatus 
} 

Function GetReport([String]$vRopsAddress, [String]$ReportResourceID, [String]$ReportID, $vRopsCreds, $Path){
 
Write-host 'Running Report'
 
#RUN Report
 
$ContentType = "application/xml;charset=utf-8"
$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$header.Add("Accept", 'application/xml')
 
$RunReporturl = 'https://'+$vRopsAddress+'/suite-api/api/reports'
 
$Body = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<ops:report xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:ops="http://webservice.vmware.com/vRealizeOpsMgr/1.0/">
    <ops:resourceId>$ReportResourceID</ops:resourceId>
    <ops:reportDefinitionId>$ReportID</ops:reportDefinitionId>
</ops:report>
"@
 
 
[xml]$Data = Invoke-RestMethod -Method POST -uri $RunReporturl -Credential $vRopsCreds -ContentType $ContentType -Headers $header -Body $body
 
$ReportLink = $Data.report.links.link | Where name -eq 'linkToSelf' | Select 'href'	
 
$ReportLinkurl = 'https://' + $vRopsAddress + $ReportLink.href
 
#Check if report is run to download
 
[xml]$ReportStatus = Invoke-RestMethod -Method GET -uri $ReportLinkurl -Credential $vRopsCreds -ContentType $ContentType -Headers $header
 
 
While ($ReportStatus.report.status -ne "COMPLETED") {
    [xml]$ReportStatus = Invoke-RestMethod -Method GET -uri $ReportLinkurl -Credential $vRopsCreds -ContentType $ContentType -Headers $header
    Write-host 'Waiting for report to finish running, current status: '  $ReportStatus.report.status
    Sleep 3
      } # End of block statement
 
 
$ReportDownload = $ReportLinkurl + '/download?format=CSV'
 
Invoke-RestMethod -Method GET -uri $ReportDownload -Credential $vRopsCreds -ContentType $ContentType -Headers $header -OutFile $Path
 
 
return $Path
}

#Lookup Function to get resourceId from VM Name
Function GetObject([String]$vRopsObjName, [String]$resourceKindKey, [String]$vRopsServer, $vRopsCredentials){

    $vRopsObjName = $vRopsObjName -replace ' ','%20'

    [xml]$Checker = Invoke-RestMethod -Method Get -Uri "https://$vRopsServer/suite-api/api/resources?resourceKind=$resourceKindKey&name=$vRopsObjName" -Credential $vRopsCredentials -Headers $header -ContentType $ContentType

#Check if we get 0

    if ([Int]$Checker.resources.pageInfo.totalCount -eq '0'){

    Return $CheckerOutput = ''

    }

    else {

        # Check if we get more than 1 result and apply some logic
            If ([Int]$Checker.resources.pageInfo.totalCount -gt '1') {

                $DataReceivingCount = $Checker.resources.resource.resourceStatusStates.resourceStatusState.resourceStatus -eq 'DATA_RECEIVING'

                    If ($DataReceivingCount.count -gt 1){

                     If ($Checker.resources.resource.ResourceKey.name -eq $vRopsObjName){

                        ForEach ($Result in $Checker.resources.resource){

                            IF ($Result.resourceStatusStates.resourceStatusState.resourceStatus -eq 'DATA_RECEIVING'){

                            $CheckerOutput = New-Object PsObject -Property @{Name=$vRopsObjName; resourceId=$Result.identifier; resourceKindKey=$Result.resourceKey.resourceKindKey}

                            Return $CheckerOutput
                    
                            }   
                        }

                      }
                    }
            
                    Else 
                    {

                    ForEach ($Result in $Checker.resources.resource){

                        IF ($Result.resourceStatusStates.resourceStatusState.resourceStatus -eq 'DATA_RECEIVING'){

                            $CheckerOutput = New-Object PsObject -Property @{Name=$vRopsObjName; resourceId=$Result.identifier; resourceKindKey=$Result.resourceKey.resourceKindKey}

                            Return $CheckerOutput
                    
                        }   
                    }
            }  
         }

        else {
    
            $CheckerOutput = New-Object PsObject -Property @{Name=$vRopsObjName; resourceId=$Checker.resources.resource.identifier; resourceKindKey=$Checker.resources.resource.resourceKey.resourceKindKey}

            Return $CheckerOutput

            }
        }
}

$ScriptPath = (Get-Item -Path ".\" -Verbose).FullName
$random = get-random
$RunDateTime = (Get-date)
$RunDateTime = $RunDateTime.tostring("yyyyMMddHHmmss")
$RunDateTime = $RunDateTime + '_'  + $random
$LogFileLoc = $ScriptPath + '\Log\Logfile.log'
[DateTime]$NowDate = (Get-date)
[int64]$NowDateEpoc = (([DateTimeOffset](Get-Date)).ToUniversalTime().ToUnixTimeMilliseconds())

#cleanupLogFile
$LogFileLoc = $ScriptPath + '\Log\Logfile.log'
Reset-Log -fileName $LogFileLoc -filesize 10mb -logcount 5


if($creds -gt ""){

    $cred = Import-Clixml -Path "$ScriptPath\config\$creds.xml"

    }
    else
    {
    echo "Environment not selected, stop hammer time!"
    Exit
    }

if($vRopsCreds -gt ""){

    $vRopsCred = Import-Clixml -Path "$ScriptPath\config\$vRopsCreds.xml"

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

$ImportedPolicy = import-csv $FileName | select @{n='VM';e={$_.'VM'.toupper()}},@{n='Entity';e={$_.'Entity'.toupper()}},@{n='Policy';e={$_.'Policy'.toupper()}},@{n='Status';e={$_.'Status'.toupper()}}

$Groups = $ImportedPolicy | Group-Object -Property 'VM'

$VMPolicyPushCount = $Groups.Count

switch($ImportType)
    {

    Full {

            Write-Host "Create XML, lookup resourceId and pushing Storage Policy Data to vRops for $VMPolicyPushCount VM's"
            Log -Message "Create XML, lookup resourceId and pushing Storage Policy Data to vRops for $VMPolicyPushCount VM's" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc

            $XMLFile = @()

            #Create XML, lookup resourceId and push Data to vRops

            ForEach($VM in $Groups){

            #Create XML Structure and populate variables from the Metadata file

                $XMLFile = @('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                            <ops:property-contents xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:ops="http://webservice.vmware.com/vRealizeOpsMgr/1.0/">')

                            ForEach($Entity in $VM.group){

                                $XMLFile += @('<ops:property-content statKey="VMAN|POLICY|STORAGE|{1}|NAME">
                                                  <ops:timestamps>{0}</ops:timestamps>
                                                  <ops:values><![CDATA[{2}]]></ops:values>
                                               </ops:property-content>
                                           <ops:property-content statKey="VMAN|POLICY|STORAGE|{1}|STATUS">
                                                  <ops:timestamps>{0}</ops:timestamps>
                                                  <ops:values><![CDATA[{3}]]></ops:values>
                                               </ops:property-content>') -f $NowDateEpoc,
                                                                        ($Entity.'Entity').replace(' ',''),
                                                                        $Entity.'Policy',
                                                                        $Entity.'Status'

            }

                $XMLFile += @('</ops:property-contents>')

            [xml]$xmlSend = $XMLFile

            ##Debug Baby
            
            ##$output = $ScriptPath + '\XML\' + $VM.'Name' + '.xml'

            ##[xml]$xmlSend.Save($output)

            $VMName = $VM.'Name'

            #Run the function to get the resourceId from the VM Name
            $resourceLookup = GetObject $VMName 'VirtualMachine' $vRopsAddress $cred

            #Create URL string for Invoke-RestMethod
            $urlsend = 'https://' + $vRopsAddress + '/suite-api/api/resources/'+ $resourceLookup.resourceId + '/properties'

            Write-Host "Pushing $VMName to $urlsend"
            Log -Message "Pushing $VMName to $urlsend" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc

            #Send Attribute data to vRops.
            $ContentType = "application/xml;charset=utf-8"
            Invoke-RestMethod -Method POST -uri $urlsend -Body $xmlSend -Credential $vRopsCred -ContentType $ContentType

            #CleanUp Variables to make sure we dont update the next object with the same data as the previous one.
            Remove-Variable urlsend -ErrorAction SilentlyContinue
            Remove-Variable xmlSend -ErrorAction SilentlyContinue
            Remove-Variable XMLFile -ErrorAction SilentlyContinue
            }

            Write-Host "Done Importing properties for $VMPolicyPushCount VM's into vROPS"
            Log -Message "Done Importing properties for $VMPolicyPushCount VM's into vROPS" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc

            }
    Diff {

            #Coming Soon
        }

}

Log -Message "Script Finished" -LogType "JOB-$RunDateTime" -LogFile $LogFileLoc
