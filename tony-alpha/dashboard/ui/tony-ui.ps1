# =====================================================================
# tony-ui.ps1  —  Tony Alpha presentation layer (WPF)
# ---------------------------------------------------------------------
# NO BUSINESS LOGIC HERE. This file takes a model object (from
# core/tony-core.ps1) and builds the WPF visual tree. It never reads
# the registry or computes anything itself.
#
# Entry point:  New-TonyDashboardVisual -Model $model
#   returns [pscustomobject]@{ Root = <FrameworkElement>; TimeBlock = <TextBlock> }
# =====================================================================

$ErrorActionPreference = 'Stop'

# ---- palette ----
$script:Col = @{
    AppBg     = '#F3F5F9'
    CardBg    = '#FFFFFF'
    Ink       = '#1F2933'
    Muted     = '#6B7280'
    Line      = '#E5E7EB'
    Accent    = '#2563EB'
    AccentSoft= '#EAF0FE'
}

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
    $b.Padding = New-Object Windows.Thickness (9,3,9,3)
    $b.Margin = New-Object Windows.Thickness (0,0,6,6)
    $b.Child = (New-Text -Text $Text -Size 11.5 -Weight 'SemiBold' -Color $Fg)
    return $b
}

function Get-StatusChipColors { param([string]$Status)
    switch ($Status) {
        'healthy' { return @('#DEF7EC','#03543F') }
        'warning' { return @('#FDF6B2','#8E4B10') }
        'broken'  { return @('#FDE2E1','#9B1C1C') }
        'paused'  { return @('#E5E7EB','#374151') }
        default   { return @('#E5E7EB','#4B5563') }   # unknown
    }
}
function Get-PriorityChipColors { param([string]$Priority)
    switch ($Priority) {
        'Critical' { return @('#FDE2E1','#9B1C1C') }
        'High'     { return @('#FEECDC','#8A4B10') }
        'Normal'   { return @('#EAF0FE','#1E429F') }
        'Low'      { return @('#E5E7EB','#374151') }
        default    { return @('#E5E7EB','#374151') }
    }
}

function New-Card {
    param([string]$Title, [Windows.UIElement]$Body, [string]$Tag = $null, [int]$Col = 0, [int]$Row = 0)
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
    $header.Margin = New-Object Windows.Thickness (0,0,0,10)
    $titleBlock = New-Text -Text $Title -Size 12.5 -Weight 'Bold' -Color $script:Col.Muted
    $titleBlock.Text = $Title.ToUpper()
    [Windows.Controls.DockPanel]::SetDock($titleBlock, 'Left')
    $header.Children.Add($titleBlock) | Out-Null
    if ($Tag) {
        $tagChip = New-Chip -Text $Tag -Bg '#FEF3C7' -Fg '#92400E'
        $tagChip.Margin = New-Object Windows.Thickness 0
        $tagChip.HorizontalAlignment = 'Right'
        $header.Children.Add($tagChip) | Out-Null
    }
    $stack.Children.Add($header) | Out-Null
    $stack.Children.Add($Body) | Out-Null

    $border.Child = $stack
    return $border
}

function New-KeyValueRow {
    param([string]$Key, [string]$Value, [string]$ValueColor = $script:Col.Ink)
    $dp = New-Object Windows.Controls.DockPanel
    $dp.Margin = New-Object Windows.Thickness (0,0,0,7)
    $k = New-Text -Text $Key -Size 13 -Color $script:Col.Muted
    [Windows.Controls.DockPanel]::SetDock($k, 'Left')
    $v = New-Text -Text $Value -Size 13 -Weight 'SemiBold' -Color $ValueColor
    $v.HorizontalAlignment = 'Right'
    $dp.Children.Add($k) | Out-Null
    $dp.Children.Add($v) | Out-Null
    return $dp
}

