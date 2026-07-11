# =====================================================================
# life-workspaces.ps1  -  Life Operating System workspace views
# ---------------------------------------------------------------------
# The editable UI for the life-and-business domains (Goals, Non-Negotiables,
# Family, Health, Financial, Agency, Learning, Home Projects). PURE
# PRESENTATION + INPUT: every view reads through a core owner's Get-* and
# writes ONLY through that owner's Add/Update/Set/Remove - never touches a
# JSON file directly, never contains business logic. Tony consumes the same
# data through the Executive Context, never from these controls.
#
# Dot-sourced by dashboard.ps1 AFTER ui/tony-ui.ps1, so it shares the theme
# palette ($script:Col/$script:Font), the UI helpers (New-Text/New-Card/
# New-MiniButton/...), and the view host ($script:TonyBody).
# =====================================================================

$ErrorActionPreference = 'Stop'

# module state (which goal is being edited inline, and the active filter)
$script:GoalEditId = $null
$script:GoalShowDone = $false

# Re-render the active life view in place (mirrors Refresh-ActionItems).
function Show-LifeView { param([scriptblock]$Builder) if ($script:TonyBody) { $script:TonyBody.Child = (& $Builder) } }

# ---- reusable input controls (themed, readable on the light body) ----
function New-LifeInput {
    param([string]$Text = '', [int]$MinLines = 1, [double]$Width = 0)
    $tb = New-Object Windows.Controls.TextBox
    $tb.FontFamily = New-Object Windows.Media.FontFamily $script:Font; $tb.FontSize = 13
    $tb.Padding = New-Object Windows.Thickness (8, 6, 8, 6)
    $tb.BorderBrush = New-Brush $script:Col.Line; $tb.BorderThickness = New-Object Windows.Thickness 1
    $tb.Background = New-Brush $script:Col.CardBg; $tb.Foreground = New-Brush $script:Col.Ink; $tb.CaretBrush = New-Brush $script:Col.Accent
    $tb.Margin = New-Object Windows.Thickness (0, 0, 0, 8); $tb.Text = [string]$Text
    if ($MinLines -gt 1) { $tb.AcceptsReturn = $true; $tb.TextWrapping = 'Wrap'; $tb.MinLines = $MinLines; $tb.MaxLines = 8; $tb.VerticalScrollBarVisibility = 'Auto' }
    else { $tb.VerticalContentAlignment = 'Center' }
    if ($Width -gt 0) { $tb.Width = $Width; $tb.HorizontalAlignment = 'Left' }
    return $tb
}
function New-LifeCombo {
    param([string[]]$Options, [string]$Selected, [double]$Width = 0)
    $cb = New-Object Windows.Controls.ComboBox
    $cb.FontFamily = New-Object Windows.Media.FontFamily $script:Font; $cb.FontSize = 13
    $cb.Padding = New-Object Windows.Thickness (8, 5, 8, 5); $cb.Margin = New-Object Windows.Thickness (0, 0, 0, 8)
    foreach ($o in $Options) { [void]$cb.Items.Add($o) }
    if ($Selected -and ($Options -contains $Selected)) { $cb.SelectedItem = $Selected } elseif ($cb.Items.Count -gt 0) { $cb.SelectedIndex = 0 }
    if ($Width -gt 0) { $cb.Width = $Width; $cb.HorizontalAlignment = 'Left' }
    return $cb
}
function New-LifeFieldLabel { param([string]$Text) return (New-Text -Text $Text -Size 11.5 -Weight 'SemiBold' -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 0, 0, 3))) }

# Standard workspace header (title + honest source-of-truth subtitle + intro).
function New-LifeHeader {
    param([string]$Title, [string]$Source, [string]$Intro)
    $sp = New-Object Windows.Controls.StackPanel; $sp.Margin = New-Object Windows.Thickness (4, 0, 4, 12)
    $sp.Children.Add((New-Text -Text $Title -Size 24 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
    $rule = New-Object Windows.Controls.Border; $rule.Background = New-Brush $script:Col.Accent; $rule.Height = 3; $rule.Width = 64; $rule.HorizontalAlignment = 'Left'; $rule.CornerRadius = New-Object Windows.CornerRadius 2; $rule.Margin = New-Object Windows.Thickness (0, 5, 0, 6)
    $sp.Children.Add($rule) | Out-Null
    if ($Intro) { $sp.Children.Add((New-Text -Text $Intro -Size 13 -Color $script:Col.Ink -Wrap $true)) | Out-Null }
    if ($Source) { $sp.Children.Add((New-Text -Text ("Your data - source of truth: {0}" -f $Source) -Size 11.5 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 2, 0, 0)))) | Out-Null }
    return $sp
}

# A small pill/chip for a status or domain (reuses New-Chip).
function New-GoalStatusChip {
    param([string]$Status)
    $c = switch ($Status) { 'active' { @('#DEF7EC', '#03543F') } 'paused' { @('#FDF6B2', '#8E4B10') } 'done' { @('#E0E7FF', '#3730A3') } 'archived' { @('#E5E7EB', '#4B5563') } default { @('#E5E7EB', '#4B5563') } }
    return (New-Chip -Text $Status.ToUpper() -Bg $c[0] -Fg $c[1])
}

