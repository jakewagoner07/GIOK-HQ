# =====================================================================
# email-intelligence.ps1  —  Executive Email Intelligence (provider-neutral)
# ---------------------------------------------------------------------
# Tony's job with email is NOT to be an email client. It is to understand
# the inbox well enough to say what deserves Jake's attention - and let
# everything else wait. This engine turns a list of NORMALIZED messages
# into an Executive Email Summary. It is pure, deterministic, testable,
# and knows nothing about Gmail: any mail backend (Gmail today; Outlook,
# Microsoft 365, or Yahoo tomorrow) normalizes its messages to the same
# shape and feeds them here. One brain, many mailboxes.
#
# A NORMALIZED message (what every backend must produce):
#   id, threadId, from (email), fromName, subject, snippet, date (datetime),
#   unread (bool), important (bool: the backend's own importance marker),
#   fromMe (bool), toMe (bool: one of Jake's addresses is a direct To/Cc
#         recipient - backends resolve aliases, e.g. via Delivered-To),
#   promo (bool: explicit marketing - promotions/social/forums category or a
#         List-Unsubscribe header), bulk (bool: mailing-list / ESP / automated
#         sender - List-Id, Feedback-ID, Precedence: bulk, etc.),
#   invite (bool: carries a calendar invite), labels (string[])
#
# Classification is honest: it uses signals we can actually observe
# (the backend's categories/flags, sender shape, a calendar-invite marker,
# an optional user-curated important-contacts / client-domains list, and
# conservative urgency/carrier keywords). It never invents a relationship
# it cannot see. No summary of every email - only what matters.
# =====================================================================

$ErrorActionPreference = 'Stop'

# Default carrier / underwriting vocabulary for an insurance agent. Jake can
# extend this (and add known contacts / client domains) in gmail.config.json.
$script:EmailCarrierHints = @(
    'underwriting', 'underwriter', 'policy', 'premium', 'claim', 'renewal',
    'binder', 'endorsement', 'commission', 'carrier', 'coverage', 'quote',
    'application', 'licensing', 'producer', 'appointment paperwork', 'e&o'
)

function Get-EmailCountWord {
    param([int]$N, [switch]$Capital)
    $words = @('zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve')
    $w = if ($N -ge 0 -and $N -le 12) { $words[$N] } else { [string]$N }
    if ($Capital -and $w.Length -gt 0) { $w = $w.Substring(0, 1).ToUpper() + $w.Substring(1) }
    return $w
}

function Get-EmailSenderKind {
    param([string]$From, [string]$FromName)
    $f = ([string]$From).ToLower()
    if ($f -match '(?i)(no-?reply|do-?not-?reply|donotreply|notifications?@|mailer-daemon|postmaster|newsletter@|marketing@|updates?@|bounce|automated|noreply)') { return 'bulk' }
    return 'person'
}

function Test-EmailCarrier {
    param([string]$Subject, [string]$Snippet, [string]$From, $Hints, $CarrierDomains = @())
    $hay = (("{0} {1}" -f $Subject, $Snippet)).ToLower()
    foreach ($h in @($Hints)) { if ($h -and $hay -match [regex]::Escape(([string]$h).ToLower())) { return $true } }
    $dom = ''
    if ($From -match '@(.+)$') { $dom = $Matches[1].ToLower() }
    foreach ($d in @($CarrierDomains)) { if ($d -and $dom -and $dom -match [regex]::Escape(([string]$d).ToLower())) { return $true } }
    return $false
}

function Test-EmailUrgent {
    param([string]$Subject, [string]$Snippet)
    $hay = (("{0} {1}" -f $Subject, $Snippet)).ToLower()
    return [bool]($hay -match '(?i)\b(urgent|asap|immediately|time[- ]sensitive|action required|response needed|final notice|last notice|past due|overdue|expir(e|es|ing|ed)|deadline|by (today|tomorrow|end of day|eod))\b')
}

