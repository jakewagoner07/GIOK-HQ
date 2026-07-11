# =====================================================================
# gohighlevel-provider.ps1  -  Read-ONLY GoHighLevel CRM backend
# ---------------------------------------------------------------------
# Randy the CRM Manager's FIRST tool. This file is a VENDOR-SPECIFIC
# backend + normalizer ONLY. It talks to the HighLevel API v2
# (services.leadconnectorhq.com, Version 2021-07-28) read-only, and maps
# GoHighLevel's data into the vendor-neutral NORMALIZED CRM MODEL. It then
# registers as the generic 'crm' live signal. Randy (core/workforce-
# specialists.ps1) reads ONLY that normalized signal - she never sees
# GoHighLevel. Swap this file for a HubSpot/Salesforce backend and Randy is
# unchanged.
#
# READ ONLY BY CONSTRUCTION: the HTTP helper issues ONLY GET. It never
# creates/updates/deletes a contact, opportunity, task, or appointment, and
# never sends a message. There is NO local CRM mirror - data is fetched on
# demand and never stored.
#
# Auth: a HighLevel Private Integration Token (static bearer), stored ONLY in
# the gitignored providers/crm.config.json. Scopes requested (read-only):
#   contacts.readonly  opportunities.readonly  calendars.readonly
#   calendars/events.readonly  locations.readonly
# The token is NEVER logged, printed, or committed. Diagnostics carry states,
# counts, timing, and error classes only.
#
# Endpoints used (all GET, HighLevel API v2, verified against the official
# docs at marketplace.gohighlevel.com/docs):
#   GET /locations/{locationId}                         (probe + label)
#   GET /opportunities/pipelines?locationId=            (stage identity)
#   GET /opportunities/search?location_id=&status=open  (pipeline + tasks)
#   GET /contacts/?locationId=                          (leads/contacts)
#   GET /calendars/events?locationId=&startTime=&endTime=&calendarId|userId (optional)
# NOTE: opportunities/search uses location_id (underscore); pipelines and
# contacts use locationId (camelCase) - a real HighLevel inconsistency.
# =====================================================================

$ErrorActionPreference = 'Stop'

function Get-CRMConfigPath { return (Join-Path $PSScriptRoot 'crm.config.json') }

function Get-CRMConfig {
    $p = Get-CRMConfigPath
    $token = $null; $locations = @(); $configured = $false
    $apiBase = 'https://services.leadconnectorhq.com'; $version = '2021-07-28'
    $agingLeadHours = 48; $stalledDays = 14; $recentLeadDays = 30
    $uwKeywords = @('underwriting', 'uw', 'in review')
    $apptCalendarIds = @(); $apptUserIds = @()
    if (Test-Path $p) {
        try {
            $c = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($c.token) { $token = [string]$c.token }
            if ($c.apiBase) { $apiBase = ([string]$c.apiBase).TrimEnd('/') }
            if ($c.version) { $version = [string]$c.version }
            if ($c.PSObject.Properties.Name -contains 'locations' -and $c.locations) {
                $locations = @($c.locations | Where-Object { $_ -and $_.id } | ForEach-Object { [pscustomobject]@{ id = [string]$_.id; label = $(if ($_.label) { [string]$_.label } else { [string]$_.id }) } })
            }
            if ($c.PSObject.Properties.Name -contains 'agingLeadHours' -and $c.agingLeadHours) { $agingLeadHours = [int]$c.agingLeadHours }
            if ($c.PSObject.Properties.Name -contains 'stalledOpportunityDays' -and $c.stalledOpportunityDays) { $stalledDays = [int]$c.stalledOpportunityDays }
            if ($c.PSObject.Properties.Name -contains 'recentLeadDays' -and $c.recentLeadDays) { $recentLeadDays = [int]$c.recentLeadDays }
            if ($c.PSObject.Properties.Name -contains 'underwritingStageKeywords' -and $c.underwritingStageKeywords) { $uwKeywords = @($c.underwritingStageKeywords | ForEach-Object { ([string]$_).ToLower() }) }
            if ($c.PSObject.Properties.Name -contains 'appointmentCalendarIds' -and $c.appointmentCalendarIds) { $apptCalendarIds = @($c.appointmentCalendarIds | ForEach-Object { [string]$_ }) }
            if ($c.PSObject.Properties.Name -contains 'appointmentUserIds' -and $c.appointmentUserIds) { $apptUserIds = @($c.appointmentUserIds | ForEach-Object { [string]$_ }) }
        } catch { }
    }
    # a token that is still the placeholder counts as NOT configured
    $realToken = ($token -and ($token -notmatch '^pit-YOUR' ) -and (-not [string]::IsNullOrWhiteSpace($token)))
    $configured = [bool]($realToken -and (@($locations).Count -gt 0))
    return [pscustomobject]@{
        token                  = $token
        configured             = $configured
        apiBase                = $apiBase
        version                = $version
        locations              = @($locations)
        agingLeadHours         = $agingLeadHours
        stalledOpportunityDays = $stalledDays
        recentLeadDays         = $recentLeadDays
        underwritingStageKeywords = @($uwKeywords)
        appointmentCalendarIds = @($apptCalendarIds)
        appointmentUserIds     = @($apptUserIds)
        readOnly               = $true
        backend                = 'gohighlevel'
    }
}

