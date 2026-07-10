# =====================================================================
# live-providers.ps1  —  Tony's live information provider registry
# ---------------------------------------------------------------------
# The permanent architecture for EVERY live service Tony will ever use:
# weather today; calendar, email, maps, news, and more tomorrow. Tony
# remains the interface; a provider is an implementation detail Tony can
# swap without changing the Brain.
#
# A live provider is an object with:
#   name        <string>  unique id, e.g. 'weather'
#   description <string>  human-readable
#   relevant    <scriptblock> param($text) -> [bool]  is this signal relevant to the question?
#   query       <scriptblock> param($options) -> structured data (with its own status + timestamp)
#   status      <scriptblock> param($live) -> { name; state; detail; lastUpdated }
#
# Tony Brain decides WHEN a signal is needed (via `relevant`), asks the
# provider for it (via `query`), and explains the result naturally. The
# registry holds no data - no duplicate storage, no hidden state.
# =====================================================================

$ErrorActionPreference = 'Stop'

$script:LiveProviders = @{}

function Register-LiveProvider {
    param([Parameter(Mandatory)] $Provider)
    if ($Provider.name -and $Provider.query) { $script:LiveProviders[$Provider.name] = $Provider }
}

function Get-LiveProviders { return @($script:LiveProviders.Values) }
function Get-LiveProvider { param([string]$Name) return $script:LiveProviders[$Name] }

# Ask a named provider for data. Returns its structured result, or $null.
function Invoke-LiveProvider {
    param([string]$Name, $Options = @{})
    $p = Get-LiveProvider $Name
    if (-not $p -or -not $p.query) { return $null }
    try { return (& $p.query $Options) } catch { return $null }
}

# A provider's connection status (for Settings). $Live triggers a real check.
function Get-LiveProviderStatus {
    param([string]$Name, [switch]$Live)
    $p = Get-LiveProvider $Name
    if (-not $p) { return [pscustomobject]@{ name = $Name; state = 'unknown'; detail = 'Provider not registered.'; lastUpdated = $null } }
    if ($p.status) { try { return (& $p.status ([bool]$Live)) } catch { return [pscustomobject]@{ name = $Name; state = 'error'; detail = $_.Exception.Message; lastUpdated = $null } } }
    return [pscustomobject]@{ name = $Name; state = 'unknown'; detail = 'No status available.'; lastUpdated = $null }
}

# THE seam Tony Brain uses: gather every live signal relevant to a question.
# Each provider decides its own relevance; irrelevant providers are never
# queried (no wasted network). Returns a hashtable name -> data.
function Get-RelevantLiveSignals {
    param([string]$Text, $Options = @{})
    $out = @{}
    foreach ($p in @($script:LiveProviders.Values)) {
        $isRel = $false
        if ($p.relevant) { try { $isRel = [bool](& $p.relevant $Text) } catch { $isRel = $false } }
        if ($isRel) { try { $out[$p.name] = (& $p.query $Options) } catch { } }
    }
    return $out
}