# =====================================================================
# GENERIC LIFE-OS DOMAIN WORKSPACE (Non-Negotiables, Family, Health,
# Financial, Agency, Learning, Home Projects). One spec-driven renderer so
# every domain is consistent (Stage 7 polish is inherent). Reads via
# Get-LifeItems; writes only via Add/Update/Set/Remove-LifeItem.
# =====================================================================
$script:LifeEditKey = $null       # "domain:id" currently in inline edit
$script:LifeShowInactive = @{}    # per-view: show paused/archived

# Build one input control for a field spec; returns the control.
function New-LifeFieldControl {
    param($Field, $Value = '')
    switch ($Field.type) {
        'combo'     { return (New-LifeCombo -Options $Field.options -Selected ([string]$Value) -Width 240) }
        'multiline' { return (New-LifeInput -Text ([string]$Value) -MinLines 2) }
        'number'    { return (New-LifeInput -Text ([string]$Value) -Width 120) }
        default     { return (New-LifeInput -Text ([string]$Value)) }
    }
}
function Get-LifeControlValue { param($Control) if ($Control -is [Windows.Controls.ComboBox]) { return [string]$Control.SelectedItem } return [string]$Control.Text }

# Validate + collect a field set from a control map. Returns @{ ok; error; fields }.
function Read-LifeFields {
    param($Spec, $Controls)
    $fields = @{}
    foreach ($f in $Spec.addFields) {
        $v = (Get-LifeControlValue $Controls[$f.key]).Trim()
        if ($f.required -and [string]::IsNullOrWhiteSpace($v)) { return @{ ok = $false; error = ("{0} is required." -f ($f.label -replace ' \*$', '')); fields = $null } }
        if ($f.type -eq 'date' -or $f.key -match 'Date$') { if ($v -and ($v -notmatch '^\d{4}-\d{2}-\d{2}$')) { return @{ ok = $false; error = ("{0} must look like 2026-12-31 (or blank)." -f ($f.label -replace ' \*$', '')); fields = $null } } }
        $fields[$f.key] = $v
    }
    return @{ ok = $true; error = ''; fields = $fields }
}

