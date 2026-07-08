# =====================================================================
# theme-loader.ps1  —  Tony Alpha theme / branding layer
# ---------------------------------------------------------------------
# Branding sits ON TOP of the application. The app reads a Theme object
# from here instead of hardcoding any colors, names, or logos.
#
# Get-Theme:
#   1. starts from a built-in NEUTRAL default (so the app runs fully even
#      with no theme.json -> functionality never depends on branding),
#   2. merges theme.json over it (partial themes are fine),
#   3. resolves logo/profile/icon paths to absolute and verifies them.
#
# To re-brand: edit theme.json (or point Get-Theme at another file).
# No application code needs to change.
# =====================================================================

$ErrorActionPreference = 'Stop'

function Get-DefaultTheme {
    # Neutral, brand-free fallback. The app is fully functional on this.
    return [pscustomobject]@{
        themeId        = 'default'
        companyName    = 'Tony'
        companyWordmark= 'Tony'
        workspaceName  = 'Command Center'
        assistantName  = 'Tony AI Assistant'
        version        = '0.x Alpha'
        tagline        = 'Local command center.'
        logoPath       = $null
        profilePath    = $null
        profileName    = ''
        iconPath       = $null
        colors = [pscustomobject]@{
            primary = '#111827'; primaryDark = '#0B1220'; primaryMid = '#1F2A3A'
            accent = '#2563EB'; accentLight = '#3B82F6'; accentDark = '#1E429F'; accentSoft = '#EAF0FE'
            background = '#F3F5F9'; surface = '#FFFFFF'; text = '#1F2933'; textMuted = '#6B7280'
            textOnPrimary = '#FFFFFF'; line = '#E5E7EB'
        }
        typography = [pscustomobject]@{ fontFamily = 'Segoe UI'; headingFamily = 'Segoe UI' }
    }
}

function Get-ThemePath { return (Join-Path $PSScriptRoot 'theme.json') }

function Get-Theme {
    param([string]$Path = (Get-ThemePath))

    $theme = Get-DefaultTheme
    if (-not (Test-Path $Path)) { return $theme }   # no branding -> neutral default; app still works

    try {
        $raw = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $theme                                # malformed theme -> fall back, don't break the app
    }

    $themeDir = Split-Path $Path -Parent
    $resolve = {
        param($rel)
        if ([string]::IsNullOrWhiteSpace($rel)) { return $null }
        $p = if ([System.IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $themeDir $rel }
        if (Test-Path $p) { return (Resolve-Path $p).Path } else { return $null }
    }

    foreach ($k in 'themeId','companyName','companyWordmark','workspaceName','assistantName','version','tagline','profileName') {
        if ($raw.PSObject.Properties.Name -contains $k -and $raw.$k) { $theme.$k = $raw.$k }
    }
    $theme.logoPath    = & $resolve $raw.logo
    $theme.profilePath = & $resolve $raw.profilePicture
    $theme.iconPath    = & $resolve $raw.icon

    if ($raw.PSObject.Properties.Name -contains 'colors') {
        foreach ($c in $raw.colors.PSObject.Properties.Name) { $theme.colors.$c = $raw.colors.$c }
    }
    if ($raw.PSObject.Properties.Name -contains 'typography') {
        foreach ($t in $raw.typography.PSObject.Properties.Name) { $theme.typography.$t = $raw.typography.$t }
    }
    return $theme
}