function Write-CRMDiag { param([string]$Level = 'info', [string]$Message = '') if (Get-Command Write-TonyDiag -ErrorAction SilentlyContinue) { Write-TonyDiag -Level $Level -Source 'crm' -Message $Message } }

# ---- read-only HTTP: GET ONLY (structural read-only guarantee) -------
function Invoke-GHLApi {
    param(
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$Path,
        $Query = @{},
        [string]$Method = 'GET'
    )
    if ($Method -ne 'GET') { throw "The CRM provider is read-only; only GET is permitted (attempted $Method)." }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    $qs = ''
    if ($Query -and $Query.Keys.Count -gt 0) {
        $pairs = @()
        foreach ($k in $Query.Keys) {
            $v = $Query[$k]
            if ($null -eq $v -or $v -eq '') { continue }
            $pairs += ('{0}={1}' -f [uri]::EscapeDataString([string]$k), [uri]::EscapeDataString([string]$v))
        }
        if ($pairs.Count -gt 0) { $qs = '?' + ($pairs -join '&') }
    }
    $uri = $BaseUrl + $Path + $qs
    $headers = @{ Authorization = ('Bearer {0}' -f $Token); Version = $Version; Accept = 'application/json' }
    return Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -ErrorAction Stop
}

# Classify an HTTP error into a calm state (no secrets, no bodies).
function Get-GHLErrorState {
    param($Err)
    $state = 'error'; $detail = 'The CRM request failed.'
    if ($Err.Exception.Response -and ($Err.Exception.Response.PSObject.Properties.Name -contains 'StatusCode')) {
        $sc = [int]$Err.Exception.Response.StatusCode
        if ($sc -eq 401) { $state = 'auth-failed'; $detail = 'Authorization failed - check the Private Integration token.' }
        elseif ($sc -eq 403) { $state = 'denied'; $detail = 'Reachable, but this token is missing a required read scope.' }
        elseif ($sc -eq 429) { $state = 'rate-limited'; $detail = 'HighLevel rate limit hit; try again shortly.' }
        elseif ($sc -ge 500) { $state = 'server-error'; $detail = 'HighLevel returned a server error.' }
        else { $state = 'error'; $detail = ('HighLevel returned HTTP {0}.' -f $sc) }
    } elseif ($Err.Exception -is [System.Net.WebException]) { $state = 'network-error'; $detail = 'The network is unavailable.' }
    return [pscustomobject]@{ state = $state; detail = $detail }
}

# ---- vendor helpers: dates + numbers ---------------------------------
function Convert-GHLDate {
    param($Value)
    if ($null -eq $Value -or $Value -eq '') { return $null }
    $s = [string]$Value
    if ($s -match '^\d+$') {
        try {
            $n = [long]$s
            if ($s.Length -ge 13) { return [DateTimeOffset]::FromUnixTimeMilliseconds($n).LocalDateTime }
            else { return [DateTimeOffset]::FromUnixTimeSeconds($n).LocalDateTime }
        } catch { return $null }
    }
    try { return [datetime]::Parse($s, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal).ToLocalTime() } catch { return $null }
}
function ConvertTo-CrmDouble { param($Value) if ($null -eq $Value) { return 0.0 } try { return [double]$Value } catch { return 0.0 } }
function Get-Prop { param($Obj, [string]$Name) if ($Obj -and ($Obj.PSObject.Properties.Name -contains $Name)) { return $Obj.$Name } return $null }