# The generic domain view.
function New-LifeDomainView {
    param([Parameter(Mandatory)][string]$Key)
    $spec = $script:LifeSpecs[$Key]
    if (-not $spec) { return (New-Text -Text ("Unknown workspace: {0}" -f $Key)) }
    $domain = $spec.domain

    $outer = New-Object Windows.Controls.DockPanel
    $head = New-LifeHeader -Title $spec.title -Source $spec.source -Intro $spec.intro
    [Windows.Controls.DockPanel]::SetDock($head, 'Top'); $outer.Children.Add($head) | Out-Null
    $body = New-Object Windows.Controls.StackPanel; $body.Margin = New-Object Windows.Thickness (4, 0, 12, 8)

    # optional: this domain's goals (from the ONE goal store), read-only pointer
    if ($spec.goalDomain) {
        $dg = @(Get-GoalsList | Where-Object { $_.domain -eq $spec.goalDomain -and $_.status -in @('active', 'paused') })
        $gBody = New-Object Windows.Controls.StackPanel
        if ($dg.Count -eq 0) { $gBody.Children.Add((New-Text -Text ("No {0} goals yet. Add them in Goals (they live in the one goal store)." -f $spec.goalDomain) -Size 12.5 -Color $script:Col.Muted -Wrap $true)) | Out-Null }
        else { foreach ($g in $dg) { $gBody.Children.Add((New-Text -Text ('- ' + $g.title + '  (' + $g.progress + '%)') -Size 12.5 -Color $script:Col.Ink -Wrap $true -Margin (New-Object Windows.Thickness (0, 0, 0, 3)))) | Out-Null } }
        $gBody.Children.Add((New-MiniButton -Text 'Open Goals' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -OnClick { param($s, $e) Set-ActiveView 'Goals' })) | Out-Null
        $body.Children.Add((New-Card -Title ($spec.goalDomain + ' goals') -Body $gBody)) | Out-Null
    }

    # --- add card ---
    $addStack = New-Object Windows.Controls.StackPanel
    $controls = @{}
    foreach ($f in $spec.addFields) {
        $addStack.Children.Add((New-LifeFieldLabel $f.label)) | Out-Null
        $ctl = New-LifeFieldControl -Field $f
        $controls[$f.key] = $ctl
        $addStack.Children.Add($ctl) | Out-Null
    }
    $err = New-Text -Text '' -Size 12 -Color '#9B1C1C' -Wrap $true
    $addStack.Children.Add($err) | Out-Null
    $saveBtn = New-MiniButton -Text ('+ ' + $spec.addVerb) -Bg $script:Col.Accent -Fg $script:Col.OnPrimary -OnClick {
        param($s, $e)
        $r = Read-LifeFields -Spec $spec -Controls $controls
        if (-not $r.ok) { $err.Text = $r.error; return }
        [void](Add-LifeItem -Domain $domain -Fields $r.fields)
        Show-LifeView { New-LifeDomainView -Key $Key }
    }.GetNewClosure()
    $saveBtn.HorizontalAlignment = 'Left'; $saveBtn.Margin = New-Object Windows.Thickness (0, 4, 0, 0)
    $addStack.Children.Add($saveBtn) | Out-Null
    $body.Children.Add((New-Card -Title $spec.addTitle -Body $addStack)) | Out-Null

    # --- active/paused toggle ---
    $all = @(Get-LifeItems -Domain $domain)
    $activeItems = @($all | Where-Object { $_.active })
    $pausedItems = @($all | Where-Object { -not $_.active })
    $showInactive = [bool]$script:LifeShowInactive[$Key]
    $toggle = New-Object Windows.Controls.StackPanel; $toggle.Orientation = 'Horizontal'; $toggle.Margin = New-Object Windows.Thickness (4, 4, 0, 6)
    $tA = New-MiniButton -Text ("Active ({0})" -f $activeItems.Count) -Bg $(if (-not $showInactive) { $script:Col.Accent } else { $script:Col.AccentSoft }) -Fg $(if (-not $showInactive) { $script:Col.OnPrimary } else { $script:Col.AccentInk }) -OnClick { param($s, $e) $script:LifeShowInactive[$Key] = $false; Show-LifeView { New-LifeDomainView -Key $Key } }.GetNewClosure()
    $tA.Margin = New-Object Windows.Thickness (0, 0, 0, 0)
    $tP = New-MiniButton -Text ("Paused ({0})" -f $pausedItems.Count) -Bg $(if ($showInactive) { $script:Col.Accent } else { $script:Col.AccentSoft }) -Fg $(if ($showInactive) { $script:Col.OnPrimary } else { $script:Col.AccentInk }) -OnClick { param($s, $e) $script:LifeShowInactive[$Key] = $true; Show-LifeView { New-LifeDomainView -Key $Key } }.GetNewClosure()
    $toggle.Children.Add($tA) | Out-Null; $toggle.Children.Add($tP) | Out-Null
    $body.Children.Add($toggle) | Out-Null

    $shown = if ($showInactive) { $pausedItems } else { $activeItems }
    if ($shown.Count -eq 0) {
        $body.Children.Add((New-Text -Text $(if ($showInactive) { 'Nothing paused.' } else { $spec.emptyText }) -Size 13 -Color $script:Col.Muted -Wrap $true -Margin (New-Object Windows.Thickness (6, 6, 0, 0)))) | Out-Null
    }
    else { foreach ($it in $shown) { $body.Children.Add((New-LifeItemCard -Key $Key -Item $it)) | Out-Null } }

    $scroll = New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility = 'Auto'; $scroll.HorizontalScrollBarVisibility = 'Disabled'; $scroll.Content = $body
    $outer.Children.Add($scroll) | Out-Null
    return $outer
}

