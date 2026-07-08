# =====================================================================
# tony-ui.ps1  —  Tony Alpha presentation layer (WPF)
# ---------------------------------------------------------------------
# NO BUSINESS LOGIC HERE. Takes data from core/tony-core.ps1 and builds
# the WPF visual tree: a shell with a nav bar and a swappable body.
#
# Entry point:  New-TonyShell -InitialView 'Dashboard' [-Now <dt>]
#   returns [pscustomobject]@{ Root = <FrameworkElement>; ClockBlock = <TextBlock> }
# Navigation:  Set-ActiveView <name>   (wired to nav + clickable cards)
# =====================================================================

$ErrorActionPreference = 'Stop'

$script:Col = @{
    AppBg = '#F3F5F9'; CardBg = '#FFFFFF'; Ink = '#1F2933'; Muted = '#6B7280'
    Line = '#E5E7EB'; Accent = '#2563EB'; AccentSoft = '#EAF0FE'; NavBg = '#111827'
}
$script:NavItems = @('Dashboard', 'Agents', 'Issues', 'Action Items', 'Weekly Review', 'Roadmap')

function New-Brush { param([string]$Hex) return (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($Hex))) }

function New-Text {
    param([string]$Text, [double]$Size = 13, [string]$Weight = 'Normal', [string]$Color = $script:Col.Ink,
          [Windows.Thickness]$Margin = (New-Object Windows.Thickness 0), [bool]$Wrap = $false)
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $Text
    $t.FontFamily = New-Object Windows.Media.FontFamily 'Segoe UI'
    $t.FontSize = $Size
    $t.FontWeight = [Windows.FontWeights]::$Weight
    $t.Foreground = New-Brush $Color
    $t.Margin = $Margin
    if ($Wrap) { $t.TextWrapping = 'Wrap' }
    return $t
}

function New-Chip {
    param([string]$Text, [string]$Bg, [string]$Fg)
    $b = New-Object Windows.Controls.Border
    $b.Background = New-Brush $Bg
    $b.CornerRadius = New-Object Windows.CornerRadius 9
    $b.Padding = New-Object Windows.Thickness (9, 3, 9, 3)
    $b.Margin = New-Object Windows.Thickness (0, 0, 6, 6)
    $b.VerticalAlignment = 'Center'
    $b.Child = (New-Text -Text $Text -Size 11.5 -Weight 'SemiBold' -Color $Fg)
    return $b
}

function Get-StatusChipColors { param([string]$Status)
    switch ($Status) {
        'healthy' { @('#DEF7EC', '#03543F') } 'warning' { @('#FDF6B2', '#8E4B10') }
        'broken'  { @('#FDE2E1', '#9B1C1C') } 'paused'  { @('#E5E7EB', '#374151') }
        default   { @('#E5E7EB', '#4B5563') }
    }
}
function Get-PriorityChipColors { param([string]$Priority)
    switch ($Priority) {
        'Critical' { @('#FDE2E1', '#9B1C1C') } 'High' { @('#FEECDC', '#8A4B10') }
        'Normal'   { @('#EAF0FE', '#1E429F') } 'Low'  { @('#E5E7EB', '#374151') }
        default    { @('#E5E7EB', '#374151') }
    }
}

