# =====================================================================
# yahoo-provider.ps1  -  Read-ONLY Yahoo Mail (IMAP) vendor backend
# ---------------------------------------------------------------------
# A SECOND communication backend behind the one provider-neutral email
# signal (Epic 8). It fetches Yahoo Mail READ-ONLY over IMAP and normalizes
# each message into the SAME shape Gmail produces (tagged provider='yahoo').
# It contains NO summary logic - the provider-neutral aggregator
# (core/communications.ps1) merges backends and runs the ONE existing
# Executive Email Summary. Sam never learns "Yahoo".
#
# AUTH (confirmed from official Yahoo Help): read-only IMAP over SSL,
# imap.mail.yahoo.com:993, using a Yahoo THIRD-PARTY APP PASSWORD (not the
# normal password; OAuth is not the documented path for a desktop mail app).
#
# READ ONLY. It EXAMINEs the mailbox (never SELECT) and fetches HEADERS ONLY
# via BODY.PEEK - so a message is NEVER marked \Seen and NO body is downloaded.
# It never issues STORE/APPEND/EXPUNGE/COPY/MOVE/DELETE or any flag change.
#
# Private local file (gitignored, never printed/committed/logged):
#   yahoo.config.json  - { email, appPassword, importantContacts, ... }
# Nothing sensitive is ever logged: diagnostics carry only provider, state,
# counts, timing, and a safe error class - never the password or message text.
# =====================================================================

$ErrorActionPreference = 'Stop'

function Get-YahooConfigPath { return (Join-Path $PSScriptRoot 'yahoo.config.json') }

function Get-YahooConfig {
    $email = $null; $appPassword = $null; $source = 'none'
    $importantContacts = @(); $clientDomains = @(); $carrierDomains = @()
    $p = Get-YahooConfigPath
    if (Test-Path $p) {
        try {
            $c = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($c.email) { $email = [string]$c.email }
            if ($c.appPassword) { $appPassword = [string]$c.appPassword }
            if ($email -and $appPassword) { $source = 'yahoo.config.json' }
            if ($c.PSObject.Properties.Name -contains 'importantContacts' -and $c.importantContacts) { $importantContacts = @($c.importantContacts) }
            if ($c.PSObject.Properties.Name -contains 'clientDomains' -and $c.clientDomains) { $clientDomains = @($c.clientDomains) }
            if ($c.PSObject.Properties.Name -contains 'carrierDomains' -and $c.carrierDomains) { $carrierDomains = @($c.carrierDomains) }
        } catch { }
    }
    return [pscustomobject]@{
        email             = $email
        appPassword       = $appPassword
        configured        = (-not [string]::IsNullOrWhiteSpace($email)) -and (-not [string]::IsNullOrWhiteSpace($appPassword))
        source            = $source
        imapHost          = 'imap.mail.yahoo.com'
        imapPort          = 993
        provider          = 'yahoo'
        appName           = 'Yahoo Mail'
        diagSource        = 'yahoo'
        readOnly          = $true
        importantContacts = $importantContacts
        clientDomains     = $clientDomains
        carrierDomains    = $carrierDomains
        analyzeCap        = 40
        timeoutMs         = 15000
    }
}

# Diagnostics: provider + state + counts + timing + safe error class ONLY.
# NEVER the app password, message contents, senders, or subjects.
function Write-YahooDiag { param([string]$Level = 'info', [string]$Message = '') if (Get-Command Write-TonyDiag -ErrorAction SilentlyContinue) { Write-TonyDiag -Level $Level -Source 'yahoo' -Message $Message } }

# ---- minimal READ-ONLY IMAP client (pure .NET; no external packages) ----

function Read-ImapLine {
    param($Ssl)
    $sb = New-Object System.Text.StringBuilder
    while ($true) {
        $b = $Ssl.ReadByte()
        if ($b -lt 0) { break }          # stream closed
        if ($b -eq 13) { continue }       # skip CR
        if ($b -eq 10) { break }          # LF ends the line
        [void]$sb.Append([char]$b)
    }
    return $sb.ToString()
}

