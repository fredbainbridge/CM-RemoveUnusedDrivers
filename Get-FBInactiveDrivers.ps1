#Find all drivers packages that are not used in a task sequence.
#this will only work if you are relying on an auto apply drivers step that considers all available drivers. (I think)

[CmdletBinding()]
param(
    [string]$SiteCode = "ARC",
    $Delete = $false
)
Import-Module "C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1"

set-location $SiteCode`:

function EvaluateTS {
    [CmdletBinding()]
    param(
        $TaskSequenceXML
    )
    $ids = @();  #category or package ID
    $TaskSequenceXML | ForEach-Object {
        #write-host "Group:  $($PSItem.name)"
        if($psitem.step){
            $psitem.step | ForEach-Object {
                if($psitem.type -eq 'SMS_TaskSequence_ApplyDriverPackageAction') 
                { 
                    #write-verbose 'RunCommandLine'
                    Write-Verbose $psitem.name
                    $index = (([xml]$PSItem.OuterXml).step.OuterXml).IndexOf('/install:')
                    $PackageID = (([xml]$PSItem.OuterXml).step.OuterXml).Substring($index + '/install:'.Length,8)
                    #if([string]$PackageID -ne ' powersh')
                    #{
                        if(Get-CMDriverPackage -Id $PackageID) 
                        {
                            write-verbose $PackageID
                            $ids += $PackageID
                        }
                    #}
                }
                if($psitem.type -eq 'SMS_TaskSequence_AutoApplyAction') 
                {
                    write-verbose 'Auto Apply Drivers'
                    $index = (([xml]$PSItem.OuterXml).step.OuterXml).IndexOf('DriverCategories:')
                    if($index -ne "-1") 
                    {
                        $CategoryID = (([xml]$PSItem.OuterXml).step.OuterXml).Substring($index + 'DriverCategories:'.Length,36)
                        write-verbose $CategoryID
                        $ids += $CategoryID
                    }
                    #write-host $CategoryIDs
                }
            } #end of steps
        }
        if($psitem.group)
        {
            $ids += EvaluateTS -TaskSequenceXML $psitem.group -verbose  
        }

    }
    #write-output $CategoryIDs -verbose
    #Write-Output $packageIDs -verbose
    write-output $ids
}
$IDs = @()


Get-CMTaskSequence | ForEach-Object {
    #([xml](Get-CMTaskSequence | select sequence).sequence)
    $sequence = [xml]$psitem.sequence
    $IDs += EvaluateTS -TaskSequenceXML $sequence.sequence -verbose 
}

#get drivers IDs used in boot images
$driversInBootMedia = @();
Write-Verbose "Looking for drivers referenced by boot images"
Get-CMBootImage | ForEach-Object {
    $bootImageName = $psitem.name
    $PSItem.ReferencedDrivers | ForEach-Object {
        $driversInBootMedia += $PSItem.id
        write-verbose "Found driver $($psitem.id) in boot image $bootImageName"
    }    
}
$IDs = $IDs | select -Unique
$UnusedDrivers = @{};

$Categories = $IDs -match ("(\{){0,1}[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}(\}){0,1}")
$Packages = $IDs -notmatch ("(\{){0,1}[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}(\}){0,1}")

#WMI Example 
#Get-WmiObject -Query "select * from sms_driver where ci_id = '17101826'" -Namespace 'root\sms\site_arc'


Get-CMDriver | ForEach-Object {
    $IsInAUsedCategory = $false
    $IsInaUsedPackage = $false
    $IsInBootMedia = $false

    $DriverID = $PSItem.CI_ID
    $driverName = $PSItem.LocalizedDisplayName
    write-verbose "---------$driverName---------"
    #is this in a used category?
    if($PSItem.CategoryInstance_UniqueIDs -ne $null)
    {
        $tmpIds = $PSItem.CategoryInstance_UniqueIDs
        $tmpIds | %{($_.ToString()).substring(17)} | Where-Object { $PSItem -in $Categories} | ForEach-Object { 
            $IsInAUsedCategory = $true 
            write-verbose "$driverName is in active category $PSItem"
        }       
    }
    if(-not $IsInAUsedCategory) {
        Write-verbose "$driverName is not in an active category"
    }
    
    #is this in a used driver package?
    $packages | ForEach-Object {
        Get-WmiObject -Query "select * from sms_drivercontainer where packageID = '$PSitem' and ci_id = '$DriverID'" -Namespace 'root\sms\site_arc' | foreach-Object {
            write-verbose "$driverName is in active package $PSitem" 
            $IsInaUsedPackage = $true
        }
    }
    if( -not $IsInaUsedPackage)
    {
        write-verbose "$driverName is not in an active package " 
    }
    
    #is it boot media?
    if($DriverID -in $driversInBootMedia)
    {
        write-verbose "$drivername is in a boot media"
        write-host "IN BOOT MEDIA" -foregroundcolor MAGENTA
        $IsInBootMedia = $true
    }
    else
    {
        write-verbose "$drivername is not in a boot media"
    }
    if(-not $IsInAUsedCategory -and (-not $IsInaUsedPackage) -and (-not $IsInBootMedia))  #this is an unused driver.
    {
        $UnusedDrivers.Add($driverID, $driverName)
        write-verbose "$driverName, ID: $DriverID is unused and can be deleted."
        write-host "unused"
    }
}

#evaluate if driver packages are used
#Unused Driver Packages.  This is unlikely to be super helpful.  Drivers in packages will also have categories.  
write-verbose "Looking for unused driver packages.  This is not super helpful"
$unusedDriverPackages = @();
Get-CMDriverPackage | ForEach-Object {
    if($PSItem.PackageID -in $packages ) {
        
        Write-verbose "Driver Package $($PSItem.Name) is in use"
    }
    else
    {
        Write-verbose "Driver Package $($PSItem.Name) is not in use" 
        $unusedDriverPackages += $PSItem.PackageID
    }
}

#evaluate which driver categories are used
$unusedCategories = @();
Get-CMCategory -CategoryType DriverCategories | ForEach-Object {
    
    $tmpCat = $psitem.CategoryInstance_UniqueID
    $tmpCat = $tmpCat.substring(17)
    if($tmpCat -in $Categories)
    {
        Write-Verbose "Category $tmpcat is in use"
    }
    else
    {
        write-verbose "Category $tmpCat is not in use"
        $unusedCategories += $tmpCat
    }
}

#delete the drivers
write-host "this should be like 1715ish"
write-host $UnusedDrivers.count
