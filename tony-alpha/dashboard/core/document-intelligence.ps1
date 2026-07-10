# =====================================================================
# document-intelligence.ps1  —  Tony reads documents for MEANING
# ---------------------------------------------------------------------
# Tony does not merely extract text. He reads a document the way an
# executive chief of staff would: he finds the meaningful information
# (goals, tasks, ideas, deadlines, people, risks, decisions) and
# connects each finding back to the user's operating system - Identity,
# Vision, Goals, Mission, Core Values, Action Items, Capture, Audits.
#
# NOTHING is ever written into GIOK automatically. The pipeline only
# READS and PROPOSES. Every suggestion carries Accept / Reject / Edit,
# and a write happens solely when the user explicitly approves it
# (Approve-DocumentSuggestion). No cloud, no Gmail, no Calendar, no GHL.
#
# The pipeline:
#   1. Read document        (Read-Document)
#   2. Extract text         (per-type extractors)
#   3. Identify meaning     (Get-DocumentEntities)
#   4. Compare to the OS     (Compare-DocumentFindings)
#   5. Generate suggestions (built into the comparison)
#   6. Present a Review      (New-DocumentReview -> Approve/Reject/Edit)
# and a chief-of-staff Document Summary (Invoke-DocumentIntelligence).
# =====================================================================

$ErrorActionPreference = 'Stop'

# The document types Tony understands today, and the ones coming next.
function Get-DocumentSupportedTypes {
    return [pscustomobject]@{
        supported = @('pdf', 'docx', 'txt', 'md', 'markdown')
        future    = @('image', 'email', 'transcript')
    }
}

function Get-DocumentType {
    param([string]$Path)
    $ext = ([System.IO.Path]::GetExtension([string]$Path)).TrimStart('.').ToLower()
    if ($ext -eq 'markdown') { $ext = 'md' }
    return $ext
}

# ------------------------------------------------------------------ #
# STEP 1 + 2 : Read the document and extract its text.
# ------------------------------------------------------------------ #