# ---- pipelines: stage identity (id -> name/position) -----------------
function Get-GHLPipelines {
    param([Parameter(Mandatory)]$Cfg, [Parameter(Mandatory)][string]$LocationId)
    $resp = Invoke-GHLApi -Token $Cfg.token -BaseUrl $Cfg.apiBase -Version $Cfg.version -Path '/opportunities/pipelines' -Query @{ locationId = $LocationId }
    $pipelines = @(); $stageIndex = @{}
    foreach ($p in @(Get-Prop $resp 'pipelines')) {
        $stages = @()
        foreach ($s in @(Get-Prop $p 'stages')) {
            $sid = [string](Get-Prop $s 'id'); $sname = [string](Get-Prop $s 'name'); $spos = [int](ConvertTo-CrmDouble (Get-Prop $s 'position'))
            $stages += [pscustomobject]@{ id = $sid; name = $sname; position = $spos }
            if ($sid) { $stageIndex[$sid] = [pscustomobject]@{ name = $sname; position = $spos; pipelineId = [string](Get-Prop $p 'id'); pipelineName = [string](Get-Prop $p 'name') } }
        }
        $pipelines += [pscustomobject]@{ id = [string](Get-Prop $p 'id'); name = [string](Get-Prop $p 'name'); stages = @($stages) }
    }
    return [pscustomobject]@{ pipelines = @($pipelines); stageIndex = $stageIndex }
}

function Test-UnderwritingStage { param([string]$StageName, $Keywords) $n = ([string]$StageName).ToLower(); foreach ($k in @($Keywords)) { if ($k -and $n.Contains([string]$k)) { return $true } } return $false }

# ---- opportunities (+ embedded tasks via getTasks) -------------------
function Get-GHLOpportunities {
    param([Parameter(Mandatory)]$Cfg, [Parameter(Mandatory)][string]$LocationId, $StageIndex = @{}, [string]$LocationLabel = '')
    $opps = @(); $followUps = @(); $seen = @{}; $page = 1; $maxPages = 5; $limit = 100; $capped = $false
    do {
        $resp = Invoke-GHLApi -Token $Cfg.token -BaseUrl $Cfg.apiBase -Version $Cfg.version -Path '/opportunities/search' -Query @{ location_id = $LocationId; status = 'open'; limit = $limit; page = $page; getTasks = 'true' }
        $batch = @(Get-Prop $resp 'opportunities')
        foreach ($o in $batch) {
            $id = [string](Get-Prop $o 'id'); if (-not $id -or $seen.ContainsKey($id)) { continue }; $seen[$id] = $true
            $stageId = [string](Get-Prop $o 'pipelineStageId')
            $stage = if ($stageId -and $StageIndex.ContainsKey($stageId)) { $StageIndex[$stageId] } else { $null }
            $stageName = if ($stage) { $stage.name } else { '' }
            $contactObj = Get-Prop $o 'contact'
            $contactName = if ($contactObj) { [string](Get-Prop $contactObj 'name') } else { '' }
            if (-not $contactName -and $contactObj) { $contactName = (('{0} {1}' -f (Get-Prop $contactObj 'firstName'), (Get-Prop $contactObj 'lastName')).Trim()) }
            $updated = Convert-GHLDate (Get-Prop $o 'updatedAt')
            $lastAction = Convert-GHLDate (Get-Prop $o 'lastActionDate')
            $lastActivity = if ($lastAction) { $lastAction } else { $updated }
            $opps += [pscustomobject]@{
                id            = $id
                title         = [string](Get-Prop $o 'name')
                contactId     = [string](Get-Prop $o 'contactId')
                contactName   = $contactName
                pipelineId    = [string](Get-Prop $o 'pipelineId')
                pipelineName  = if ($stage) { $stage.pipelineName } else { '' }
                stageId       = $stageId
                stageName     = $stageName
                stagePosition = if ($stage) { $stage.position } else { $null }
                status        = [string](Get-Prop $o 'status')
                value         = (ConvertTo-CrmDouble (Get-Prop $o 'monetaryValue'))
                createdAt     = (Convert-GHLDate (Get-Prop $o 'createdAt'))
                updatedAt     = $updated
                lastActivityAt = $lastActivity
                inUnderwriting = (Test-UnderwritingStage -StageName $stageName -Keywords $Cfg.underwritingStageKeywords)
                sourceAccount = $LocationLabel
                sourceId      = $id
            }
            # opportunity-linked tasks (from getTasks=true) -> follow-ups
            foreach ($t in @(Get-Prop $o 'tasks')) {
                $tid = [string](Get-Prop $t 'id'); if (-not $tid -or $seen.ContainsKey('t:' + $tid)) { continue }; $seen['t:' + $tid] = $true
                $followUps += [pscustomobject]@{
                    id            = $tid
                    title         = [string](Get-Prop $t 'title')
                    dueDate       = (Convert-GHLDate (Get-Prop $t 'dueDate'))
                    completed     = [bool](Get-Prop $t 'completed')
                    contactId     = [string](Get-Prop $t 'contactId')
                    opportunityId = $id
                    sourceAccount = $LocationLabel
                    sourceId      = $tid
                }
            }
        }
        $more = ($batch.Count -ge $limit); $page++
        if ($page -gt $maxPages -and $more) { $capped = $true; break }
    } while ($batch.Count -ge $limit)
    return [pscustomobject]@{ opportunities = @($opps); followUps = @($followUps); capped = $capped }
}