function New-Card {
    param([string]$Title, [Windows.UIElement]$Body, [string]$Tag = $null,
          [int]$Col = 0, [int]$Row = 0, [string]$NavTo = $null)
    $border = New-Object Windows.Controls.Border
    $border.Background = New-Brush $script:Col.CardBg
    $border.CornerRadius = New-Object Windows.CornerRadius 12
    $border.Padding = New-Object Windows.Thickness 16
    $border.Margin = New-Object Windows.Thickness 8
    $border.BorderBrush = New-Brush $script:Col.Line
    $border.BorderThickness = New-Object Windows.Thickness 1
    $shadow = New-Object Windows.Media.Effects.DropShadowEffect
    $shadow.Color = [Windows.Media.ColorConverter]::ConvertFromString('#22000000')
    $shadow.BlurRadius = 14; $shadow.ShadowDepth = 2; $shadow.Opacity = 0.5; $shadow.Direction = 270
    $border.Effect = $shadow
    [Windows.Controls.Grid]::SetColumn($border, $Col)
    [Windows.Controls.Grid]::SetRow($border, $Row)

    $stack = New-Object Windows.Controls.StackPanel
    $header = New-Object Windows.Controls.DockPanel
    $header.Margin = New-Object Windows.Thickness (0, 0, 0, 10)
    $titleBlock = New-Text -Text $Title.ToUpper() -Size 12.5 -Weight 'Bold' -Color $script:Col.Muted
    [Windows.Controls.DockPanel]::SetDock($titleBlock, 'Left')
    $header.Children.Add($titleBlock) | Out-Null
    if ($NavTo) {
        $go = New-Text -Text 'open >' -Size 11.5 -Weight 'SemiBold' -Color $script:Col.Accent
        $go.HorizontalAlignment = 'Right'
        $header.Children.Add($go) | Out-Null
    } elseif ($Tag) {
        $tagChip = New-Chip -Text $Tag -Bg '#FEF3C7' -Fg '#92400E'
        $tagChip.Margin = New-Object Windows.Thickness 0; $tagChip.HorizontalAlignment = 'Right'
        $header.Children.Add($tagChip) | Out-Null
    }
    $stack.Children.Add($header) | Out-Null
    $stack.Children.Add($Body) | Out-Null
    $border.Child = $stack

    if ($NavTo) {
        $border.Cursor = 'Hand'
        $border.Tag = $NavTo
        $border.Add_MouseLeftButtonUp({ param($s, $e) Set-ActiveView $s.Tag }) | Out-Null
    }
    return $border
}

function New-KeyValueRow {
    param([string]$Key, [string]$Value, [string]$ValueColor = $script:Col.Ink)
    $dp = New-Object Windows.Controls.DockPanel
    $dp.Margin = New-Object Windows.Thickness (0, 0, 0, 7)
    $k = New-Text -Text $Key -Size 13 -Color $script:Col.Muted
    [Windows.Controls.DockPanel]::SetDock($k, 'Left')
    $v = New-Text -Text $Value -Size 13 -Weight 'SemiBold' -Color $ValueColor
    $v.HorizontalAlignment = 'Right'
    $dp.Children.Add($k) | Out-Null
    $dp.Children.Add($v) | Out-Null
    return $dp
}

