function Test-Port {
    param (
        [Parameter(Position = 0, Mandatory = $true)]
        [string[]]$Hosts,
        
        [Parameter(Position = 1, Mandatory = $true)]
        [int[]]$Ports,
        
        [int]$Timeout = 200 # Timeout in milliseconds
    )
    
    $Results = @()
    $Jobs = @()
    
    foreach ($theHost in $Hosts) {
        foreach ($Port in $Ports) {
            $Jobs += Start-Job -ScriptBlock {
                param ($theHost, $Port, $Timeout)
                $Result = [PSCustomObject]@{
                    Host  = $theHost
                    Port  = $Port
                    Status = "Closed"
                }

                try {
                    $TcpClient = New-Object System.Net.Sockets.TcpClient
                    $ConnectTask = $TcpClient.ConnectAsync($theHost, $Port)
                    
                    if ($ConnectTask.Wait($Timeout)) {  # Wait for the task with the specified timeout
                        if ($TcpClient.Connected) {
                            $TcpClient.Close()
                            $Result.Status = "Open"
                        }
                    } else {
                        # Timeout occurred
                        $TcpClient.Close()
                        $Result.Status = "Closed (Timeout)"
                    }
                } catch {
                    # Handle exceptions like connection refused
                    $Result.Status = "Closed (Error)"
                }

                return $Result
            } -ArgumentList $theHost, $Port, $Timeout
        }
    }
    
    # Wait for all jobs to complete
    $Jobs | ForEach-Object { $_ | Wait-Job | Out-Null }
    
    # Collect all job results
    $Jobs | ForEach-Object { 
        $Results += Receive-Job -Job $_
        Remove-Job -Job $_ | Out-Null
    }
    
    # Output results in table format
    $Results | Select-Object Host, Port, Status | Format-Table -AutoSize
}
function Get-IPRange {
    param (
        [Parameter(Mandatory=$true)]
        [string]$StartIP,
        
        [Parameter(Mandatory=$true)]
        [string]$EndIP
    )

    # Convert the start and end IP addresses to 32-bit integers
    $startBytes = [System.Net.IPAddress]::Parse($StartIP).GetAddressBytes()
    [Array]::Reverse($startBytes)
    $startInt = [BitConverter]::ToUInt32($startBytes, 0)

    $endBytes = [System.Net.IPAddress]::Parse($EndIP).GetAddressBytes()
    [Array]::Reverse($endBytes)
    $endInt = [BitConverter]::ToUInt32($endBytes, 0)

    # Generate all IP addresses in the range
    for ($i = $startInt; $i -le $endInt; $i++) {
        $ipBytes = [BitConverter]::GetBytes($i)
        [Array]::Reverse($ipBytes)
        $ipAddress = [System.Net.IPAddress]::new($ipBytes)
        $ipAddress.IPAddressToString
    }
}

function Get-SubnetIPs {
    param (
        [Parameter(Mandatory=$true)]
        [string]$SubnetCIDR
    )

    # Split the CIDR notation into subnet and prefix length
    $parts = $SubnetCIDR -split '/'
    $Subnet = $parts[0]
    $PrefixLength = [int]$parts[1]

    # Calculate the number of addresses in the subnet
    $numAddresses = [math]::Pow(2, 32 - $PrefixLength)

    # Convert the subnet to an IP address object
    $subnetIP = [System.Net.IPAddress]::Parse($Subnet)

    # Convert the IP address to a 32-bit integer
    $subnetBytes = $subnetIP.GetAddressBytes()
    [Array]::Reverse($subnetBytes)
    $subnetInt = [BitConverter]::ToUInt32($subnetBytes, 0)

    # Generate all IP addresses in the subnet
    for ($i = 0; $i -lt $numAddresses; $i++) {
        $ipInt = $subnetInt + $i
        $ipBytes = [BitConverter]::GetBytes($ipInt)
        [Array]::Reverse($ipBytes)
        $ipAddress = [System.Net.IPAddress]::new($ipBytes)
        $ipAddress.IPAddressToString
    }
}

function Test-Ports {
    param (
        [Parameter(Position = 0, Mandatory = $true)]
        [string[]]$Hosts,
        
        [Parameter(Position = 1, Mandatory = $true)]
        [int[]]$Ports,
        
        [int]$Timeout = 200 # Timeout in milliseconds
    )
    
    Write-Host "WARNING: This should only be used for testing."
    $Results = @()
    $Jobs = @()

    # Handle each host (whether range, CIDR, or single IP/hostname)
    foreach ($theHost in $Hosts) {
        if ($theHost -match '^(\d{1,3}\.){3}\d{1,3}-(\d{1,3}\.){3}\d{1,3}$') {
            # Handle IP range (e.g., 192.168.1.1-192.168.1.5)
            $ipRange = $theHost.Split('-')
            $expandedHosts = Get-IPRange -StartIP $ipRange[0] -EndIP $ipRange[1]
        } elseif ($theHost -match '^(\d{1,3}\.){3}\d{1,3}\/\d{1,2}$') {
            # Handle CIDR notation
            $expandedHosts = Get-SubnetIPs -SubnetCIDR $theHost
        } else {
            # Assume it's a single hostname or IP
            $expandedHosts = @($theHost)
        }

        # For each expanded host, test all specified ports
        foreach ($expandedHost in $expandedHosts) {
            foreach ($Port in $Ports) {
                $Jobs += Start-Job -ScriptBlock {
                    param ($expandedHost, $Port, $Timeout)
                    $Result = [PSCustomObject]@{
                        Host   = $expandedHost
                        Port   = $Port
                        Status = "Closed"
                    }
                    
                    try {
                        $TcpClient = New-Object System.Net.Sockets.TcpClient
                        $ConnectTask = $TcpClient.ConnectAsync($expandedHost, $Port)
                        
                        if ($ConnectTask.Wait($Timeout)) {
                            if ($TcpClient.Connected) {
                                $TcpClient.Close()
                                $Result.Status = "Open"
                            }
                        } else {
                            $TcpClient.Close()
                            $Result.Status = "Closed (Timeout)"
                        }
                    } catch {
                        $Result.Status = "Closed (Error)"
                    }

                    return $Result
                } -ArgumentList $expandedHost, $Port, $Timeout
            }
        }
    }
    
    # Wait for all jobs to complete
    $Jobs | ForEach-Object { $_ | Wait-Job | Out-Null }
    
    # Collect all job results
    $Jobs | ForEach-Object { 
        $Results += Receive-Job -Job $_
        Remove-Job -Job $_ | Out-Null
    }
    
    # Output results in table format
    $Results | Select-Object Host, Port, Status | Format-Table -AutoSize
}