function New-TonyDashboardVisual {
    param([Parameter(Mandatory)] $Model)

    # ---------- root ----------
    $root = New-Object Windows.Controls.Border
    $root.Background = New-Brush $script:Col.AppBg
    $grid = New-Object Windows.Controls.Grid
    $grid.Margin = New-Object Windows.Thickness 20
    foreach ($h in 'Auto','*','Auto') {
        $rd = New-Object Windows.Controls.RowDefinition
        $rd.Height = [Windows.GridLength]::new(0, 'Auto')
        if ($h -eq '*') { $rd.Height = [Windows.GridLength]::new(1, 'Star') }
        $grid.RowDefinitions.Add($rd) | Out-Null
    }
    $root.Child = $grid

    # ---------- header ----------
    $head = New-Object Windows.Controls.StackPanel
    $head.Margin = New-Object Windows.Thickness (4,0,4,14)
    $brandRow = New-Object Windows.Controls.DockPanel
    $brand = New-Text -Text 'TONY ALPHA' -Size 12 -Weight 'Bold' -Color $script:Col.Accent
    [Windows.Controls.DockPanel]::SetDock($brand, 'Left')
    $brandRow.Children.Add($brand) | Out-Null
    $head.Children.Add($brandRow) | Out-Null

    $head.Children.Add((New-Text -Text $Model.greeting -Size 30 -Weight 'Bold' -Color $script:Col.Ink -Margin (New-Object Windows.Thickness (0,2,0,2)))) | Out-Null
    $timeBlock = New-Text -Text ("{0}   -   {1}" -f $Model.dateText, $Model.timeText) -Size 14 -Color $script:Col.Muted
    $head.Children.Add($timeBlock) | Out-Null
    [Windows.Controls.Grid]::SetRow($head, 0)
    $grid.Children.Add($head) | Out-Null

    # ---------- content grid (3 x 2) ----------
    $cards = New-Object Windows.Controls.Grid
    [Windows.Controls.Grid]::SetRow($cards, 1)
    foreach ($i in 0..2) {
        $cd = New-Object Windows.Controls.ColumnDefinition
        $cd.Width = [Windows.GridLength]::new(1,'Star')
        $cards.ColumnDefinitions.Add($cd) | Out-Null
    }
    foreach ($i in 0..1) {
        $rd = New-Object Windows.Controls.RowDefinition
        $rd.Height = [Windows.GridLength]::new(1,'Star')
        $cards.RowDefinitions.Add($rd) | Out-Null
    }
    $grid.Children.Add($cards) | Out-Null

    # ----- Card 1: Agent Summary (LIVE) -----
    $asBody = New-Object Windows.Controls.StackPanel
    $bigRow = New-Object Windows.Controls.StackPanel; $bigRow.Orientation = 'Horizontal'
    $bigRow.Children.Add((New-Text -Text ([string]$Model.agentSummary.total) -Size 42 -Weight 'Bold' -Color $script:Col.Ink)) | Out-Null
    $bigRow.Children.Add((New-Text -Text 'agents tracked' -Size 13 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (8,20,0,0)))) | Out-Null
    $asBody.Children.Add($bigRow) | Out-Null

    $asBody.Children.Add((New-Text -Text 'STATUS' -Size 10.5 -Weight 'Bold' -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0,8,0,4)))) | Out-Null
    $statusWrap = New-Object Windows.Controls.WrapPanel
    foreach ($k in $Model.agentSummary.byStatus.Keys) {
        $n = $Model.agentSummary.byStatus[$k]
        if ($n -gt 0) { $c = Get-StatusChipColors $k; $statusWrap.Children.Add((New-Chip -Text ("{0} {1}" -f $k, $n) -Bg $c[0] -Fg $c[1])) | Out-Null }
    }
    $asBody.Children.Add($statusWrap) | Out-Null

    $asBody.Children.Add((New-Text -Text 'PRIORITY' -Size 10.5 -Weight 'Bold' -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0,6,0,4)))) | Out-Null
    $prioWrap = New-Object Windows.Controls.WrapPanel
    foreach ($k in $Model.agentSummary.byPriority.Keys) {
        $n = $Model.agentSummary.byPriority[$k]
        $c = Get-PriorityChipColors $k
        $prioWrap.Children.Add((New-Chip -Text ("{0} {1}" -f $k, $n) -Bg $c[0] -Fg $c[1])) | Out-Null
    }
    $asBody.Children.Add($prioWrap) | Out-Null
    $cards.Children.Add((New-Card -Title 'Agent Summary' -Body $asBody -Col 0 -Row 0)) | Out-Null

    # ----- Card 2: Registry Health (LIVE) -----
    $rh = $Model.registryHealth
    $rhBody = New-Object Windows.Controls.StackPanel
    $rhBody.Children.Add((New-KeyValueRow -Key 'Registry version' -Value $rh.version)) | Out-Null
    $rhBody.Children.Add((New-KeyValueRow -Key 'Verified vs scheduler' -Value ($(if ($rh.verified) {'Yes'} else {'No'})) -ValueColor $(if ($rh.verified) {'#03543F'} else {'#9B1C1C'}))) | Out-Null
    $rhBody.Children.Add((New-KeyValueRow -Key 'Registry status' -Value $rh.registryStatus)) | Out-Null
    $rhBody.Children.Add((New-KeyValueRow -Key 'Health score' -Value ("{0} ({1})" -f $rh.overallHealth, $rh.healthCoverage))) | Out-Null
    $rhBody.Children.Add((New-KeyValueRow -Key 'Agents with issues' -Value ([string]$rh.agentsWithIssues))) | Out-Null
    $rhBody.Children.Add((New-KeyValueRow -Key 'Source' -Value $rh.sourceFile)) | Out-Null
    $rhBody.Children.Add((New-KeyValueRow -Key 'Last updated' -Value $rh.lastUpdated)) | Out-Null
    $cards.Children.Add((New-Card -Title 'Registry Health' -Body $rhBody -Col 1 -Row 0)) | Out-Null

    # ----- Card 3: Current Sprint (PLACEHOLDER) -----
    $sp = $Model.currentSprint
    $spBody = New-Object Windows.Controls.StackPanel
    $spBody.Children.Add((New-Text -Text $sp.name -Size 15 -Weight 'Bold' -Color $script:Col.Ink -Wrap $true)) | Out-Null
    $spBody.Children.Add((New-Text -Text $sp.objective -Size 12.5 -Color $script:Col.Muted -Wrap $true -Margin (New-Object Windows.Thickness (0,2,0,8)))) | Out-Null
    $spStatus = New-Chip -Text ("Status: {0}" -f $sp.status) -Bg '#EAF0FE' -Fg '#1E429F'
    $spBody.Children.Add($spStatus) | Out-Null
    foreach ($it in $sp.items) {
        $spBody.Children.Add((New-Text -Text ("- {0}" -f $it) -Size 12 -Color $script:Col.Ink -Wrap $true -Margin (New-Object Windows.Thickness (0,3,0,0)))) | Out-Null
    }
    $cards.Children.Add((New-Card -Title 'Current Sprint' -Body $spBody -Tag 'PLACEHOLDER' -Col 2 -Row 0)) | Out-Null

    # ----- Card 4: Open Issues (PLACEHOLDER) -----
    $oiBody = New-Object Windows.Controls.StackPanel
    $oiBody.Children.Add((New-Text -Text ("{0} open" -f $Model.openIssues.Count) -Size 15 -Weight 'Bold' -Color $script:Col.Ink -Margin (New-Object Windows.Thickness (0,0,0,6)))) | Out-Null
    foreach ($iss in $Model.openIssues) {
        $row = New-Object Windows.Controls.DockPanel; $row.Margin = New-Object Windows.Thickness (0,0,0,5)
        $chip = New-Chip -Text $iss.id -Bg '#EEF2FF' -Fg '#3730A3'; $chip.VerticalAlignment = 'Top'
        [Windows.Controls.DockPanel]::SetDock($chip, 'Left')
        $row.Children.Add($chip) | Out-Null
        $txt = New-Text -Text $iss.title -Size 12 -Color $script:Col.Ink -Wrap $true
        $txt.Margin = New-Object Windows.Thickness (4,2,0,0)
        $row.Children.Add($txt) | Out-Null
        $oiBody.Children.Add($row) | Out-Null
    }
    $cards.Children.Add((New-Card -Title 'Open Issues' -Body $oiBody -Tag 'PLACEHOLDER' -Col 0 -Row 1)) | Out-Null

    # ----- Card 5: Action Items (PLACEHOLDER) -----
    $aiBody = New-Object Windows.Controls.StackPanel
    foreach ($ai in $Model.actionItems) {
        $mark = if ($ai.done) { '[x]' } else { '[ ]' }
        $clr  = if ($ai.done) { $script:Col.Muted } else { $script:Col.Ink }
        $row = New-Object Windows.Controls.DockPanel; $row.Margin = New-Object Windows.Thickness (0,0,0,6)
        $markTb = New-Text -Text $mark -Size 12.5 -Weight 'SemiBold' -Color $script:Col.Accent
        $markTb.Margin = New-Object Windows.Thickness (0,0,6,0); $markTb.VerticalAlignment = 'Top'
        [Windows.Controls.DockPanel]::SetDock($markTb, 'Left')
        $row.Children.Add($markTb) | Out-Null
        $row.Children.Add((New-Text -Text ("{0}  {1}" -f $ai.id, $ai.title) -Size 12 -Color $clr -Wrap $true)) | Out-Null
        $aiBody.Children.Add($row) | Out-Null
    }
    $cards.Children.Add((New-Card -Title 'Action Items' -Body $aiBody -Tag 'PLACEHOLDER' -Col 1 -Row 1)) | Out-Null

    # ----- Card 6: Data Sources -----
    $dsBody = New-Object Windows.Controls.StackPanel
    $dsBody.Children.Add((New-Text -Text 'LIVE (from registry)' -Size 10.5 -Weight 'Bold' -Color '#03543F' -Margin (New-Object Windows.Thickness (0,0,0,3)))) | Out-Null
    $dsBody.Children.Add((New-Text -Text $Model.dataSources.live -Size 12 -Color $script:Col.Ink -Wrap $true -Margin (New-Object Windows.Thickness (0,0,0,8)))) | Out-Null
    $dsBody.Children.Add((New-Text -Text 'PLACEHOLDER (static this build)' -Size 10.5 -Weight 'Bold' -Color '#92400E' -Margin (New-Object Windows.Thickness (0,0,0,3)))) | Out-Null
    $dsBody.Children.Add((New-Text -Text $Model.dataSources.placeholder -Size 12 -Color $script:Col.Ink -Wrap $true)) | Out-Null
    $cards.Children.Add((New-Card -Title 'Data Sources' -Body $dsBody -Col 2 -Row 1)) | Out-Null

    # ---------- footer ----------
    $footer = New-Text -Text 'Tony Alpha - local desktop command center. Single source of truth: agents_registry.json. No external services connected.' -Size 11 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (4,12,4,0))
    [Windows.Controls.Grid]::SetRow($footer, 2)
    $grid.Children.Add($footer) | Out-Null

    return [pscustomobject]@{ Root = $root; TimeBlock = $timeBlock }
}
