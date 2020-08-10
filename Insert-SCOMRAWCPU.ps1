<#
.Synopsis
   Inserts selected scom alerts to custom database
.DESCRIPTION
   Inserts selected scom alerts to custom database
.EXAMPLE
   .\Insert-SCOMRAWCPU.ps1 -SQLServer 'opwscomdb1' -Instance 'default,1977' -Database 'SCOMDashboard' -DWServer 'OvwScomDW,1977' -Verbose
    
    VERBOSE: [27.04.2020 16:24:51] Script Started.
    WARNING: Using provider context. Server = opwscomdb1\default,1977, Database = [SCOMDashboard].
    VERBOSE: [27.04.2020 16:25:21] Inserted 1691 number of CPU Samples in total
    VERBOSE: [27.04.2020 16:25:21] Script ended.Script dutation is 29.8307143
#>

#requires -version 5.1 -Modules SqlServer,OperationsManager


[CmdletBinding()]
Param(

[Parameter(Mandatory= $true)]
[string]$SQLServer,

[Parameter(Mandatory= $true)]
[string]$Instance,
[Parameter(Mandatory= $true)]
[string]$Database,

[Parameter(Mandatory= $true)]
[string]$DWServer,
[string]$DWDatabase = 'OperationsManagerDW'


)



$ScriptStart = Get-date


Write-Verbose "[$(Get-Date -Format G)] Script Started."

$SelectLatestCPUTable = "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' AND TABLE_CATALOG='$database' and TABLE_NAME = 'LatestCPU'"

$LatestCPUQuery=@'
declare @G as Varchar(max);
Set @G='All Windows Computers';
;WITH cte AS (
select ManagedEntityRowId, vraw.PerformanceRuleInstanceRowId, max(DateTime) DateTime
from perf.vPerfRaw vraw
join PerformanceRuleInstance prfrlins on vraw.PerformanceRuleInstanceRowId = prfrlins.PerformanceRuleInstanceRowId
join PerformanceRule prfrl on prfrlins.RuleRowId = prfrl.RuleRowId
join vrule vr on prfrl.RuleRowId = vr.RuleRowId
where --prfrl.ObjectName like 'Processor Information' and
--vr.RuleSystemName in ('Microsoft.Windows.Server.2012.R2.OperatingSystem.TotalPercentProcessorTime.Collection','Microsoft.Windows.Server.2008.R2.OperatingSystem.TotalPercentProcessorTime.Collection','Microsoft.Windows.Server.2008.Processor.PercentProcessorTime.Collection')
vr.RuleSystemName like '%TotalPercentProcessorTime%'
and prfrl.CounterName='% Processor Time'
and vraw.DateTime > DATEADD(DAY, -1, GETDATE())
group by vraw.ManagedEntityRowId, vraw.PerformanceRuleInstanceRowId)
,cmp AS (
Select 
vManagedEntity.Displayname
from vManagedEntity 
join vRelationship on vRelationship.TargetManagedEntityRowId=vManagedEntity.ManagedEntityRowId 
join vManagedEntity vme2 on vme2.ManagedEntityRowId=vRelationship.SourceManagedEntityRowId 
join vRelationshipManagementGroup rmg on rmg.relationshiprowid=vrelationship.relationshiprowid
where vme2.DisplayName = @G  and getutcdate() between rmg.fromdatetime and isnull(rmg.todatetime,'99991231')
),
OSs as
(select vme.ManagedEntityRowId,vme.path,vme.DisplayName as OS
from vManagedEntity vme  
join vManagedEntityType vmetype on vme.ManagedEntityTypeRowId=vmetype.ManagedEntityTypeRowId
where vmetype.ManagedEntityTypeSystemName='Microsoft.Windows.OperatingSystem' )
--and vme.DisplayName like 'Microsoft Windows Server 2012 R2%')
,
Procs as
(select vme.ManagedEntityRowId,vme.DisplayName as computername,vmepropset.PropertyValue as LogicalProcessors
from vManagedEntity vme  
join vManagedEntityType vmetype on vme.ManagedEntityTypeRowId=vmetype.ManagedEntityTypeRowId
join vManagedEntityTypeProperty vmeprop on vmetype.ManagedEntityTypeRowId=vmeprop.ManagedEntityTypeRowId
join vManagedEntityPropertySet vmepropset on vmeprop.PropertyGuid=vmepropset.PropertyGuid and vmepropset.ManagedEntityRowId=vme.ManagedEntityRowId
where vmetype.ManagedEntityTypeSystemName='Microsoft.Windows.Computer' 
--and vme.DisplayName like 'Microsoft Windows Server 2012 R2%' 
and vmeprop.PropertySystemName='LogicalProcessors'
AND (GETUTCDATE() BETWEEN vmepropset.FromDateTime AND ISNULL(vmepropset.ToDateTime, '99991231')))
select  vme.Path,OS.OS ,pr.LogicalProcessors,DATEADD(hour, DATEDIFF(hour, GETUTCDATE(), GETDATE()), vraw.DateTime) DateTime, vraw.SampleValue 
from cte
join perf.vPerfRaw vraw ON cte.ManagedEntityRowId = vraw.ManagedEntityRowId AND cte.PerformanceRuleInstanceRowId = vraw.PerformanceRuleInstanceRowId AND cte.DateTime = vraw.DateTime
join vManagedEntity vme on vraw.ManagedEntityRowId=vme.ManagedEntityRowId
join cmp cm on vme.Path=cm.DisplayName
join procs pr on pr.computername=cm.DisplayName
join OSs OS on OS.Path=cm.DisplayName
--where vme.path like '%VM%'
order by 5 desc
'@



try {

$LatestCpuData = Invoke-Sqlcmd -ServerInstance $DWServer -Database $DWDatabase -Query $LatestCPUQuery -ErrorAction Stop -QueryTimeout 600

}

catch {

Throw "Could not query $DWDatabase database on $DWServer .`nError: $($_.Exception.Message)"

}

Try {

if((Invoke-Sqlcmd -ServerInstance "$SQLServer\$Instance" -Database $Database -Query $SelectLatestCPUTable -ErrorAction stop)) {

Write-Verbose "[$(Get-date -Format G)]Found LatestCPU table dropping."

Invoke-Sqlcmd -ServerInstance "$SQLServer\$Instance" -Database $Database -Query 'DROP TABLE [dbo].[LatestCPU]' -ErrorAction Stop

}
} catch {

Throw "[$(Get-Date -Format G)] Select or delete LatestCPU`nError: $($_.Exception.Message)"

}

try {

New-PSDrive -Name SCOMDashboard -PSProvider 'SQLServer' -root "SQLSERVER:\SQL\$SQLServer\$Instance\Databases\$Database" -ErrorAction stop | Out-Null
cd 'SCOMDashboard:\Tables'
Write-SqlTableData -TableName LatestCPU -InputData $LatestCpuData -Force -SchemaName dbo -ErrorAction Stop
Write-Verbose "[$(Get-Date -Format G)] Inserted $($LatestCpuData.Count) number of CPU Samples in total"

} 

Catch {

Throw "[$(Get-Date -Format G)] Couldnt Insert to SQL.`nError: $($_.Exception.Message)"


} 
Finally {
cd c:\
Remove-PSDrive SCOMDashboard
}


Write-verbose "[$(Get-date -Format G)] Script ended. Script dutation is $(((Get-date) - $ScriptStart).TotalSeconds)" 
