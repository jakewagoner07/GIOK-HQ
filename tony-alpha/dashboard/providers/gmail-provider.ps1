# =====================================================================
# gmail-provider.ps1  —  Read-ONLY Gmail (live provider, MULTI-ACCOUNT)
# ---------------------------------------------------------------------
# Tony understands Jake's inbox well enough to say what deserves his
# attention - he is NOT an email client. ONE Gmail provider serves ALL
# connected Google accounts (D17): it fetches each account read-only,
# tags every message with its source account, and hands the combined set
# to the provider-neutral Email Intelligence engine
# (core/email-intelligence.ps1), which MERGES + DEDUPES and produces one
# Executive Email Summary. Never a provider per account.
#
# READ ONLY. It never composes, sends, replies, forwards, labels, marks,
# archives, or deletes. The only scope requested is gmail.readonly.
#
# Auth: the SHARED account-aware Google OAuth module (core/google-oauth.ps1)
# - installed-desktop-app flow (PKCE + loopback + offline refresh), with
# each account's tokens stored separately (keyed by email) in the gitignored
# gmail.tokens.json. One expired account never breaks the others.
#
# Private local files (gitignored, never printed/committed/logged):
#   gmail.config.json  - OAuth client id/secret (+ optional triage lists)
#   gmail.tokens.json  - per-account access/refresh tokens
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
        analyzeCap        = 60   # analyze the most recent N of each account's inbox today
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

# Resolve an account's identity (email) from a token - read-only.
function Resolve-GmailIdentity {
    param([Parameter(Mandatory)][string]$Token)
    $p = Invoke-GoogleApi -Token $Token -BaseUrl (Get-GmailConfig).apiBase -Path '/users/me/profile'
    return [string]$p.emailAddress
}

# ---- connect / token / disconnect (per account) --------------------
# Connect adds ANOTHER account (the browser lets Jake pick which one).
function Connect-Gmail {
    if (-not (Get-Command Connect-GoogleAccount -ErrorAction SilentlyContinue)) { return [pscustomobject]@{ ok = $false; state = 'error'; detail = 'OAuth module not loaded.' } }
    $cfg = Get-GmailConfig
    if (-not $cfg.configured) { return [pscustomobject]@{ ok = $false; state = 'not-configured'; detail = 'No OAuth client configured. Add gmail.config.json (client id/secret for a Desktop app).' } }
    return (Connect-GoogleAccount -Config (Get-GmailOAuthConfig) -ResolveIdentity { param($tok) Resolve-GmailIdentity -Token $tok })
}
function Disconnect-Gmail {
    param([Parameter(Mandatory)][string]$Account)
    return (Disconnect-GoogleAccount -Config (Get-GmailOAuthConfig) -Id $Account)
}
# Ids of all connected Gmail accounts.
function Get-GmailAccountIds { return @(Get-GoogleAccountIds -Path (Get-GmailTokenPath)) }

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
# for the provider-neutral Email Intelligence engine. Read only. Every
# message carries its sourceAccount and the RFC822 Message-ID (messageId),
# which the intelligence layer uses to dedupe the same email across accounts.
function Convert-GmailMessage {
    param($Raw, [string]$Account, $Aliases = @(), [string]$SourceAccount = '')
    $headers = $Raw.payload.headers
    $fromRaw = Get-GmailHeaderValue -Headers $headers -Name 'From'
    $from = Split-EmailFrom -Value $fromRaw
    $subject = Get-GmailHeaderValue -Headers $headers -Name 'Subject'
    $to = Get-GmailHeaderValue -Headers $headers -Name 'To'
    $cc = Get-GmailHeaderValue -Headers $headers -Name 'Cc'
    $deliveredTo = Get-GmailHeaderValue -Headers $headers -Name 'Delivered-To'
    $listUnsub = Get-GmailHeaderValue -Headers $headers -Name 'List-Unsubscribe'
    $contentType = Get-GmailHeaderValue -Headers $headers -Name 'Content-Type'
    $messageId = (Get-GmailHeaderValue -Headers $headers -Name 'Message-ID').Trim()
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
        id            = [string]$Raw.id
        threadId      = [string]$Raw.threadId
        messageId     = $messageId
        sourceAccount = $SourceAccount
        from          = $from.email
        fromName      = $from.name
        subject       = $subject
        snippet       = [string]$Raw.snippet
        date          = $date
        unread        = ($labels -contains 'UNREAD')
        important     = ($labels -contains 'IMPORTANT')
        fromMe        = $fromMe
        toMe          = $toMe
        promo         = (Test-GmailPromo -LabelIds $labels -ListUnsub $listUnsub)
        bulk          = (Test-GmailBulk -Headers $headers)
        invite        = (Test-GmailInvite -Raw $Raw -Subject $subject -FromEmail $from.email -ContentType $contentType)
        labels        = $labels
    }
}

