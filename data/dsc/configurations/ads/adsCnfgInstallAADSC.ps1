# https://azure.microsoft.com/en-us/documentation/articles/automation-dsc-compile/
# https://blogs.msdn.microsoft.com/powershell/2014/01/09/separating-what-from-where-in-powershell-dsc/
# https://social.msdn.microsoft.com/Forums/en-US/ccf2d18e-632b-46a8-b649-31be20dc0d22/dsc-with-xactivedirectory-verification-of-prerequisites-for-domain-controller-promotion-failed?forum=azureautomation

configuration NewAddsCnfgLitware
{
 # This is the credential for the new domain that must have already been created in the Azure Automation account as a credential asset:
 # The credential asset will use the Name: CredsLitware, UserName: <username>@domain.tld, password: **********
 param
 (
    [string] $rgName,
    [string] $AutoAcctName
 )

$CredentialAsset = Get-AzureRmAutomationCredential -ResourceGroupName $rgName -AutomationAccountName $AutoAcctName -Name 'adcreds'

# $UniversalAdmName = $cred.UserName
# $securePassword = $cred.Password
$password = $CredentialAsset.GetNetworkCredential().Password

 $ErrorActionPreference = "SilentlyContinue"
 # In addition to modules that have been imported into the Azure Automation Account, the specific resources used must also be imported from those modules for this configuration
 # Import-DscResource -ModuleName xPSDesiredStateConfiguration
 Import-DscResource -Name xDisk -Module xStorage
 Import-DscResource -Name xADDomain -Module xActiveDirectory

 # Write-Verbose $ConfigData.NonNodeData.Message

 Node "dc11"
 # $AllNodes.Where{$_.Role -eq "DomainController"}.NodeName
 {
  # Prepare NTDS and LOG disk. Note that the disk number must be the next incremented number in the series of existing disks.
  # So if the VM has 2 disk (not including the temporary D drive, the existing disk numbers will be 0 and 1, so the next in the series is 2.

  xDisk "Volume"
  {
   DiskId = '2'
   DriveLetter = 'F'
   FSLabel = 'DATA'
  } #end resource

  # Create NTDS directory
  File "NTDS"
  {
   DestinationPath = 'F:\NTDS'
   Type = 'Directory'
   Ensure = 'Present'
   DependsOn = "[xDisk]Volume"
  } #end resource

  # Create LOG directory
  File "LOGS"
  {
   DestinationPath = 'F:\LOGS'
   Type = 'Directory'
   Ensure = 'Present'
   DependsOn = "[xDisk]Volume"
  } #end resource

  # Prepare SYSV disk, which will be disk number 3 in the series of disks on this system, since disk 2 was used above for the NTDS volume
  xDisk "SYSV"
  {
   DiskId = '3'
   DriveLetter = 'F'
   FSLabel = 'SYSV'
   DependsOn = "[xDisk]Volume"
  } #end resource

  # Create SYSV directory
  File "SYSV"
  {
   DestinationPath = 'F:\SYSV'
   Type = 'Directory'
   Ensure = 'Present'
   DependsOn = "[xDisk]SVolume"
  } #end resource

  # Install Dsc features
  WindowsFeature "DscServiceFeature"
  {
   Ensure = "Present"
   Name = "DSC-Service"
  } #end resource

  # Optional GUI tools
  WindowsFeature "ADDSTools"
  {
   Ensure = "Present"
   Name = "RSAT-ADDS-Tools"
  } #end resource

  WindowsFeature "ADDS"
  {
   Ensure = "Present"
   Name = "RSAT-ADDS"
  } #end resource

  WindowsFeature "RSATRoleTools"
  {
   Ensure = "Present"
   Name = "RSAT-Role-Tools"
  } #end resource

  WindowsFeature "RSATADPowerShell"
  {
   Ensure = "Present"
   Name = "RSAT-AD-PowerShell"
  } #end resource

  WindowsFeature "ADDSInstall"
  {
   Ensure = "Present"
   Name = "AD-Domain-Services"
   IncludeAllSubFeature = $true
   DependsOn = "[WindowsFeature]DscServiceFeature","[File]ADFilesNTDS","[File]ADFilesSYSV","[File]ADFilesLOGS"
  } #end resource

  # No slash at end of folder paths
  xADDomain "FirstDS"
  {
   DomainName = "litware.lab"
   DomainAdministratorCredential = $CredentialAsset
   SafeModeAdministratorPassword = $password
   DatabasePath = 'N:\NTDS'
   LogPath = 'N:\LOGS'
   SysvolPath = 'S:\SYSV'
   DependsOn = "[WindowsFeature]DscServiceFeature","[WindowsFeature]ADDSInstall","[File]ADFilesNTDS","[File]ADFilesSYSV","[File]ADFilesLOGS"
  } #end resource
 } #end nodes
} #end configuration