function Get-RegressionSimulationResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$SimulationExitCode,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$SimulationOutput
    )

    $hasPassMarker = [bool]($SimulationOutput -match "\[TB\] RESULT:\s*PASS")
    $hasFatal = [bool]($SimulationOutput -match "\*\* Fatal:")
    $hasErrors = [bool]($SimulationOutput -match "Errors:\s*[1-9][0-9]*")

    [PSCustomObject]@{
        SimulatorExit = $SimulationExitCode
        HasPassMarker = $hasPassMarker
        HasFatal = $hasFatal
        HasErrors = $hasErrors
        Passed = ($SimulationExitCode -eq 0) -and
                 $hasPassMarker -and
                 -not $hasFatal -and
                 -not $hasErrors
    }
}