# Fetch today's inbox for ONE account (read-only). Returns normalized
# messages tagged with the account, plus its status. Errors are captured
# per account so one failure never blocks the others.
function Get-GmailAccountData {
    param([Parameter(Mandatory)][string]$Id, [datetime]$Now = (Get-Date))
    $cfg = Get-GmailConfig
    $at = Get-GoogleAccountAccessToken -Config (Get-GmailOAuthConfig) -Id $Id
    if (-not $at.ok) { return [pscustomobject]@{ ok = $false; id = $Id; email = $Id; state = $at.state; detail = $at.detail; messages = @(); total = 0; capped = $false } }
    try {
        $profile = Invoke-GoogleApi -Token $at.token -BaseUrl $cfg.apiBase -Path '/users/me/profile'
        $email = [string]$profile.emailAddress
        # migrate a legacy/placeholder id to the real email (seamless upgrade)
        if (($Id -eq 'default' -or $Id -like 'account-*') -and $email) { Rename-GoogleAccountRecord -Path $cfg.tokenPath -OldId $Id -NewId $email }

        $midnight = [int]([DateTimeOffset]$Now.Date).ToUnixTimeSeconds()
        $q = ("in:inbox after:{0}" -f $midnight)
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
        $pagedCapped = [bool]($pageToken)

        $cap = [int]$cfg.analyzeCap
        $toAnalyze = @($ids | Select-Object -First $cap)
        $messages = @()
        foreach ($mid in $toAnalyze) {
            $raw = Invoke-GoogleApi -Token $at.token -BaseUrl $cfg.apiBase -Path ("/users/me/messages/{0}" -f $mid) -Query @{ format = 'metadata' }
            $messages += (Convert-GmailMessage -Raw $raw -Account $email -Aliases @($cfg.myAddresses) -SourceAccount $email)
        }
        $capped = [bool](($totalToday -gt $toAnalyze.Count) -or $pagedCapped)
        return [pscustomobject]@{ ok = $true; id = $email; email = $email; state = 'connected'; detail = ('Live from Gmail ({0}).' -f $email); messages = @($messages); total = $totalToday; capped = $capped }
    } catch {
        $msg = $_.Exception.Message; $state = 'error'
        if ($_.Exception.Response -and ($_.Exception.Response.PSObject.Properties.Name -contains 'StatusCode')) {
            $sc = [int]$_.Exception.Response.StatusCode
            if ($sc -eq 401) { $state = 'needs-attention'; $msg = 'Authorization expired; reconnect this account.' }
            elseif ($sc -eq 403) { $state = 'denied'; $msg = 'I can reach Gmail, but the request was denied.' }
        } elseif ($_.Exception -is [System.Net.WebException]) { $state = 'network-error'; $msg = 'The network is unavailable.' }
        Write-GmailDiag -Level 'error' -Message ("Gmail fetch {0} for one account." -f $state)
        return [pscustomobject]@{ ok = $false; id = $Id; email = $Id; state = $state; detail = $msg; messages = @(); total = 0; capped = $false }
    }
}