# DOCX = a zip; the text lives in word/document.xml. Pull it out and
# strip the XML down to readable prose. Pure .NET, no Word, no cloud.
function Get-DocxText {
    param([string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $zip = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        $entry = $zip.Entries | Where-Object { $_.FullName -eq 'word/document.xml' } | Select-Object -First 1
        if (-not $entry) { return '' }
        $reader = New-Object System.IO.StreamReader($entry.Open())
        $xml = $reader.ReadToEnd(); $reader.Close()
        # Paragraph and line breaks become newlines, then drop every tag.
        $xml = $xml -replace '</w:p>', "`n"
        $xml = $xml -replace '<w:br[^>]*/>', "`n"
        $xml = $xml -replace '<w:tab[^>]*/>', "`t"
        $txt = $xml -replace '<[^>]+>', ''
        $txt = [System.Net.WebUtility]::HtmlDecode($txt)
        return $txt
    } finally { if ($zip) { $zip.Dispose() } }
}

# PDF text extraction WITHOUT a third-party library is best-effort:
# uncompressed text operators are read directly; FlateDecode streams
# are inflated when possible. When a PDF can't be decoded here, Tony
# says so honestly rather than guessing - a future extractor plugs in
# without changing the workflow.
function Get-PdfText {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $latin = [System.Text.Encoding]::GetEncoding(28591)   # Latin-1: byte-accurate
    $raw = $latin.GetString($bytes)
    $sb = New-Object System.Text.StringBuilder

    # Find every stream ... endstream and try to inflate it (zlib -> raw DEFLATE).
    $streamRegex = [regex]'stream\r?\n'
    $decoded = New-Object System.Text.StringBuilder
    $searchStart = 0
    while ($true) {
        $m = $streamRegex.Match($raw, $searchStart)
        if (-not $m.Success) { break }
        $dataStart = $m.Index + $m.Length
        $end = $raw.IndexOf('endstream', $dataStart)
        if ($end -lt 0) { break }
        $searchStart = $end + 9
        $len = $end - $dataStart
        if ($len -le 2) { continue }
        try {
            $chunk = $latin.GetBytes($raw.Substring($dataStart, $len))
            # zlib header is 2 bytes; DeflateStream wants raw DEFLATE.
            $ms = New-Object System.IO.MemoryStream(@(, $chunk[2..($chunk.Length - 1)]))
            $ds = New-Object System.IO.Compression.DeflateStream($ms, [System.IO.Compression.CompressionMode]::Decompress)
            $sr = New-Object System.IO.StreamReader($ds, $latin)
            [void]$decoded.Append($sr.ReadToEnd())
            [void]$decoded.Append("`n")
            $sr.Close()
        } catch { }
    }

    # Pull the drawn text out of content streams: (text)Tj and [..]TJ.
    $content = $decoded.ToString()
    if ([string]::IsNullOrWhiteSpace($content)) { $content = $raw }  # uncompressed fallback
    $tj = [regex]::Matches($content, '\(((?:\\.|[^\\()])*)\)\s*Tj')
    foreach ($t in $tj) { [void]$sb.Append((_UnescapePdf $t.Groups[1].Value)); [void]$sb.Append(' ') }
    $tjArr = [regex]::Matches($content, '\[((?:[^\[\]]|\\.)*)\]\s*TJ')
    foreach ($a in $tjArr) {
        $parts = [regex]::Matches($a.Groups[1].Value, '\(((?:\\.|[^\\()])*)\)')
        foreach ($p in $parts) { [void]$sb.Append((_UnescapePdf $p.Groups[1].Value)) }
        [void]$sb.Append(' ')
    }
    return $sb.ToString()
}

function _UnescapePdf {
    param([string]$S)
    $S = $S -replace '\\\(', '(' -replace '\\\)', ')' -replace '\\\\', '\'
    $S = $S -replace '\\n', ' ' -replace '\\r', ' ' -replace '\\t', ' '
    return $S
}

# The single entry point for reading a document. Never throws to the
# caller: returns { path, type, text, ok, note }.
function Read-Document {
    param([Parameter(Mandatory)][string]$Path)
    $type = Get-DocumentType $Path
    $result = [pscustomobject]@{ path = $Path; type = $type; text = ''; ok = $false; note = '' }
    if (-not (Test-Path $Path)) { $result.note = 'File not found.'; return $result }
    $supported = (Get-DocumentSupportedTypes).supported
    if ($type -notin $supported) {
        $result.note = "Unsupported type '.$type'. Supported: $($supported -join ', '). Coming later: images, email, transcripts."
        return $result
    }
    try {
        switch ($type) {
            'txt'  { $result.text = (Get-Content -Path $Path -Raw -Encoding UTF8) }
            'md'   { $result.text = (Get-Content -Path $Path -Raw -Encoding UTF8) }
            'docx' { $result.text = (Get-DocxText $Path) }
            'pdf'  { $result.text = (Get-PdfText $Path) }
        }
        if ([string]::IsNullOrWhiteSpace($result.text)) {
            $result.ok = $false
            if ($type -eq 'pdf') { $result.note = 'This PDF stores its text in a form Tony cannot decode yet (scanned or heavily compressed). A future extractor will handle it - the review workflow stays the same.' }
            else { $result.note = 'The document appears to be empty.' }
        } else {
            $result.ok = $true
        }
    } catch {
        $result.note = "Could not read the document: $($_.Exception.Message)"
    }
    return $result
}

# ------------------------------------------------------------------ #
# STEP 3 : Identify meaning - not text.
# Heuristic today (transparent, testable); a future model informs the
# same categories without changing anything downstream.
# ------------------------------------------------------------------ #

function _DocLines { param([string]$Text) return @($Text -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

function _MatchLines {
    param([string[]]$Lines, [string]$Pattern, [int]$Max = 6)
    $out = @()
    foreach ($ln in $Lines) {
        if ($ln -match $Pattern) { $out += ($ln -replace '^\s*[-*+>\d\.\)\]\[\(\s]+', '').Trim() }
        if ($out.Count -ge $Max) { break }
    }
    return @($out | Where-Object { $_.Length -gt 2 } | Select-Object -Unique)
}

# The full set of things Tony looks for in a document.
function Get-DocumentEntities {
    param([Parameter(Mandatory)][string]$Text)
    $lines = _DocLines $Text

    $goals    = _MatchLines $lines '(?i)\b(goal|objective|target|aim to|want to achieve|aspire|by end of (year|quarter))\b'
    $projects = _MatchLines $lines '(?i)\b(project|initiative|rollout|launch|build out|program)\b'
    $actions  = _MatchLines $lines '(?i)(^\s*(?:[-*+]\s*)?\[[ x]\]|^\s*(?:[-*+]\s*)?(todo|action item|action|task|next step)\b[:\-]|^\s*(?:[-*+]\s*)?(call|email|send|prepare|schedule|follow up|review|draft|buy|book|finish|complete|fix|update)\b)'
    $ideas    = _MatchLines $lines '(?i)\b(idea|what if|consider|maybe we|we could|opportunity|brainstorm|concept)\b'
    $risks    = _MatchLines $lines '(?i)\b(risk|concern|blocker|issue|problem|threat|challenge|worried)\b'
    $decisions= _MatchLines $lines '(?i)\b(decided|decision|we will|agreed to|going with|chose to|resolved to)\b'
    $meetings = _MatchLines $lines '(?i)\b(meeting|call with|sync|1:1|one on one|standup|kickoff|review with)\b'
    $questions= @($lines | Where-Object { $_ -match '\?\s*$' } | Select-Object -First 8 -Unique)

    # Entities via regex over the whole text (deduped, capped).
    $dates = @()
    $dates += [regex]::Matches($Text, '\b\d{4}-\d{2}-\d{2}\b') | ForEach-Object { $_.Value }
    $dates += [regex]::Matches($Text, '(?i)\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2}(?:,?\s+\d{4})?\b') | ForEach-Object { $_.Value }
    $dates += [regex]::Matches($Text, '\b\d{1,2}/\d{1,2}/\d{2,4}\b') | ForEach-Object { $_.Value }
    $dates = @($dates | Select-Object -Unique -First 10)

    $deadlines = _MatchLines $lines '(?i)\b(due|deadline|by (mon|tue|wed|thu|fri|the|end)|no later than|deliver by|eod|eow)\b' 8

    # People: "Firstname Lastname" pairs (heuristic). First catch names
    # that follow an action/relation verb ("call Sarah Johnson") - the
    # greedy pair match would otherwise swallow the verb and lose the
    # name. Then add generic pairs, rejecting verb/heading leads and
    # company-suffix tails (those are actions, headings, or orgs).
    $notNameLead = '(?i)^(Call|Email|Send|Prepare|Schedule|Follow|Review|Draft|Buy|Book|Finish|Complete|Fix|Update|Goal|Action|Growth|Plan|Meeting|Idea|Risk|Decided|Decision|Should|Todo|Next|Open|Key|Executive|Annual|Core|Project|Suggested|Quarterly|Weekly|Monthly)\b'
    $notNameTail = '(?i)\b(Insurance|Agency|Group|Company|Corp|Corporation|Inc|Llc|Partners|Plan|Items|Item|Program|Team|Deck|Portal)$'
    $people = @()
    foreach ($nm in [regex]::Matches($Text, '\b(?i:call|email|send|with|for|met|meeting with|contact|ask|tell)\s+([A-Z][a-z]+\s+[A-Z][a-z]+)\b')) {
        $val = $nm.Groups[1].Value
        if ($val -notmatch $notNameTail) { $people += $val }
    }
    $people += @([regex]::Matches($Text, '\b([A-Z][a-z]+)\s+([A-Z][a-z]+)\b') | ForEach-Object { $_.Value } |
        Where-Object { $_ -notmatch $notNameLead -and $_ -notmatch $notNameTail })
    $people = @($people | Select-Object -Unique -First 10)

    # Companies: name followed by a corporate suffix.
    $companies = @([regex]::Matches($Text, '\b([A-Z][A-Za-z0-9&\.\-]+(?:\s+[A-Z][A-Za-z0-9&\.\-]+)*)\s+(Inc|LLC|L\.L\.C\.|Corp|Corporation|Company|Co|Agency|Group|Partners|Insurance)\b') | ForEach-Object { $_.Value } | Select-Object -Unique -First 10)

    return [pscustomobject]@{
        goals      = @($goals)
        projects   = @($projects)
        actionItems= @($actions)
        ideas      = @($ideas)
        deadlines  = @($deadlines)
        dates      = @($dates)
        people     = @($people)
        companies  = @($companies)
        meetings   = @($meetings)
        risks      = @($risks)
        decisions  = @($decisions)
        questions  = @($questions)
    }
}

# ------------------------------------------------------------------ #
# STEP 4 + 5 : Compare findings to the user's OS and generate
# suggestions. Read-only: gathers context via existing accessors,
# never writes.
# ------------------------------------------------------------------ #

function _NormalizeText { param([string]$S) return (([string]$S).ToLower() -replace '[^a-z0-9 ]', ' ' -replace '\s+', ' ').Trim() }

# Cheap keyword-overlap similarity (0..1). No AI; good enough to say
# "this already exists" vs "this is new."
function _SimilarityScore {
    param([string]$A, [string]$B)
    $na = _NormalizeText $A; $nb = _NormalizeText $B
    if (-not $na -or -not $nb) { return 0.0 }
    $stop = @('the', 'and', 'for', 'with', 'this', 'that', 'from', 'you', 'your', 'our', 'are', 'was', 'will', 'a', 'to', 'of', 'in', 'on', 'is', 'it')
    $wa = @($na -split ' ' | Where-Object { $_.Length -gt 2 -and $_ -notin $stop })
    $wb = @($nb -split ' ' | Where-Object { $_.Length -gt 2 -and $_ -notin $stop })
    if ($wa.Count -eq 0 -or $wb.Count -eq 0) { return 0.0 }
    $common = @($wa | Where-Object { $_ -in $wb } | Select-Object -Unique)
    $denom = [math]::Min($wa.Count, $wb.Count)
    return [math]::Round($common.Count / [double]$denom, 2)
}

$script:DocSuggestionSeq = 0
function New-DocumentSuggestion {
    param([string]$Type, [string]$Finding, [string]$Comparison, [string]$ProposedAction, [string]$Category = '', [bool]$Editable = $true)
    $script:DocSuggestionSeq++
    return [pscustomobject]@{
        id             = ('DS-{0:000}' -f $script:DocSuggestionSeq)
        type           = $Type            # goal | action-item | idea | project | question | conflict | info
        finding        = $Finding
        comparison     = $Comparison       # Tony's read: how it connects to the OS
        proposedAction = $ProposedAction
        category       = $Category
        editable       = $Editable
        status         = 'pending'         # pending | accepted | rejected | edited
        applied        = $false
    }
}

# Gather the operating-system context a chief of staff needs. All reads.
function Get-DocumentReviewContext {
    $ctx = [pscustomobject]@{
        identity = $null; vision = $null; goals = @(); mission = $null; values = @()
        annualTheme = $null; nonNegotiables = @(); actionItems = @(); capture = @(); audits = @()
    }
    if (Get-Command Get-IdentityOverview     -ErrorAction SilentlyContinue) { try { $ctx.identity = Get-IdentityOverview } catch { } }
    if (Get-Command Get-IdentityVision       -ErrorAction SilentlyContinue) { try { $ctx.vision = Get-IdentityVision } catch { } }
    if (Get-Command Get-IdentityGoals        -ErrorAction SilentlyContinue) { try { $g = Get-IdentityGoals; if ($g) { $ctx.goals = @($g.goals) } } catch { } }
    if (Get-Command Get-IdentityMission      -ErrorAction SilentlyContinue) { try { $ctx.mission = Get-IdentityMission } catch { } }
    if (Get-Command Get-IdentityValues       -ErrorAction SilentlyContinue) { try { $v = Get-IdentityValues; if ($v) { $ctx.values = @($v.values) } } catch { } }
    if (Get-Command Get-IdentityAnnualTheme  -ErrorAction SilentlyContinue) { try { $ctx.annualTheme = Get-IdentityAnnualTheme } catch { } }
    if (Get-Command Get-NonNegotiableDefs    -ErrorAction SilentlyContinue) { try { $ctx.nonNegotiables = @(Get-NonNegotiableDefs) } catch { } }
    if (Get-Command Get-ActionItemsData      -ErrorAction SilentlyContinue) { try { $a = Get-ActionItemsData; if ($a) { $ctx.actionItems = @($a.items) } } catch { } }
    if (Get-Command Get-CaptureData          -ErrorAction SilentlyContinue) { try { $c = Get-CaptureData; if ($c) { $ctx.capture = @($c.items) } } catch { } }
    return $ctx
}

# Compare each finding to the OS and produce suggestions (Step 5).
function Compare-DocumentFindings {
    param([Parameter(Mandatory)] $Entities, $Context)
    if (-not $Context) { $Context = Get-DocumentReviewContext }
    $suggestions = @()
    $conflicts = @()

    $existingGoals   = @($Context.goals | ForEach-Object { if ($_.title) { $_.title } else { [string]$_ } })
    $existingActions = @($Context.actionItems | Where-Object { -not $_.archived })
    $existingIdeas   = @($Context.capture | ForEach-Object { $_.text })
    $themeText = if ($Context.annualTheme) { "$($Context.annualTheme.theme) $($Context.annualTheme.description)" } else { '' }

    # Goals: exist already, or brand new?
    foreach ($g in @($Entities.goals)) {
        $best = 0.0; foreach ($eg in $existingGoals) { $s = _SimilarityScore $g $eg; if ($s -gt $best) { $best = $s } }
        if ($best -ge 0.5) {
            $suggestions += New-DocumentSuggestion 'goal' $g 'This goal appears to already exist in your Identity - no need to add it twice.' 'Skip (already tracked)' '' $false
        } else {
            $suggestions += New-DocumentSuggestion 'goal' $g 'This goal does not exist yet in your Identity.' 'Add to Identity > Goals'
        }
    }

    # Action items: match an existing AI-### or propose a new one.
    foreach ($a in @($Entities.actionItems)) {
        $match = $null; $best = 0.0
        foreach ($ea in $existingActions) { $s = _SimilarityScore $a $ea.title; if ($s -gt $best) { $best = $s; $match = $ea } }
        if ($match -and $best -ge 0.5) {
            $suggestions += New-DocumentSuggestion 'action-item' $a "This action item matches $($match.id) ('$($match.title)') - already on your list." 'Skip (matches existing)' '' $false
        } else {
            $suggestions += New-DocumentSuggestion 'action-item' $a 'New action item, not currently on your list.' 'Add to Action Items'
        }
    }

    # Ideas: seen before in Capture?
    foreach ($idea in @($Entities.ideas)) {
        $seen = $false
        foreach ($ei in $existingIdeas) { if ((_SimilarityScore $idea $ei) -ge 0.5) { $seen = $true; break } }
        if ($seen) {
            $suggestions += New-DocumentSuggestion 'idea' $idea 'You captured this same idea before - it keeps coming up, which may mean it matters.' 'Skip (already captured)' 'Idea' $false
        } else {
            $suggestions += New-DocumentSuggestion 'idea' $idea 'A new idea worth keeping.' 'Save to Capture' 'Idea'
        }
    }

    # Projects: exist or new (compared against goals as the nearest signal).
    foreach ($p in @($Entities.projects)) {
        $best = 0.0; foreach ($eg in $existingGoals) { $s = _SimilarityScore $p $eg; if ($s -gt $best) { $best = $s } }
        if ($best -ge 0.5) {
            $suggestions += New-DocumentSuggestion 'project' $p 'This project appears to already exist in your world.' 'Skip (already exists)' '' $false
        } else {
            $suggestions += New-DocumentSuggestion 'project' $p 'A project referenced here that GIOK is not tracking yet.' 'Save to Capture for triage' 'Business'
        }
    }

    # Questions the document raises -> capture for Tony to help answer.
    foreach ($qn in @($Entities.questions)) {
        $suggestions += New-DocumentSuggestion 'question' $qn 'An open question this document raises.' 'Save to Capture' 'Note'
    }

    # Conflicts: does a finding clash with the Annual Theme?
    if ($themeText.Trim()) {
        $themeWords = @((_NormalizeText $themeText) -split ' ' | Where-Object { $_.Length -gt 3 } | Select-Object -Unique)
        $negative = @('cut', 'drop', 'abandon', 'stop', 'pause', 'delay', 'reduce', 'less', 'avoid', 'skip')
        foreach ($d in (@($Entities.decisions) + @($Entities.risks))) {
            $nd = _NormalizeText $d
            $touchesTheme = $false; foreach ($tw in $themeWords) { if ($nd -match "\b$tw\b") { $touchesTheme = $true; break } }
            $isNegative = $false; foreach ($neg in $negative) { if ($nd -match "\b$neg\b") { $isNegative = $true; break } }
            if ($touchesTheme -and $isNegative) {
                $c = "This document may conflict with your Annual Theme ('$($Context.annualTheme.theme)') - it points away from what you said this year is about."
                $conflicts += $c
                $suggestions += New-DocumentSuggestion 'conflict' $d $c 'Review against your Annual Theme before acting' '' $false
            }
        }
    }

    return [pscustomobject]@{ suggestions = @($suggestions); conflicts = @($conflicts) }
}

# ------------------------------------------------------------------ #
# STEP 6 : The Review model. Nothing is saved automatically; every
# suggestion carries Accept / Reject / Edit. A write happens only on an
# explicit Approve call.
# ------------------------------------------------------------------ #

function New-DocumentReview {
    param([Parameter(Mandatory)] $Suggestions, [string]$Source = '')
    return [pscustomobject]@{
        source      = $Source
        createdAt   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        suggestions = @($Suggestions)
        actions     = @('Accept', 'Reject', 'Edit')   # what the user may do with each suggestion
        note        = 'Nothing is saved until you approve it. Accept writes to GIOK; Reject discards; Edit changes the text first.'
    }
}

# Edit a suggestion's text before approving it. Returns the suggestion.
function Edit-DocumentSuggestion {
    param([Parameter(Mandatory)] $Suggestion, [Parameter(Mandatory)][string]$NewText)
    if (-not $Suggestion.editable) { return $Suggestion }
    $Suggestion.finding = $NewText.Trim()
    $Suggestion.status = 'edited'
    return $Suggestion
}

# Reject a suggestion. Nothing is written. Returns the suggestion.
function Reject-DocumentSuggestion {
    param([Parameter(Mandatory)] $Suggestion)
    $Suggestion.status = 'rejected'
    return $Suggestion
}

# Accept a suggestion - THE ONLY PLACE A DOCUMENT CAUSES A WRITE, and
# only when the user explicitly calls it. Routes to the right store by
# type. Returns a small result describing what happened.
function Approve-DocumentSuggestion {
    param([Parameter(Mandatory)] $Suggestion)
    $result = [pscustomobject]@{ id = $Suggestion.id; type = $Suggestion.type; applied = $false; target = ''; message = '' }
    $text = [string]$Suggestion.finding
    if ([string]::IsNullOrWhiteSpace($text)) { $result.message = 'Nothing to save (empty finding).'; return $result }

    switch ($Suggestion.type) {
        'action-item' {
            if (Get-Command Add-ActionItem -ErrorAction SilentlyContinue) {
                $data = Get-ActionItemsData; $data = Add-ActionItem -Data $data -Title $text; Save-ActionItemsData -Data $data
                $result.applied = $true; $result.target = 'Action Items'; $result.message = "Added to Action Items."
            }
        }
        'goal' {
            if (Get-Command Add-IdentityGoal -ErrorAction SilentlyContinue) {
                $g = Add-IdentityGoal -Title $text
                $result.applied = $true; $result.target = 'Identity > Goals'; $result.message = "Added goal $($g.id) to your Identity."
            }
        }
        default {
            # ideas, projects, questions, and anything else land safely in Capture.
            if (Get-Command Add-Capture -ErrorAction SilentlyContinue) {
                $cat = if ($Suggestion.category) { $Suggestion.category } else { 'Note' }
                $data = Get-CaptureData; $item = Add-Capture -Data $data -Text $text -Category $cat -CreatedFrom 'document-intelligence'; Save-CaptureData -Data $data
                $result.applied = $true; $result.target = 'Capture'; $result.message = "Saved to Capture ($($item.id))."
            }
        }
    }
    if ($result.applied) { $Suggestion.status = 'accepted'; $Suggestion.applied = $true }
    else { $result.message = 'No writer available for this suggestion type.' }
    return $result
}

# ------------------------------------------------------------------ #
# The Document Summary - Tony as chief of staff, not a summarizer.
# Runs the whole pipeline and returns the executive package.
# ------------------------------------------------------------------ #

function Invoke-DocumentIntelligence {
    param([Parameter(Mandatory)][string]$Path)

    $doc = Read-Document -Path $Path
    $name = [System.IO.Path]::GetFileName($Path)
    if (-not $doc.ok) {
        return [pscustomobject]@{
            ok = $false; source = $name; type = $doc.type
            executiveSummary = "Tony couldn't read this document. $($doc.note)"
            keyFindings = $null; suggestedGoals = @(); suggestedTasks = @(); suggestedProjects = @()
            suggestedQuestions = @(); potentialConflicts = @(); alignmentScore = 0; review = (New-DocumentReview @() $name)
        }
    }

    $entities = Get-DocumentEntities -Text $doc.text
    $ctx = Get-DocumentReviewContext
    $cmp = Compare-DocumentFindings -Entities $entities -Context $ctx
    $review = New-DocumentReview -Suggestions $cmp.suggestions -Source $name

    # Alignment: reuse Tony's judgment layer on the document's gist.
    $alignment = 50
    if (Get-Command Evaluate-TonyDecision -ErrorAction SilentlyContinue) {
        $gist = (@($entities.goals) + @($entities.projects) + @($entities.actionItems) | Select-Object -First 8) -join '. '
        if (-not $gist) { $gist = ($doc.text.Substring(0, [math]::Min(400, $doc.text.Length))) }
        try {
            $judgment = Evaluate-TonyDecision -Identity $ctx.identity -Vision $ctx.vision -Goals $ctx.goals `
                -Mission $ctx.mission -CoreValues $ctx.values -AnnualTheme $ctx.annualTheme `
                -NonNegotiables $ctx.nonNegotiables -CurrentWorkspace 'Documents' -CurrentQuestion $gist `
                -OpenTasks $ctx.actionItems -RecentAudits $ctx.audits
            if ($judgment) { $alignment = $judgment.alignmentScore }
        } catch { }
    }

    $sugGoals   = @($cmp.suggestions | Where-Object { $_.type -eq 'goal' -and $_.status -ne 'rejected' -and $_.editable })
    $sugTasks   = @($cmp.suggestions | Where-Object { $_.type -eq 'action-item' -and $_.editable })
    $sugProjects= @($cmp.suggestions | Where-Object { $_.type -eq 'project' -and $_.editable })
    $sugQuestions = @($cmp.suggestions | Where-Object { $_.type -eq 'question' })

    # Executive summary: connect the document back to the operating system.
    $counts = @()
    if ($entities.goals.Count)       { $counts += "$($entities.goals.Count) goal(s)" }
    if ($entities.actionItems.Count) { $counts += "$($entities.actionItems.Count) action item(s)" }
    if ($entities.projects.Count)    { $counts += "$($entities.projects.Count) project(s)" }
    if ($entities.people.Count)      { $counts += "$($entities.people.Count) people" }
    if ($entities.dates.Count)       { $counts += "$($entities.dates.Count) date(s)" }
    if ($entities.risks.Count)       { $counts += "$($entities.risks.Count) risk(s)" }
    $countStr = if ($counts.Count) { $counts -join ', ' } else { 'no clearly structured items' }
    $newGoals = @($cmp.suggestions | Where-Object { $_.type -eq 'goal' -and $_.editable }).Count
    $newTasks = $sugTasks.Count
    $conflictStr = if ($cmp.conflicts.Count) { " Heads up: $($cmp.conflicts.Count) potential conflict(s) with your Annual Theme." } else { '' }
    $exec = "Tony's read of '$name': it contains $countStr. Connecting it to your operating system, " +
            "$newGoals of the goals aren't in your Identity yet and $newTasks action item(s) aren't on your list. " +
            "Overall alignment with the life you're building is about $alignment/100.$conflictStr " +
            "Nothing has been saved - review each suggestion below and Accept, Reject, or Edit it."

    return [pscustomobject]@{
        ok                 = $true
        source             = $name
        type               = $doc.type
        executiveSummary   = $exec
        keyFindings        = $entities
        suggestedGoals     = $sugGoals
        suggestedTasks     = $sugTasks
        suggestedProjects  = $sugProjects
        suggestedQuestions = $sugQuestions
        potentialConflicts = @($cmp.conflicts)
        alignmentScore     = $alignment
        review             = $review
    }
}