# One-time codes, verification/login/security codes, and automated identity
# messages. These are transient machine noise - NOT things that "need
# attention" - even though they often say a code "expires." Detecting them
# stops them from tripping the urgency heuristic.
function Test-EmailAutomatedCode {
    param([string]$Subject, [string]$Snippet)
    $hay = (("{0} {1}" -f $Subject, $Snippet)).ToLower()
    return [bool]($hay -match '(?i)(one-?time (code|password|passcode|pin)|verification code|login code|security code|access code|confirmation code|authentication code|is your .{0,40}code|your .{0,30}code is|\botp\b|passcode|two-?factor|2fa|verify your (email|account|identity)|confirm your (email|account)|sign-?in (code|attempt)|new sign-?in)')
}

# Is the sender one of Jake's important contacts / client domains?
function Test-EmailImportantContact {
    param([string]$From, $ImportantContacts = @(), $ClientDomains = @())
    $f = ([string]$From).ToLower()
    foreach ($c in @($ImportantContacts)) { if ($c -and $f -eq ([string]$c).ToLower()) { return $true } }
    $dom = ''
    if ($f -match '@(.+)$') { $dom = $Matches[1] }
    foreach ($d in @($ClientDomains)) { if ($d -and $dom -and $dom -eq ([string]$d).ToLower()) { return $true } }
    return $false
}

# Classify ONE normalized message. Deterministic; returns category + priority
# + a short honest 'why'. Order matters: strongest, most specific signal wins.
function Get-EmailClassification {
    param([Parameter(Mandatory)] $Msg, $Context = @{})
    $important = @($Context.importantContacts)
    $clientDomains = @($Context.clientDomains)
    $carrierDomains = @($Context.carrierDomains)
    $hints = if ($Context.carrierHints) { @($Context.carrierHints) } else { $script:EmailCarrierHints }

    $subject = [string]$Msg.subject
    $snippet = [string]$Msg.snippet
    $kind = Get-EmailSenderKind -From $Msg.from -FromName $Msg.fromName

    # 1) calendar invitations - a look / RSVP, not a reply
    if ($Msg.invite) { return [pscustomobject]@{ category = 'calendar-invite'; priority = 'normal'; why = 'A calendar invitation arrived.' } }

    # 2) known important contact / client - always surfaces
    if (Test-EmailImportantContact -From $Msg.from -ImportantContacts $important -ClientDomains $clientDomains) {
        return [pscustomobject]@{ category = 'important-contact'; priority = 'high'; why = 'From someone on your important-contacts list.' }
    }

    # 3) newsletters / promotions - low priority (marketing only; transactional
    #    business mail is intentionally NOT demoted here)
    if ($Msg.promo) {
        return [pscustomobject]@{ category = 'newsletter-promo'; priority = 'low'; why = 'Newsletter or promotional; it can wait.' }
    }

    # 3.5) one-time codes / verification / sign-in noise - automated and
    #      transient; never "needs attention" even if it says it expires.
    if (Test-EmailAutomatedCode -Subject $subject -Snippet $snippet) {
        return [pscustomobject]@{ category = 'automated'; priority = 'low'; why = 'One-time code or automated sign-in notice; nothing to do.' }
    }

    # 4) carrier / underwriting business updates
    if (Test-EmailCarrier -Subject $subject -Snippet $snippet -From $Msg.from -Hints $hints -CarrierDomains $carrierDomains) {
        return [pscustomobject]@{ category = 'carrier-underwriting'; priority = 'high'; why = 'Looks like a carrier or underwriting update.' }
    }

    # 4.5) bulk / automated senders (mailing lists, ESPs like SES/SendGrid,
    #      Precedence: bulk) that carry no unsubscribe UI but are clearly not a
    #      person expecting a reply. Checked AFTER carrier (so business updates
    #      survive) and BEFORE needs-reply (so newsletters don't masquerade as
    #      people). A real person on a known list is still surfaced via the
    #      important-contacts path above.
    if ($Msg.bulk) {
        return [pscustomobject]@{ category = 'newsletter-promo'; priority = 'low'; why = 'Bulk or automated sender; low priority.' }
    }

    # 5) explicit urgency - but only from a real person (or addressed directly
    #    to Jake). Automated bulk blasts that merely contain "urgent"/"expires"
    #    are not attention-worthy; genuine carrier urgency is already caught above.
    if ((Test-EmailUrgent -Subject $subject -Snippet $snippet) -and ($kind -eq 'person' -or $Msg.toMe)) {
        return [pscustomobject]@{ category = 'urgent'; priority = 'high'; why = 'Language suggests it is urgent or time-sensitive.' }
    }

    # 6) a real person writing to Jake, still unread -> likely wants a reply
    if ($kind -eq 'person' -and $Msg.toMe -and $Msg.unread -and -not $Msg.fromMe) {
        return [pscustomobject]@{ category = 'needs-reply'; priority = 'high'; why = 'A person wrote to you and is likely waiting for a response.' }
    }

    # 7) everything else
    if ($kind -eq 'bulk') { return [pscustomobject]@{ category = 'newsletter-promo'; priority = 'low'; why = 'Automated message; low priority.' } }
    return [pscustomobject]@{ category = 'other'; priority = 'normal'; why = 'Read or informational; nothing needed right now.' }
}

