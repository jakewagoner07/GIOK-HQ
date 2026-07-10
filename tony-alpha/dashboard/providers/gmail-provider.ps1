# =====================================================================
# gmail-provider.ps1  —  Read-ONLY Gmail (live provider)
# ---------------------------------------------------------------------
# Tony understands Jake's inbox well enough to say what deserves his
# attention - he is NOT an email client. This provider retrieves messages
# and hands them to the provider-neutral Email Intelligence engine
# (core/email-intelligence.ps1), which produces the Executive Email
# Summary. Tony owns the conversation; Gmail owns the data; the provider
# is an implementation detail.
#
# READ ONLY. It never composes, sends, replies, forwards, labels, marks,
# archives, or deletes. The only scope requested is gmail.readonly. Any
# write capability is out of scope and would need separate, explicit,
# consent-gated approval (mirroring Memory With Permission).
#
# Auth: the SHARED Google OAuth module (core/google-oauth.ps1) - the exact
# same installed-desktop-app flow (PKCE + loopback + offline refresh) that
# Calendar uses. Built so Outlook / Microsoft 365 / Yahoo can plug into the
# same shape later: swap endpoints + scope, normalize messages to the same
# fields, reuse this engine and this registry entry ('email') unchanged.
#
# Private local files (gitignored, never printed/committed/logged):
#   gmail.config.json  - OAuth client id/secret (+ optional important
#                        contacts / client domains for smarter triage)
#   gmail.tokens.json  - access/refresh tokens
# Registers as the generic 'email' live signal (backend = gmail).
# =====================================================================

$ErrorActionPreference = 'Stop'

function Get-GmailConfigPath { return (Join-Path $PSScriptRoot 'gmail.config.json') }
function Get-GmailTokenPath  { return (Join-Path $PSScriptRoot '..\..\gmail.tokens.json') }

# Full config, including the optional triage lists Jake can curate locally.
function Get-GmailConfig {
    $clientId = $null; $clientSecret = $null; $source = 'none'
    $importantContacts = @(); $clientDomains = @(); $carrierDomains = @(); $carrierHints = $null; $myAddresses = @()
    $p = Get-GmailConfigPath
    if (Test-Path $p) {
        try {
            $c = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($c.clientId) { $clientId = [string]$c.clientId }
            if ($c.clientSecret) { $clientSecret = [string]$c.clientSecret }
            if ($clientId) { $source = 'gmail.config.json' }
            if ($c.PSObject.Properties.Name -contains 'importantContacts' -and $c.importantContacts) { $importantContacts = @($c.importantContacts) }
            if ($c.PSObject.Properties.Name -contains 'clientDomains' -and $c.clientDomains) { $clientDomains = @($c.clientDomains) }
            if ($c.PSObject.Properties.Name -contains 'carrierDomains' -and $c.carrierDomains) { $carrierDomains = @($c.carrierDomains) }
            if ($c.PSObject.Properties.Name -contains 'carrierHints' -and $c.carrierHints) { $carrierHints = @($c.carrierHints) }
            if ($c.PSObject.Properties.Name -contains 'myAddresses' -and $c.myAddresses) { $myAddresses = @($c.myAddresses) }
        } catch { }
    }
    return [pscustomobject]@{
        clientId          = $clientId
        clientSecret      = $clientSecret
        configured        = -not [string]::IsNullOrWhiteSpace($clientId)
        source            = $source
        scope             = 'https://www.googleapis.com/auth/gmail.readonly'
        authEndpoint      = 'https://accounts.google.com/o/oauth2/v2/auth'
        tokenEndpoint     = 'https://oauth2.googleapis.com/token'
        revokeEndpoint    = 'https://oauth2.googleapis.com/revoke'
        apiBase           = 'https://gmail.googleapis.com/gmail/v1'
        tokenPath         = (Get-GmailTokenPath)
        appName           = 'Gmail'
        diagSource        = 'gmail'
        readOnly          = $true
        importantContacts = $importantContacts
        clientDomains     = $clientDomains
        carrierDomains    = $carrierDomains
        carrierHints      = $carrierHints
        myAddresses       = $myAddresses
        analyzeCap        = 60   # analyze the most recent N of today's inbox
    }
}

# The subset passed to the shared OAuth module.
function Get-GmailOAuthConfig {
    $c = Get-GmailConfig
    return [pscustomobject]@{
        clientId       = $c.clientId
        clientSecret   = $c.clientSecret
        scope          = $c.scope
        authEndpoint   = $c.authEndpoint
        tokenEndpoint  = $c.tokenEndpoint
        revokeEndpoint = $c.revokeEndpoint
        apiBase        = $c.apiBase
        tokenPath      = $c.tokenPath
        appName        = $c.appName
        diagSource     = $c.diagSource
    }
}

