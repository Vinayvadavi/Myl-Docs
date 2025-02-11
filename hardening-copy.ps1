Connect-VIServer -Server ec6vm004.myl.com -User root -Password 20Pme1esx!

$hosts = get-vmhost -name ec6vm004.myl.com

#esxi-7.account-auto-unlock-time

$hosts | Set-VMHostAdvancedConfiguration Security.AccountUnlockTime -Value 600    #10 minutes

#esxi-7.account-lockout

$hosts | Set-VMHostAdvancedConfiguration Security.AccountLockFailures -Value 3

#esxi-7.cpu-hyperthread-warning

$hosts | Get-AdvancedSetting | Where-Object {$_.Name -eq "UserVars.SuppressHyperthreadWarning"} | Set-AdvancedSetting -Value "1" -Confirm:$false

#esxi-7.dcui-timeout

$hosts | Get-AdvancedSetting UserVars.DcuiTimeOut | Set-AdvancedSetting -Value 600 -Confirm:$false

#esxi-7.disable-cim

Get-VMHostService -VMHost $hosts | where {$_.Key -eq 'sfcbd-watchdog'} | Set-VMHostService -Policy Off
Get-VMHostService -VMHost $hosts | where {$_.Key -eq 'sfcbd-watchdog'} | Stop-VMHostService 

#esxi-7.disable-slp

Get-VMHostService -VMHost $hosts | where {$_.Key -eq 'slpd'} | Set-VMHostService -Policy Off
Get-VMHostService -VMHost $hosts | where {$_.Key -eq 'slpd'} | Stop-VMHostService

#esxi-7.disable-snmp

Get-VMHostService -VMHost $hosts | Where-Object {$_.Key -eq 'snmpd' -and $_.Running -eq 'True'}
Get-VMHostService -VMHost $hosts | Where-Object {$_.Key -eq 'snmpd' -and $_.Policy -eq 'On'}

#esxi-7.shell-interactive-timeout

$hosts | Get-AdvancedSetting UserVars.ESXiShellInteractiveTimeOut | Set-AdvancedSetting -Value 600 -Confirm:$false

#esxi-7.shell-timeout

$hosts | Get-AdvancedSetting UserVars.ESXiShellTimeOut | Set-AdvancedSetting -Value 600 -Confirm:$false

#esxi-7.shell-warning

$hosts | Get-AdvancedSetting UserVars.SuppressShellWarning | Set-AdvancedSetting -Value 0 -Confirm:$false

#esxi-7.tls-protocols

$hosts | Get-AdvancedSetting UserVars.ESXiVPsDisabledProtocols | Set-AdvancedSetting -Value "sslv3,tlsv1" -Confirm:$false