# =====================  VIEW: DASHBOARD  =====================
function New-DashboardView {
    param([Parameter(Mandatory)] $Model)
    $outer = New-Object Windows.Controls.StackPanel
    $outer.Margin = New-Object Windows.Thickness (4, 0, 4, 0)

    $outer.Children.Add((New-Text -Text $Model.greeting -Size 28 -Weight 'Bold' -Color $script:Col.Ink)) | Out-Null
    $outer.Children.Add((New-Text -Text 'Command hub - click a card or use the tabs above.' -Size 13 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 2, 0, 12)))) | Out-Null

    $cards = New-Object Windows.Controls.Grid
    foreach ($i in 0..2) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = [Windows.GridLength]::new(1, 'Star'); $cards.ColumnDefinitions.Add($cd) | Out-Null }
    foreach ($i in 0..1) { $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = [Windows.GridLength]::new(1, 'Star'); $cards.RowDefinitions.Add($rd) | Out-Null }

    # Card: Agent Summary (LIVE, clickable -> Agents)
    $asBody = New-Object Windows.Controls.StackPanel
    $bigRow = New-Object Windows.Controls.StackPanel; $bigRow.Orientation = 'Horizontal'
    $bigRow.Children.Add((New-Text -Text ([string]$Model.agentSummary.total) -Size 42 -Weight 'Bold')) | Out-Null
    $bigRow.Children.Add((New-Text -Text 'agents tracked' -Size 13 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (8, 20, 0, 0)))) | Out-Null
    $asBody.Children.Add($bigRow) | Out-Null
    $asBody.Children.Add((New-Text -Text 'STATUS' -Size 10.5 -Weight 'Bold' -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 8, 0, 4)))) | Out-Null
    $sw = New-Object Windows.Controls.WrapPanel
    foreach ($k in $Model.agentSummary.byStatus.Keys) { $n = $Model.agentSummary.byStatus[$k]; if ($n -gt 0) { $c = Get-StatusChipColors $k; $sw.Children.Add((New-Chip -Text ("{0} {1}" -f $k, $n) -Bg $c[0] -Fg $c[1])) | Out-Null } }
    $asBody.Children.Add($sw) | Out-Null
    $asBody.Children.Add((New-Text -Text 'PRIORITY' -Size 10.5 -Weight 'Bold' -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 6, 0, 4)))) | Out-Null
    $pw = New-Object Windows.Controls.WrapPanel
    foreach ($k in $Model.agentSummary.byPriority.Keys) { $n = $Model.agentSummary.byPriority[$k]; $c = Get-PriorityChipColors $k; $pw.Children.Add((New-Chip -Text ("{0} {1}" -f $k, $n) -Bg $c[0] -Fg $c[1])) | Out-Null }
    $asBody.Children.Add($pw) | Out-Null
    $cards.Children.Add((New-Card -Title 'Agents' -Body $asBody -Col 0 -Row 0 -NavTo 'Agents')) | Out-Null

    # Card: Registry Health (LIVE)
    $rh = $Model.registryHealth
    $rhBody = New-Object Windows.Controls.StackPanel
    $rhBody.Children.Add((New-KeyValueRow -Key 'Registry version' -Value $rh.version)) | Out-Null
    $rhBody.Children.Add((New-KeyValueRow -Key 'Verified vs scheduler' -Value ($(if ($rh.verified) { 'Yes' } else { 'No' })) -ValueColor $(if ($rh.verified) { '#03543F' } else { '#9B1C1C' }))) | Out-Null
    $rhBody.Children.Add((New-KeyValueRow -Key 'Registry status' -Value $rh.registryStatus)) | Out-Null
    $rhBody.Children.Add((New-KeyValueRow -Key 'Health score' -Value ("{0} ({1})" -f $rh.overallHealth, $rh.healthCoverage))) | Out-Null
    $rhBody.Children.Add((New-KeyValueRow -Key 'Agents with issues' -Value ([string]$rh.agentsWithIssues))) | Out-Null
    $rhBody.Children.Add((New-KeyValueRow -Key 'Source' -Value $rh.sourceFile)) | Out-Null
    $rhBody.Children.Add((New-KeyValueRow -Key 'Last updated' -Value $rh.lastUpdated)) | Out-Null
    $cards.Children.Add((New-Card -Title 'Registry Health' -Body $rhBody -Col 1 -Row 0)) | Out-Null

    # Card: Current Sprint (placeholder) -> Weekly Review
    $sp = $Model.currentSprint
    $spBody = New-Object Windows.Controls.StackPanel
    $spBody.Children.Add((New-Text -Text $sp.name -Size 15 -Weight 'Bold' -Wrap $true)) | Out-Null
    $spBody.Children.Add((New-Text -Text $sp.objective -Size 12.5 -Color $script:Col.Muted -Wrap $true -Margin (New-Object Windows.Thickness (0, 2, 0, 8)))) | Out-Null
    $spBody.Children.Add((New-Chip -Text ("Status: {0}" -f $sp.status) -Bg '#EAF0FE' -Fg '#1E429F')) | Out-Null
    $cards.Children.Add((New-Card -Title 'Current Sprint' -Body $spBody -Col 2 -Row 0 -NavTo 'Weekly Review')) | Out-Null

    # Card: Open Issues (from file) -> Issues
    $oiBody = New-Object Windows.Controls.StackPanel
    $oiBody.Children.Add((New-Text -Text ("{0} open flags" -f $Model.openIssues.Count) -Size 15 -Weight 'Bold' -Margin (New-Object Windows.Thickness (0, 0, 0, 6)))) | Out-Null
    foreach ($iss in ($Model.openIssues | Select-Object -First 7)) {
        $row = New-Object Windows.Controls.DockPanel; $row.Margin = New-Object Windows.Thickness (0, 0, 0, 4)
        $chip = New-Chip -Text $iss.id -Bg '#EEF2FF' -Fg '#3730A3'; $chip.VerticalAlignment = 'Top'
        [Windows.Controls.DockPanel]::SetDock($chip, 'Left'); $row.Children.Add($chip) | Out-Null
        $tx = New-Text -Text $iss.title -Size 12 -Wrap $true; $tx.Margin = New-Object Windows.Thickness (4, 2, 0, 0)
        $row.Children.Add($tx) | Out-Null
        $oiBody.Children.Add($row) | Out-Null
    }
    $cards.Children.Add((New-Card -Title 'Open Issues' -Body $oiBody -Col 0 -Row 1 -NavTo 'Issues')) | Out-Null

    # Card: Action Items (from file) -> Action Items
    $aiBody = New-Object Windows.Controls.StackPanel
    $open = @($Model.actionItems | Where-Object { -not $_.done })
    $aiBody.Children.Add((New-Text -Text ("{0} open, {1} total" -f $open.Count, $Model.actionItems.Count) -Size 15 -Weight 'Bold' -Margin (New-Object Windows.Thickness (0, 0, 0, 6)))) | Out-Null
    foreach ($ai in ($open | Select-Object -First 6)) {
        $row = New-Object Windows.Controls.DockPanel; $row.Margin = New-Object Windows.Thickness (0, 0, 0, 5)
        $mk = New-Text -Text '[ ]' -Size 12.5 -Weight 'SemiBold' -Color $script:Col.Accent; $mk.Margin = New-Object Windows.Thickness (0, 0, 6, 0); $mk.VerticalAlignment = 'Top'
        [Windows.Controls.DockPanel]::SetDock($mk, 'Left'); $row.Children.Add($mk) | Out-Null
        $row.Children.Add((New-Text -Text ("{0}  {1}" -f $ai.id, $ai.title) -Size 12 -Wrap $true)) | Out-Null
        $aiBody.Children.Add($row) | Out-Null
    }
    $cards.Children.Add((New-Card -Title 'Action Items' -Body $aiBody -Col 1 -Row 1 -NavTo 'Action Items')) | Out-Null

    # Card: Docs / quick links
    $qlBody = New-Object Windows.Controls.StackPanel
    $qlBody.Children.Add((New-Text -Text 'Reads live from files:' -Size 12 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 0, 0, 6)))) | Out-Null
    foreach ($lnk in @(@('Weekly Review', 'weekly_status.md'), @('Roadmap', 'ROADMAP.md'))) {
        $row = New-Object Windows.Controls.Border
        $row.Cursor = 'Hand'; $row.Tag = $lnk[0]; $row.Margin = New-Object Windows.Thickness (0, 0, 0, 6)
        $row.Background = New-Brush $script:Col.AccentSoft; $row.CornerRadius = New-Object Windows.CornerRadius 8; $row.Padding = New-Object Windows.Thickness (10, 6, 10, 6)
        $row.Child = (New-Text -Text ("{0}  ->  {1}" -f $lnk[0], $lnk[1]) -Size 12.5 -Weight 'SemiBold' -Color '#1E429F')
        $row.Add_MouseLeftButtonUp({ param($s, $e) Set-ActiveView $s.Tag }) | Out-Null
        $qlBody.Children.Add($row) | Out-Null
    }
    $cards.Children.Add((New-Card -Title 'Documents' -Body $qlBody -Col 2 -Row 1)) | Out-Null

    $outer.Children.Add($cards) | Out-Null
    return $outer
}

