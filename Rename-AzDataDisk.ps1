<#
.SYNOPSIS Rename Azure Data Disks.

.DESCRIPTION Rename Azure VM Data Disks for Linux and Windows.

.NOTES File Name : Rename-AzDataDisk.ps1
Author   : Microsoft MVP/MCT - Charbel Nemnom
Version  : 1.0
Date     : 22-March-2022
Update   : 23-March-2022
Requires : PowerShell 5.1 or PowerShell 7.2.x (Core)
Module   : Az Module
OS       : Windows or Linux VMs

.LINK
To provide feedback or for further assistance please visit: https://charbelnemnom.com

.EXAMPLE
.\Rename-AzDataDisk.ps1 -VMName [VMName] -lunDataDisk [1] -newDataDiskName [NewDataDiskName] -Verbose
This example will rename the Data Disk for the specified VM, you need to specify the VM name, the LUN number of the existing data disk, and the new data disk name.
The script will create a copy of the existing data disk and then use the detach/attach disk feature in Azure to change the data disk on the fly.
#>

[CmdletBinding()]
Param (
    [Parameter(Position = 1, Mandatory = $True, HelpMessage = 'Enter Azure Virtual Machine name')]
    [Alias('VM')]
    [String]$VMName,

    [Parameter(Position = 2, Mandatory = $true, HelpMessage = 'Enter the Logical Unit Number (LUN) of the existing Data Disk that you want to rename')]
    [Alias('DataDiskLun')]
    [String]$lunDataDisk,

    [Parameter(Position = 2, Mandatory = $true, HelpMessage = 'Enter the new Data Disk name')]
    [Alias('DataDiskName')]
    [String]$newDataDiskName

)

#! Check Azure Connection
Try {
    Write-Verbose "Connecting to Azure Cloud..."
    Connect-AzAccount -ErrorAction Stop | Out-Null
}
Catch {
    Write-Warning "Cannot connect to Azure Cloud. Please check your credentials. Exiting!"
    Exit
}

$azSubs = Get-AzSubscription
$lookVM = 0
foreach ( $azSub in $azSubs ) {
    Set-AzContext -Subscription $azSub | Out-Null

    #! Get the details of the VM
    Write-Verbose "Get the VM information details: $VMName"
    $VM = Get-AzVM -Name $VMName

    if ($VM) {
        $lookVM++

        #! Get source Data Disk information
        Write-Verbose "Get the source Data Disk information: $diskName"
        $dataDiskInfo = ($VM.StorageProfile.DataDisks | where-object { $_.Lun -eq "$lunDataDisk" })
        if (!$dataDiskInfo) {
            Write-Warning "The Data Disk LUN Number $lunDataDisk cannot be found. Please check the Logical Unit Number. Exiting!"
            Exit
        }
        $sourceDataDisk = Get-AzDisk -ResourceGroupName $vm.resourceGroupName -DiskName $dataDiskInfo.Name

        #! Create the managed disk configuration
        Write-Verbose "Create the managed data disk configuration..."
        $diskConfig = New-AzDiskConfig -SkuName $sourceDataDisk.Sku.Name -Location $VM.Location `
            -DiskSizeGB $sourceDataDisk.diskSizeGB -SourceResourceId $sourceDataDisk.id -CreateOption Copy

        #! Create the new data disk
        Write-Verbose "Create the new Data Disk: $newDataDiskName"
        $newDataDisk = New-AzDisk -Disk $diskConfig -DiskName $newDataDiskName -ResourceGroupName $vm.resourceGroupName

        #! Detach the old data disk
        Write-Verbose "Detach the old data disk: $($dataDiskInfo.Name)"
        Remove-AzVMDataDisk -VM $VM -Name $dataDiskInfo.Name | Out-Null
        #! Updates the state of the Azure virtual machine.
        Write-Verbose "Updates the state of the Azure virtual machine: $VMName"
        Update-AzVM -ResourceGroupName $vm.resourceGroupName -VM $VM

        #! Attach the new data disk
        Write-Verbose "Attach the new data disk: $newDataDiskName"
        if ($dataDiskInfo.caching -like "None") {
            $dataDisk = Add-AzVMDataDisk -VM $vm -Name $newDataDiskName -Lun $lunDataDisk `
                -CreateOption Attach -ManagedDiskId $newDataDisk.Id
        }
        else {
            $dataDisk = Add-AzVMDataDisk -VM $vm -Name $newDataDiskName -Caching $dataDiskInfo.caching -Lun $lunDataDisk `
                -CreateOption Attach -ManagedDiskId $newDataDisk.Id
        }
        #! Updates the state of the Azure virtual machine.
        Write-Verbose "Updates the state of the Azure virtual machine: $VMName"
        Update-AzVM -ResourceGroupName $vm.resourceGroupName -VM $VM

        #! Delete the old Data Disk
        $delete = Read-Host "Do you want to delete the original Data Disk: $($dataDiskInfo.Name) [y/n]"
        If ($delete -eq "y" -or $delete -eq "Y") {
            Write-Warning "Deleting the old Data Disk: $($dataDiskInfo.Name)"
            Remove-AzDisk -ResourceGroupName $vm.resourceGroupName -DiskName $dataDiskInfo.Name -Force -Confirm:$false
        }
        Break
    }
}

If ($lookVM -eq 0) {
    Write-Warning "The Azure VM < $VMName > cannot be found. Please check your virtual machine name!"
}