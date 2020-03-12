[Cmdletbinding()]
Param(
[Parameter(Mandatory=$true)]
[string[]]$MonitorDisplayName='Total CPU Utilization Percentage','Windows Remote Management Service Health'
)

$MonitorColl = @()
$MonitorColl = New-Object "System.Collections.Generic.List[Microsoft.EnterpriseManagement.Configuration.ManagementPackMonitor]"

$monitors = Get-SCOMMonitor -DisplayName $MonitorDisplayName
Foreach ($monitor in $monitors) {

$objects = get-scomclass -Name ($Monitor.Target.Identifier.Path) | Get-SCOMClassInstance




ForEach ($object in $objects)
{
    #Set the monitor collection to empty and create the collection to contain monitors
    $MonitorColl = @()
    $MonitorColl = New-Object "System.Collections.Generic.List[Microsoft.EnterpriseManagement.Configuration.ManagementPackMonitor]"

    #Get specific monitors matching a displayname for this instance of URLtest ONLY
    #$Monitor = Get-SCOMMonitor -Instance $object -Recurse| where {$_.DisplayName -eq "Computer Not Reachable"} 
    
    #Add this monitor to a collection
    $MonitorColl.Add($Monitor)

    #Get the state associated with this specific monitor
    $State=$object.getmonitoringstates($MonitorColl)

if ($state.HealthState -eq 'Error') {  
$Props=@{}
$Props.DisplayName=$Object.DisplayName
$Props.Path= $Object.Path
$Props.HealthState=$state.HealthState
$Props.MonitorDisplayName = $monitor.DisplayName
New-Object -TypeName PSCustomObject -Property $props | Write-Output 
}
}


}
