@{
    Severity = @('Error', 'Warning')
    IncludeRules = @(
        'PSAvoidDefaultValueSwitchParameter',
        'PSAvoidGlobalVars',
        'PSAvoidNullOrEmptyHelpMessageAttribute',
        'PSAvoidTrailingWhitespace',
        'PSAvoidUsingEmptyCatchBlock',
        'PSAvoidUsingPositionalParameters',
        'PSAvoidUsingPlainTextForPassword',
        'PSAvoidUsingWMICmdlet',
        'PSPossibleIncorrectComparisonWithNull',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSUseSingularNouns',
        'PSUseApprovedVerbs'
    )
    ExcludeRules = @(
        'PSAvoidUsingWriteHost', # Write-Host is intentionally used for rich colored terminal output
        'PSUseSingularNouns',
        'PSAvoidUsingPositionalParameters'
    )
}