function Read-ImapLiteral {
    param($Ssl, [int]$N)
    if ($N -le 0) { return '' }
    $buf = New-Object byte[] $N; $off = 0
    while ($off -lt $N) {
        $r = $Ssl.Read($buf, $off, ($N - $off))
        if ($r -le 0) { break }
        $off += $r
    }
    return [System.Text.Encoding]::ASCII.GetString($buf, 0, $off)
}

# Send a tagged command. NEVER logs the command text (it can carry the password).
function Send-Imap {
    param($Session, [string]$Command)
    $Session.tag++
    $tag = ('A{0}' -f $Session.tag)
    $bytes = [System.Text.Encoding]::ASCII.GetBytes(('{0} {1}' -f $tag, $Command) + "`r`n")
    $Session.ssl.Write($bytes, 0, $bytes.Length); $Session.ssl.Flush()
    return $tag
}

# Read a full tagged response, materializing any {n} literals inline.
function Read-ImapResponse {
    param($Session, [string]$Tag)
    $parts = New-Object System.Collections.Generic.List[string]
    $guard = 0
    while ($true) {
        $guard++; if ($guard -gt 100000) { break }
        $line = Read-ImapLine -Ssl $Session.ssl
        $m = [regex]::Match($line, '\{(\d+)\}\s*$')
        if ($m.Success) {
            $n = [int]$m.Groups[1].Value
            $lit = Read-ImapLiteral -Ssl $Session.ssl -N $n
            $parts.Add($line)
            $parts.Add('<<LIT>>' + $lit)
            continue
        }
        $parts.Add($line)
        if ($line -match ('^' + [regex]::Escape($Tag) + '\s+(OK|NO|BAD)\b')) {
            return [pscustomobject]@{ ok = ($Matches[1] -eq 'OK'); status = $Matches[1]; lines = $parts.ToArray() }
        }
        if ($line -match '^\*\s*BYE\b') { return [pscustomobject]@{ ok = $false; status = 'BYE'; lines = $parts.ToArray() } }
    }
    return [pscustomobject]@{ ok = $false; status = 'INCOMPLETE'; lines = $parts.ToArray() }
}

function Invoke-Imap { param($Session, [string]$Command) $tag = Send-Imap -Session $Session -Command $Command; return (Read-ImapResponse -Session $Session -Tag $tag) }

# Open a TLS IMAP session and authenticate. Read-only intent (EXAMINE later).
# Returns a session object, or throws a classified error. Never logs the secret.
function Connect-YahooSession {
    param([Parameter(Mandatory)][string]$Email, [Parameter(Mandatory)][string]$AppPassword, [int]$TimeoutMs = 15000)
    $cfg = Get-YahooConfig
    $client = New-Object System.Net.Sockets.TcpClient
    $iar = $client.BeginConnect($cfg.imapHost, $cfg.imapPort, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs)) { $client.Close(); throw (New-Object System.TimeoutException('connect-timeout')) }
    $client.EndConnect($iar)
    $client.ReceiveTimeout = $TimeoutMs; $client.SendTimeout = $TimeoutMs
    $ssl = New-Object System.Net.Security.SslStream($client.GetStream(), $false)
    $ssl.AuthenticateAsClient($cfg.imapHost)
    $session = [pscustomobject]@{ client = $client; ssl = $ssl; tag = 0 }
    [void](Read-ImapLine -Ssl $ssl)   # server greeting (untagged * OK)
    # LOGIN - quote and escape the two arguments; the command is NEVER logged.
    $esc = { param($s) '"' + (([string]$s) -replace '\\', '\\' -replace '"', '\"') + '"' }
    $login = Invoke-Imap -Session $session -Command ('LOGIN {0} {1}' -f (& $esc $Email), (& $esc $AppPassword))
    if (-not $login.ok) { Close-YahooSession -Session $session; throw (New-Object System.Security.Authentication.AuthenticationException('auth-failed')) }
    return $session
}