# THE Executive Email Summary. Takes the analyzed normalized messages plus the
# exact total received today (which may exceed the analyzed subset), and
# composes the calm "what deserves attention" summary - never a list of every
# email. Pure and deterministic.
function Get-ExecutiveEmailSummary {
    param(
        $Messages = @(),
        [int]$TotalToday = -1,
        [bool]$Capped = $false,
        $Context = @{}
    )
    $msgs = @($Messages)

    # MERGE POINT (multi-account, D17): the same email can arrive in more than
    # one connected account. Dedupe by RFC822 Message-ID (fallback to the
    # per-mailbox id), keeping one copy and remembering every account it landed
    # in. This is the provider-neutral place where account data is merged.
    $seen = @{}; $deduped = @()
    foreach ($m in $msgs) {
        $mid = if (($m.PSObject.Properties.Name -contains 'messageId') -and $m.messageId) { [string]$m.messageId } else { '' }
        $key = if ($mid) { 'mid:' + $mid.ToLower() } else { 'id:' + [string]$m.id }
        $sa = if (($m.PSObject.Properties.Name -contains 'sourceAccount') -and $m.sourceAccount) { [string]$m.sourceAccount } else { '' }
        if ($seen.ContainsKey($key)) {
            $existing = $seen[$key]
            if ($sa -and ($existing.sourceAccounts -notcontains $sa)) { $existing.sourceAccounts = @($existing.sourceAccounts + $sa) }
            continue
        }
        $m | Add-Member -NotePropertyName sourceAccounts -NotePropertyValue @($(if ($sa) { $sa } else { $null }) | Where-Object { $_ }) -Force
        $seen[$key] = $m
        $deduped += $m
    }
    $msgs = @($deduped)

    $classified = @()
    foreach ($m in $msgs) {
        $c = Get-EmailClassification -Msg $m -Context $Context
        $classified += [pscustomobject]@{ msg = $m; category = $c.category; priority = $c.priority; why = $c.why }
    }
    $analyzed = $classified.Count
    $total = if ($TotalToday -ge 0) { $TotalToday } else { $analyzed }

    $byCat = { param($cat) @($classified | Where-Object { $_.category -eq $cat }) }
    $needsReply = @(& $byCat 'needs-reply')
    $invites = @(& $byCat 'calendar-invite')
    $carrier = @(& $byCat 'carrier-underwriting')
    $importantC = @(& $byCat 'important-contact')
    $urgent = @(& $byCat 'urgent')
    $lowPri = @($classified | Where-Object { $_.priority -eq 'low' })

    $attention = @($classified | Where-Object { $_.priority -eq 'high' })
    $needsAttention = $attention.Count
    $unreadCount = @($msgs | Where-Object { $_.unread -and -not $_.fromMe }).Count
    # people awaiting a response (a person wrote; still unread)
    $waiting = @($needsReply + $importantC | Where-Object { $_.msg.unread })
    $waitingForReply = $waiting.Count

    # -- compose the summary sentences (calm, specific, honest) --
    $s = @()
    $plEmail = if ($total -eq 1) { '' } else { 's' }
    $line = ('You received {0} email{1} today.' -f $total, $plEmail)   # exact count for the headline

    if ($needsAttention -eq 0) {
        $s += 'Nothing needs your attention right now.'
    } else {
        $verb = if ($needsAttention -eq 1) { 'requires' } else { 'require' }
        $s += ('{0} {1} your attention.' -f (Get-EmailCountWord -N $needsAttention -Capital), $verb)
    }
    if ($waitingForReply -gt 0) {
        $who = if ($waitingForReply -eq 1) { 'One person is' } else { ('{0} people are' -f (Get-EmailCountWord -N $waitingForReply -Capital)) }
        $s += ('{0} waiting for a response.' -f $who)
    }
    if ($invites.Count -gt 0) {
        $iv = if ($invites.Count -eq 1) { 'One calendar invitation arrived.' } else { ('{0} calendar invitations arrived.' -f (Get-EmailCountWord -N $invites.Count -Capital)) }
        $s += $iv
    }
    if ($carrier.Count -gt 0) {
        $cw = if ($carrier.Count -eq 1) { 'One carrier or underwriting update came in.' } else { ('{0} carrier or underwriting updates came in.' -f (Get-EmailCountWord -N $carrier.Count -Capital)) }
        $s += $cw
    }
    if ($needsAttention -gt 0 -and ($lowPri.Count -gt 0 -or $total -gt ($needsAttention + $invites.Count))) {
        $s += 'Everything else can wait.'
    }

    # -- the few items that actually deserve a look (never the whole inbox) --
    $rank = @{ 'urgent' = 0; 'needs-reply' = 1; 'important-contact' = 1; 'carrier-underwriting' = 2; 'calendar-invite' = 3 }
    $items = @($classified |
        Where-Object { $_.priority -eq 'high' -or $_.category -eq 'calendar-invite' } |
        Sort-Object @{ e = { if ($rank.ContainsKey($_.category)) { $rank[$_.category] } else { 9 } } }, @{ e = { $_.msg.date }; Descending = $true } |
        Select-Object -First 5 |
        ForEach-Object {
            [pscustomobject]@{
                from     = $(if ($_.msg.fromName) { [string]$_.msg.fromName } else { [string]$_.msg.from })
                subject  = $(if ($_.msg.subject) { [string]$_.msg.subject } else { '(no subject)' })
                category = $_.category
                why      = $_.why
                unread   = [bool]$_.msg.unread
                accounts = @($(if (($_.msg.PSObject.Properties.Name -contains 'sourceAccounts') -and $_.msg.sourceAccounts) { $_.msg.sourceAccounts } else { @() }))
            }
        })

    $headline = if ($needsAttention -eq 0) { 'Inbox is calm - nothing needs you right now.' }
    else { ('{0} email{1} need your attention' -f $needsAttention, $(if ($needsAttention -eq 1) { '' } else { 's' })) }

    return [pscustomobject]@{
        total           = $total
        analyzed        = $analyzed
        capped          = [bool]$Capped
        unread          = $unreadCount
        needsAttention  = $needsAttention
        waitingForReply = $waitingForReply
        invitations     = $invites.Count
        carrierUpdates  = $carrier.Count
        importantContacts = $importantC.Count
        urgent          = $urgent.Count
        needsReply      = $needsReply.Count
        lowPriority     = $lowPri.Count
        line            = $line
        sentences       = @($s)
        summaryText     = (@(@($line) + $s) -join ' ')
        headline        = $headline
        attentionItems  = @($items)
    }
}
