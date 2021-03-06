<#
.Synopsis
   Inserts selected scom alerts to custom database
.DESCRIPTION
   Inserts selected scom alerts to custom database
.EXAMPLE
   .\Insert-ServiceFailedToStartEvents -SQLServer 'SQLServer1' -Instance 'default,1977' -Database 'SCOMDashboard' -TableName 'ServiceFailedToStartEvents' 
#>

#requires -version 5.1 -Modules OperationsManager
[CmdletBinding()]
Param(

[Parameter(Mandatory= $true)]
[string]$SQLServer,
[Parameter(Mandatory= $true)]
[string]$Instance,
[Parameter(Mandatory= $true)]
[string]$Database,

[Parameter(Mandatory= $true)]
[string]$TableName,


[string]$RuleDisplayName = 'Collection rule for Service or Driver Failed to Start events',
[string]$ManagementServer = 'defaultms.fqdn'

)

Class BasicMonitoringEvent 
{

    [string]$LoggingComputer
    [string]$MonitoringObjectDisplayName
    [string]$MonitoringObjectPath
    [String]$ServiceDisplayName
    [datetime]$TimeAdded

BasicMonitoringEvent() {}

BasicMonitoringEvent(

    [string]$LoggingComputer ,
    [string]$MonitoringObjectDisplayName,
    [string]$MonitoringObjectPath,
    [String]$ServiceDisplayName,
    [datetime]$TimeAdded


){


    this.LoggingComputer = $LoggingComputer
    this.MonitoringObjectDisplayName = $MonitoringObjectDisplayName
    this.MonitoringObjectPath = $MonitoringObjectPath
    this.ServiceDisplayName = $ServiceDisplayName
    this.TimeAdded = $TimeAdded


}

}



Function Get-EventParameterHash {

[CmdletBinding()]
Param(

[Parameter(Mandatory = $true)]
[string]$Name,
[Parameter(Mandatory = $true)]
[int32]$ParameterIndex,
[switch]$ResolveErrors
)

if ($ResolveErrors) {

$Expression = @"

               if(`$ErrorHash[`$_.Parameters[$ParameterIndex]]) {
               
               `$ErrorHash[`$_.Parameters[$ParameterIndex]]

               } else {
               
               `$_.Parameters[$ParameterIndex]
               
               }
               
"@

    @{Name=$Name;Expression=[scriptblock]::Create($Expression)}

} else {

    @{Name=$Name;Expression=[scriptblock]::Create("`$_.Parameters[$ParameterIndex]")}
}
}

$ScriptStart = Get-date
$SelectTableName = "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' AND TABLE_CATALOG='$database' and TABLE_NAME = '$TableName'"



Write-Verbose "[$(Get-Date -Format G)] Script Started."


try {

   New-SCOMManagementGroupConnection -ComputerName $ManagementServer -ErrorAction Stop


} Catch {

    throw "Could not connect to $ManagementServer. Error. $($_.Exception.Message)"

}



$ErrorHash =  @{

    '%%1331' = 'Account Currently Disabled'
    '%%50' = 'Insufficient Rights'
    '%%1909' = 'The Referenced account is currently locked out and may not be logged on to.'
    '%%8' = 'Not enough memory'
    '%%1326' = 'The User Name and password is incorrect'
    '%%1787' = 'The security database on the server does not have a computer account for this workstation trust relationship'
    '%%1069' = 'The service did not start to due to a logon failure'
    '%%1053' = 'The Service did not respond to the start or control request in a timely fashion'
    '%%2' = 'The system cannot find the file specified.'
    '%%1275' = 'This driver has been blocked from loading'
    '%%1455' = 'The paging file is to small for this operation to complete.'
    '%%3' = 'The system cannot find the path specified.'

}

$ServiceFailedToStartEventRules = Get-scomrule -DisplayName $RuleDisplayName 
$ServiceFailedToStartEvents = Get-SCOMEvent -Rule $ServiceFailedToStartEventRules

#$LogonFailedEvents = $ServiceFailedToStartEvents.where({$_.Number -eq 7038})| Select-Object -Property 'LoggingComputer','MonitoringObjectPath','MonitoringObjectDisplayName','TimeAdded','TimeRaised',(Get-EventParameterHash -Name 'ServiceDisplayname' -ParameterIndex 0),(Get-EventParameterHash -Name 'UserName' -ParameterIndex 0),(Get-EventParameterHash -Name 'ErrorCode' -ParameterIndex 2 -ResolveErrors )
$ServiceStartEvents =$ServiceFailedToStartEvents.where({$_.Number -eq 7000})| Select-Object -Property 'LoggingComputer','MonitoringObjectPath','MonitoringObjectDisplayName','TimeAdded',(Get-EventParameterHash -Name 'ServiceDisplayname' -ParameterIndex 0),(Get-EventParameterHash -Name 'ErrorCode' -ParameterIndex 1 -ResolveErrors )
Write-Verbose "[$(Get-Date -Format G)] Found $($ServiceStartEvents.Count) number of Events in total"

#convert custom objects to a proper classs so that we can insert into sql healthy
$ConvertedEvents = $ServiceStartEvents | ForEach-Object {

[BasicMonitoringEvent]@{

LoggingComputer = $_.LoggingComputer.ToString()
MonitoringObjectDisplayName = $_.MonitoringObjectDisplayName.ToString() 
MonitoringObjectPath = $_.MonitoringObjectPath.ToString()
ServiceDisplayName = $_.ServiceDisplayName.ToString()
TimeAdded = [datetime]$_.TimeAdded

}
}

Write-Verbose "[$(Get-Date -Format G)] Converted Events."

# Drop table if it exists, we will create it during insert automatically.
Try {

if((Invoke-Sqlcmd -ServerInstance "$SQLServer\$Instance" -Database $Database -Query $SelectTableName -ErrorAction stop)) {

Write-Verbose "[$(Get-date -Format G)]Found $TableName table dropping."

Invoke-Sqlcmd -ServerInstance "$SQLServer\$Instance" -Database $Database -Query "DROP TABLE [dbo].[$TableName]" -ErrorAction Stop

}
} catch {

Throw "[$(Get-Date -Format G)] Select or delete TableName`nError: $($_.Exception.Message)"

}



try {

New-PSDrive -Name SCOMDashboard -PSProvider 'SQLServer' -root "SQLSERVER:\SQL\$SQLServer\$Instance\Databases\$Database" -ErrorAction stop | Out-Null
cd 'SCOMDashboard:\Tables'
Write-SqlTableData -TableName $TableName -InputData $ServiceStartEvents -Force -SchemaName dbo -ErrorAction Stop
Write-Verbose "[$(Get-Date -Format G)] Inserted $($ConvertedEvents.Count) number of Rows in total"

} 

Catch {

Throw "[$(Get-Date -Format G)] Couldnt Insert to SQL.`nError: $($_.Exception.Message)"


} 
Finally {
cd c:\
Remove-PSDrive SCOMDashboard
}

Write-verbose "[$(Get-date -Format G)] Script ended. Script dutation is $(((Get-date) - $ScriptStart).TotalSeconds)"  