function New-LifeItemCard {
    param([string]$Key, $Item)
    $spec = $script:LifeSpecs[$Key]; $domain = $spec.domain
    if ($script:LifeEditKey -eq ($domain + ':' + $Item.id)) { return (New-LifeItemEditor -Key $Key -Item $Item) }
    $body = New-Object Windows.Controls.StackPanel

    # optional 'kind' chip
    if (($spec.addFields | Where-Object { $_.key -eq 'kind' }) -and $Item.kind) {
        $chips = New-Object Windows.Controls.StackPanel; $chips.Orientation = 'Horizontal'; $chips.Margin = New-Object Windows.Thickness (0, 0, 0, 6)
        $chips.Children.Add((New-Chip -Text $Item.kind -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk)) | Out-Null
        $body.Children.Add($chips) | Out-Null
    }
    foreach ($cf in $spec.cardFields) {
        $val = [string]$Item.($cf.key)
        if ($cf.key -eq 'progress') { continue }
        if (-not [string]::IsNullOrWhiteSpace($val)) {
            $body.Children.Add((New-Text -Text ($cf.label + ': ' + $val) -Size 12.5 -Color $script:Col.Ink -Wrap $true -Margin (New-Object Windows.Thickness (0, 0, 0, 3)))) | Out-Null
        }
    }
    # progress bar + steppers (learning)
    if ($spec.addFields | Where-Object { $_.key -eq 'progress' }) {
        $iid = $Item.id
        $prow = New-Object Windows.Controls.DockPanel; $prow.Margin = New-Object Windows.Thickness (0, 4, 0, 6)
        $pt = New-Text -Text ("Progress: {0}%" -f $Item.progress) -Size 12.5 -Weight 'SemiBold' -Color $script:Col.Ink
        [Windows.Controls.DockPanel]::SetDock($pt, 'Left'); $prow.Children.Add($pt) | Out-Null
        $st = New-Object Windows.Controls.StackPanel; $st.Orientation = 'Horizontal'; $st.HorizontalAlignment = 'Right'
        $st.Children.Add((New-MiniButton -Text '-10%' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -OnClick { param($s, $e) [void](Update-LifeItem -Domain $domain -Id $iid -Fields @{ progress = ([int]$Item.progress - 10) }); Show-LifeView { New-LifeDomainView -Key $Key } }.GetNewClosure())) | Out-Null
        $st.Children.Add((New-MiniButton -Text '+10%' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -OnClick { param($s, $e) [void](Update-LifeItem -Domain $domain -Id $iid -Fields @{ progress = ([int]$Item.progress + 10) }); Show-LifeView { New-LifeDomainView -Key $Key } }.GetNewClosure())) | Out-Null
        $prow.Children.Add($st) | Out-Null; $body.Children.Add($prow) | Out-Null
        $track = New-Object Windows.Controls.Border; $track.Height = 8; $track.CornerRadius = New-Object Windows.CornerRadius 4; $track.Background = New-Brush $script:Col.Line; $track.Margin = New-Object Windows.Thickness (0, 0, 0, 8)
        $fill = New-Object Windows.Controls.Border; $fill.Height = 8; $fill.CornerRadius = New-Object Windows.CornerRadius 4; $fill.Background = New-Brush $script:Col.Accent; $fill.HorizontalAlignment = 'Left'; $fill.Width = [math]::Max(0, [math]::Min(100, [int]$Item.progress)) * 3.0
        $track.Child = $fill; $body.Children.Add($track) | Out-Null
    }

    # actions
    $iid = $Item.id
    $actions = New-Object Windows.Controls.StackPanel; $actions.Orientation = 'Horizontal'
    $actions.Children.Add((New-MiniButton -Text 'Edit' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -OnClick { param($s, $e) $script:LifeEditKey = ($domain + ':' + $iid); Show-LifeView { New-LifeDomainView -Key $Key } }.GetNewClosure())) | Out-Null
    if ($Item.active) { $actions.Children.Add((New-MiniButton -Text 'Pause' -Bg '#FDF6B2' -Fg '#8E4B10' -OnClick { param($s, $e) [void](Set-LifeItemActive -Domain $domain -Id $iid -Active $false); Show-LifeView { New-LifeDomainView -Key $Key } }.GetNewClosure())) | Out-Null }
    else { $actions.Children.Add((New-MiniButton -Text 'Resume' -Bg '#DEF7EC' -Fg '#03543F' -OnClick { param($s, $e) [void](Set-LifeItemActive -Domain $domain -Id $iid -Active $true); Show-LifeView { New-LifeDomainView -Key $Key } }.GetNewClosure())) | Out-Null }
    $actions.Children.Add((New-MiniButton -Text 'Delete' -Bg '#FDE2E1' -Fg '#9B1C1C' -OnClick { param($s, $e) [void](Remove-LifeItem -Domain $domain -Id $iid); Show-LifeView { New-LifeDomainView -Key $Key } }.GetNewClosure())) | Out-Null
    $body.Children.Add($actions) | Out-Null

    $titleText = [string]$Item.($spec.titleKey); if ([string]::IsNullOrWhiteSpace($titleText)) { $titleText = '(untitled)' }
    return (New-Card -Title $titleText -Body $body)
}

function New-LifeItemEditor {
    param([string]$Key, $Item)
    $spec = $script:LifeSpecs[$Key]; $domain = $spec.domain
    $body = New-Object Windows.Controls.StackPanel
    $controls = @{}
    foreach ($f in $spec.addFields) {
        $body.Children.Add((New-LifeFieldLabel $f.label)) | Out-Null
        $ctl = New-LifeFieldControl -Field $f -Value ([string]$Item.($f.key))
        $controls[$f.key] = $ctl
        $body.Children.Add($ctl) | Out-Null
    }
    $err = New-Text -Text '' -Size 12 -Color '#9B1C1C' -Wrap $true; $body.Children.Add($err) | Out-Null
    $iid = $Item.id
    $row = New-Object Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = New-Object Windows.Thickness (0, 4, 0, 0)
    $row.Children.Add((New-MiniButton -Text 'Save' -Bg $script:Col.Accent -Fg $script:Col.OnPrimary -OnClick {
                param($s, $e)
                $r = Read-LifeFields -Spec $spec -Controls $controls
                if (-not $r.ok) { $err.Text = $r.error; return }
                [void](Update-LifeItem -Domain $domain -Id $iid -Fields $r.fields)
                $script:LifeEditKey = $null; Show-LifeView { New-LifeDomainView -Key $Key }
            }.GetNewClosure())) | Out-Null
    $row.Children.Add((New-MiniButton -Text 'Cancel' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -OnClick { param($s, $e) $script:LifeEditKey = $null; Show-LifeView { New-LifeDomainView -Key $Key } }.GetNewClosure())) | Out-Null
    $body.Children.Add($row) | Out-Null
    return (New-Card -Title ('Editing: ' + [string]$Item.($spec.titleKey)) -Body $body)
}