# ---- contacts (leads/clients) ----------------------------------------
function Get-GHLContacts {
    param([Parameter(Mandatory)]$Cfg, [Parameter(Mandatory)][string]$LocationId, [string]$LocationLabel = '')
    $contacts = @(); $seen = @{}; $startAfter = $null; $startAfterId = $null; $pages = 0; $maxPages = 5; $limit = 100; $capped = $false
    do {
        $q = @{ locationId = $LocationId; limit = $limit }
        if ($startAfter) { $q['startAfter'] = $startAfter }
        if ($startAfterId) { $q['startAfterId'] = $startAfterId }
        $resp = Invoke-GHLApi -Token $Cfg.token -BaseUrl $Cfg.apiBase -Version $Cfg.version -Path '/contacts/' -Query $q
        $batch = @(Get-Prop $resp 'contacts')
        foreach ($c in $batch) {
            $id = [string](Get-Prop $c 'id'); if (-not $id -or $seen.ContainsKey($id)) { continue }; $seen[$id] = $true
            $name = [string](Get-Prop $c 'contactName'); if (-not $name) { $name = [string](Get-Prop $c 'name') }
            if (-not $name) { $name = (('{0} {1}' -f (Get-Prop $c 'firstName'), (Get-Prop $c 'lastName')).Trim()) }
            if (-not $name) { $name = [string](Get-Prop $c 'email') }
            $contacts += [pscustomobject]@{
                id            = $id
                name          = $name
                type          = 'contact'
                createdAt     = (Convert-GHLDate (Get-Prop $c 'dateAdded'))
                lastUpdatedAt = (Convert-GHLDate (Get-Prop $c 'dateUpdated'))
                tags          = @(Get-Prop $c 'tags')
                sourceAccount = $LocationLabel
                sourceId      = $id
            }
        }
        $meta = Get-Prop $resp 'meta'
        $startAfter = if ($meta) { Get-Prop $meta 'startAfter' } else { $null }
        $startAfterId = if ($meta) { Get-Prop $meta 'startAfterId' } else { $null }
        $pages++
        $more = (($batch.Count -ge $limit) -and $startAfterId)
        if ($pages -ge $maxPages -and $more) { $capped = $true; break }
    } while ((($batch.Count -ge $limit)) -and $startAfterId)
    return [pscustomobject]@{ contacts = @($contacts); capped = $capped }
}