function Close-YahooSession {
    param($Session)
    if (-not $Session) { return }
    try { [void](Invoke-Imap -Session $Session -Command 'LOGOUT') } catch { }
    try { $Session.ssl.Dispose() } catch { }
    try { $Session.client.Close() } catch { }
}

# ---- header parsing + normalization (pure; testable) ----

# Parse an RFC822 header block into a name->value lookup (unfolds continuations).
function ConvertFrom-RfcHeaders {
    param([string]$Block)
    $map = @{}
    $lines = @($Block -split "`n")
    $curName = $null; $curVal = New-Object System.Text.StringBuilder
    $commit = { if ($curName) { $map[$curName.ToLower()] = ($curVal.ToString().Trim()) } }
    foreach ($raw in $lines) {
        $line = $raw -replace "`r$", ''
        if ($line -match '^\s+' -and $curName) { [void]$curVal.Append(' ' + $line.Trim()); continue }  # folded continuation
        $idx = $line.IndexOf(':')
        if ($idx -gt 0) {
            & $commit
            $curName = $line.Substring(0, $idx).Trim()
            $curVal = New-Object System.Text.StringBuilder
            [void]$curVal.Append($line.Substring($idx + 1).Trim())
        }
    }
    & $commit
    return $map
}
function Get-RfcHeader { param($Map, [string]$Name) $k = $Name.ToLower(); if ($Map.ContainsKey($k)) { return [string]$Map[$k] } return '' }

# "Display Name <user@host>" -> { name; email }. Self-contained (no cross-file dep).
function Split-YahooAddress {
    param([string]$Value)
    $name = ''; $email = ''
    if ($Value -match '^\s*"?([^"<]*)"?\s*<([^>]+)>') { $name = $Matches[1].Trim(); $email = $Matches[2].Trim() }
    elseif ($Value -match '([^\s<>]+@[^\s<>]+)') { $email = $Matches[1].Trim() }
    else { $email = ([string]$Value).Trim() }
    return [pscustomobject]@{ name = $name; email = $email }
}

# Parse an IMAP INTERNALDATE ("01-Jan-2026 10:30:00 +0000") to LOCAL DateTime.
function ConvertFrom-ImapDate {
    param([string]$Value, [datetime]$Fallback = (Get-Date))
    $v = ([string]$Value).Trim('"').Trim()
    try { return ([datetimeoffset]::Parse($v, [Globalization.CultureInfo]::InvariantCulture)).LocalDateTime } catch { }
    try { return [datetime]::ParseExact($v, 'dd-MMM-yyyy HH:mm:ss zzz', [Globalization.CultureInfo]::InvariantCulture).ToLocalTime() } catch { }
    return $Fallback
}

