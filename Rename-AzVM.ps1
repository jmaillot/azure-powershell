<#
.SYNOPSIS
Rename Azure VM.

.DESCRIPTION
Rename an Azure virtual machine for Linux and Windows OS.

.NOTES
File Name : Rename-AzVM.ps1
Author    : Microsoft MVP/MCT - Charbel Nemnom
Version   : 2.3
Date      : 29-August-2021
Update    : 24-January-2023
Requires  : PowerShell 5.1 or PowerShell 7.2.x (Core)
Module    : Az Module
OS        : Windows or Linux VMs
Support   : Managed and UnManaged Disks   

.LINK
To provide feedback or for further assistance please visit: https://charbelnemnom.com

.EXAMPLE
.\Rename-AzVM.ps1 -resourceGroup [ResourceGroupName] -OldVMName [VMName] -NewVMName [VMName] -Verbose
This example will rename an existing Azure virtual machine, you need to specify the Resource Group name, old VM name and the new VM name.
The script will preserve the old VM settings and resources, and then apply them to the new Azure VM.
#>

[CmdletBinding()]
Param (
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = 'Enter the Resource Group of the Azure VM')]
    [Alias('rg')]
    [String]$resourceGroup,

    [Parameter(Position = 1, Mandatory = $True, HelpMessage = 'Enter the existing Azure VM name')]
    [Alias('OldVM')]
    [String]$OldVMName,

    [Parameter(Position = 2, Mandatory = $true, HelpMessage = 'Enter the desired new Azure VM name')]
    [Alias('NewVM')]
    [String]$NewVMName
)

#! Check Azure Connection
Try {
    Write-Verbose "Connecting to Azure Cloud..."
    Connect-AzAccount -ErrorAction Stop | Out-Null
}
Catch {
    Write-Warning "Cannot connect to Azure Cloud. Please check your credentials. Exiting!"
    Break
}

$azSubs = Get-AzSubscription
$azSub = 0
Do {
    Write-Verbose "Set Azure Subscription context to: $($azSubs[$azSub].Name)"
    Set-AzContext -Subscription $azSubs[$azSub] | Out-Null
    $VMInfo = Get-AzVM | Where-Object { $_.Name -eq $OldVMName -and $_.ResourceGroupName -eq $resourceGroup }
    if ($VMInfo) {
        #! Get original Azure VM properties and export it
        Try {
            Write-Verbose "Get original Azure VM properties and export its configuration to $(get-location)"
            Get-AzVM -ResourceGroupName $resourceGroup -Name $OldVMName -ErrorAction Stop | Export-Clixml .\AzVM_Backup.xml -Depth 5
        }
        Catch {
            Write-Warning "Cannot Export Azure VM $OldVMName to $(get-location) - Exiting!"
            Break
        }
    }
    $azSub++
} while ((!$VMInfo) -and ($azSub -lt $azSubs.count))

If (!$VMInfo) {
    Write-Warning "The Azure VM $OldVMName does not exist. Please check your virtual machine name!"
    Exit
}

#! Import Azure VM settings from backup XML and store it in a variable
Write-Verbose "Importing the old Azure VM properties..."
$oldVM = Import-Clixml .\AzVM_Backup.xml

#! Check if the delete behavior on existing VM is set to "Delete"
If ($oldVM.StorageProfile.OsDisk.DeleteOption -eq "Delete") {
    Write-Warning "The Azure VM $($OldVMName) has the OS Disk Deletion set to [Delete]. Please update it to [Detach] before you continue renaming your virtual machine. Exiting!"
    Exit
}

If ($oldVM.StorageProfile.DataDisks.DeleteOption -contains "Delete") {
    Write-Warning "The Azure VM $($OldVMName) has the Data Disk Deletion set to [Delete]. Please update it to [Detach] before you continue renaming your virtual machine. Exiting!"
    Exit
}

If ($oldVM.NetworkProfile.NetworkInterfaces.DeleteOption -eq "Delete") {
    Write-Warning "The Azure VM $($OldVMName) has the NIC Interface Deletion set to [Delete]. Please update it to [Detach] before you continue renaming your virtual machine. Exiting!"
    Exit 
}

#! Delete the Old Azure VM
Write-Verbose "Deleting the old Azure VM and keeping the other resources intact..."
Remove-AzVM -ResourceGroupName $oldVM.ResourceGroupName -Name $oldVM.Name -Force

