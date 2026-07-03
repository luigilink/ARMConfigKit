@{
    # Rules intentionally excluded for this repository.
    ExcludeRules = @(
        # StartAzVM.ps1 is an interactive, colour-coded console tool: Write-Host is
        # the intended output mechanism (per-VM status and the coloured summary).
        # The success/output pipeline is reserved for the per-VM result objects, so
        # switching these messages to Write-Output would corrupt the returned data.
        'PSAvoidUsingWriteHost'
    )
}