# ---- appointments (optional; only when a calendar/user id is given) --
function Get-GHLAppointments {
    param([Parameter(Mandatory)]$Cfg, [Parameter(Mandatory)][string]$LocationId, [datetime]$Now, [string]$LocationLabel = '')
    $ids = @($Cfg.appointmentCalendarIds); $userIds = @($Cfg.appointmentUserIds)
    if ($ids.Count -eq 0 -and $userIds.Count -eq 0) {
        return [pscustomobject]@{ available = $false; reason = 'No calendarId/userId configured (HighLevel requires one to read events).'; items = @() }
    }
    $start = [DateTimeOffset]$Now.ToUniversalTime(); $end = [DateTimeOffset]$Now.ToUniversalTime().AddDays(14)
    $items = @(); $seen = @{}
    $targets = @(); foreach ($cid in $ids) { $targets += @{ key = 'calendarId'; val = $cid } }; foreach ($uid in $userIds) { $targets += @{ key = 'userId'; val = $uid } }
    foreach ($tg in $targets) {
        $q = @{ locationId = $LocationId; startTime = $start.ToUnixTimeMilliseconds(); endTime = $end.ToUnixTimeMilliseconds() }
        $q[$tg.key] = $tg.val
        $resp = Invoke-GHLApi -Token $Cfg.token -BaseUrl $Cfg.apiBase -Version $Cfg.version -Path '/calendars/events' -Query $q
        foreach ($e in @(Get-Prop $resp 'events')) {
            $id = [string](Get-Prop $e 'id'); if (-not $id -or $seen.ContainsKey($id)) { continue }; $seen[$id] = $true
            $items += [pscustomobject]@{
                id = $id; title = [string](Get-Prop $e 'title'); contactId = [string](Get-Prop $e 'contactId')
                start = (Convert-GHLDate (Get-Prop $e 'startTime')); end = (Convert-GHLDate (Get-Prop $e 'endTime'))
                status = [string](Get-Prop $e 'appointmentStatus'); sourceAccount = $LocationLabel; sourceId = $id
            }
        }
    }
    return [pscustomobject]@{ available = $true; reason = ''; items = @($items) }
}

# ---- one location, read-only; errors captured so others survive ------
function Get-GHLLocationData {
    param([Parameter(Mandatory)]$Cfg, [Parameter(Mandatory)]$Location, [datetime]$Now)
    $locId = $Location.id; $label = $Location.label
    try {
        $pl = Get-GHLPipelines -Cfg $Cfg -LocationId $locId
        $op = Get-GHLOpportunities -Cfg $Cfg -LocationId $locId -StageIndex $pl.stageIndex -LocationLabel $label
        $co = Get-GHLContacts -Cfg $Cfg -LocationId $locId -LocationLabel $label
        $ap = Get-GHLAppointments -Cfg $Cfg -LocationId $locId -Now $Now -LocationLabel $label
        Write-CRMDiag -Level 'info' -Message ('CRM location ok: {0} opps, {1} contacts, {2} follow-ups.' -f @($op.opportunities).Count, @($co.contacts).Count, @($op.followUps).Count)
        return [pscustomobject]@{
            ok = $true; id = $locId; label = $label; state = 'connected'; detail = ('Live (read-only) from {0}.' -f $label)
            pipelines = @($pl.pipelines); opportunities = @($op.opportunities); followUps = @($op.followUps); contacts = @($co.contacts)
            appointments = $ap; oppCapped = [bool]$op.capped; contactCapped = [bool]$co.capped
        }
    } catch {
        $cls = Get-GHLErrorState -Err $_
        Write-CRMDiag -Level 'error' -Message ('CRM location error ({0}) for one location.' -f $cls.state)
        return [pscustomobject]@{ ok = $false; id = $locId; label = $label; state = $cls.state; detail = $cls.detail; pipelines = @(); opportunities = @(); followUps = @(); contacts = @(); appointments = [pscustomobject]@{ available = $false; reason = $cls.detail; items = @() }; oppCapped = $false; contactCapped = $false }
    }
}