# ---- domain spec registry (Stages 2-5 add entries here) --------------
$script:LifeSpecs = @{
    'Non-Negotiables' = @{
        domain = 'nonNegotiables'; title = 'Non-Negotiables'; source = 'life_os.json'; addVerb = 'Add commitment'; addTitle = 'Add a non-negotiable'
        intro  = 'Your bright lines - the commitments you protect no matter what (gym, family dinner, weekly planning). Tony watches the day and warns you when the schedule threatens one.'
        goalDomain = $null; titleKey = 'title'
        addFields = @(
            @{ key = 'title'; label = 'Commitment *'; type = 'text'; required = $true },
            @{ key = 'cadence'; label = 'Cadence (daily, Mon/Wed/Fri, weekly, ...)'; type = 'text' },
            @{ key = 'purpose'; label = 'Why it protects you'; type = 'text' },
            @{ key = 'protection'; label = 'Protection rule (what to guard - e.g. no meetings after 6pm)'; type = 'multiline' }
        )
        cardFields = @(@{ key = 'cadence'; label = 'Cadence' }, @{ key = 'purpose'; label = 'Purpose' }, @{ key = 'protection'; label = 'Protect' })
        emptyText  = 'No non-negotiables yet. Add your first bright line above - Tony will help you protect it.'
    }
    'Family' = @{
        domain = 'family'; title = 'Family'; source = 'life_os.json'; addVerb = 'Add'; addTitle = 'Add a family item'
        intro  = 'The people who matter most - commitments, important dates, priorities, and anything you are keeping an eye on. Family before Financial, always.'
        goalDomain = 'family'; titleKey = 'title'
        addFields = @(
            @{ key = 'kind'; label = 'Type'; type = 'combo'; options = @('commitment', 'important-date', 'priority', 'concern') },
            @{ key = 'title'; label = 'Title *'; type = 'text'; required = $true },
            @{ key = 'detail'; label = 'Detail'; type = 'multiline' },
            @{ key = 'date'; label = 'Date (YYYY-MM-DD, optional)'; type = 'date' }
        )
        cardFields = @(@{ key = 'detail'; label = 'Detail' }, @{ key = 'date'; label = 'Date' })
        emptyText  = 'Nothing here yet. Add a family commitment, an important date, or something on your mind.'
    }
    'Health' = @{
        domain = 'health'; title = 'Health'; source = 'life_os.json'; addVerb = 'Add'; addTitle = 'Add a health item'
        intro  = 'Your routines, workouts, recovery, and the next action that keeps you strong. Health goals live in Goals; the day-to-day lives here.'
        goalDomain = 'health'; titleKey = 'title'
        addFields = @(
            @{ key = 'kind'; label = 'Type'; type = 'combo'; options = @('routine', 'workout', 'recovery', 'next-action') },
            @{ key = 'title'; label = 'Title *'; type = 'text'; required = $true },
            @{ key = 'detail'; label = 'Detail'; type = 'multiline' },
            @{ key = 'cadence'; label = 'Cadence (daily, 3x/week, ...)'; type = 'text' }
        )
        cardFields = @(@{ key = 'detail'; label = 'Detail' }, @{ key = 'cadence'; label = 'Cadence' })
        emptyText  = 'Nothing here yet. Add a routine, a workout, or a recovery habit.'
    }
    'Financial' = @{
        domain = 'financial'; title = 'Financial'; source = 'life_os.json'; addVerb = 'Add'; addTitle = 'Add a financial item'
        intro  = 'Obligations, targets, and review dates - the money you owe, aim for, and check. You enter every value; Tony never invents a number.'
        goalDomain = 'financial'; titleKey = 'title'
        addFields = @(
            @{ key = 'kind'; label = 'Type'; type = 'combo'; options = @('obligation', 'target', 'review') },
            @{ key = 'title'; label = 'Title *'; type = 'text'; required = $true },
            @{ key = 'amount'; label = 'Amount (as you write it, e.g. $2,400/mo)'; type = 'text' },
            @{ key = 'detail'; label = 'Detail'; type = 'multiline' },
            @{ key = 'dueDate'; label = 'Due / review date (YYYY-MM-DD, optional)'; type = 'date' }
        )
        cardFields = @(@{ key = 'amount'; label = 'Amount' }, @{ key = 'detail'; label = 'Detail' }, @{ key = 'dueDate'; label = 'Due' })
        emptyText  = 'Nothing here yet. Add an obligation, a target, or a review date - values are yours to enter.'
    }
    'Agency' = @{
        domain = 'agency'; title = 'Agency'; source = 'life_os.json'; addVerb = 'Add'; addTitle = 'Add an agency item'
        intro  = 'Production targets, strategic priorities, and next steps for the business. Agency goals live in Goals; the working priorities live here. You enter every value.'
        goalDomain = 'agency'; titleKey = 'title'
        addFields = @(
            @{ key = 'kind'; label = 'Type'; type = 'combo'; options = @('production-target', 'strategic-priority', 'next-step') },
            @{ key = 'title'; label = 'Title *'; type = 'text'; required = $true },
            @{ key = 'detail'; label = 'Detail'; type = 'multiline' },
            @{ key = 'metric'; label = 'Metric / target (as you write it)'; type = 'text' }
        )
        cardFields = @(@{ key = 'detail'; label = 'Detail' }, @{ key = 'metric'; label = 'Metric' })
        emptyText  = 'Nothing here yet. Add a production target, a strategic priority, or the next step.'
    }
}
function Get-LifeSpecKeys { return @($script:LifeSpecs.Keys) }

