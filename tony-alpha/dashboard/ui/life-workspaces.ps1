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