# ---- THE contract: one normalized CRM read across ALL locations ------
function Get-CRM {
    param([datetime]$Now = (Get-Date))
    $cfg = Get-CRMConfig
    $nowStr = $Now.ToString('yyyy-MM-dd HH:mm:ss')
    $fail = {
        param($state, $detail)
        [pscustomobject]@{ provider = 'crm'; backend = 'gohighlevel'; ok = $false; errorState = $state
            status = [pscustomobject]@{ state = $state; detail = $detail; lastRefresh = $null; lastError = $detail }
            timestamp = $nowStr; locations = @(); locationCount = 0
            contacts = [pscustomobject]@{ available = $false; items = @(); total = 0; capped = $false }
            opportunities = [pscustomobject]@{ available = $false; items = @(); total = 0; capped = $false }
            pipelines = [pscustomobject]@{ available = $false; items = @() }
            followUps = [pscustomobject]@{ available = $false; items = @(); source = 'opportunity-linked-tasks' }
            appointments = [pscustomobject]@{ available = $false; reason = 'Not connected.'; items = @() }
            requirements = [pscustomobject]@{ available = $false; reason = 'Not exposed by the GoHighLevel standard API.'; items = @() }
            policies = [pscustomobject]@{ available = $false; reason = 'Not exposed by the GoHighLevel standard API.'; items = @() }
            renewals = [pscustomobject]@{ available = $false; reason = 'Not exposed by the GoHighLevel standard API.'; items = @() }
            underwriting = [pscustomobject]@{ available = $false; source = 'pipeline-stage-name'; items = @() }
            summary = $null }
    }
    if (-not $cfg.configured) { return (& $fail 'not-configured' 'The CRM is not connected yet. Add a Private Integration token and location to crm.config.json.') }

    $allOpps = @(); $allContacts = @(); $allFollowUps = @(); $allPipelines = @(); $allAppts = @()
    $locInfos = @(); $anyOk = $false; $oppCapped = $false; $contactCapped = $false; $apptAvailable = $false; $apptReason = 'No calendarId/userId configured.'
    $firstBadState = $null; $firstBadDetail = $null
    foreach ($loc in $cfg.locations) {
        $d = Get-GHLLocationData -Cfg $cfg -Location $loc -Now $Now
        $locInfos += [pscustomobject]@{ id = $d.id; label = $d.label; state = $d.state; detail = $d.detail; opportunities = @($d.opportunities).Count; contacts = @($d.contacts).Count }
        if ($d.ok) {
            $anyOk = $true
            $allOpps += @($d.opportunities); $allContacts += @($d.contacts); $allFollowUps += @($d.followUps); $allPipelines += @($d.pipelines)
            if ($d.appointments.available) { $apptAvailable = $true; $allAppts += @($d.appointments.items) } else { $apptReason = $d.appointments.reason }
            $oppCapped = $oppCapped -or $d.oppCapped; $contactCapped = $contactCapped -or $d.contactCapped
        } elseif (-not $firstBadState) { $firstBadState = $d.state; $firstBadDetail = $d.detail }
    }
    if (-not $anyOk) { return (& $fail $firstBadState $firstBadDetail) }

    # dedupe across locations by id (safety against overlapping reads)
    $allOpps = @($allOpps | Group-Object -Property id | ForEach-Object { $_.Group[0] })
    $allContacts = @($allContacts | Group-Object -Property id | ForEach-Object { $_.Group[0] })
    $allFollowUps = @($allFollowUps | Group-Object -Property id | ForEach-Object { $_.Group[0] })

    $underwriting = @($allOpps | Where-Object { $_.inUnderwriting })

    $crm = [pscustomobject]@{
        provider = 'crm'; backend = 'gohighlevel'; ok = $true; errorState = $null
        status = [pscustomobject]@{ state = 'connected'; detail = ('Live (read-only) from GoHighLevel across {0} location(s).' -f @($locInfos | Where-Object { $_.state -eq 'connected' }).Count); lastRefresh = $nowStr; lastError = $(if ($firstBadDetail) { $firstBadDetail } else { $null }) }
        timestamp = $nowStr; locations = @($locInfos); locationCount = @($locInfos).Count
        contacts = [pscustomobject]@{ available = $true; items = @($allContacts); total = @($allContacts).Count; capped = $contactCapped }
        opportunities = [pscustomobject]@{ available = $true; items = @($allOpps); total = @($allOpps).Count; capped = $oppCapped }
        pipelines = [pscustomobject]@{ available = $true; items = @($allPipelines) }
        followUps = [pscustomobject]@{ available = $true; items = @($allFollowUps); source = 'opportunity-linked-tasks' }
        appointments = [pscustomobject]@{ available = $apptAvailable; reason = $(if ($apptAvailable) { '' } else { $apptReason }); items = @($allAppts) }
        requirements = [pscustomobject]@{ available = $false; reason = 'Not exposed by the GoHighLevel standard API (no requirements object).'; items = @() }
        policies = [pscustomobject]@{ available = $false; reason = 'Not exposed by the GoHighLevel standard API (insurance policies are not native objects).'; items = @() }
        renewals = [pscustomobject]@{ available = $false; reason = 'Not exposed by the GoHighLevel standard API (no renewal object).'; items = @() }
        underwriting = [pscustomobject]@{ available = $true; source = 'pipeline-stage-name'; items = @($underwriting) }
    }
    if (Get-Command Get-CRMSummary -ErrorAction SilentlyContinue) {
        $crm | Add-Member -NotePropertyName summary -NotePropertyValue (Get-CRMSummary -Crm $crm -Now $Now -Config $cfg) -Force
    } else {
        $crm | Add-Member -NotePropertyName summary -NotePropertyValue $null -Force
    }
    return $crm
}