# ---- Goals workspace -------------------------------------------------
# The ONE goal store (identity/goals.json), full CRUD. Domain-tagged goals
# feed the Executive Context and the Priority Engine unchanged.
function New-GoalsView {
    $outer = New-Object Windows.Controls.DockPanel
    $head = New-LifeHeader -Title 'Goals' -Source 'identity/goals.json' -Intro 'The goals you are actually working toward. Each one carries why it matters, a next step, and progress - Tony and the Priority Engine see your active goals.'
    [Windows.Controls.DockPanel]::SetDock($head, 'Top'); $outer.Children.Add($head) | Out-Null

    $scrollBody = New-Object Windows.Controls.StackPanel; $scrollBody.Margin = New-Object Windows.Thickness (4, 0, 12, 8)

    # --- add-a-goal card ---
    $addStack = New-Object Windows.Controls.StackPanel
    $titleBox = New-LifeInput
    $domainBox = New-LifeCombo -Options (Get-GoalDomains) -Selected 'personal' -Width 200
    $reasonBox = New-LifeInput
    $dateBox = New-LifeInput -Width 200
    $nextBox = New-LifeInput
    $addStack.Children.Add((New-LifeFieldLabel 'Goal *')) | Out-Null; $addStack.Children.Add($titleBox) | Out-Null
    $addStack.Children.Add((New-LifeFieldLabel 'Domain')) | Out-Null; $addStack.Children.Add($domainBox) | Out-Null
    $addStack.Children.Add((New-LifeFieldLabel 'Why it matters')) | Out-Null; $addStack.Children.Add($reasonBox) | Out-Null
    $addStack.Children.Add((New-LifeFieldLabel 'Target date (YYYY-MM-DD, optional)')) | Out-Null; $addStack.Children.Add($dateBox) | Out-Null
    $addStack.Children.Add((New-LifeFieldLabel 'Next step')) | Out-Null; $addStack.Children.Add($nextBox) | Out-Null
    $errText = New-Text -Text '' -Size 12 -Color '#9B1C1C' -Wrap $true
    $addStack.Children.Add($errText) | Out-Null
    $saveBtn = New-MiniButton -Text '+ Add goal' -Bg $script:Col.Accent -Fg $script:Col.OnPrimary -OnClick {
        param($s, $e)
        $t = $titleBox.Text
        if ([string]::IsNullOrWhiteSpace($t)) { $errText.Text = 'A goal needs a title.'; return }
        $d = [string]$dateBox.Text
        if ($d -and ($d -notmatch '^\d{4}-\d{2}-\d{2}$')) { $errText.Text = 'Target date must look like 2026-12-31 (or leave it blank).'; return }
        [void](Add-Goal -Title $t -Domain ([string]$domainBox.SelectedItem) -Reason ([string]$reasonBox.Text) -TargetDate $d -NextStep ([string]$nextBox.Text))
        Show-LifeView { New-GoalsView }
    }.GetNewClosure()
    $saveBtn.HorizontalAlignment = 'Left'; $saveBtn.Margin = New-Object Windows.Thickness (0, 4, 0, 0)
    $addStack.Children.Add($saveBtn) | Out-Null
    $scrollBody.Children.Add((New-Card -Title 'Add a goal' -Body $addStack)) | Out-Null

    # --- filter toggle (active vs. done/archived) ---
    $goals = @(Get-GoalsList)
    $activeGoals = @($goals | Where-Object { $_.status -in @('active', 'paused') })
    $doneGoals = @($goals | Where-Object { $_.status -in @('done', 'archived') })
    $toggle = New-Object Windows.Controls.StackPanel; $toggle.Orientation = 'Horizontal'; $toggle.Margin = New-Object Windows.Thickness (4, 4, 0, 6)
    $showDone = [bool]$script:GoalShowDone
    $tgA = New-MiniButton -Text ("Active ({0})" -f $activeGoals.Count) -Bg $(if (-not $showDone) { $script:Col.Accent } else { $script:Col.AccentSoft }) -Fg $(if (-not $showDone) { $script:Col.OnPrimary } else { $script:Col.AccentInk }) -OnClick { param($s, $e) $script:GoalShowDone = $false; Show-LifeView { New-GoalsView } }
    $tgA.Margin = New-Object Windows.Thickness (0, 0, 0, 0)
    $tgD = New-MiniButton -Text ("Done / Archived ({0})" -f $doneGoals.Count) -Bg $(if ($showDone) { $script:Col.Accent } else { $script:Col.AccentSoft }) -Fg $(if ($showDone) { $script:Col.OnPrimary } else { $script:Col.AccentInk }) -OnClick { param($s, $e) $script:GoalShowDone = $true; Show-LifeView { New-GoalsView } }
    $toggle.Children.Add($tgA) | Out-Null; $toggle.Children.Add($tgD) | Out-Null
    $scrollBody.Children.Add($toggle) | Out-Null

    $shown = if ($showDone) { $doneGoals } else { $activeGoals }
    if ($shown.Count -eq 0) {
        $empty = if ($showDone) { 'Nothing here yet - completed and archived goals will collect here.' } else { 'No active goals yet. Add your first above - even one clear goal helps Tony focus your day.' }
        $scrollBody.Children.Add((New-Text -Text $empty -Size 13 -Color $script:Col.Muted -Wrap $true -Margin (New-Object Windows.Thickness (6, 6, 0, 0)))) | Out-Null
    }
    else {
        foreach ($g in $shown) { $scrollBody.Children.Add((New-GoalCard -Goal $g)) | Out-Null }
    }

    $scroll = New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility = 'Auto'; $scroll.HorizontalScrollBarVisibility = 'Disabled'; $scroll.Content = $scrollBody
    $outer.Children.Add($scroll) | Out-Null
    return $outer
}