function Write-GmailDiag { param([string]$Level = 'info', [string]$Message = '') if (Get-Command Write-TonyDiag -ErrorAction SilentlyContinue) { Write-TonyDiag -Level $Level -Source 'gmail' -Message $Message } }

# ---- connect / token / disconnect (delegated to the shared module) --
function Connect-Gmail {
    if (-not (Get-Command Connect-GoogleOAuth -ErrorAction SilentlyContinue)) { return [pscustomobject]@{ ok = $false; state = 'error'; detail = 'OAuth module not loaded.' } }
    $cfg = Get-GmailConfig
    if (-not $cfg.configured) { return [pscustomobject]@{ ok = $false; state = 'not-configured'; detail = 'No OAuth client configured. Add gmail.config.json (client id/secret for a Desktop app).' } }
    return (Connect-GoogleOAuth -Config (Get-GmailOAuthConfig))
}
function Get-GmailAccessToken { return (Get-GoogleOAuthAccessToken -Config (Get-GmailOAuthConfig)) }
function Disconnect-Gmail { return (Disconnect-GoogleOAuth -Config (Get-GmailOAuthConfig)) }

# ---- header + parsing helpers --------------------------------------
function Get-GmailHeaderValue {
    param($Headers, [string]$Name)
    $h = @($Headers | Where-Object { $_.name -and ($_.name.ToLower() -eq $Name.ToLower()) }) | Select-Object -First 1
    if ($h) { return [string]$h.value }
    return ''
}

# "Display Name <user@host>" -> { name; email }
function Split-EmailFrom {
    param([string]$Value)
    $name = ''; $email = ''
    if ($Value -match '^\s*"?([^"<]*)"?\s*<([^>]+)>') { $name = $Matches[1].Trim(); $email = $Matches[2].Trim() }
    elseif ($Value -match '([^\s<>]+@[^\s<>]+)') { $email = $Matches[1].Trim() }
    else { $email = ([string]$Value).Trim() }
    return [pscustomobject]@{ name = $name; email = $email }
}

# Does this message carry a calendar invitation? Read-only heuristics only.
function Test-GmailInvite {
    param($Raw, [string]$Subject, [string]$FromEmail, [string]$ContentType)
    if ($ContentType -match '(?i)text/calendar|method=REQUEST') { return $true }
    if ($FromEmail -match '(?i)calendar-notification@google\.com') { return $true }
    if ($Subject -match '(?i)^\s*(invitation|updated invitation|accepted|declined|tentatively accepted|canceled event|new event|reminder):') { return $true }
    return $false
}

# Marketing / promotional -> low priority. Deliberately EXCLUDES
# CATEGORY_UPDATES: Gmail files transactional business mail (carrier and
# underwriting notices, statements, confirmations) there, and those must
# stay eligible for the carrier/underwriting and needs-attention paths.
function Test-GmailPromo {
    param($LabelIds, [string]$ListUnsub)
    $labels = @($LabelIds)
    foreach ($l in @('CATEGORY_PROMOTIONS', 'CATEGORY_SOCIAL', 'CATEGORY_FORUMS')) { if ($labels -contains $l) { return $true } }
    if (-not [string]::IsNullOrWhiteSpace($ListUnsub)) { return $true }
    return $false
}

# Mailing-list / ESP / automated bulk sender - a message no human is waiting
# on a reply to, even without a List-Unsubscribe UI. Standard bulk headers:
# List-Id, Feedback-ID, Precedence: bulk/list/junk, Auto-Submitted, and common
# ESP markers (Amazon SES, SendGrid, Mailgun, Mandrill). Checked in the engine
# AFTER carrier/underwriting, so business updates from an ESP still survive.
function Test-GmailBulk {
    param($Headers)
    $val = { param($n) Get-GmailHeaderValue -Headers $Headers -Name $n }
    foreach ($h in @('List-Id', 'Feedback-ID', 'X-SES-Outgoing', 'X-SG-EID', 'X-SG-ID', 'X-Mailgun-Sid', 'X-Mandrill-User', 'X-Campaign', 'X-CSA-Complaints')) {
        if (-not [string]::IsNullOrWhiteSpace((& $val $h))) { return $true }
    }
    $prec = ([string](& $val 'Precedence')).ToLower()
    if ($prec -match 'bulk|list|junk') { return $true }
    $auto = ([string](& $val 'Auto-Submitted')).ToLower().Trim()
    if ($auto -and $auto -ne 'no') { return $true }
    return $false
}