# =====================  VIEW: AGENTS  =====================
function New-AgentCard {
    param([Parameter(Mandatory)] $Agent)
    $a = $Agent
    $card = New-Object Windows.Controls.Border
    $card.Background = New-Brush $script:Col.CardBg
    $card.CornerRadius = New-Object Windows.CornerRadius 10
    $card.BorderBrush = New-Brush $script:Col.Line; $card.BorderThickness = New-Object Windows.Thickness 1
    $card.Padding = New-Object Windows.Thickness 14; $card.Margin = New-Object Windows.Thickness (0, 0, 0, 10)

    $stack = New-Object Windows.Controls.StackPanel

    # header: id + name (left)   chips (right)
    $head = New-Object Windows.Controls.DockPanel
    $chips = New-Object Windows.Controls.StackPanel; $chips.Orientation = 'Horizontal'; $chips.HorizontalAlignment = 'Right'
    $sc = Get-StatusChipColors $a.status; $chips.Children.Add((New-Chip -Text $a.status -Bg $sc[0] -Fg $sc[1])) | Out-Null
    $pc = Get-PriorityChipColors $a.priority; $chips.Children.Add((New-Chip -Text $a.priority -Bg $pc[0] -Fg $pc[1])) | Out-Null
    $chips.Children.Add((New-Chip -Text $a.owner -Bg '#EEF2FF' -Fg '#3730A3')) | Out-Null
    [Windows.Controls.DockPanel]::SetDock($chips, 'Right'); $head.Children.Add($chips) | Out-Null
    $titleWrap = New-Object Windows.Controls.StackPanel; $titleWrap.Orientation = 'Horizontal'
    $titleWrap.Children.Add((New-Chip -Text $a.stable_id -Bg '#111827' -Fg '#FFFFFF')) | Out-Null
    $nm = New-Text -Text $a.name -Size 15 -Weight 'Bold'; $nm.VerticalAlignment = 'Center'; $nm.Margin = New-Object Windows.Thickness (2, 0, 0, 6)
    $titleWrap.Children.Add($nm) | Out-Null
    $head.Children.Add($titleWrap) | Out-Null
    $stack.Children.Add($head) | Out-Null

    # fields grid (2 columns of key/value)
    $deps = if (@($a.dependencies).Count -gt 0) { ($a.dependencies -join ', ') } else { '-' }
    $lastRun = if ($null -eq $a.last_run) { '-' } else { [string]$a.last_run }
    $health  = if ($null -eq $a.health_score) { '-' } else { "$($a.health_score)%" }
    $issues  = if (@($a.issues).Count -gt 0) { ($a.issues -join '; ') } else { 'None' }
    $notes   = if ([string]::IsNullOrWhiteSpace($a.notes)) { '-' } else { $a.notes }

    $grid = New-Object Windows.Controls.Grid
    $grid.Margin = New-Object Windows.Thickness (0, 4, 0, 0)
    foreach ($i in 0..1) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = [Windows.GridLength]::new(1, 'Star'); $grid.ColumnDefinitions.Add($cd) | Out-Null }
    $pairs = @(
        @('Schedule', $a.schedule), @('Last run', $lastRun),
        @('Health score', $health), @('Dependencies', $deps)
    )
    for ($i = 0; $i -lt $pairs.Count; $i++) {
        $r = [int][math]::Floor($i / 2); $c = $i % 2
        if ($c -eq 0) { $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = [Windows.GridLength]::Auto; $grid.RowDefinitions.Add($rd) | Out-Null }
        $cell = New-Object Windows.Controls.StackPanel; $cell.Orientation = 'Horizontal'; $cell.Margin = New-Object Windows.Thickness (0, 0, 12, 4)
        $cell.Children.Add((New-Text -Text ("{0}: " -f $pairs[$i][0]) -Size 12.5 -Color $script:Col.Muted)) | Out-Null
        $cell.Children.Add((New-Text -Text ([string]$pairs[$i][1]) -Size 12.5 -Weight 'SemiBold')) | Out-Null
        [Windows.Controls.Grid]::SetRow($cell, $r); [Windows.Controls.Grid]::SetColumn($cell, $c)
        $grid.Children.Add($cell) | Out-Null
    }
    $stack.Children.Add($grid) | Out-Null

    # issues + notes (full width, wrap)
    $ig = New-Object Windows.Controls.StackPanel; $ig.Orientation = 'Horizontal'; $ig.Margin = New-Object Windows.Thickness (0, 4, 0, 0)
    $ig.Children.Add((New-Text -Text 'Issues: ' -Size 12.5 -Color $script:Col.Muted)) | Out-Null
    $ig.Children.Add((New-Text -Text $issues -Size 12.5 -Weight 'SemiBold' -Color $(if ($issues -eq 'None') { '#03543F' } else { '#9B1C1C' }))) | Out-Null
    $stack.Children.Add($ig) | Out-Null
    $nt = New-Object Windows.Controls.StackPanel; $nt.Margin = New-Object Windows.Thickness (0, 3, 0, 0)
    $nt.Children.Add((New-Text -Text 'Notes / report' -Size 11 -Weight 'Bold' -Color $script:Col.Muted)) | Out-Null
    $nt.Children.Add((New-Text -Text $notes -Size 12.5 -Wrap $true)) | Out-Null
    $stack.Children.Add($nt) | Out-Null

    $card.Child = $stack
    return $card
}

