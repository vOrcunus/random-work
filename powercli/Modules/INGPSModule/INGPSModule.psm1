<#

Prepared by : Ozan Orçunus
Module Name : PSModule
Version     : 1.0.0.1
Create Date : 16.04.2013
Description : This module contains set of codes which enable scripters to easily consume most common functions
Commands    : Import-Module -Name PSModule -WarningAction:SilentlyContinue
			  Remove-Module -Name PSModule
			  
Change      : Write-INGLog function modified. Writing to logfile is missing.		  
#>

<# ============== COMMON FUNCTIONS ====================================================================================================================================== #>

function Initialize-INGScript {
	[CmdletBinding()]
	param ( [Parameter(Mandatory=$true)][String]$ScriptName)
	
	If (Test-Path -Path "D:\Users\oorcunus\Documents\Scripts") { 
		$Global:ScrPath   = ("D:\Users\oorcunus\Documents\Scripts\{0}\" -f $ScriptName)
	} else {
		$Global:ScrPath   = ("C:\Scripts\{0}\" -f $ScriptName)
	}
	
	$Global:LogFile   = ("{0}{1}.log"      -f $Global:ScrPath,$ScriptName)
	$Global:XlsFile   = ("{0}{1}.xlsx"     -f $Global:ScrPath,$ScriptName)
	$Global:CtrlFile  = ("{0}{1}.ctrl"     -f $Global:ScrPath,$ScriptName)
	$Global:OutFile   = ("{0}{1}_Out.xlsx" -f $Global:ScrPath,$ScriptName)
	$Global:ScrptName = $ScriptName
	
	Confirm-INGPowerCLI $Global:ScrPath
	Write-INGLog (" ")
	Write-INGLog ("********** Script started **********")
	#Get-INGCredentials
	Write-INGLog ("Initializing environment completed")
}

function Uninitialize-INGScript {
	Write-INGLog ("********** Script completed **********")
	Remove-Module -Name INGPSModule
	
	$Global:ScrPath   = $null
	$Global:LogFile   = $null
	$Global:XlsFile   = $null
	$Global:CtrlFile  = $null
	$Global:OutFile   = $null
}

function Confirm-INGPowerCLI {
	param ([String]$PSPath)
	$VMSnapin = (Get-PSSnapin | Where {$_.Name -eq "VMware.VimAutomation.Core"}).Name
	if ($VMSnapin -ne "VMware.VimAutomation.Core") {
		CD "C:\Program Files\VMware\Infrastructure\vSphere PowerCLI\Scripts\"
		Add-PSSnapin VMware.VimAutomation.Core
		.\Initialize-PowerCLIEnvironment.ps1
		CD $PSPath
	}
}

function New-INGCredential {
	[CmdletBinding()]
	param ( [Parameter(Mandatory=$true)][System.Object]$CredStore, 
			[Parameter(Mandatory=$true)][String]$CredName)
	
	$CredPass  = ConvertTo-SecureString ($CredStore | Where {$_.Host -eq $CredName}).Password -AsPlainText -Force
	$CredUser  = ($CredStore | Where {$_.Host -eq $CredName}).User
	$Cred      = New-Object System.Management.Automation.PSCredential ($CredUser, $CredPass)
	$Cred
}

function Get-INGCredentials {
	$Culture    = New-Object System.Globalization.CultureInfo("en-US")
	$ScriptUser = ([Environment]::UserName).ToUpper($Culture)
	$ScriptHost = ([Environment]::MachineName).ToUpper($Culture)
	
	If (Test-Path -Path "D:\Users\oorcunus\Documents\Scripts\CredStore") {
		$CredStorePath = "D:\Users\oorcunus\Documents\Scripts\CredStore"
	} else {
		$CredStorePath = "C:\Scripts\CredStore"
	}
	
	$CouldOpen = $False
	Do {
		Try {
			Switch ($ScriptUser) {
				"ORCUNUSO" { $CredStore = Get-VICredentialStoreItem -File ("{0}\OZAN-Store.xml" -f $CredStorePath)   }
				Default    { $CredStore = Get-VICredentialStoreItem -File ("{0}\ORCH-Store.xml" -f $CredStorePath)   }
			}
			$CouldOpen = $True
		}
		Catch {
			Start-Sleep -s 1
			Write-INGLog ("Waiting for another process for CredStore") -Color YELLOW
			#$CouldOpen = $True
		}
	} Until ($CouldOpen)
	
	$Global:CredNetApp     = New-INGCredential -CredStore $CredStore -CredName "NETAPP"
	$Global:CredVCenter    = New-INGCredential -CredStore $CredStore -CredName "VCENTER"
	$Global:CredVCenter51  = New-INGCredential -CredStore $CredStore -CredName "VCENTER51"
	$Global:CredEsx        = New-INGCredential -CredStore $CredStore -CredName "ESX"
	$Global:CredDefault    = New-INGCredential -CredStore $CredStore -CredName "WINDEF"
	$Global:CredAttribute  = New-INGCredential -CredStore $CredStore -CredName "SVCATTRIBUTE"
}

function Get-INGSecurePass {
	[CmdletBinding()]
    param ( [Parameter(Mandatory=$true)][string]$SecurePassword)
	
    $Ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($SecurePassword)
    $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($Ptr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeCoTaskMemUnicode($Ptr)
    $Password
}

function Write-INGLog {
	[CmdletBinding()]
	param ( [Parameter(Mandatory=$true)][String]$Message, 
			[string]$Color,
			[switch]$NoReturn,
			[switch]$NoDateLog)
	
	if (!$Color) { $Color = "WHITE" }
	if ($NoDateLog) { $LogMessage = $Message }
		else { $LogMessage = (Get-Date).ToString() + " | " + $Message }
	
	Write-Host $LogMessage -ForegroundColor $Color -NoNewline:$NoReturn
	#Out-File -InputObject $LogMessage -FilePath $Global:LogFile -Append -NoClobber -Confirm:$false -ErrorAction:SilentlyContinue
}

function Connect-INGNetApp {
	[CmdletBinding()]
	param ( [Parameter(Mandatory=$true)][String]$Controller, 
			[Parameter(Mandatory=$true)][System.Management.Automation.PSCredential]$Credential)
			
	Connect-NaController -Name $Controller -Credential $Credential -HTTPS | Out-Null
	Write-INGLog ("Connected to " + $Controller)
}

function Get-INGVMUplink {
	[CmdletBinding()]
	param ( [Parameter(Mandatory=$true)][VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl]$VM)
	
	Connect-VIServer -Server $VM.VMHost.Name -Credential $Global:CredEsx
	$Netport = Get-EsxTop -CounterName NetPort | Where-Object { $_.ClientName -match $VM.Name }
	Disconnect-VIServer -Server $VM.VMHost.Name -Confirm:$false
	if ($Netport) { 
		if ($Netport.GetType().BaseType.Name -eq "Array") {
			$ReturnString = $null
			foreach ($Port in $Netport) {
				if ($Port.TeamUplink) { $ReturnString += " " + $Port.TeamUplink }
			}
			return $ReturnString.TrimStart()
		}
		
		if ($Netport.TeamUplink) { return $Netport.TeamUplink }
			else { return "NoUplink-NoTeamUplink" } 
	} else { return "NoUplink-NoNetport" }
}

function Import-INGModule {
	Remove-Module -Name INGPSModule
	Import-Module -Name INGPSModule -WarningAction:SilentlyContinue
}

<# ============== VSPHERE COMMON FUNCTIONS ========================================================================================================================= #>

function Connect-INGvCenter {
	param ( [Parameter(Mandatory=$true)][String]$vCenter, 
			[System.Management.Automation.PSCredential]$Credential)
			
	$vCenterFQDN = $vCenter
	switch ($vCenter) {
		"dc1vc" { $vCenterFQDN = "dc1vc.mydomain.local"   }
		"dc2vc" { $vCenterFQDN = "dc2vc.mydomain.local"   }
	}
	try {
		if ($Credential) {
			Connect-VIServer -Server $vCenterFQDN -Credential $Credential -WarningAction:SilentlyContinue | Out-Null
		} else {
			Connect-VIServer -Server $vCenterFQDN -WarningAction:SilentlyContinue | Out-Null
		}
		Write-INGLog ("Connected to " + $vCenterFQDN)
		$host.ui.RawUI.WindowTitle = ("CONNECTED TO " + $vCenter)
	} catch {
		Write-INGLog ("Cannot connect to " + $vCenterFQDN) -Color RED
	}
}

function Connect-INGESXServer {
	param ( [Parameter(Mandatory=$true)][String]$ESXServer )
			
	try {
		#$ReturnValue = Connect-VIServer -Server $ESXServer -Credential $Global:CredEsx -WarningAction:SilentlyContinue
		$ReturnValue = Connect-VIServer -Server $ESXServer -WarningAction:SilentlyContinue
		Write-INGLog ("Connected to " + $ESXServer) -Color Cyan
	} catch {
		Write-INGLog ("Cannot connect to " + $ESXServer) -Color RED
	}
	return $ReturnValue
}

function Disconnect-INGvCenter {
	[CmdletBinding()]
	param ([String]$vCenter)
	
	$vCenterFQDN = $vCenter
	switch ($vCenter) {
		"dc1vc" { $vCenterFQDN = "dc1vc.mydomain.local"   }
		"dc2vc" { $vCenterFQDN = "dc2vc.mydomain.local"   }
	}
	
	Disconnect-VIServer -Confirm:$false -ErrorAction:SilentlyContinue -WarningAction:SilentlyContinue | Out-Null
	if ($vCenterFQDN) { Write-INGLog -Message ("Disconnected from " + $vCenterFQDN) }
		else { Write-INGLog -Message ("Disconnected from vCenter Server") }
	$host.ui.RawUI.WindowTitle = ("!!!!! NOT CONNECTED TO ANY VCENTER SERVERS !!!!!")
}

function Confirm-INGVMExists {
	[CmdletBinding()]
	param ( [Parameter(Mandatory=$true)][String]$VMName)
	
	$VM = Get-VM -Name $VMName -ErrorAction SilentlyContinue
	if ($VM -eq $null) { return $false }
		else { return $true }
}

function Get-INGFolderFromVM {
	[CmdletBinding()]
	param ( [Parameter(Mandatory=$true)][String]$VMName)
	
	$VM = Get-VM -Name $VMName -ErrorAction SilentlyContinue
	$Parent = $VM.ExtensionData.Parent
	if ($Parent.Type -eq "Folder") {
		$FolderID = ("{0}-{1}" -f $Parent.Type, $Parent.Value)
		$Folder = Get-Folder -Id $FolderID
		return $Folder.Name
	}
	
	return $null
}

function Get-INGDatastoreFromVM {
	[CmdletBinding()]
	param ( [Parameter(Mandatory=$true)][string]$VMName )
	
	$VM = Get-VM -Name $VMName -ErrorAction SilentlyContinue
	$ConfFile = $VM.ExtensionData.Config.Files.VmPathName
	$DSName = $ConfFile.Split(@("[","]"))[1]
	return $DSName
}

function Shutdown-INGVMs {
	[CmdletBinding()]
	param ( [Parameter(Mandatory=$true)][string[]]$VMs)
	
	foreach ($VMName in $VMs) {
		$VM = $null
		$VM = Get-VM -Name $VMName -ErrorAction:SilentlyContinue
		if (!$VM) {
			Write-Host ("{0}: VM does not exist" -f $VMName)
			Continue
		}
		
		if ($VM.ExtensionData.Runtime.PowerState -eq "PoweredOff") {
			Write-Host ("{0}: VM is already powered off" -f $VMName)
			Continue
		}
	
		$VMToolState = $VM.ExtensionData.Guest.ToolsRunningStatus
		if ($VMToolState -eq "guestToolsNotRunning") {
			Write-Host ("{0}: VMtools not running, powering off" -f $VMName)
			$VM.ExtensionData.PowerOffVM()
		} else {
			Write-Host ("{0}: VMtools running, shutting down" -f $VMName)
			$VM.ExtensionData.ShutdownGuest()
		}
		Start-Sleep -Milliseconds 1000
	}
}

<# ============== VSPHERE STORAGE FUNCTIONS =========================================================================================================================== #>

Function Get-INGDatastoreMountInfo {
	[CmdletBinding()]
	Param (
		[Parameter(ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.VmfsDatastoreImpl]$Datastore
	)
	Process {
		if (-not $Datastore) {
			$Datastore = Get-Datastore
		}
		Foreach ($ds in $Datastore) {  
			if ($ds.ExtensionData.info.Vmfs) {
				$hostviewDSDiskName = $ds.ExtensionData.Info.vmfs.extent[0].diskname
				if ($ds.ExtensionData.Host) {
					$attachedHosts = $ds.ExtensionData.Host
					Foreach ($VMHost in $attachedHosts) {
						$hostview = Get-View $VMHost.Key
						$hostviewDSState = $VMHost.MountInfo.Mounted
						$StorageSys = Get-View $HostView.ConfigManager.StorageSystem
						$devices = $StorageSys.StorageDeviceInfo.ScsiLun
						Foreach ($device in $devices) {
							$Info = "" | Select Datastore, VMHost, Lun, Device, Mounted, State
							if ($device.canonicalName -eq $hostviewDSDiskName) {
								$hostviewDSAttachState = ""
								if ($device.operationalState[0] -eq "ok") {
									$hostviewDSAttachState = "Attached"							
								} elseif ($device.operationalState[0] -eq "off") {
									$hostviewDSAttachState = "Detached"							
								} else {
									$hostviewDSAttachState = $device.operationalstate[0]
								}
								$Info.Datastore = $ds.Name
								$Info.Lun = $hostviewDSDiskName
								$Info.VMHost = $hostview.Name
								$Info.Mounted = $HostViewDSState
								$Info.State = $hostviewDSAttachState
								$Info.Device = $device.DisplayName
								$Info
							}
						}
					}
				}
			}
		}
	}
}	# Get-Datastore -Name DS | Get-INGDatastoreMountInfo | Sort Datastore,VMHost | FT -Autosize

Function Unmount-INGDatastore {
	[CmdletBinding()]
	Param (
		[Parameter(ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.VmfsDatastoreImpl]$Datastore
	)
	Process {
		if (-not $Datastore) {
			Write-INGLog -Message ("No Datastore defined as input") -Color YELLOW
			Exit
		}
		Foreach ($ds in $Datastore) {
			$hostviewDSDiskName = $ds.ExtensionData.Info.vmfs.extent[0].Diskname
			if ($ds.ExtensionData.Host) {
				$attachedHosts = $ds.ExtensionData.Host | Sort-Object Name
				Foreach ($VMHost in $attachedHosts) {
					$hostview = Get-View $VMHost.Key
					$StorageSys = Get-View $HostView.ConfigManager.StorageSystem
					Write-INGLog -Message "Unmounting VMFS Datastore $($DS.Name) from host $($hostview.Name)..."
					try {
						$StorageSys.UnmountVmfsVolume($DS.ExtensionData.Info.vmfs.uuid)
					} catch {
						$ErrorMessage = $_.Exception.Message
						Write-INGLog -Message $ErrorMessage -Color RED
					}
				}
			}
		}
	}
}

Function Detach-INGDatastore {
	[CmdletBinding()]
	Param (
		[Parameter(ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.VmfsDatastoreImpl]$Datastore
	)
	Process {
		if (-not $Datastore) {
			Write-INGLog -Message ("No Datastore defined as input") -Color YELLOW
			Exit
		}
		Foreach ($ds in $Datastore) {
			$hostviewDSDiskName = $ds.ExtensionData.Info.vmfs.extent[0].Diskname
			if ($ds.ExtensionData.Host) {
				$attachedHosts = $ds.ExtensionData.Host
				Foreach ($VMHost in $attachedHosts) {
					$hostview = Get-View $VMHost.Key
					$StorageSys = Get-View $HostView.ConfigManager.StorageSystem
					$devices = $StorageSys.StorageDeviceInfo.ScsiLun
					Foreach ($device in $devices) {
						if ($device.canonicalName -eq $hostviewDSDiskName) {
							$LunUUID = $Device.Uuid
							Write-INGLog -Message "Detaching LUN $($Device.DisplayName) from host $($hostview.Name)..."
							try { 
								$StorageSys.DetachScsiLun($LunUUID)
							} catch {
								$ErrorMessage = $_.Exception.Message
								Write-INGLog -Message $ErrorMessage -Color RED
							}
						}
					}
				}
			}
		}
	}
}

Function Mount-INGDatastore {
	[CmdletBinding()]
	Param (
		[Parameter(ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.VmfsDatastoreImpl]$Datastore
	)
	Process {
		if (-not $Datastore) {
			Write-Host "No Datastore defined as input"
			Exit
		}
		Foreach ($ds in $Datastore) {
			$hostviewDSDiskName = $ds.ExtensionData.Info.vmfs.extent[0].Diskname
			if ($ds.ExtensionData.Host) {
				$attachedHosts = $ds.ExtensionData.Host
				Foreach ($VMHost in $attachedHosts) {
					$hostview = Get-View $VMHost.Key
					$StorageSys = Get-View $HostView.ConfigManager.StorageSystem
					Write-Host "Mounting VMFS Datastore $($DS.Name) on host $($hostview.Name)..."
					try {
						$StorageSys.MountVmfsVolume($DS.ExtensionData.Info.vmfs.uuid)
					} catch {
						$ErrorMessage = $_.Exception.Message
						Write-Host $ErrorMessage -ForegroundColor Red
					}
				}
			}
		}
	}
}

Function Attach-INGDatastore {
	[CmdletBinding()]
	Param (
		[Parameter(ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.VmfsDatastoreImpl]$Datastore
	)
	Process {
		if (-not $Datastore) {
			Write-Host "No Datastore defined as input"
			Exit
		}
		Foreach ($ds in $Datastore) {
			$hostviewDSDiskName = $ds.ExtensionData.Info.vmfs.extent[0].Diskname
			if ($ds.ExtensionData.Host) {
				$attachedHosts = $ds.ExtensionData.Host
				Foreach ($VMHost in $attachedHosts) {
					$hostview = Get-View $VMHost.Key
					$StorageSys = Get-View $HostView.ConfigManager.StorageSystem
					$devices = $StorageSys.StorageDeviceInfo.ScsiLun
					Foreach ($device in $devices) {
						if ($device.canonicalName -eq $hostviewDSDiskName) {
							$LunUUID = $Device.Uuid
							Write-Host "Attaching LUN $($Device.CanonicalName) to host $($hostview.Name)..."
							try {
								$StorageSys.AttachScsiLun($LunUUID)
							} catch {
								$ErrorMessage = $_.Exception.Message
								Write-Host $ErrorMessage -ForegroundColor Red
							}
						}
					}
				}
			}
		}
	}
}

function Attach-INGDisk {
    param(  [Parameter(Mandatory=$true)][string]$ClusterName,
        	[Parameter(Mandatory=$true)][string]$DisplayName )

	$Cluster = Get-Cluster -Name $ClusterName -ErrorAction:SilentlyContinue
	if ($Cluster) {
		foreach ($VMHost in ($Cluster | Get-VMHost | Sort-Object Name)) {
			$HostView = Get-View -Id $VMHost.Id
			$StorageSys = Get-View $HostView.ConfigManager.StorageSystem
			$Devices = $StorageSys.StorageDeviceInfo.ScsiLun
			Foreach ($Device in $Devices) {
				if ($Device.DisplayName -eq $DisplayName) {
					$LunUUID = $Device.Uuid
					Write-Host ("Attaching SCSI Device {0} ({2}) to host {1}" -f $Device.DisplayName, $VMHost.Name, $Device.CanonicalName)
					try {
						$StorageSys.AttachScsiLun($LunUUID)
					} catch {
						$ErrorMessage = $_.Exception.Message
						Write-Host $ErrorMessage -ForegroundColor Red
					}
				}
			}
		}
	} else {
		Write-Host "Cluster Object not found" -ForegroundColor Red
	}
}

function Detach-INGDisk {
    param(  [Parameter(Mandatory=$true)][string]$ClusterName,
        	[Parameter(Mandatory=$true)][string]$DisplayName )

	$Cluster = Get-Cluster -Name $ClusterName -ErrorAction:SilentlyContinue
	if ($Cluster) {
		foreach ($VMHost in ($Cluster | Get-VMHost | Sort-Object Name)) {
			$HostView = Get-View -Id $VMHost.Id
			$StorageSys = Get-View $HostView.ConfigManager.StorageSystem
			$Devices = $StorageSys.StorageDeviceInfo.ScsiLun
			Foreach ($Device in $Devices) {
				if ($Device.DisplayName -eq $DisplayName) {
					$LunUUID = $Device.Uuid
					Write-Host ("Detaching SCSI Device {0} ({2}) from host {1}" -f $Device.DisplayName, $VMHost.Name, $Device.CanonicalName)
					try {
						$StorageSys.DetachScsiLun($LunUUID)
					} catch {
						$ErrorMessage = $_.Exception.Message
						Write-Host $ErrorMessage -ForegroundColor Red
					}
				}
			}
		}
	} else {
		Write-Host "Cluster Object not found" -ForegroundColor Red
	}
}

function Mount-INGNFSDatastore {
	param(  [Parameter(Mandatory=$false)][string]$ClusterName)
	
	if ($ClusterName) { $VMHosts = Get-Cluster -Name $ClusterName | Get-VMHost }
		else { $VMHosts = Get-VMHost }
	
	foreach ($VMHost in $VMHosts) {
		try {
			$DS = New-Datastore -Nfs -VMHost $VMHost -Name "COMMON.Templates" -Path "/VM_NFS" -NfsHost DC1VMPRHNSAT01 -Confirm:$false
			Write-INGLog -Message ("NFS Datastore mounted on {0}" -f $VMHost.Name)
		} catch {
			$ErrorMessage = $_.Exception.Message
			Write-INGLog -Message $ErrorMessage -Color Red 
		}
	}
}

<# ============== VSPHERE NETWORK FUNCTIONS ======================================================================================================================== #>

function Get-INGObservedIPRange {
	param(	[Parameter(Mandatory=$true,ValueFromPipeline=$true,HelpMessage="Physical NIC from Get-VMHostNetworkAdapter")]
            [VMware.VimAutomation.Client20.Host.NIC.PhysicalNicImpl]$Nic,
			[switch]$help)
 
    process {
		$hostView = Get-VMHost -Id $Nic.VMHostId | Get-View -Property ConfigManager
        $ns = Get-View $hostView.ConfigManager.NetworkSystem
        $hints = $ns.QueryNetworkHint($Nic.Name)
 
        foreach ($hint in $hints) {
            foreach ($subnet in $hint.subnet) {
                $observed = New-Object -TypeName PSObject
                $observed | Add-Member -MemberType NoteProperty -Name Device -Value $Nic.Name
                $observed | Add-Member -MemberType NoteProperty -Name VMHostId -Value $Nic.VMHostId
                $observed | Add-Member -MemberType NoteProperty -Name IPSubnet -Value $subnet.IPSubnet
                $observed | Add-Member -MemberType NoteProperty -Name VlanId -Value $subnet.VlanId
                Write-Output $observed
            }
        }
    }
}	# Get-VMHost -Name DC2ESXRSF01.mydomain.local | Get-VMHostNetworkAdapter | Where { $_.Name -eq "vmnic1" } | Get-INGObservedIPRange | Sort VlanId

$host.ui.RawUI.WindowTitle = ("!!!!! NOT CONNECTED TO ANY VCENTER SERVERS !!!!!")
Export-ModuleMember -Function * -Alias *