# Convert a raw Gmail message (format=metadata) into a NORMALIZED message
# for the provider-neutral Email Intelligence engine. Read only.
#
# toMe resolves Jake's ALIASES: a GIOK Workspace mailbox often aggregates mail
# addressed to several of his addresses (personal Gmail, other aliases). The
# per-message Delivered-To header names the address that actually received it
# in this mailbox, so a message counts as "to me" when the To/Cc contains the
# connected account, this message's Delivered-To, or any configured alias.
function Convert-GmailMessage {
    param($Raw, [string]$Account, $Aliases = @())
    $headers = $Raw.payload.headers
    $fromRaw = Get-GmailHeaderValue -Headers $headers -Name 'From'
    $from = Split-EmailFrom -Value $fromRaw
    $subject = Get-GmailHeaderValue -Headers $headers -Name 'Subject'
    $to = Get-GmailHeaderValue -Headers $headers -Name 'To'
    $cc = Get-GmailHeaderValue -Headers $headers -Name 'Cc'
    $deliveredTo = Get-GmailHeaderValue -Headers $headers -Name 'Delivered-To'
    $listUnsub = Get-GmailHeaderValue -Headers $headers -Name 'List-Unsubscribe'
    $contentType = Get-GmailHeaderValue -Headers $headers -Name 'Content-Type'
    $labels = @($Raw.labelIds)

    $date = (Get-Date)
    if ($Raw.internalDate) { try { $date = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$Raw.internalDate).LocalDateTime } catch { } }

    $acct = ([string]$Account).ToLower()
    $recips = ("{0} {1}" -f $to, $cc).ToLower()
    $myAddrs = @(); foreach ($a in (@($acct) + @($Aliases) + @($deliveredTo))) { $al = ([string]$a).ToLower().Trim(); if ($al -and ($myAddrs -notcontains $al)) { $myAddrs += $al } }
    $toMe = $false
    foreach ($a in $myAddrs) { if ($a -and $recips.Contains($a)) { $toMe = $true; break } }
    $fromMe = [bool]($acct -and ($from.email.ToLower() -eq $acct))

    return [pscustomobject]@{
        id       = [string]$Raw.id
        threadId = [string]$Raw.threadId
        from     = $from.email
        fromName = $from.name
        subject  = $subject
        snippet  = [string]$Raw.snippet
        date     = $date
        unread   = ($labels -contains 'UNREAD')
        important = ($labels -contains 'IMPORTANT')
        fromMe   = $fromMe
        toMe     = $toMe
        promo    = (Test-GmailPromo -LabelIds $labels -ListUnsub $listUnsub)
        bulk     = (Test-GmailBulk -Headers $headers)
        invite   = (Test-GmailInvite -Raw $Raw -Subject $subject -FromEmail $from.email -ContentType $contentType)
        labels   = $labels
    }
}

# ---- THE contract: Executive Email Summary (or an honest failure) --
function Get-Email {
    param([string]$When = 'today', [datetime]$Now = (Get-Date))
    $cfg = Get-GmailConfig
    $nowStr = $Now.ToString('yyyy-MM-dd HH:mm:ss')
    $fail = {
        param($state, $detail)
        [pscustomobject]@{ provider = 'email'; backend = 'gmail'; ok = $false; errorState = $state; status = [pscustomobject]@{ state = $state; detail = $detail; lastRefresh = $null; lastError = $detail }; timestamp = $nowStr; account = $null; totalToday = 0; analyzed = 0; capped = $false; messages = @(); summary = $null }
    }
    if (-not $cfg.configured) { return (& $fail 'not-configured' 'Gmail is not connected yet.') }
    $at = Get-GmailAccessToken
    if (-not $at.ok) { return (& $fail $at.state $at.detail) }

    try {
        $profile = Invoke-GoogleApi -Token $at.token -BaseUrl $cfg.apiBase -Path '/users/me/profile'
        $account = [string]$profile.emailAddress

        # today's received mail: inbox, on/after local midnight
        $midnight = [int]([DateTimeOffset]$Now.Date).ToUnixTimeSeconds()
        $q = ("in:inbox after:{0}" -f $midnight)

        # page ids for an EXACT count (cap pages so a huge day never runs away)
        $ids = @(); $pageToken = $null; $pages = 0; $maxPages = 3
        do {
            $query = @{ q = $q; maxResults = '100' }
            if ($pageToken) { $query['pageToken'] = $pageToken }
            $list = Invoke-GoogleApi -Token $at.token -BaseUrl $cfg.apiBase -Path '/users/me/messages' -Query $query
            foreach ($mi in @($list.messages)) { $ids += [string]$mi.id }
            $pageToken = $list.nextPageToken
            $pages++
        } while ($pageToken -and $pages -lt $maxPages)
        $totalToday = $ids.Count
        $pagedCapped = [bool]($pageToken)   # more pages existed than we counted

        # analyze the most recent N (Gmail returns newest first)
        $cap = [int]$cfg.analyzeCap
        $toAnalyze = @($ids | Select-Object -First $cap)
        # format=metadata (no metadataHeaders) returns ALL headers + labelIds +
        # snippet + internalDate, and never the message body - read-only and light.
        $messages = @()
        foreach ($id in $toAnalyze) {
            $raw = Invoke-GoogleApi -Token $at.token -BaseUrl $cfg.apiBase -Path ("/users/me/messages/{0}" -f $id) -Query @{ format = 'metadata' }
            $messages += (Convert-GmailMessage -Raw $raw -Account $account -Aliases @($cfg.myAddresses))
        }
        $analyzedCapped = [bool]($totalToday -gt $toAnalyze.Count)

        $ctx = @{
            userEmail         = $account
            importantContacts = @($cfg.importantContacts)
            clientDomains     = @($cfg.clientDomains)
            carrierDomains    = @($cfg.carrierDomains)
            carrierHints      = $cfg.carrierHints
        }
        $summary = Get-ExecutiveEmailSummary -Messages $messages -TotalToday $totalToday -Capped ($analyzedCapped -or $pagedCapped) -Context $ctx

        return [pscustomobject]@{
            provider   = 'email'; backend = 'gmail'; ok = $true; errorState = $null
            status     = [pscustomobject]@{ state = 'connected'; detail = ('Live from Gmail ({0}).' -f $account); lastRefresh = $nowStr; lastError = $null }
            timestamp  = $nowStr; account = $account
            totalToday = $totalToday; analyzed = @($messages).Count; capped = ($analyzedCapped -or $pagedCapped)
            messages   = @($messages)
            summary    = $summary
        }
    } catch {
        $msg = $_.Exception.Message; $state = 'error'
        if ($_.Exception.Response -and ($_.Exception.Response.PSObject.Properties.Name -contains 'StatusCode')) {
            $sc = [int]$_.Exception.Response.StatusCode
            if ($sc -eq 401) { $state = 'needs-attention'; $msg = 'Your Google authorization expired and needs to be renewed.' }
            elseif ($sc -eq 403) { $state = 'denied'; $msg = 'I can reach Gmail, but the request was denied.' }
        } elseif ($_.Exception -is [System.Net.WebException]) { $state = 'network-error'; $msg = 'I could not retrieve email because the network is unavailable.' }
        Write-GmailDiag -Level 'error' -Message ("Gmail fetch {0}." -f $state)
        return (& $fail $state $msg)
    }
}