function New-AgentsView {
    param([Parameter(Mandatory)] $Agents)
    $head = New-Object Windows.Controls.StackPanel; $head.Margin = New-Object Windows.Thickness (4, 0, 4, 10)
    $head.Children.Add((New-Text -Text 'Agents' -Size 24 -Weight 'Bold')) | Out-Null
    $head.Children.Add((New-Text -Text ("{0} registered agents - live from agents_registry.json" -f @($Agents).Count) -Size 13 -Color $script:Col.Muted)) | Out-Null

    $list = New-Object Windows.Controls.StackPanel; $list.Margin = New-Object Windows.Thickness (4, 0, 4, 0)
    foreach ($a in $Agents) { $list.Children.Add((New-AgentCard -Agent $a)) | Out-Null }

    $scroll = New-Object Windows.Controls.ScrollViewer
    $scroll.VerticalScrollBarVisibility = 'Auto'; $scroll.Content = $list

    $outer = New-Object Windows.Controls.DockPanel
    [Windows.Controls.DockPanel]::SetDock($head, 'Top'); $outer.Children.Add($head) | Out-Null
    $outer.Children.Add($scroll) | Out-Null
    return $outer
}

# =====================  VIEW: MARKDOWN DOC  =====================
function New-MarkdownView {
    param([string]$Title, [string]$Text)
    $stack = New-Object Windows.Controls.StackPanel; $stack.Margin = New-Object Windows.Thickness (4, 0, 4, 0)

    foreach ($raw in ($Text -split "`r?`n")) {
        $line = $raw.TrimEnd()
        if ($line -match '^#\s+(.+)')      { $stack.Children.Add((New-Text -Text $Matches[1] -Size 22 -Weight 'Bold' -Wrap $true -Margin (New-Object Windows.Thickness (0, 8, 0, 4)))) | Out-Null; continue }
        if ($line -match '^##\s+(.+)')     { $stack.Children.Add((New-Text -Text $Matches[1] -Size 16 -Weight 'Bold' -Wrap $true -Margin (New-Object Windows.Thickness (0, 10, 0, 3)))) | Out-Null; continue }
        if ($line -match '^###\s+(.+)')    { $stack.Children.Add((New-Text -Text $Matches[1] -Size 13.5 -Weight 'SemiBold' -Color $script:Col.Accent -Wrap $true -Margin (New-Object Windows.Thickness (0, 6, 0, 2)))) | Out-Null; continue }
        if ($line -match '^\s*[-*]\s+(.+)'){ $stack.Children.Add((New-Text -Text ("- " + ($Matches[1] -replace '\*\*', '' -replace '`', '')) -Size 12.5 -Wrap $true -Margin (New-Object Windows.Thickness (12, 1, 0, 1)))) | Out-Null; continue }
        if ($line -match '^\s*\|')         { $stack.Children.Add((New-Text -Text ($line -replace '\|', '  ') -Size 12 -Color $script:Col.Muted -Wrap $true)) | Out-Null; continue }
        if ($line -match '^---+$' -or $line -eq '') { continue }
        $stack.Children.Add((New-Text -Text ($line -replace '\*\*', '' -replace '`', '') -Size 12.5 -Wrap $true -Margin (New-Object Windows.Thickness (0, 1, 0, 1)))) | Out-Null
    }

    $scroll = New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility = 'Auto'; $scroll.Content = $stack
    $outer = New-Object Windows.Controls.DockPanel
    $hd = New-Object Windows.Controls.StackPanel; $hd.Margin = New-Object Windows.Thickness (4, 0, 4, 8)
    $hd.Children.Add((New-Text -Text $Title -Size 24 -Weight 'Bold')) | Out-Null
    [Windows.Controls.DockPanel]::SetDock($hd, 'Top'); $outer.Children.Add($hd) | Out-Null
    $outer.Children.Add($scroll) | Out-Null
    return $outer
}

