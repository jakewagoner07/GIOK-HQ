# =====================================================================
# communications.ps1  -  The provider-neutral communications aggregator
# ---------------------------------------------------------------------
# Epic 8. Sam is Head of Communications and reads ONE normalized signal.
# This layer is where MANY vendor backends become ONE combined report:
# it collects normalized messages from each connected backend (Gmail via
# Get-Email, Yahoo via Get-YahooMessages) and runs the EXISTING Executive
# Email Summary (Get-ExecutiveEmailSummary) exactly ONCE over the merged set.
#
# There is NO second Email Intelligence engine and NO second Executive Email
# Summary - the merge happens only here, at the provider-neutral layer, and
# every message keeps its sourceAccount + provider. It registers the generic
# 'email' live signal (moved here from the Gmail provider), so Tony and Sam
# consume the combined signal without ever learning the vendor.
#
# READ ONLY. It performs no writes and adds no store. Future backends
# (Outlook/M365, SMS, voicemail, Slack/Teams, social) plug in here identically.
# =====================================================================

$ErrorActionPreference = 'Stop'

# The set of email/communication backends. Each entry is resolved at RUNTIME
# (Get-Command guards), so a backend that isn't loaded simply doesn't contribute.
function Get-CommBackends {
    return @(
        [pscustomobject]@{ provider = 'gmail'; fetch = 'Get-Email';         status = 'Get-GmailStatus'; config = 'Get-GmailConfig' }
        [pscustomobject]@{ provider = 'yahoo'; fetch = 'Get-YahooMessages'; status = 'Get-YahooStatus'; config = 'Get-YahooConfig' }
    )
}

# Gather the triage context lists (important contacts / client & carrier domains)
# from every backend config, merged - so classification is consistent regardless
# of which inbox a message arrived in.
function Get-CommContext {
    $important = @(); $clientDomains = @(); $carrierDomains = @(); $carrierHints = $null; $userEmail = $null
    foreach ($b in (Get-CommBackends)) {
        if (-not (Get-Command $b.config -ErrorAction SilentlyContinue)) { continue }
        try {
            $c = & $b.config
            if ($c.importantContacts) { $important += @($c.importantContacts) }
            if ($c.clientDomains) { $clientDomains += @($c.clientDomains) }
            if ($c.carrierDomains) { $carrierDomains += @($c.carrierDomains) }
            if ((-not $carrierHints) -and ($c.PSObject.Properties.Name -contains 'carrierHints') -and $c.carrierHints) { $carrierHints = $c.carrierHints }
            if ((-not $userEmail) -and $c.PSObject.Properties.Name -contains 'email' -and $c.email) { $userEmail = $c.email }
        } catch { }
    }
    return @{
        userEmail         = $userEmail
        importantContacts = @($important | Select-Object -Unique)
        clientDomains     = @($clientDomains | Select-Object -Unique)
        carrierDomains    = @($carrierDomains | Select-Object -Unique)
        carrierHints      = $carrierHints
    }
}

# THE combined communications read across every connected backend. Same shape as
# the old Gmail 'email' signal (ok/summary/accounts/messages/...) plus a per-
# provider breakdown, so every existing consumer keeps working unchanged.
function Get-Communications {
    param([datetime]$Now = (Get-Date))
    $nowStr = $Now.ToString('yyyy-MM-dd HH:mm:ss')

    $allMessages = @(); $accountsInfo = @(); $providersUsed = @()
    $anyOk = $false; $totalToday = 0; $anyCapped = $false; $firstBadState = $null; $firstBadDetail = $null

    # -- Gmail backend (unchanged): returns its own messages + per-account info --
    if (Get-Command Get-Email -ErrorAction SilentlyContinue) {
        $g = $null; try { $g = Get-Email -When 'today' -Now $Now } catch { $g = $null }
        if ($g) {
            if ($g.ok) {
                $anyOk = $true; $providersUsed += 'gmail'
                $allMessages += @($g.messages); $totalToday += [int]$g.totalToday; $anyCapped = $anyCapped -or [bool]$g.capped
                foreach ($a in @($g.accounts)) { $accountsInfo += [pscustomobject]@{ email = $a.email; provider = 'gmail'; state = $a.state; detail = $a.detail } }
            }
            elseif ($g.errorState -notin @('not-configured', 'not-connected')) {
                foreach ($a in @($g.accounts)) { $accountsInfo += [pscustomobject]@{ email = $a.email; provider = 'gmail'; state = $a.state; detail = $a.detail } }
                if (-not $firstBadState) { $firstBadState = $g.errorState; $firstBadDetail = $g.status.detail }
            }
        }
    }

    # -- Yahoo backend: normalized messages only (no summary of its own) --
    if (Get-Command Get-YahooMessages -ErrorAction SilentlyContinue) {
        $y = $null; try { $y = Get-YahooMessages -Now $Now } catch { $y = $null }
        if ($y) {
            if ($y.ok) {
                $anyOk = $true; $providersUsed += 'yahoo'
                $allMessages += @($y.messages); $totalToday += [int]$y.total; $anyCapped = $anyCapped -or [bool]$y.capped
                $accountsInfo += [pscustomobject]@{ email = $y.email; provider = 'yahoo'; state = 'connected'; detail = $y.detail }
            }
            elseif ($y.state -ne 'not-configured') {
                $accountsInfo += [pscustomobject]@{ email = $y.email; provider = 'yahoo'; state = $y.state; detail = $y.detail }
                if (-not $firstBadState) { $firstBadState = $y.state; $firstBadDetail = $y.detail }
            }
        }
    }

    if (-not $anyOk) {
        $state = if ($firstBadState) { $firstBadState } else { 'not-connected' }
        $detail = if ($firstBadDetail) { $firstBadDetail } else { 'No communication accounts are connected yet.' }
        return [pscustomobject]@{ provider = 'email'; backend = 'communications'; ok = $false; errorState = $state; status = [pscustomobject]@{ state = $state; detail = $detail; lastRefresh = $null; lastError = $detail }; timestamp = $nowStr; account = $null; accounts = @($accountsInfo); accountCount = @($accountsInfo).Count; providers = @($providersUsed); totalToday = 0; analyzed = 0; capped = $false; messages = @(); summary = $null }
    }

    # MERGE happens ONLY here, then the ONE existing engine summarizes once. It
    # dedupes the same email across accounts/providers (by Message-ID) and keeps
    # every source account.
    $ctx = Get-CommContext
    $summary = Get-ExecutiveEmailSummary -Messages $allMessages -TotalToday $totalToday -Capped $anyCapped -Context $ctx

    $connected = @($accountsInfo | Where-Object { $_.state -eq 'connected' })
    $primary = if ($connected.Count -gt 0) { $connected[0].email } else { $null }
    $degraded = @($accountsInfo | Where-Object { $_.state -ne 'connected' })
    $provText = (@($providersUsed | Select-Object -Unique) -join ' + ')
    $detail = if ($degraded.Count -eq 0) { ('Live across {0} inbox(es) ({1}).' -f $connected.Count, $provText) }
    else { ('Live across {0} of {1} inbox(es) ({2}); {3} need attention.' -f $connected.Count, $accountsInfo.Count, $provText, $degraded.Count) }

    return [pscustomobject]@{
        provider   = 'email'; backend = 'communications'; ok = $true; errorState = $null
        status     = [pscustomobject]@{ state = 'connected'; detail = $detail; lastRefresh = $nowStr; lastError = $(if ($degraded.Count) { $degraded[0].detail } else { $null }) }
        timestamp  = $nowStr; account = $primary; accounts = @($accountsInfo); accountCount = @($accountsInfo).Count
        providers  = @($providersUsed | Select-Object -Unique)
        totalToday = $totalToday; analyzed = @($summary.attentionItems).Count; capped = $anyCapped
        messages   = @($allMessages)
        summary    = $summary
    }
}