# Convert one fetched Yahoo message (header block + flags + internaldate) into the
# SHARED normalized model. Pure. provider='yahoo'; read-only fields only.
function Convert-YahooMessage {
    param([string]$HeaderBlock, [string]$Flags, [string]$InternalDate, [string]$Uid, [Parameter(Mandatory)][string]$Account, $Aliases = @())
    $h = ConvertFrom-RfcHeaders -Block $HeaderBlock
    $from = Split-YahooAddress -Value (Get-RfcHeader $h 'From')
    $subject = Get-RfcHeader $h 'Subject'
    $to = Get-RfcHeader $h 'To'; $cc = Get-RfcHeader $h 'Cc'
    $messageId = (Get-RfcHeader $h 'Message-ID').Trim()
    $listUnsub = Get-RfcHeader $h 'List-Unsubscribe'
    $listId = Get-RfcHeader $h 'List-Id'
    $precedence = (Get-RfcHeader $h 'Precedence').ToLower()
    $autoSub = (Get-RfcHeader $h 'Auto-Submitted').ToLower().Trim()
    $contentType = (Get-RfcHeader $h 'Content-Type').ToLower()

    $acct = ([string]$Account).ToLower()
    $recips = ("{0} {1}" -f $to, $cc).ToLower()
    $myAddrs = @($acct); foreach ($a in @($Aliases)) { $al = ([string]$a).ToLower().Trim(); if ($al -and ($myAddrs -notcontains $al)) { $myAddrs += $al } }
    $toMe = $false; foreach ($a in $myAddrs) { if ($a -and $recips.Contains($a)) { $toMe = $true; break } }
    $fromMe = [bool]($acct -and ($from.email.ToLower() -eq $acct))

    $flagsL = ([string]$Flags).ToLower()
    $unread = -not ($flagsL -match '\\seen')
    $important = [bool]($flagsL -match '\\flagged')

    $promo = (-not [string]::IsNullOrWhiteSpace($listUnsub))
    $bulk = $false
    if (-not [string]::IsNullOrWhiteSpace($listId)) { $bulk = $true }
    elseif ($precedence -match 'bulk|list|junk') { $bulk = $true }
    elseif ($autoSub -and $autoSub -ne 'no') { $bulk = $true }
    $invite = [bool](($contentType -match 'text/calendar|method=request') -or ($subject -match '(?i)^\s*(invitation|updated invitation|canceled event|new event):'))
    $hasAttachments = [bool]($contentType -match 'multipart/mixed')

    return [pscustomobject]@{
        id            = ('yahoo-' + [string]$Uid)
        threadId      = (Get-RfcHeader $h 'References').Split(' ')[0]
        messageId     = $messageId
        sourceAccount = $Account
        provider      = 'yahoo'
        from          = $from.email
        fromName      = $from.name
        subject       = $subject
        snippet       = ''                      # metadata only - bodies are never fetched
        date          = (ConvertFrom-ImapDate -Value $InternalDate)
        unread        = $unread
        important     = $important
        fromMe        = $fromMe
        toMe          = $toMe
        promo         = $promo
        bulk          = $bulk
        invite        = $invite
        hasAttachments = $hasAttachments
        labels        = @()
    }
}

# Parse one "* n FETCH (...)" response's parts into FLAGS / INTERNALDATE / UID /
# header literal. Pure over the response-line array from Read-ImapResponse.
function Read-YahooFetchParts {
    param($Lines)
    $flags = ''; $internal = ''; $uid = ''; $header = ''
    foreach ($p in @($Lines)) {
        if ($p -like '<<LIT>>*') { $header = $p.Substring(7); continue }
        $mf = [regex]::Match($p, '(?i)FLAGS\s*\(([^)]*)\)'); if ($mf.Success) { $flags = $mf.Groups[1].Value }
        $mi = [regex]::Match($p, '(?i)INTERNALDATE\s+"([^"]*)"'); if ($mi.Success) { $internal = $mi.Groups[1].Value }
        $mu = [regex]::Match($p, '(?i)\bUID\s+(\d+)'); if ($mu.Success) { $uid = $mu.Groups[1].Value }
    }
    return [pscustomobject]@{ flags = $flags; internalDate = $internal; uid = $uid; header = $header }
}

$script:YahooHeaderFields = 'FROM TO CC SUBJECT DATE MESSAGE-ID REFERENCES LIST-ID LIST-UNSUBSCRIBE PRECEDENCE AUTO-SUBMITTED CONTENT-TYPE'