# =====================  NAV + SHELL  =====================
function Set-ActiveView {
    param([Parameter(Mandatory)][string]$Name)
    $script:TonyActiveView = $Name
    foreach ($n in $script:TonyNav) {
        if ($n.Name -eq $Name) { $n.Border.Background = New-Brush $script:Col.Accent; $n.Text.Foreground = New-Brush '#FFFFFF' }
        else { $n.Border.Background = New-Brush '#1F2A3A'; $n.Text.Foreground = New-Brush '#D1D5DB' }
    }
    $body = switch ($Name) {
        'Dashboard'    { New-DashboardView -Model (Get-TonyModel -Now $script:TonyNow) }
        'Agents'       { New-AgentsView    -Agents (Get-AgentsList) }
        'Issues'       { New-MarkdownView  -Title 'Open Issues'   -Text (Get-DocText 'issues_log.md') }
        'Action Items' { New-MarkdownView  -Title 'Action Items'  -Text (Get-DocText 'action_items.md') }
        'Weekly Review'{ New-MarkdownView  -Title 'Weekly Review' -Text (Get-DocText 'weekly_status.md') }
        'Roadmap'      { New-MarkdownView  -Title 'Roadmap'       -Text (Get-DocText 'ROADMAP.md') }
        default        { New-DashboardView -Model (Get-TonyModel -Now $script:TonyNow) }
    }
    $script:TonyBody.Child = $body
}

