function Get-ComputerStatus {
    [CmdletBinding()]
    param (
            [Parameter(Mandatory=$true,
                ValueFromPipeline=$true)]
            [string]
            $ComputerName,

            [Parameter(Mandatory=$false)]
            [switch]
            # Indicates whether to force all tests to run.
            $Force=$false
        )

    BEGIN {
        $ping = New-Object System.Net.NetworkInformation.Ping
    }

    PROCESS {
        $result = New-Object PSObject -Property @{
            "DnsStatus"         = "NotFound"
            "HostName"          = $ComputerName
            "IpAddress"         = $null
            "PingStatus"        = $null
            "PingRoundTripTime" = $null
            "WmiStatus"         = $null
            "WmiError"          = $null
            "Manufacturer"      = $null
            "Model"             = $null
            "OSVersion"         = $null
            "OSName"            = $null
            "PSRemotingStatus"  = $null
            "PSRemotingError"   = $null
        }

        Write-Verbose "$ComputerName : starting."

        try {
            Write-Verbose "$ComputerName : Resolving DNS name"
            $dns = [System.Net.Dns]::GetHostEntry($ComputerName)
            $result.DnsStatus = "Found"
            $result.HostName = $dns.HostName
            $result.IpAddress = $dns.AddressList[0].IpAddressToString
        } catch {
            $result.DnsStatus = "NotFound"
            Write-Verbose "$ComputerName : Name not found in DNS."
            if (!$Force) {
                return $result
            }
        }

        $pingResult = $ping.Send($ComputerName, 1000)
        $result.PingStatus = $pingResult.Status
        $result.PingRoundTripTime = $pingResult.RoundTripTime

        if ($pingResult.Status -ne 'Success') {
            Write-Verbose "$ComputerName : Did not respond to ping."
            if (!$Force) {
                return $result
            }
        }

        Write-Verbose "$ComputerName : Attempting WMI connections"
        $error.Clear()
        $computerSystem = Get-WmiObject -ComputerName $ComputerName -Class Win32_ComputerSystem
        if ($computerSystem -eq $null) {
            Write-Verbose "$ComputerName : Could not connect to WMI (Win32_ComputerSystem)"
            $result.WmiStatus = "Failed"
            $result.WmiError = $error[0].Exception
            if (!$Force) {
                return $result
            }
        } else {
            $result.WmiStatus = "Success (ComputerSystem)"
            $result.Manufacturer = $computerSystem.Manufacturer
            $result.Model = $computerSystem.Model

            $error.Clear()
            $operatingSystem = Get-WmiObject -ComputerName $ComputerName -Class Win32_OperatingSystem
            if ($operatingSystem -eq $null) {
                Write-Verbose "$ComputerName : Could not connect to WMI (Win32_OperatingSystem)"
                $result.WmiStatus += "/Failed (OperatingSystem)"
                $result.WmiError += $error[0].Exception
                if (!$Force) {
                    return $result
                }
            } else {
                $result.WmiStatus = "Success"
                $result.OSVersion = $operatingSystem.Version
                $result.OSName = $operatingSystem.Name.Split("|")[0]
            }
        }

        Write-Verbose "$ComputerName : Attempting Remote PowerShell (WS-Man) connection"
        $error.Clear()
        $serverName = Invoke-Command -ComputerName $ComputerName `
                        -ScriptBlock { Get-Item Env:ComputerName } `
                        -ErrorAction SilentlyContinue
        if ($serverName -eq $null) {
            Write-Verbose "$ComputerName : Could not connect to server via Remote PowerShell"
            $result.PSRemotingStatus = "Failed"
            $result.PSRemotingError = $error[0].Exception
        } else {
            $result.PSRemotingStatus = "Success"
        }

        return $result
    }
}