# ---- status for Settings (-Live probes one location, read-only) ------
function Get-CRMStatus {
    param([switch]$Live)
    $cfg = Get-CRMConfig
    if (-not $cfg.configured) {
        return [pscustomobject]@{ name = 'CRM (GoHighLevel)'; state = 'not-configured'; detail = 'Not connected. Add a HighLevel Private Integration token and location id to crm.config.json.'; backend = 'gohighlevel'; locations = @(); readOnly = $true; lastRefresh = $null; lastError = $null }
    }
    if (-not $Live) {
        $locs = @($cfg.locations | ForEach-Object { [pscustomobject]@{ id = $_.id; label = $_.label; state = 'configured'; detail = 'Configured (read-only). Run Test Connection to confirm live access.' } })
        return [pscustomobject]@{ name = 'CRM (GoHighLevel)'; state = 'configured'; detail = ('{0} location(s) configured (read-only). Run Test Connection to confirm live access.' -f @($cfg.locations).Count); backend = 'gohighlevel'; locations = $locs; readOnly = $true; lastRefresh = $null; lastError = $null }
    }
    # live probe: GET each location by id (cheap, read-only)
    $locs = @(); $anyOk = $false; $firstErr = $null
    foreach ($loc in $cfg.locations) {
        try {
            $resp = Invoke-GHLApi -Token $cfg.token -BaseUrl $cfg.apiBase -Version $cfg.version -Path ('/locations/{0}' -f $loc.id)
            $name = ''; $lo = Get-Prop $resp 'location'; if ($lo) { $name = [string](Get-Prop $lo 'name') }
            $locs += [pscustomobject]@{ id = $loc.id; label = $(if ($name) { $name } else { $loc.label }); state = 'connected'; detail = 'Connected (read-only).' }
            $anyOk = $true
        } catch {
            $cls = Get-GHLErrorState -Err $_
            $locs += [pscustomobject]@{ id = $loc.id; label = $loc.label; state = $cls.state; detail = $cls.detail }
            if (-not $firstErr) { $firstErr = $cls.detail }
        }
    }
    $state = if ($anyOk -and -not $firstErr) { 'connected' } elseif ($anyOk) { 'degraded' } else { 'error' }
    $detail = if ($state -eq 'connected') { ('{0} location(s) connected (read-only).' -f @($locs).Count) } elseif ($state -eq 'degraded') { 'Some locations connected; one or more failed.' } else { $firstErr }
    return [pscustomobject]@{ name = 'CRM (GoHighLevel)'; state = $state; detail = $detail; backend = 'gohighlevel'; locations = @($locs); readOnly = $true; lastRefresh = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); lastError = $firstErr }
}

# Is a question about the CRM / book of business? Tony Brain uses this to route.
function Test-CRMRelevant {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return [bool]($Text -match '(?i)\b(crm|pipeline|lead|leads|prospect|opportunit|renewal|underwriting|follow.?up|policy|policies|book of business|revenue|deal|deals|gohighlevel|ghl|client(s)?)\b')
}

# ---- register as the generic 'crm' live signal (backend = gohighlevel)
if (Get-Command Register-LiveProvider -ErrorAction SilentlyContinue) {
    Register-LiveProvider -Provider ([pscustomobject]@{
            name        = 'crm'
            description = 'Read-only CRM across one or more locations. Backend = GoHighLevel (HighLevel API v2, read-only). Normalized to the vendor-neutral CRM model and read by Randy the CRM Manager.'
            relevant    = { param($text) Test-CRMRelevant $text }
            query       = { param($opts) Get-CRM }
            status      = { param($live) Get-CRMStatus -Live:([bool]$live) }
        })
}
