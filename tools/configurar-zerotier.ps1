$ErrorActionPreference = 'Stop'
$portNumber = [int]$env:PORT
if ($portNumber -lt 1 -or $portNumber -gt 65535) { throw 'Porta invalida.' }

$adapters = @(Get-NetAdapter | Where-Object {
    $_.Status -eq 'Up' -and ($_.InterfaceDescription -like '*ZeroTier*' -or $_.Name -like '*ZeroTier*')
})
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
foreach ($adapter in $adapters) {
    $addresses = @(Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 |
        Where-Object AddressState -eq 'Preferred' | Select-Object -ExpandProperty IPAddress)
    if (!$addresses.Count) { Write-Warning 'ZeroTier sem IPv4 atribuido.'; continue }
    foreach ($ip in $addresses) { Write-Host ("Link para seus amigos: http://{0}:{1}" -f $ip, $portNumber) }

    $name = "Knox-ZeroTier-IPv4-$($adapter.InterfaceGuid)-$portNumber"
    $rule = Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue
    if ($rule) {
        $current = @($rule | Get-NetFirewallAddressFilter | Select-Object -ExpandProperty LocalAddress)
        if (!(Compare-Object $addresses $current) -and $rule.Enabled -eq 'True') { continue }
    }
    if (!$isAdmin) {
        Write-Warning 'Execute o BAT como administrador para configurar o Firewall do Windows.'
        continue
    }
    if ($rule) {
        Set-NetFirewallRule -Name $name -LocalAddress $addresses -Enabled True
    } else {
        New-NetFirewallRule -Name $name -DisplayName "Condado de Knox - ZeroTier TCP $portNumber" `
            -LocalAddress $addresses -LocalPort $portNumber -Protocol TCP -Direction Inbound `
            -Action Allow -Profile Any | Out-Null
    }
    Write-Host "Firewall configurado para ZeroTier na porta TCP $portNumber."
}
if (!$adapters.Count) { Write-Warning 'ZeroTier sem adaptador ativo. Confira sua rede ZeroTier.' }