function New-TonyShell {
    param([string]$InitialView = 'Dashboard', [datetime]$Now = (Get-Date))
    $script:TonyNow = $Now

    $root = New-Object Windows.Controls.Border
    $root.Background = New-Brush $script:Col.AppBg
    $grid = New-Object Windows.Controls.Grid
    foreach ($h in 'Auto', 'Auto', '*') {
        $rd = New-Object Windows.Controls.RowDefinition
        $rd.Height = if ($h -eq '*') { [Windows.GridLength]::new(1, 'Star') } else { [Windows.GridLength]::Auto }
        $grid.RowDefinitions.Add($rd) | Out-Null
    }
    $root.Child = $grid

    # top bar
    $top = New-Object Windows.Controls.Border
    $top.Background = New-Brush $script:Col.NavBg; $top.Padding = New-Object Windows.Thickness (20, 12, 20, 12)
    $topDock = New-Object Windows.Controls.DockPanel
    $brand = New-Text -Text 'TONY ALPHA' -Size 15 -Weight 'Bold' -Color '#FFFFFF'
    [Windows.Controls.DockPanel]::SetDock($brand, 'Left'); $topDock.Children.Add($brand) | Out-Null
    $clock = New-Text -Text ('{0}   -   {1}' -f $Now.ToString('dddd, MMMM d, yyyy'), $Now.ToString('h:mm:ss tt')) -Size 12.5 -Color '#9CA3AF'
    $clock.HorizontalAlignment = 'Right'; $topDock.Children.Add($clock) | Out-Null
    $top.Child = $topDock
    [Windows.Controls.Grid]::SetRow($top, 0); $grid.Children.Add($top) | Out-Null

    # nav bar
    $navBar = New-Object Windows.Controls.Border
    $navBar.Background = New-Brush '#0B1220'; $navBar.Padding = New-Object Windows.Thickness (14, 8, 14, 8)
    $navStack = New-Object Windows.Controls.StackPanel; $navStack.Orientation = 'Horizontal'
    $script:TonyNav = @()
    foreach ($name in $script:NavItems) {
        $b = New-Object Windows.Controls.Border
        $b.CornerRadius = New-Object Windows.CornerRadius 7; $b.Padding = New-Object Windows.Thickness (14, 6, 14, 6)
        $b.Margin = New-Object Windows.Thickness (0, 0, 6, 0); $b.Cursor = 'Hand'; $b.Tag = $name
        $t = New-Text -Text $name -Size 12.5 -Weight 'SemiBold' -Color '#D1D5DB'
        $b.Child = $t
        $b.Add_MouseLeftButtonUp({ param($s, $e) Set-ActiveView $s.Tag }) | Out-Null
        $navStack.Children.Add($b) | Out-Null
        $script:TonyNav += [pscustomobject]@{ Name = $name; Border = $b; Text = $t }
    }
    $navBar.Child = $navStack
    [Windows.Controls.Grid]::SetRow($navBar, 1); $grid.Children.Add($navBar) | Out-Null

    # body host
    $body = New-Object Windows.Controls.Border
    $body.Padding = New-Object Windows.Thickness (20, 18, 20, 18)
    [Windows.Controls.Grid]::SetRow($body, 2); $grid.Children.Add($body) | Out-Null
    $script:TonyBody = $body

    Set-ActiveView $InitialView
    return [pscustomobject]@{ Root = $root; ClockBlock = $clock }
}