# ---- THE backend read (daily): new + unread mail, read-only, normalized ----
function Get-YahooMessages {
    param([datetime]$Now = (Get-Date), [int]$Max = 0)
    $cfg = Get-YahooConfig
    $fail = { param($state, $detail) [pscustomobject]@{ ok = $false; provider = 'yahoo'; id = $cfg.email; email = $cfg.email; state = $state; detail = $detail; messages = @(); total = 0; capped = $false } }
    if (-not $cfg.configured) { return (& $fail 'not-configured' 'Yahoo Mail is not connected yet.') }
    if ($Max -le 0) { $Max = [int]$cfg.analyzeCap }

    $session = $null
    try { $session = Connect-YahooSession -Email $cfg.email -AppPassword $cfg.appPassword -TimeoutMs $cfg.timeoutMs }
    catch {
        $state = 'network-error'; $detail = 'Could not reach Yahoo Mail right now.'
        if ($_.Exception -is [System.Security.Authentication.AuthenticationException]) { $state = 'auth-failed'; $detail = 'Yahoo sign-in failed - check the app password in yahoo.config.json.' }
        Write-YahooDiag -Level 'error' -Message ('connect {0}' -f $state)
        return (& $fail $state $detail)
    }
    try {
        $ex = Invoke-Imap -Session $session -Command 'EXAMINE INBOX'   # READ-ONLY select
        if (-not $ex.ok) { Write-YahooDiag -Level 'error' -Message 'examine denied'; return (& $fail 'denied' 'Yahoo allowed sign-in but denied inbox access.') }

        $since = $Now.AddDays(-3).ToString('dd-MMM-yyyy', [Globalization.CultureInfo]::InvariantCulture)
        $search = Invoke-Imap -Session $session -Command ('UID SEARCH OR UNSEEN SINCE {0}' -f $since)
        $uids = @()
        foreach ($l in @($search.lines)) { $sm = [regex]::Match($l, '(?i)^\*\s+SEARCH\b(.*)$'); if ($sm.Success) { $uids += @($sm.Groups[1].Value.Trim() -split '\s+' | Where-Object { $_ -match '^\d+$' }) } }
        $uids = @($uids | Select-Object -Unique | Sort-Object { [int]$_ } -Descending)
        $total = $uids.Count
        $take = @($uids | Select-Object -First $Max)
        $capped = ($total -gt $take.Count)

        $messages = @()
        foreach ($u in $take) {
            $f = Invoke-Imap -Session $session -Command ('UID FETCH {0} (UID FLAGS INTERNALDATE BODY.PEEK[HEADER.FIELDS ({1})])' -f $u, $script:YahooHeaderFields)
            if (-not $f.ok) { continue }
            $parts = Read-YahooFetchParts -Lines $f.lines
            if (-not $parts.header) { continue }
            $messages += (Convert-YahooMessage -HeaderBlock $parts.header -Flags $parts.flags -InternalDate $parts.internalDate -Uid $(if ($parts.uid) { $parts.uid } else { $u }) -Account $cfg.email)
        }
        Write-YahooDiag -Level 'info' -Message ('read ok: {0} found, {1} analyzed' -f $total, @($messages).Count)
        return [pscustomobject]@{ ok = $true; provider = 'yahoo'; id = $cfg.email; email = $cfg.email; state = 'connected'; detail = ('Live from Yahoo Mail ({0}).' -f $cfg.email); messages = @($messages); total = $total; capped = $capped }
    }
    catch { Write-YahooDiag -Level 'error' -Message 'read network-error'; return (& $fail 'network-error' 'The Yahoo connection dropped mid-read.') }
    finally { Close-YahooSession -Session $session }
}