# Status for Settings. Without -Live: config/connection state, no network.
# With -Live: a real read to confirm access.
function Get-GmailStatus {
    param([switch]$Live)
    $cfg = Get-GmailConfig
    $t = if (Get-Command Get-GoogleOAuthTokens -ErrorAction SilentlyContinue) { Get-GoogleOAuthTokens -Path $cfg.tokenPath } else { $null }
    if (-not $cfg.configured) { return [pscustomobject]@{ name = 'Gmail'; state = 'not-configured'; detail = 'No OAuth client configured. Add a Desktop-app client id/secret to gmail.config.json, then Connect.'; account = $null; readOnly = $true; lastRefresh = $null; lastError = $null } }
    if (-not $t) { return [pscustomobject]@{ name = 'Gmail'; state = 'not-connected'; detail = 'Configured but not connected. Click Connect Gmail.'; account = $null; readOnly = $true; lastRefresh = $null; lastError = $null } }
    if (-not $Live) { return [pscustomobject]@{ name = 'Gmail'; state = 'connected'; detail = 'Connected (read-only). Run Test Connection to confirm live access.'; account = $null; readOnly = $true; lastRefresh = $null; lastError = $null } }
    $e = Get-Email -When 'today'
    $state = if ($e.ok) { 'connected' } else { $e.status.state }
    return [pscustomobject]@{ name = 'Gmail'; state = $state; detail = $e.status.detail; account = $e.account; readOnly = $true; lastRefresh = $e.status.lastRefresh; lastError = $e.status.lastError }
}

# Is a question about email/inbox? Tony Brain uses this to route.
function Test-EmailRelevant {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return [bool]($Text -match '(?i)\b(e-?mails?|inbox|gmail|mailbox|messages?\s+(from|in)|unread|who\s+(emailed|e-mailed|wrote)|anything\s+(important\s+)?(in\s+)?(my\s+)?(email|inbox)|need(s)?\s+(a\s+)?(reply|response)|newsletters?)\b')
}

# ---- register with the generic live-provider registry --------------
if (Get-Command Register-LiveProvider -ErrorAction SilentlyContinue) {
    Register-LiveProvider -Provider ([pscustomobject]@{
            name        = 'email'
            description = 'Read-only Gmail via OAuth 2.0 (installed desktop app, PKCE). Backend = gmail. Explained by Tony as an Executive Email Summary.'
            relevant    = { param($text) Test-EmailRelevant $text }
            query       = { param($opts) Get-Email -When 'today' }
            status      = { param($live) Get-GmailStatus -Live:([bool]$live) }
        })
}