# ---- THE contract: one Executive Email Summary across ALL accounts --
function Get-Email {
    param([string]$When = 'today', [datetime]$Now = (Get-Date))
    $cfg = Get-GmailConfig
    $nowStr = $Now.ToString('yyyy-MM-dd HH:mm:ss')
    $fail = {
        param($state, $detail)
        [pscustomobject]@{ provider = 'email'; backend = 'gmail'; ok = $false; errorState = $state; status = [pscustomobject]@{ state = $state; detail = $detail; lastRefresh = $null; lastError = $detail }; timestamp = $nowStr; account = $null; accounts = @(); accountCount = 0; totalToday = 0; analyzed = 0; capped = $false; messages = @(); summary = $null }
    }
    if (-not $cfg.configured) { return (& $fail 'not-configured' 'Gmail is not connected yet.') }
    $ids = @(Get-GoogleAccountIds -Path $cfg.tokenPath)
    if ($ids.Count -eq 0) { return (& $fail 'not-connected' 'Gmail is not connected yet.') }

    $allMessages = @(); $accountsInfo = @(); $anyOk = $false; $totalToday = 0; $anyCapped = $false; $firstBadState = $null; $firstBadDetail = $null
    foreach ($id in $ids) {
        $d = Get-GmailAccountData -Id $id -Now $Now
        $accountsInfo += [pscustomobject]@{ email = $d.email; state = $d.state; detail = $d.detail; total = $d.total; analyzed = @($d.messages).Count }
        if ($d.ok) { $anyOk = $true; $allMessages += @($d.messages); $totalToday += [int]$d.total; $anyCapped = $anyCapped -or $d.capped }
        elseif (-not $firstBadState) { $firstBadState = $d.state; $firstBadDetail = $d.detail }
    }
    if (-not $anyOk) { return (& $fail $firstBadState $firstBadDetail) }

    $ctx = @{
        userEmail         = ($accountsInfo | Where-Object { $_.state -eq 'connected' } | Select-Object -First 1).email
        importantContacts = @($cfg.importantContacts)
        clientDomains     = @($cfg.clientDomains)
        carrierDomains    = @($cfg.carrierDomains)
        carrierHints      = $cfg.carrierHints
    }
    # MERGE happens in the provider-neutral intelligence layer: it dedupes the
    # same email across accounts (by Message-ID) and produces one summary.
    $summary = Get-ExecutiveEmailSummary -Messages $allMessages -TotalToday $totalToday -Capped $anyCapped -Context $ctx

    $connected = @($accountsInfo | Where-Object { $_.state -eq 'connected' })
    $primary = if ($connected.Count -gt 0) { $connected[0].email } else { $null }
    $degraded = @($accountsInfo | Where-Object { $_.state -ne 'connected' })
    $detail = if ($degraded.Count -eq 0) { ('Live from Gmail ({0} account(s)).' -f $connected.Count) }
    else { ('Live from Gmail ({0} of {1} account(s); {2} need attention).' -f $connected.Count, $accountsInfo.Count, $degraded.Count) }

    return [pscustomobject]@{
        provider   = 'email'; backend = 'gmail'; ok = $true; errorState = $null
        status     = [pscustomobject]@{ state = 'connected'; detail = $detail; lastRefresh = $nowStr; lastError = $(if ($degraded.Count) { $degraded[0].detail } else { $null }) }
        timestamp  = $nowStr; account = $primary; accounts = @($accountsInfo); accountCount = @($accountsInfo).Count
        totalToday = $totalToday; analyzed = @($summary.attentionItems).Count; capped = $anyCapped
        messages   = @($allMessages)
        summary    = $summary
    }
}