#! Creating the new Azure VM configuration
Write-Verbose "Creating the new Azure VM configuration..."
$newVM = New-AzVMConfig -VMName $NewVMName -VMSize $oldVM.HardwareProfile.VmSize -Tags $oldVM.Tags

#! Attaching the OS Managed Disk of the old VM to the new Azure VM (Windows/Linux)
if ($oldVM.StorageProfile.OsDisk.vhd -eq $null -and $oldvm.StorageProfile.osdisk.ostype.value -eq "Windows") {
    Write-Verbose "Attaching the Windows OS Managed Disk of the old VM to the new Azure VM..."
    Set-AzVMOSDisk -VM $newVM -CreateOption Attach -ManagedDiskId $oldVM.StorageProfile.OsDisk.ManagedDisk.Id -Name $oldVM.StorageProfile.OsDisk.Name -Windows -Caching $oldVM.StorageProfile.OsDisk.Caching.Value | Out-Null
}
elseif ($oldVM.StorageProfile.OsDisk.vhd -eq $null -and $oldvm.StorageProfile.osdisk.ostype.value -eq "Linux") {
    Write-Verbose "Attaching the Linux OS Managed Disk of the old VM to the new Azure VM..."
    Set-AzVMOSDisk -VM $newVM -CreateOption Attach -ManagedDiskId $oldVM.StorageProfile.OsDisk.ManagedDisk.Id -Name $oldVM.StorageProfile.OsDisk.Name -Linux -Caching $oldVM.StorageProfile.OsDisk.Caching.Value | Out-Null
}

#! Attaching the OS UnManaged Disk of the old VM to the new Azure VM (Windows/Linux)
if ($oldVM.StorageProfile.OsDisk.vhd -ne $null -and $oldvm.StorageProfile.osdisk.ostype.value -eq "Windows") {
    Write-Verbose "Attaching the Windows OS UnManaged Disk of the old VM to the new Azure VM..."
    Set-AzVMOSDisk -VM $newVM -CreateOption Attach -VhdUri $oldVM.StorageProfile.OsDisk.vhd.value -Name $oldVM.StorageProfile.OsDisk.Name -Windows -Caching $oldVM.StorageProfile.OsDisk.Caching.Value | Out-Null
}
elseif ($oldVM.StorageProfile.OsDisk.vhd -ne $null -and $oldvm.StorageProfile.osdisk.ostype.value -eq "Linux") {
    Write-Verbose "Attaching the Linux OS UnManaged Disk of the old VM to the new Azure VM..."
    Set-AzVMOSDisk -VM $newVM -CreateOption Attach -VhdUri $oldVM.StorageProfile.OsDisk.vhd.value -Name $oldVM.StorageProfile.OsDisk.Name -Linux -Caching $oldVM.StorageProfile.OsDisk.Caching.Value | Out-Null
}

# Checking if the old VM is deployed with Trusted Launch enabled
$securityType = Get-AzDisk -Name $oldVM.StorageProfile.OsDisk.Name
Write-Verbose "Checking if the old VM is deployed with Trusted Launch enabled..."
if ($securityType.SecurityProfile.SecurityType -eq "TrustedLaunch") {
    Write-Verbose "Setting the OS Disk Security Profile to [TrustedLaunch] and enable [SecureBoot]"
    $newVM = Set-AzVmSecurityProfile -VM $newVM -SecurityType "TrustedLaunch" 
    $newVM = Set-AzVmUefi -VM $newVM -EnableVtpm $true  -EnableSecureBoot $true 
}

#! Attaching all NICs of the old VM to the new Azure VM
Write-Verbose "Attaching all NICs of the old VM to the new Azure VM..."
$oldVM.NetworkProfile.NetworkInterfaces | % { Add-AzVMNetworkInterface -VM $newVM -Id $_.Id } | Out-Null

#! Attaching all Data Disks (if any) of the old VM to the new Azure VM
Write-Verbose "Attaching all Data Disks (if any) of the old VM to the new Azure VM..."
$oldVM.StorageProfile.DataDisks | % { Add-AzVMDataDisk -VM $newVM -Name $_.Name -ManagedDiskId $_.ManagedDisk.Id -Caching $_.Caching -Lun $_.Lun -DiskSizeInGB $_.DiskSizeGB -CreateOption Attach }

#! Creating the new Azure VM
Write-Verbose "Creating the new Azure VM..."
New-AzVM -ResourceGroupName $oldVM.ResourceGroupName -Location $oldVM.Location -VM $newVM