# ---- Historical Search Mode: EXPLICIT only, read-only, evidence returned ----
# Searches OLDER Yahoo mail for a person/subject/text. Never auto-triggered and
# never creates a proposal on its own - the caller shows evidence and asks Jake.
function Search-YahooMail {
    param([Parameter(Mandatory)][string]$Query, [int]$SinceDays = 365, [int]$Max = 25, [datetime]$Now = (Get-Date))
    $cfg = Get-YahooConfig
    $fail = { param($state, $detail) [pscustomobject]@{ ok = $false; provider = 'yahoo'; mode = 'historical'; state = $state; detail = $detail; query = $Query; results = @() } }
    if (-not $cfg.configured) { return (& $fail 'not-configured' 'Yahoo Mail is not connected yet.') }
    if ([string]::IsNullOrWhiteSpace($Query)) { return (& $fail 'no-query' 'No search terms were given.') }

    $session = $null
    try { $session = Connect-YahooSession -Email $cfg.email -AppPassword $cfg.appPassword -TimeoutMs $cfg.timeoutMs }
    catch {
        $state = 'network-error'; if ($_.Exception -is [System.Security.Authentication.AuthenticationException]) { $state = 'auth-failed' }
        Write-YahooDiag -Level 'error' -Message ('search connect {0}' -f $state); return (& $fail $state 'Could not connect to Yahoo Mail for the search.')
    }
    try {
        [void](Invoke-Imap -Session $session -Command 'EXAMINE INBOX')   # READ-ONLY
        $since = $Now.AddDays(-[math]::Abs($SinceDays)).ToString('dd-MMM-yyyy', [Globalization.CultureInfo]::InvariantCulture)
        $q = ([string]$Query -replace '"', '')
        $search = Invoke-Imap -Session $session -Command ('UID SEARCH SINCE {0} TEXT "{1}"' -f $since, $q)
        $uids = @()
        foreach ($l in @($search.lines)) { $sm = [regex]::Match($l, '(?i)^\*\s+SEARCH\b(.*)$'); if ($sm.Success) { $uids += @($sm.Groups[1].Value.Trim() -split '\s+' | Where-Object { $_ -match '^\d+$' }) } }
        $uids = @($uids | Select-Object -Unique | Sort-Object { [int]$_ } -Descending | Select-Object -First $Max)
        $results = @()
        foreach ($u in $uids) {
            $f = Invoke-Imap -Session $session -Command ('UID FETCH {0} (UID FLAGS INTERNALDATE BODY.PEEK[HEADER.FIELDS ({1})])' -f $u, $script:YahooHeaderFields)
            if (-not $f.ok) { continue }
            $parts = Read-YahooFetchParts -Lines $f.lines
            if (-not $parts.header) { continue }
            $results += (Convert-YahooMessage -HeaderBlock $parts.header -Flags $parts.flags -InternalDate $parts.internalDate -Uid $(if ($parts.uid) { $parts.uid } else { $u }) -Account $cfg.email)
        }
        Write-YahooDiag -Level 'info' -Message ('historical search: {0} matches' -f @($results).Count)
        return [pscustomobject]@{ ok = $true; provider = 'yahoo'; mode = 'historical'; state = 'connected'; detail = ('{0} match(es).' -f @($results).Count); query = $Query; results = @($results) }
    }
    catch { Write-YahooDiag -Level 'error' -Message 'historical search network-error'; return (& $fail 'network-error' 'The Yahoo search connection dropped.') }
    finally { Close-YahooSession -Session $session }
}

# Status for Settings / the aggregator. Without -Live: config state, no network.
# With -Live: a real read-only login + EXAMINE to confirm access.
function Get-YahooStatus {
    param([switch]$Live)
    $cfg = Get-YahooConfig
    if (-not $cfg.configured) { return [pscustomobject]@{ name = 'Yahoo Mail'; provider = 'yahoo'; state = 'not-configured'; detail = 'Add your Yahoo address + app password to yahoo.config.json (read-only IMAP).'; account = $null; readOnly = $true } }
    if (-not $Live) { return [pscustomobject]@{ name = 'Yahoo Mail'; provider = 'yahoo'; state = 'connected'; detail = ('Configured ({0}); run Test Connection to confirm live access.' -f $cfg.email); account = $cfg.email; readOnly = $true } }
    $r = Get-YahooMessages -Max 1
    $state = if ($r.ok) { 'connected' } else { $r.state }
    return [pscustomobject]@{ name = 'Yahoo Mail'; provider = 'yahoo'; state = $state; detail = $r.detail; account = $cfg.email; readOnly = $true }
}