# Aging unread mail (read-only) for the Executive Timeline: unread inbox
# messages received BEFORE today, within the last $Days. Returns a count plus
# a few normalized examples (with age in days and a carrier flag). Derived
# entirely from existing Gmail timestamps - no storage, promotions excluded.
function Get-EmailWaiting {
    param([datetime]$Now = (Get-Date), [int]$Days = 6, [int]$MinAgeDays = 2, [int]$MaxExamples = 10)
    $cfg = Get-GmailConfig
    if (-not $cfg.configured) { return [pscustomobject]@{ count = 0; items = @() } }
    $ids = @(Get-GoogleAccountIds -Path $cfg.tokenPath)
    if ($ids.Count -eq 0) { return [pscustomobject]@{ count = 0; items = @() } }
    # Genuine "waiting on you": PRIMARY-category unread mail from real people
    # (not no-reply/notifications), aged MinAgeDays..Days - recent enough to act
    # on, not the whole ancient backlog. Derived from Gmail timestamps only.
    $q = ("is:unread in:inbox category:primary older_than:{0}d newer_than:{1}d -from:noreply -from:no-reply -from:notifications -from:mailer-daemon" -f $MinAgeDays, $Days)
    $hints = if ($cfg.carrierHints) { $cfg.carrierHints } else { $script:EmailCarrierHints }
    $seen = @{}; $items = @(); $count = 0
    foreach ($id in $ids) {
        $at = Get-GoogleAccountAccessToken -Config (Get-GmailOAuthConfig) -Id $id
        if (-not $at.ok) { continue }
        try {
            $pageToken = $null; $pages = 0; $mids = @()
            do {
                $query = @{ q = $q; maxResults = '100' }; if ($pageToken) { $query['pageToken'] = $pageToken }
                $list = Invoke-GoogleApi -Token $at.token -BaseUrl $cfg.apiBase -Path '/users/me/messages' -Query $query
                foreach ($mi in @($list.messages)) { $mids += [string]$mi.id }
                $pageToken = $list.nextPageToken; $pages++
            } while ($pageToken -and $pages -lt 3)
            $count += @($mids).Count
            $fetched = 0
            foreach ($mid in $mids) {
                if ($fetched -ge $MaxExamples) { break }
                $raw = Invoke-GoogleApi -Token $at.token -BaseUrl $cfg.apiBase -Path ("/users/me/messages/{0}" -f $mid) -Query @{ format = 'metadata' }
                $n = Convert-GmailMessage -Raw $raw -Account $id -Aliases @($cfg.myAddresses) -SourceAccount $id
                $fetched++
                if ($n.promo -or $n.bulk) { continue }   # aging noise isn't "waiting on you"
                $key = if ($n.messageId) { $n.messageId } else { $n.id }
                if ($seen.ContainsKey($key)) { continue }
                $seen[$key] = $true
                $carrier = Test-EmailCarrier -Subject $n.subject -Snippet $n.snippet -From $n.from -Hints $hints -CarrierDomains @($cfg.carrierDomains)
                $items += [pscustomobject]@{ from = $n.from; fromName = $n.fromName; subject = $n.subject; date = $n.date; ageDays = [int][math]::Floor(($Now - $n.date).TotalDays); account = $id; messageId = $key; carrier = [bool]$carrier }
            }
        } catch { }
    }
    return [pscustomobject]@{ count = $count; items = @($items | Sort-Object ageDays -Descending) }
}

# Status for Settings. Without -Live: config/connection state (per account),
# no network. With -Live: a real read to confirm access across all accounts.
function Get-GmailStatus {
    param([switch]$Live)
    $cfg = Get-GmailConfig
    if (-not $cfg.configured) { return [pscustomobject]@{ name = 'Gmail'; state = 'not-configured'; detail = 'No OAuth client configured. Add a Desktop-app client id/secret to gmail.config.json, then Connect.'; account = $null; accounts = @(); readOnly = $true; lastRefresh = $null; lastError = $null } }
    $ids = @(Get-GoogleAccountIds -Path $cfg.tokenPath)
    if ($ids.Count -eq 0) { return [pscustomobject]@{ name = 'Gmail'; state = 'not-connected'; detail = 'Configured but not connected. Click Connect Gmail.'; account = $null; accounts = @(); readOnly = $true; lastRefresh = $null; lastError = $null } }
    if (-not $Live) {
        $accts = @($ids | ForEach-Object { [pscustomobject]@{ email = $_; state = 'connected'; detail = 'Connected (read-only).' } })
        return [pscustomobject]@{ name = 'Gmail'; state = 'connected'; detail = ('{0} account(s) connected (read-only). Run Test Connection to confirm live access.' -f $ids.Count); account = $ids[0]; accounts = $accts; readOnly = $true; lastRefresh = $null; lastError = $null }
    }
    $e = Get-Email -When 'today'
    $accts = @($e.accounts | ForEach-Object { [pscustomobject]@{ email = $_.email; state = $_.state; detail = $_.detail } })
    $state = if ($e.ok) { 'connected' } else { $e.status.state }
    return [pscustomobject]@{ name = 'Gmail'; state = $state; detail = $e.status.detail; account = $e.account; accounts = $accts; readOnly = $true; lastRefresh = $e.status.lastRefresh; lastError = $e.status.lastError }
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
            description = 'Read-only Gmail across one or more Google accounts (OAuth 2.0 desktop, PKCE). Backend = gmail. Explained by Tony as one Executive Email Summary.'
            relevant    = { param($text) Test-EmailRelevant $text }
            query       = { param($opts) Get-Email -When 'today' }
            status      = { param($live) Get-GmailStatus -Live:([bool]$live) }
        })
}