# One goal - either read view (with actions) or inline editor.
function New-GoalCard {
    param($Goal)
    if ($script:GoalEditId -eq $Goal.id) { return (New-GoalEditor -Goal $Goal) }

    $body = New-Object Windows.Controls.StackPanel
    # chips row
    $chips = New-Object Windows.Controls.StackPanel; $chips.Orientation = 'Horizontal'; $chips.Margin = New-Object Windows.Thickness (0, 0, 0, 6)
    $chips.Children.Add((New-Chip -Text $Goal.domain -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk)) | Out-Null
    $chips.Children.Add((New-GoalStatusChip -Status $Goal.status)) | Out-Null
    if ($Goal.targetDate) { $chips.Children.Add((New-Chip -Text ('by ' + $Goal.targetDate) -Bg '#E5E7EB' -Fg '#374151')) | Out-Null }
    $body.Children.Add($chips) | Out-Null
    if ($Goal.reason) { $body.Children.Add((New-Text -Text ('Why: ' + $Goal.reason) -Size 12.5 -Color $script:Col.Ink -Wrap $true -Margin (New-Object Windows.Thickness (0, 0, 0, 4)))) | Out-Null }
    if ($Goal.nextStep) { $body.Children.Add((New-Text -Text ('Next: ' + $Goal.nextStep) -Size 12.5 -Weight 'SemiBold' -Color $script:Col.Accent -Wrap $true -Margin (New-Object Windows.Thickness (0, 0, 0, 4)))) | Out-Null }
    if ($Goal.notes) { $body.Children.Add((New-Text -Text $Goal.notes -Size 12 -Color $script:Col.Muted -Wrap $true -Margin (New-Object Windows.Thickness (0, 0, 0, 4)))) | Out-Null }

    # progress row: label + steppers
    $prow = New-Object Windows.Controls.DockPanel; $prow.Margin = New-Object Windows.Thickness (0, 4, 0, 6)
    $pText = New-Text -Text ("Progress: {0}%" -f $Goal.progress) -Size 12.5 -Weight 'SemiBold' -Color $script:Col.Ink
    [Windows.Controls.DockPanel]::SetDock($pText, 'Left'); $prow.Children.Add($pText) | Out-Null
    $steppers = New-Object Windows.Controls.StackPanel; $steppers.Orientation = 'Horizontal'; $steppers.HorizontalAlignment = 'Right'
    $gid = $Goal.id
    $minus = New-MiniButton -Text '-10%' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -OnClick { param($s, $e) [void](Set-GoalProgress -Id $gid -Progress ([int]$Goal.progress - 10)); Show-LifeView { New-GoalsView } }.GetNewClosure()
    $plus = New-MiniButton -Text '+10%' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -OnClick { param($s, $e) [void](Set-GoalProgress -Id $gid -Progress ([int]$Goal.progress + 10)); Show-LifeView { New-GoalsView } }.GetNewClosure()
    $steppers.Children.Add($minus) | Out-Null; $steppers.Children.Add($plus) | Out-Null
    $prow.Children.Add($steppers) | Out-Null; $body.Children.Add($prow) | Out-Null
    # progress bar
    $track = New-Object Windows.Controls.Border; $track.Height = 8; $track.CornerRadius = New-Object Windows.CornerRadius 4; $track.Background = New-Brush $script:Col.Line; $track.Margin = New-Object Windows.Thickness (0, 0, 0, 8)
    $fill = New-Object Windows.Controls.Border; $fill.Height = 8; $fill.CornerRadius = New-Object Windows.CornerRadius 4; $fill.Background = New-Brush $script:Col.Accent; $fill.HorizontalAlignment = 'Left'
    $fill.Width = [math]::Max(0, [math]::Min(100, [int]$Goal.progress)) * 3.0
    $track.Child = $fill; $body.Children.Add($track) | Out-Null

    # actions row
    $actions = New-Object Windows.Controls.StackPanel; $actions.Orientation = 'Horizontal'
    $actions.Children.Add((New-MiniButton -Text 'Edit' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -OnClick { param($s, $e) $script:GoalEditId = $gid; Show-LifeView { New-GoalsView } }.GetNewClosure())) | Out-Null
    if ($Goal.status -ne 'done') { $actions.Children.Add((New-MiniButton -Text 'Complete' -Bg '#DEF7EC' -Fg '#03543F' -OnClick { param($s, $e) [void](Complete-Goal -Id $gid); Show-LifeView { New-GoalsView } }.GetNewClosure())) | Out-Null }
    if ($Goal.status -eq 'active') { $actions.Children.Add((New-MiniButton -Text 'Pause' -Bg '#FDF6B2' -Fg '#8E4B10' -OnClick { param($s, $e) [void](Set-GoalStatus -Id $gid -Status 'paused'); Show-LifeView { New-GoalsView } }.GetNewClosure())) | Out-Null }
    elseif ($Goal.status -eq 'paused') { $actions.Children.Add((New-MiniButton -Text 'Resume' -Bg '#DEF7EC' -Fg '#03543F' -OnClick { param($s, $e) [void](Set-GoalStatus -Id $gid -Status 'active'); Show-LifeView { New-GoalsView } }.GetNewClosure())) | Out-Null }
    if ($Goal.status -ne 'archived') { $actions.Children.Add((New-MiniButton -Text 'Archive' -Bg '#E5E7EB' -Fg '#374151' -OnClick { param($s, $e) [void](Archive-Goal -Id $gid); Show-LifeView { New-GoalsView } }.GetNewClosure())) | Out-Null }
    else { $actions.Children.Add((New-MiniButton -Text 'Restore' -Bg '#DEF7EC' -Fg '#03543F' -OnClick { param($s, $e) [void](Restore-Goal -Id $gid); Show-LifeView { New-GoalsView } }.GetNewClosure())) | Out-Null }
    $actions.Children.Add((New-MiniButton -Text 'Delete' -Bg '#FDE2E1' -Fg '#9B1C1C' -OnClick { param($s, $e) [void](Remove-Goal -Id $gid); Show-LifeView { New-GoalsView } }.GetNewClosure())) | Out-Null
    $body.Children.Add($actions) | Out-Null

    return (New-Card -Title $Goal.title -Body $body)
}

