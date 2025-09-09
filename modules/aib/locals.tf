# Local values for Azure Image Builder module

locals {
  # Static configuration values
  api_version = "2023-07-01"

  # Default AVD image customizations - applied to all images unless overridden
  default_customizations = [
    {
      name           = "avdBuiltInScript_preWindowsUpdate"
      type           = "WindowsUpdate"
      searchCriteria = "IsInstalled=0"
      filters = [
        "exclude:$_.Title -like '*Preview*'",
        "exclude:$_.KBArticleIDs -Contains '5040442'",
        "include:$true"
      ]
      updateLimit = 20
    },
    {
      name           = "avdBuiltInScript_preWindowsUpdate-windowsRestart"
      type           = "WindowsRestart"
      restartTimeout = "10m"
    },
    {
      name           = "avdBuiltInScript_installLanguagePacks"
      type           = "File"
      destination    = "C:\\AVDImage\\installLanguagePacks.ps1"
      sourceUri      = "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/InstallLanguagePacks.ps1"
      sha256Checksum = "519f1dcb41c15dc1726f28c51c11fb60876304ab9eb9535e70015cdb704a61b2"
    },
    {
      name        = "avdBuiltInScript_installLanguagePacks-parameter"
      type        = "PowerShell"
      runAsSystem = true
      runElevated = true
      inline      = ["C:\\AVDImage\\installLanguagePacks.ps1 -LanguageList \"English (United Kingdom)\""]
    },
    {
      name        = "avdBuiltInScript_installLanguagePacks-windowsUpdate"
      type        = "WindowsUpdate"
      updateLimit = 0
    },
    {
      name           = "avdBuiltInScript_installLanguagePacks-windowsRestart"
      type           = "WindowsRestart"
      restartTimeout = "10m"
    },
    {
      name           = "avdBuiltInScript_setDefaultLanguage"
      type           = "File"
      destination    = "C:\\AVDImage\\setDefaultLanguage.ps1"
      sourceUri      = "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/SetDefaultLang.ps1"
      sha256Checksum = "3eec0ffb74a9a343cf1b38dd73d266bfc8c82b23f0fd2c3f7e9d29c975eb6bab"
    },
    {
      name        = "avdBuiltInScript_setDefaultLanguage-parameter"
      type        = "PowerShell"
      runAsSystem = true
      runElevated = true
      inline      = ["C:\\AVDImage\\setDefaultLanguage.ps1 -Language \"English (United Kingdom)\""]
    },
    {
      name        = "avdBuiltInScript_setDefaultLanguage-windowsUpdate"
      type        = "WindowsUpdate"
      updateLimit = 0
    },
    {
      name           = "avdBuiltInScript_setDefaultLanguage-windowsRestart"
      type           = "WindowsRestart"
      restartTimeout = "5m"
    },
    {
      name           = "avdBuiltInScript_timeZoneRedirection"
      type           = "PowerShell"
      runAsSystem    = true
      runElevated    = true
      scriptUri      = "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/TimezoneRedirection.ps1"
      sha256Checksum = "b8dbc50b02f64cc7a99f6eeb7ada676673c9e431255e69f3e7a97a027becd8d5"
    },
    {
      name           = "avdBuiltInScript_disableStorageSense"
      type           = "PowerShell"
      runAsSystem    = true
      runElevated    = true
      scriptUri      = "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/DisableStorageSense.ps1"
      sha256Checksum = "558180fc9d73ed3d7ccc922e38eff3f28e10eaeddca89e32b66e2ded7390ff5a"
    },
    {
      name           = "avdBuiltInScript_configureRdpShortpath"
      type           = "PowerShell"
      runAsSystem    = true
      runElevated    = true
      scriptUri      = "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/RDPShortpath.ps1"
      sha256Checksum = "24e9821ddcc63aceba2682286d03cd7042bcadcf08a74fb0a30a1a1cd0cbf910"
    },
    {
      name           = "avdBuiltInScript_multiMediaRedirection"
      type           = "File"
      destination    = "C:\\AVDImage\\multiMediaRedirection.ps1"
      sourceUri      = "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/MultiMediaRedirection.ps1"
      sha256Checksum = "f577c9079aaa7da399121879213825a3f263f7b067951a234509e72f8b59a7fd"
    },
    {
      name        = "avdBuiltInScript_multiMediaRedirection-parameter"
      type        = "PowerShell"
      runAsSystem = true
      runElevated = true
      inline      = ["C:\\AVDImage\\multiMediaRedirection.ps1 -VCRedistributableLink \"https://aka.ms/vs/17/release/vc_redist.x64.exe\" -EnableEdge \"true\" -EnableChrome \"false\""]
    },
    {
      name           = "avdBuiltInScript_windowsOptimization"
      type           = "File"
      destination    = "C:\\AVDImage\\windowsOptimization.ps1"
      sourceUri      = "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/WindowsOptimization.ps1"
      sha256Checksum = "3a84266be0a3fcba89f2adf284f3cc6cc2ac41242921010139d6e9514ead126f"
    },
    {
      name        = "avdBuiltInScript_windowsOptimization-parameter"
      type        = "PowerShell"
      runAsSystem = true
      runElevated = true
      inline      = ["C:\\AVDImage\\windowsOptimization.ps1 -Optimizations \"ScheduledTasks\",\"DefaultUserSettings\",\"Autologgers\",\"Services\",\"NetworkOptimizations\",\"LGPO\",\"DiskCleanup\",\"Edge\",\"WindowsMediaPlayer\""]
    },
    {
      name        = "avdBuiltInScript_windowsOptimization-windowsUpdate"
      type        = "WindowsUpdate"
      updateLimit = 0
    },
    {
      name = "avdBuiltInScript_windowsOptimization-windowsRestart"
      type = "WindowsRestart"
    },
    {
      name           = "avdBuiltInScript_removeAppxPackages"
      type           = "File"
      destination    = "C:\\AVDImage\\removeAppxPackages.ps1"
      sourceUri      = "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/RemoveAppxPackages.ps1"
      sha256Checksum = "422b4c7b961f4d8b4216f126d8f38b00da583748b2d65b835504c1e9a07b0ece"
    },
    {
      name        = "avdBuiltInScript_removeAppxPackages-parameter"
      type        = "PowerShell"
      runAsSystem = true
      runElevated = true
      inline      = ["C:\\AVDImage\\removeAppxPackages.ps1 -AppxPackages \"Clipchamp.Clipchamp\",\"Microsoft.BingNews\",\"Microsoft.BingWeather\",\"Microsoft.GamingApp\",\"Microsoft.GetHelp\",\"Microsoft.Getstarted\",\"Microsoft.MicrosoftSolitaireCollection\",\"Microsoft.People\",\"Microsoft.PowerAutomateDesktop\",\"Microsoft.SkypeApp\",\"Microsoft.windowscommunicationsapps\",\"Microsoft.WindowsFeedbackHub\",\"Microsoft.WindowsMaps\",\"Microsoft.Xbox.TCUI\",\"Microsoft.XboxGameOverlay\",\"Microsoft.XboxGamingOverlay\",\"Microsoft.XboxIdentityProvider\",\"Microsoft.XboxSpeechToTextOverlay\",\"Microsoft.YourPhone\",\"Microsoft.ZuneMusic\",\"Microsoft.ZuneVideo\",\"Microsoft.XboxApp\",\"Microsoft.MicrosoftStickyNotes\",\"Microsoft.WindowsTerminal\",\"Microsoft.MicrosoftOfficeHub\",\"Microsoft.WindowsAlarms\",\"Microsoft.WindowsCamera\",\"Microsoft.Todos\",\"Microsoft.WindowsSoundRecorder\""]
    },
    {
      name           = "Business Apps Installation"
      type           = "PowerShell"
      runAsSystem    = true
      runElevated    = true
      scriptUri      = "CUSTOM_SCRIPT_PLACEHOLDER"
      sha256Checksum = "CUSTOM_SCRIPT_CHECKSUM_PLACEHOLDER"
    },
    {
      name           = "avdBuiltInScript_windowsRestart"
      type           = "WindowsRestart"
      restartTimeout = "10m"
    },
    {
      name        = "avdBuiltInScript_windowsUpdate"
      type        = "WindowsUpdate"
      updateLimit = 0
    },
    {
      name = "avdBuiltInScript_windowsUpdate-windowsRestart"
      type = "WindowsRestart"
    },
    {
      name           = "avdBuiltInScript_adminSysPrep"
      type           = "PowerShell"
      runAsSystem    = true
      runElevated    = true
      scriptUri      = "https://raw.githubusercontent.com/Azure/RDS-Templates/master/CustomImageTemplateScripts/CustomImageTemplateScripts_2024-03-27/AdminSysPrep.ps1"
      sha256Checksum = "1dcaba4823f9963c9e51c5ce0adce5f546f65ef6034c364ef7325a0451bd9de9"
    }
  ]
}
