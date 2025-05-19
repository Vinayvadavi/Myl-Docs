function Set-RoundRobinIOPSLimitCluster
{
<#
    .Synopsis
        Set IOPS limit to 1 for Round Robin multipathing policy for iSCSI & FC LUNs presented to ESXi hosts in specific cluster for the specified vCenter.

    .DESCRIPTION
        This function sets IOPS limit to 1 for Round Robin multipathing policy for iSCSI & FC LUNs presented to ESXi hosts in specific cluster for the specified vCenter.

    .PARAMETER vcenterFQDN
        The name of a vCenter in the form of FQDN like 96vcsat001.myl.edu.

    .EXAMPLE
        .\Set-RoundRobinIOPSLimitCluster.ps1
#>

[CmdletBinding()]
    
    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$VCenterFQDN        
    )

    Begin
    {
        #Initialize
        Write-Host "Initializing..." -ForegroundColor Cyan
        try {
            Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -ErrorAction Stop | Out-Null 
            Write-Host "Initialization successfull." -ForegroundColor Green
        }
        catch {
            Write-Warning $_.Exception.Message
            Write-Host "Error: Initilization failed. Check if VMware PowerCLI module (VMware.PowerCLI) is installed in this machine." -ForegroundColor Red
            exit 1
        }
    }

    Process
    {
        #Reachability test of specified vCenter server
        Write-Host "Perfoming telnet test of the specified vCenter Server over port 443..." -ForegroundColor Cyan
        $OriginalProgressPreference = $Global:ProgressPreference
        $Global:ProgressPreference = 'SilentlyContinue'
        $TelnetTest = Test-NetConnection -ComputerName $vCenterFQDN -Port 443 -InformationLevel Quiet -ErrorAction SilentlyContinue
        $Global:ProgressPreference = $OriginalProgressPreference

        if ($TelnetTest -eq $true) {
        Write-Host "Telnet test of the specified vCenter Server over port 443 is successful." -ForegroundColor Green
        }
        else {
        Write-Host "Telnet test of the specified vCenter server failed. Please check if you have entered the correct hostname and TCP port 443 is open." -ForegroundColor Red
        exit 1
        }

        #Input for vCenter credentials
        $cred = Get-Credential -Message "Enter credentials to connect to mentioned vCenter server"

        #Connectivity test with specified credentials
        try 
        {
            Connect-VIServer -Server $vcenterFQDN -Credential $cred -ErrorAction Stop | Out-Null
            Write-Host "Successfully connected to the specified vCenter server using provided credentials." -ForegroundColor Green
        }
        catch 
        {
            Write-Warning $_.Exception.Message
            Write-Host "Unable to connect to specified vCenter server. Please check if you have entered correct credentials." -ForegroundColor Red
            exit 1
        }

        #Define function to disconnect from vCenter
        function Disconnect-VcenterSession {
            try {
                Disconnect-VIServer -Server $VCenterFQDN -Confirm:$false -ErrorAction Stop
                Write-Host "Successfuly disconnected from vCenter Server $VCenterFQDN." -ForegroundColor Green
            }
            catch {
                Write-Warning $_.Exception.Message
                Write-Host "Failed to disconnect from vCenter server $VCenterFQDN." -ForegroundColor Yellow
            }
        }

        #Input for VMware Cluster
        $clusterName = Read-Host "Enter name of VMware cluster"

        #Validate specified Cluster name
        try {
            $cluster = Get-Cluster -Name $clusterName -ErrorAction Stop
            Write-Host "Input recieved for VMware Cluster name is valid" -ForegroundColor Green
        }
        catch {
            Write-Warning $_.Exception.Message
            Write-Host "Input recieved for VMware Cluster name is not valid" -ForegroundColor Red
            Disconnect-VcenterSession
            exit 1
        }

        #Process
        Write-Host "Processing..." -ForegroundColor Cyan

        #Get details of ESXi Hosts in mentioned cluster and output details of Disconnected or Powered Off ESXi hosts
        try {
            $EsxiHosts = Get-VMHost -Location $cluster -ErrorAction Stop
            Write-Host "Retrieved details of ESXi Hosts for mentioned Cluster." -ForegroundColor Green
            $NotConnectedPoweredOffEsxiHosts = $EsxiHosts | Where-Object {$_.ConnectionState -notlike "Connected" -or $_.PowerState -notlike "PoweredOn"}
            if ($NotConnectedPoweredOffEsxiHosts) {
                Write-Host "Below mentioned ESXi Hosts are either 'Not Connected' or in 'PoweredOff' state." -ForegroundColor Red
                $NotConnectedPoweredOffEsxiHosts | Select-Object Name, ConnectionState, PowerState | Format-Table
            }
        }
        catch {
            Write-Warning $_.Exception.Message
            Write-Host "Error encountered while fetching details of ESXi hosts in mentioned cluster." -ForegroundColor Red
            Disconnect-VcenterSession
            exit 1
        }
            
        #Get details of SCSI LUNs of type disk and output details of LUNs of type disk which do not have RR Mpath policy or have IOPS Limit already set
        try {
            $ScsiLunTypeDisk = $EsxiHosts | Where-Object {$_.ConnectionState -like "Connected" -and $_.PowerState -like "PoweredOn"} | Get-ScsiLun -LunType disk -ErrorAction Stop
            Write-Host "Retrieved details of SCSI LUNs of type disk for ESXi hosts in mentioned cluster." -ForegroundColor Green
            $ScsiLunsNotRoundRobin = $ScsiLunTypeDisk | Where-Object {$_.Multipathpolicy -notlike "RoundRobin"}
            if ($ScsiLunsNotRoundRobin) {
            $ScsiLunsNotRoundRobin | Select-Object CanonicalName, CapacityGB, VMHost, MultipathPolicy | Export-Csv ".\ScsiLunsNotRoundRobin.csv" -NoTypeInformation
            Write-Host "Found LUNs with multipath policy not set to 'Round Robin' for some ESXi hosts in cluster $clusterName. Details of the same exported to '.\ScsiLunsNotRoundRobin.csv'." -ForegroundColor Yellow
            }
            $ScsiLunsIopsLimitAlreadySet = $ScsiLunTypeDisk | Where-Object {$_.Multipathpolicy -like "RoundRobin" -and $_.CommandsToSwitchPath -eq 1}
            if ($ScsiLunsIopsLimitAlreadySet) {
                $ScsiLunsIopsLimitAlreadySet | Select-Object CanonicalName, CapacityGB, VMHost, MultipathPolicy, CommandsToSwitchPath | Export-Csv ".\ScsiLunsIopsLimitAlreadySet.csv" -NoTypeInformation
                Write-Host "Found LUNs with Round Robin IOPS Limit already set to 1 for certain ESXi hosts in cluster $clusterName. Details of the same exported to '.\ScsiLunsIopsLimitAlreadySet.csv'." -ForegroundColor Green
            }
        }
        catch {
            Write-Warning $_.Exception.Message
            Write-Host "Error encountered while fetching LUN details for ESXi hosts in mentioned cluster." -ForegroundColor Red
            Disconnect-VcenterSession
            exit 1
        }          
            
        #Set IOPS limit for SCSI LUNs of type disk which have RR Mpath policy but do not have IOPS limit set
        try {
            $ScsiLunsIopsLimitNotSet = $ScsiLunTypeDisk | Where-Object {$_.Multipathpolicy -like "RoundRobin" -and $_.CommandsToSwitchPath -ne 1}
            if ($ScsiLunsIopsLimitNotSet) {
                $ScsiLunsIopsLimitNotSet | Select-Object CanonicalName, CapacityGB, VMHost, MultipathPolicy, CommandsToSwitchPath | Export-Csv '.\ScsiLunsIopsLimitNotSet.csv' -NoTypeInformation
                Write-Host "Found LUNs with Round Robin IOPS Limit not set to 1 for certain ESXi hosts in cluster $clusterName. Details of the same exported to '.\ScsiLunsIopsLimitNotSet.csv'." -ForegroundColor Cyan
                Write-Host "Setting Round Robin IOPS Limit to 1 for LUNs with RR IOPS Limit not set to 1..." -ForegroundColor Cyan
                $ScsiLunsIopsLimitUpdated = $ScsiLunsIopsLimitNotSet | Set-ScsiLun -CommandsToSwitchPath 1 -ErrorAction Stop
                $ScsiLunsIopsLimitUpdated | Select-Object CanonicalName, CapacityGB, VMHost, MultipathPolicy, CommandsToSwitchPath | Export-Csv '.\ScsiLunsIopsLimitUpdated.csv' -NoTypeInformation
                Write-Host "Round Robin IOPS Limit successfully set to 1 for LUNs with RR IOPS Limit not set to 1 for ESXi hosts in cluster $clusterName. Details of the same exported to '.\ScsiLunsIopsLimitUpdated.csv'" -ForegroundColor Green
            }
            else {
                Write-Host "Could not find any LUN with Round Robin multipath policy but IOPS limit not set to 1 for ESXi hosts in mentioned cluster." -ForegroundColor Cyan
            }
        }
        catch {
            Write-Warning $_.Exception.Message
            Write-Host "Error encountered while setting Round Robin IOPS Limit to 1 for LUNs for ESXi hosts in mentioned cluster." -ForegroundColor Red
            Disconnect-VcenterSession
            exit 1
        }
    }

    End
    {   
        #Wrap it up
        Write-Host "Wrapping it up..." -ForegroundColor Cyan
        #Disconnect from connected vCenter
        Disconnect-VcenterSession
        Write-Host "=====> Finished <=====" -ForegroundColor Cyan
    }
}
Set-RoundRobinIOPSLimitCluster