# Inline editor for one goal.
function New-GoalEditor {
    param($Goal)
    $body = New-Object Windows.Controls.StackPanel
    $titleBox = New-LifeInput -Text $Goal.title
    $domainBox = New-LifeCombo -Options (Get-GoalDomains) -Selected $Goal.domain -Width 200
    $reasonBox = New-LifeInput -Text $Goal.reason
    $dateBox = New-LifeInput -Text $Goal.targetDate -Width 200
    $nextBox = New-LifeInput -Text $Goal.nextStep
    $notesBox = New-LifeInput -Text $Goal.notes -MinLines 2
    $err = New-Text -Text '' -Size 12 -Color '#9B1C1C' -Wrap $true
    $body.Children.Add((New-LifeFieldLabel 'Goal *')) | Out-Null; $body.Children.Add($titleBox) | Out-Null
    $body.Children.Add((New-LifeFieldLabel 'Domain')) | Out-Null; $body.Children.Add($domainBox) | Out-Null
    $body.Children.Add((New-LifeFieldLabel 'Why it matters')) | Out-Null; $body.Children.Add($reasonBox) | Out-Null
    $body.Children.Add((New-LifeFieldLabel 'Target date (YYYY-MM-DD)')) | Out-Null; $body.Children.Add($dateBox) | Out-Null
    $body.Children.Add((New-LifeFieldLabel 'Next step')) | Out-Null; $body.Children.Add($nextBox) | Out-Null
    $body.Children.Add((New-LifeFieldLabel 'Notes')) | Out-Null; $body.Children.Add($notesBox) | Out-Null
    $body.Children.Add($err) | Out-Null
    $gid = $Goal.id
    $row = New-Object Windows.Controls.StackPanel; $row.Orientation = 'Horizontal'; $row.Margin = New-Object Windows.Thickness (0, 4, 0, 0)
    $row.Children.Add((New-MiniButton -Text 'Save' -Bg $script:Col.Accent -Fg $script:Col.OnPrimary -OnClick {
                param($s, $e)
                if ([string]::IsNullOrWhiteSpace($titleBox.Text)) { $err.Text = 'A goal needs a title.'; return }
                $d = [string]$dateBox.Text
                if ($d -and ($d -notmatch '^\d{4}-\d{2}-\d{2}$')) { $err.Text = 'Target date must look like 2026-12-31 (or blank).'; return }
                [void](Update-Goal -Id $gid -Fields @{ title = ([string]$titleBox.Text).Trim(); domain = [string]$domainBox.SelectedItem; reason = ([string]$reasonBox.Text).Trim(); targetDate = $d.Trim(); nextStep = ([string]$nextBox.Text).Trim(); notes = ([string]$notesBox.Text).Trim() })
                $script:GoalEditId = $null; Show-LifeView { New-GoalsView }
            }.GetNewClosure())) | Out-Null
    $row.Children.Add((New-MiniButton -Text 'Cancel' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -OnClick { param($s, $e) $script:GoalEditId = $null; Show-LifeView { New-GoalsView } })) | Out-Null
    $body.Children.Add($row) | Out-Null
    return (New-Card -Title ('Editing: ' + $Goal.title) -Body $body)
}