# Combined status for Settings (per backend, per account). Read-only.
function Get-CommunicationsStatus {
    param([switch]$Live)
    $accts = @(); $states = @()
    foreach ($b in (Get-CommBackends)) {
        if (-not (Get-Command $b.status -ErrorAction SilentlyContinue)) { continue }
        try {
            $st = & $b.status -Live:([bool]$Live)
            $states += $st.state
            if ($st.PSObject.Properties.Name -contains 'accounts' -and @($st.accounts).Count -gt 0) {
                foreach ($a in @($st.accounts)) { $accts += [pscustomobject]@{ email = $a.email; provider = $b.provider; state = $a.state; detail = $a.detail } }
            } else {
                $accts += [pscustomobject]@{ email = $st.account; provider = $b.provider; state = $st.state; detail = $st.detail }
            }
        } catch { }
    }
    $connected = @($accts | Where-Object { $_.state -eq 'connected' })
    $overall = if ($connected.Count -gt 0) { 'connected' } elseif (@($accts).Count -gt 0) { @($accts)[0].state } else { 'not-configured' }
    return [pscustomobject]@{ name = 'Communications'; state = $overall; detail = ('{0} inbox(es) connected (read-only).' -f $connected.Count); accounts = @($accts); readOnly = $true }
}

# Historical Search Mode - EXPLICIT only. Dispatches to each backend's read-only
# search. Returns evidence; NEVER auto-triggered; NEVER creates a proposal here.
function Search-Communications {
    param([Parameter(Mandatory)][string]$Query, [int]$SinceDays = 365, [int]$Max = 25, [datetime]$Now = (Get-Date))
    $results = @(); $searched = @()
    if (Get-Command Search-YahooMail -ErrorAction SilentlyContinue) {
        $searched += 'yahoo'
        $r = Search-YahooMail -Query $Query -SinceDays $SinceDays -Max $Max -Now $Now
        if ($r.ok) { $results += @($r.results) }
    }
    return [pscustomobject]@{ ok = ($results.Count -ge 0); mode = 'historical'; query = $Query; providersSearched = @($searched); results = @($results); note = 'Read-only search; nothing is saved and no proposal is created without your approval.' }
}

# Relevance: any email/communication phrasing (reuses the Gmail relevance test
# when present) plus explicit provider words. Used by the 'email' live signal.
function Test-CommunicationsRelevant {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    if ((Get-Command Test-EmailRelevant -ErrorAction SilentlyContinue) -and (Test-EmailRelevant $Text)) { return $true }
    return [bool]($Text -match '(?i)\b(yahoo|communication|communications|voicemail|slack|teams|outlook)\b')
}

# ---- register the generic 'email' live signal HERE (one registrant) ----
if (Get-Command Register-LiveProvider -ErrorAction SilentlyContinue) {
    Register-LiveProvider -Provider ([pscustomobject]@{
            name        = 'email'
            description = 'Read-only communications across Gmail and Yahoo (one normalized signal). Merged and explained by Tony as one Executive Email Summary.'
            relevant    = { param($text) Test-CommunicationsRelevant $text }
            query       = { param($opts) Get-Communications }
            status      = { param($live) Get-CommunicationsStatus -Live:([bool]$live) }
        })
}
