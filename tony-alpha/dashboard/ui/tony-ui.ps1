# =====================================================================
# tony-ui.ps1  —  GIOK presentation layer (WPF)
# ---------------------------------------------------------------------
# NO BUSINESS LOGIC. Renders data (core/) with a THEME (theme/). GIOK is
# the product; Tony is the AI Chief of Staff inside it. Layout: a left
# sidebar (brand + Jake + nav) and a swappable main area whose home view
# answers "what does Jake need to know right now?"
# All colors/fonts/names/images come from the theme.
# =====================================================================

$ErrorActionPreference = 'Stop'

$script:Col  = @{}
$script:Font = 'Segoe UI'
$script:Theme = $null

function Initialize-TonyTheme {
    param([Parameter(Mandatory)] $Theme)
    $script:Theme = $Theme
    $c = $Theme.colors
    $names = $c.PSObject.Properties.Name
    $accentInk = if ($names -contains 'accentInk') { $c.accentInk } else { $c.accentDark }
    $heading   = if ($names -contains 'heading')   { $c.heading }   else { $c.primary }
    $script:Col = @{
        AppBg = $c.background; CardBg = $c.surface; Ink = $c.text; Muted = $c.textMuted; Line = $c.line
        Accent = $c.accent; AccentSoft = $c.accentSoft; AccentInk = $accentInk; Heading = $heading
        Primary = $c.primary; PrimaryDark = $c.primaryDark; PrimaryMid = $c.primaryMid
        OnPrimary = $c.textOnPrimary; OnPrimaryMuted = '#AEB9CC'
    }
    $script:Font = $Theme.typography.fontFamily
}

function New-Brush { param([string]$Hex) return (New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($Hex))) }

function New-ImageSource {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) { return $null }
    $bi = New-Object Windows.Media.Imaging.BitmapImage
    $bi.BeginInit(); $bi.CacheOption = 'OnLoad'; $bi.UriSource = New-Object Uri($Path); $bi.EndInit()
    return $bi
}

function New-Text {
    param([string]$Text, [double]$Size = 13, [string]$Weight = 'Normal', [string]$Color = $null,
          [Windows.Thickness]$Margin = (New-Object Windows.Thickness 0), [bool]$Wrap = $false)
    if (-not $Color) { $Color = $script:Col.Ink }
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $Text
    $t.FontFamily = New-Object Windows.Media.FontFamily $script:Font
    $t.FontSize = $Size; $t.FontWeight = [Windows.FontWeights]::$Weight
    $t.Foreground = New-Brush $Color; $t.Margin = $Margin
    if ($Wrap) { $t.TextWrapping = 'Wrap' }
    return $t
}

function New-Chip {
    param([string]$Text, [string]$Bg, [string]$Fg)
    $b = New-Object Windows.Controls.Border
    $b.Background = New-Brush $Bg; $b.CornerRadius = New-Object Windows.CornerRadius 9
    $b.Padding = New-Object Windows.Thickness (9, 3, 9, 3); $b.Margin = New-Object Windows.Thickness (0, 0, 6, 6)
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
    param([string]$Title, [Windows.UIElement]$Body, [string]$Tag = $null, [int]$Col = 0, [int]$Row = 0, [string]$NavTo = $null)
    $border = New-Object Windows.Controls.Border
    $border.Background = New-Brush $script:Col.CardBg; $border.CornerRadius = New-Object Windows.CornerRadius 12
    $border.Padding = New-Object Windows.Thickness 16; $border.Margin = New-Object Windows.Thickness 8
    $border.BorderBrush = New-Brush $script:Col.Line; $border.BorderThickness = New-Object Windows.Thickness 1
    $shadow = New-Object Windows.Media.Effects.DropShadowEffect
    $shadow.Color = [Windows.Media.ColorConverter]::ConvertFromString('#22000000')
    $shadow.BlurRadius = 14; $shadow.ShadowDepth = 2; $shadow.Opacity = 0.5; $shadow.Direction = 270
    $border.Effect = $shadow
    [Windows.Controls.Grid]::SetColumn($border, $Col); [Windows.Controls.Grid]::SetRow($border, $Row)

    $stack = New-Object Windows.Controls.StackPanel
    $header = New-Object Windows.Controls.DockPanel; $header.Margin = New-Object Windows.Thickness (0, 0, 0, 10)
    # reserve the right-side affordance first, so a long title fills the remaining space (no overlap)
    $right = New-Object Windows.Controls.StackPanel; $right.Orientation = 'Horizontal'; $right.HorizontalAlignment = 'Right'; $right.VerticalAlignment = 'Center'
    if ($Tag)   { $tc = New-Chip -Text $Tag -Bg '#FEF3C7' -Fg '#92400E'; $tc.Margin = New-Object Windows.Thickness (6, 0, 6, 0); $right.Children.Add($tc) | Out-Null }
    if ($NavTo) { $right.Children.Add((New-Text -Text 'open >' -Size 11.5 -Weight 'SemiBold' -Color $script:Col.Accent)) | Out-Null }
    [Windows.Controls.DockPanel]::SetDock($right, 'Right'); $header.Children.Add($right) | Out-Null
    $titleBlock = New-Text -Text $Title.ToUpper() -Size 12.5 -Weight 'Bold' -Color $script:Col.Muted
    $titleBlock.TextTrimming = 'CharacterEllipsis'; $header.Children.Add($titleBlock) | Out-Null
    $stack.Children.Add($header) | Out-Null; $stack.Children.Add($Body) | Out-Null
    $border.Child = $stack
    if ($NavTo) {
        $border.Cursor = 'Hand'; $border.Tag = $NavTo
        $border.Add_MouseLeftButtonUp({ param($s, $e) Set-ActiveView $s.Tag }) | Out-Null
        $border.Add_MouseEnter({ param($s, $e) $s.BorderBrush = (New-Brush $script:Col.Accent); $s.BorderThickness = (New-Object Windows.Thickness 2) }) | Out-Null
        $border.Add_MouseLeave({ param($s, $e) $s.BorderBrush = (New-Brush $script:Col.Line);   $s.BorderThickness = (New-Object Windows.Thickness 1) }) | Out-Null
    }
    return $border
}

function New-KeyValueRow {
    param([string]$Key, [string]$Value, [string]$ValueColor = $null)
    if (-not $ValueColor) { $ValueColor = $script:Col.Ink }
    $dp = New-Object Windows.Controls.DockPanel; $dp.Margin = New-Object Windows.Thickness (0, 0, 0, 7)
    $k = New-Text -Text $Key -Size 13 -Color $script:Col.Muted
    [Windows.Controls.DockPanel]::SetDock($k, 'Left'); $v = New-Text -Text $Value -Size 13 -Weight 'SemiBold' -Color $ValueColor
    $v.HorizontalAlignment = 'Right'; $dp.Children.Add($k) | Out-Null; $dp.Children.Add($v) | Out-Null
    return $dp
}

function New-MiniButton {
    param([string]$Text, [string]$Bg, [string]$Fg, [string]$Tag, [scriptblock]$OnClick)
    $b = New-Object Windows.Controls.Border
    $b.Background = New-Brush $Bg; $b.CornerRadius = New-Object Windows.CornerRadius 6
    $b.Padding = New-Object Windows.Thickness (10, 5, 10, 5); $b.Margin = New-Object Windows.Thickness (6, 0, 0, 0)
    $b.Cursor = 'Hand'; $b.VerticalAlignment = 'Center'
    if ($Tag) { $b.Tag = $Tag }
    $b.Child = (New-Text -Text $Text -Size 12 -Weight 'SemiBold' -Color $Fg)
    if ($OnClick) { $b.Add_MouseLeftButtonUp($OnClick) | Out-Null }
    return $b
}

function New-NumBadge {
    param([int]$N)
    $b = New-Object Windows.Controls.Border
    $b.Width = 24; $b.Height = 24; $b.CornerRadius = New-Object Windows.CornerRadius 12
    $b.Background = New-Brush $script:Col.Accent; $b.VerticalAlignment = 'Top'; $b.Margin = New-Object Windows.Thickness (0, 1, 10, 0)
    $t = New-Text -Text ([string]$N) -Size 12.5 -Weight 'Bold' -Color $script:Col.OnPrimary
    $t.HorizontalAlignment = 'Center'; $t.VerticalAlignment = 'Center'; $b.Child = $t
    return $b
}

# =====================  GLOBAL COMMAND BAR ("Ask Tony")  =====================
$script:CommandBox = $null
$script:CommandResult = $null
$script:CmdPlaceholder = 'Ask Tony...   try:  open agents   -   add task: call the Millers   (Ctrl+K)'

function New-CommandBar {
    $wrap = New-Object Windows.Controls.Border
    $wrap.Background = New-Brush $script:Col.CardBg; $wrap.CornerRadius = New-Object Windows.CornerRadius 10
    $wrap.BorderBrush = New-Brush $script:Col.Accent; $wrap.BorderThickness = New-Object Windows.Thickness 1
    $wrap.Padding = New-Object Windows.Thickness (14, 9, 14, 9); $wrap.Margin = New-Object Windows.Thickness (0, 0, 0, 14)

    $dp = New-Object Windows.Controls.DockPanel
    $label = New-Text -Text 'Ask Tony' -Size 13 -Weight 'Bold' -Color $script:Col.Accent; $label.VerticalAlignment = 'Center'; $label.Margin = New-Object Windows.Thickness (0, 0, 12, 0)
    [Windows.Controls.DockPanel]::SetDock($label, 'Left'); $dp.Children.Add($label) | Out-Null
    $hint = New-Text -Text 'Ctrl+K' -Size 11 -Weight 'SemiBold' -Color $script:Col.Muted; $hint.VerticalAlignment = 'Center'; $hint.Margin = New-Object Windows.Thickness (10, 0, 0, 0)
    [Windows.Controls.DockPanel]::SetDock($hint, 'Right'); $dp.Children.Add($hint) | Out-Null

    $tb = New-Object Windows.Controls.TextBox
    $tb.FontFamily = New-Object Windows.Media.FontFamily $script:Font; $tb.FontSize = 14
    $tb.Background = (New-Object Windows.Media.SolidColorBrush ([Windows.Media.Colors]::Transparent))
    $tb.BorderThickness = New-Object Windows.Thickness 0; $tb.VerticalContentAlignment = 'Center'
    $tb.CaretBrush = New-Brush $script:Col.Accent
    $tb.Text = $script:CmdPlaceholder; $tb.Foreground = New-Brush $script:Col.Muted; $tb.Tag = 'placeholder'
    $tb.Add_GotFocus({ param($s, $e) if ($s.Tag -eq 'placeholder') { $s.Text = ''; $s.Foreground = New-Brush $script:Col.Ink; $s.Tag = '' } }) | Out-Null
    $tb.Add_LostFocus({ param($s, $e) if ([string]::IsNullOrEmpty($s.Text)) { $s.Text = $script:CmdPlaceholder; $s.Foreground = New-Brush $script:Col.Muted; $s.Tag = 'placeholder' } }) | Out-Null
    $tb.Add_KeyDown({
        param($s, $e)
        if ($e.Key -ne [System.Windows.Input.Key]::Return) { return }
        if ($s.Tag -eq 'placeholder') { return }
        $res = Invoke-TonyCommand -Text $s.Text
        switch ($res.type) {
            'navigate' { Set-ActiveView $res.target }
            'addtask'  { $d = Get-ActionItemsData; Add-ActionItem -Data $d -Title $res.title | Out-Null; Save-ActionItemsData $d; $script:CommandResult = ("Added task: {0}" -f $res.title); Set-ActiveView 'Home' }
            'unknown'  { $script:CommandResult = $res.message; Set-ActiveView 'Home' }
            default    { }
        }
        $e.Handled = $true
    }) | Out-Null
    $script:CommandBox = $tb
    $dp.Children.Add($tb) | Out-Null
    $wrap.Child = $dp
    return $wrap
}

function Focus-CommandBar {
    if ($script:TonyActiveView -ne 'Home') { Set-ActiveView 'Home' }
    if ($script:CommandBox) { $script:CommandBox.Focus() | Out-Null }
}

# =====================  VIEW: HOME (executive)  =====================
function New-HomeView {
    param([Parameter(Mandatory)] $Model)
    $stack = New-Object Windows.Controls.StackPanel; $stack.Margin = New-Object Windows.Thickness (4, 0, 4, 0)

    # global command bar ("Ask Tony")
    $stack.Children.Add((New-CommandBar)) | Out-Null
    if ($script:CommandResult) {
        $stack.Children.Add((New-Text -Text $script:CommandResult -Size 12.5 -Weight 'SemiBold' -Color $script:Col.AccentInk -Margin (New-Object Windows.Thickness (2, 0, 0, 12)))) | Out-Null
        $script:CommandResult = $null
    }

    # greeting + brand quote
    $stack.Children.Add((New-Text -Text $Model.greeting -Size 30 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
    $rule = New-Object Windows.Controls.Border; $rule.Background = New-Brush $script:Col.Accent; $rule.Height = 3; $rule.Width = 66
    $rule.HorizontalAlignment = 'Left'; $rule.CornerRadius = New-Object Windows.CornerRadius 2; $rule.Margin = New-Object Windows.Thickness (0, 5, 0, 8)
    $stack.Children.Add($rule) | Out-Null
    $stack.Children.Add((New-Text -Text ('"{0}"' -f $Model.brandQuote) -Size 17 -Weight 'SemiBold' -Color $script:Col.AccentInk)) | Out-Null
    $stack.Children.Add((New-Text -Text $Model.dateText -Size 12.5 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 2, 0, 14)))) | Out-Null

    # ---- Row A: Top 3 Priorities | Tony Recommends ----
    $gA = New-Object Windows.Controls.Grid
    $c0 = New-Object Windows.Controls.ColumnDefinition; $c0.Width = [Windows.GridLength]::new(3, 'Star'); $gA.ColumnDefinitions.Add($c0) | Out-Null
    $c1 = New-Object Windows.Controls.ColumnDefinition; $c1.Width = [Windows.GridLength]::new(2, 'Star'); $gA.ColumnDefinitions.Add($c1) | Out-Null

    $topBody = New-Object Windows.Controls.StackPanel
    if (@($Model.top3).Count -eq 0) {
        $topBody.Children.Add((New-Text -Text 'All clear - no open priorities right now.' -Size 13 -Color $script:Col.Muted)) | Out-Null
    } else {
        $i = 1
        foreach ($p in $Model.top3) {
            $row = New-Object Windows.Controls.DockPanel; $row.Margin = New-Object Windows.Thickness (0, 0, 0, 10)
            $badge = New-NumBadge -N $i; [Windows.Controls.DockPanel]::SetDock($badge, 'Left'); $row.Children.Add($badge) | Out-Null
            $wrap = New-Object Windows.Controls.StackPanel
            $wrap.Children.Add((New-Text -Text $p.title -Size 14 -Weight 'SemiBold' -Wrap $true)) | Out-Null
            $wrap.Children.Add((New-Text -Text $p.id -Size 11 -Color $script:Col.Muted)) | Out-Null
            $row.Children.Add($wrap) | Out-Null
            $topBody.Children.Add($row) | Out-Null
            $i++
        }
    }
    $gA.Children.Add((New-Card -Title "Today's Top 3 Priorities" -Body $topBody -Col 0 -NavTo 'Action Items')) | Out-Null

    $recBody = New-Object Windows.Controls.StackPanel
    foreach ($r in $Model.tonyRecommends) {
        $row = New-Object Windows.Controls.DockPanel; $row.Margin = New-Object Windows.Thickness (0, 0, 0, 8)
        $dot = New-Text -Text "*" -Size 15 -Weight 'Bold' -Color $script:Col.Accent; $dot.Margin = New-Object Windows.Thickness (0, 0, 8, 0); $dot.VerticalAlignment = 'Top'
        [Windows.Controls.DockPanel]::SetDock($dot, 'Left'); $row.Children.Add($dot) | Out-Null
        $txt = New-Text -Text $r.text -Size 12.5 -Wrap $true
        if ($r.source -eq 'placeholder') { $txt.Text = $r.text + '  (sample)' }
        $row.Children.Add($txt) | Out-Null
        $recBody.Children.Add($row) | Out-Null
    }
    $gA.Children.Add((New-Card -Title 'Tony Recommends' -Body $recBody -Col 1 -NavTo 'Recommendations')) | Out-Null
    $stack.Children.Add($gA) | Out-Null

    # ---- Row B: Agency Overview | Upcoming Appointments | Agent Health ----
    $gB = New-Object Windows.Controls.Grid
    foreach ($i in 0..2) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = [Windows.GridLength]::new(1, 'Star'); $gB.ColumnDefinitions.Add($cd) | Out-Null }

    # Agency Overview (placeholder metrics)
    $agBody = New-Object Windows.Controls.Grid
    foreach ($i in 0..1) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = [Windows.GridLength]::new(1, 'Star'); $agBody.ColumnDefinitions.Add($cd) | Out-Null }
    $mi = 0
    foreach ($m in $Model.agencyMetrics.items) {
        $r = [int][math]::Floor($mi / 2); $c = $mi % 2
        if ($c -eq 0) { $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = [Windows.GridLength]::Auto; $agBody.RowDefinitions.Add($rd) | Out-Null }
        $cell = New-Object Windows.Controls.StackPanel; $cell.Margin = New-Object Windows.Thickness (0, 0, 8, 12)
        $cell.Children.Add((New-Text -Text $m.value -Size 24 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
        $cell.Children.Add((New-Text -Text $m.label -Size 11.5 -Color $script:Col.Muted)) | Out-Null
        [Windows.Controls.Grid]::SetRow($cell, $r); [Windows.Controls.Grid]::SetColumn($cell, $c); $agBody.Children.Add($cell) | Out-Null
        $mi++
    }
    $gB.Children.Add((New-Card -Title 'Agency Overview' -Body $agBody -Tag 'SAMPLE' -Col 0 -NavTo 'Agency')) | Out-Null

    # Upcoming Appointments (placeholder)
    $apBody = New-Object Windows.Controls.StackPanel
    foreach ($ap in $Model.appointments.items) {
        $row = New-Object Windows.Controls.StackPanel; $row.Margin = New-Object Windows.Thickness (0, 0, 0, 9)
        $row.Children.Add((New-Text -Text $ap.time -Size 12.5 -Weight 'Bold' -Color $script:Col.AccentInk)) | Out-Null
        $row.Children.Add((New-Text -Text $ap.title -Size 12.5 -Weight 'SemiBold' -Wrap $true)) | Out-Null
        $row.Children.Add((New-Text -Text $ap.who -Size 11.5 -Color $script:Col.Muted)) | Out-Null
        $apBody.Children.Add($row) | Out-Null
    }
    $gB.Children.Add((New-Card -Title 'Upcoming Appointments' -Body $apBody -Tag 'SAMPLE' -Col 1 -NavTo 'Appointments')) | Out-Null

    # Agent Health Summary (live)
    $h = $Model.agentHealth
    $hBody = New-Object Windows.Controls.StackPanel
    $big = New-Object Windows.Controls.StackPanel; $big.Orientation = 'Horizontal'
    $big.Children.Add((New-Text -Text ([string]$h.total) -Size 30 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
    $big.Children.Add((New-Text -Text 'agents' -Size 12 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (6, 15, 0, 0)))) | Out-Null
    $hBody.Children.Add($big) | Out-Null
    $sw = New-Object Windows.Controls.WrapPanel; $sw.Margin = New-Object Windows.Thickness (0, 4, 0, 4)
    foreach ($k in $h.byStatus.Keys) { $n = $h.byStatus[$k]; if ($n -gt 0) { $cc = Get-StatusChipColors $k; $sw.Children.Add((New-Chip -Text ("{0} {1}" -f $k, $n) -Bg $cc[0] -Fg $cc[1])) | Out-Null } }
    $hBody.Children.Add($sw) | Out-Null
    $hBody.Children.Add((New-KeyValueRow -Key 'Health measured' -Value $h.healthCoverage)) | Out-Null
    $hBody.Children.Add((New-KeyValueRow -Key 'Agents with issues' -Value ([string]$h.withIssues))) | Out-Null
    $gB.Children.Add((New-Card -Title 'Agent Health' -Body $hBody -Col 2 -NavTo 'Agents')) | Out-Null
    $stack.Children.Add($gB) | Out-Null

    # ---- Quick links ----
    $ql = New-Object Windows.Controls.StackPanel; $ql.Orientation = 'Horizontal'; $ql.Margin = New-Object Windows.Thickness (8, 6, 0, 6)
    $ql.Children.Add((New-Text -Text 'Quick links:' -Size 12.5 -Weight 'SemiBold' -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 4, 4, 0)))) | Out-Null
    foreach ($lnk in @('Agents', 'Issues', 'Action Items', 'Weekly Review', 'Roadmap')) {
        $ql.Children.Add((New-MiniButton -Text $lnk -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -Tag $lnk -OnClick { param($s, $e) Set-ActiveView $s.Tag })) | Out-Null
    }
    $stack.Children.Add($ql) | Out-Null

    # ---- System strip (lower priority) ----
    $sys = New-Object Windows.Controls.Border
    $sys.Background = New-Brush $script:Col.AppBg; $sys.BorderBrush = New-Brush $script:Col.Line; $sys.BorderThickness = New-Object Windows.Thickness (0, 1, 0, 0)
    $sys.Margin = New-Object Windows.Thickness (8, 10, 8, 0); $sys.Padding = New-Object Windows.Thickness (0, 8, 0, 0)
    $verified = if ($h.verified) { 'verified' } else { 'unverified' }
    $sys.Child = (New-Text -Text ("System: registry v{0} ({1}) - {2} open issues - Focus: {3}    (open Issues >)" -f $h.registryVersion, $verified, $Model.issueCount, $Model.sprint) -Size 11 -Color $script:Col.Muted -Wrap $true)
    $sys.Cursor = 'Hand'; $sys.Tag = 'Issues'
    $sys.Add_MouseLeftButtonUp({ param($s, $e) Set-ActiveView $s.Tag }) | Out-Null
    $stack.Children.Add($sys) | Out-Null

    $scroll = New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility = 'Auto'; $scroll.Content = $stack
    return $scroll
}

# =====================  VIEW: SETTINGS  =====================
function New-SettingsView {
    $t = $script:Theme
    $outer = New-Object Windows.Controls.StackPanel; $outer.Margin = New-Object Windows.Thickness (4, 0, 4, 0)
    $outer.Children.Add((New-Text -Text 'Settings' -Size 24 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
    $outer.Children.Add((New-Text -Text 'Workspace & branding' -Size 12.5 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 0, 0, 12)))) | Out-Null

    $body = New-Object Windows.Controls.StackPanel
    $body.Children.Add((New-KeyValueRow -Key 'Company' -Value $t.companyName)) | Out-Null
    $body.Children.Add((New-KeyValueRow -Key 'Workspace' -Value $t.workspaceName)) | Out-Null
    $body.Children.Add((New-KeyValueRow -Key 'Assistant' -Value $t.assistantName)) | Out-Null
    $body.Children.Add((New-KeyValueRow -Key 'Version' -Value $t.version)) | Out-Null
    $body.Children.Add((New-KeyValueRow -Key 'Theme' -Value $t.themeId)) | Out-Null
    $sw = New-Object Windows.Controls.WrapPanel; $sw.Margin = New-Object Windows.Thickness (0, 6, 0, 0)
    foreach ($pair in @(@('Primary', $t.colors.primary), @('Accent', $t.colors.accent), @('Background', $t.colors.background))) {
        $chip = New-Object Windows.Controls.Border; $chip.Background = New-Brush $pair[1]; $chip.Width = 26; $chip.Height = 26
        $chip.CornerRadius = New-Object Windows.CornerRadius 6; $chip.Margin = New-Object Windows.Thickness (0, 0, 6, 0)
        $chip.BorderBrush = New-Brush $script:Col.Line; $chip.BorderThickness = New-Object Windows.Thickness 1
        $sw.Children.Add($chip) | Out-Null
    }
    $body.Children.Add($sw) | Out-Null
    $note = New-Text -Text 'Branding is theme-driven. Edit theme/theme.json to re-brand this workspace (logo, colors, tagline, profile) - no code change needed. See THEME.md. Per-user personalization is planned; this is not multi-user yet.' -Size 12 -Color $script:Col.Muted -Wrap $true -Margin (New-Object Windows.Thickness (0, 12, 0, 0))
    $body.Children.Add($note) | Out-Null

    $card = New-Card -Title 'Workspace' -Body $body
    $card.HorizontalAlignment = 'Left'; $card.MaxWidth = 560; $card.Margin = New-Object Windows.Thickness (0, 0, 0, 0)
    $outer.Children.Add($card) | Out-Null
    return $outer
}

# =====================  PLACEHOLDER DETAIL VIEWS  =====================
# Focused views for cards whose real tab doesn't exist yet. "Coming soon"
# + sample data, clearly structured so a live integration can replace them.
function New-ComingSoonView {
    param([string]$Title, [string]$Subtitle, [Windows.UIElement]$Body, [string]$RelatedTab, [string]$RelatedLabel)
    $outer = New-Object Windows.Controls.StackPanel; $outer.Margin = New-Object Windows.Thickness (4, 0, 4, 0)

    $bar = New-Object Windows.Controls.StackPanel; $bar.Orientation = 'Horizontal'; $bar.Margin = New-Object Windows.Thickness (0, 0, 0, 10)
    $back = New-MiniButton -Text '< Home' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -OnClick { param($s, $e) Set-ActiveView 'Home' }
    $back.Margin = New-Object Windows.Thickness (0, 0, 0, 0); $bar.Children.Add($back) | Out-Null
    if ($RelatedTab) { $bar.Children.Add((New-MiniButton -Text $RelatedLabel -Bg $script:Col.Accent -Fg $script:Col.OnPrimary -Tag $RelatedTab -OnClick { param($s, $e) Set-ActiveView $s.Tag })) | Out-Null }
    $outer.Children.Add($bar) | Out-Null

    $outer.Children.Add((New-Text -Text $Title -Size 24 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
    $outer.Children.Add((New-Text -Text $Subtitle -Size 12.5 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 0, 0, 10)))) | Out-Null

    $banner = New-Object Windows.Controls.Border
    $banner.Background = New-Brush $script:Col.AccentSoft; $banner.CornerRadius = New-Object Windows.CornerRadius 8
    $banner.Padding = New-Object Windows.Thickness (12, 8, 12, 8); $banner.Margin = New-Object Windows.Thickness (0, 0, 0, 14)
    $banner.Child = (New-Text -Text 'Coming soon. Sample data shown below - a live integration will replace it.' -Size 12.5 -Weight 'SemiBold' -Color $script:Col.AccentInk -Wrap $true)
    $outer.Children.Add($banner) | Out-Null

    $outer.Children.Add($Body) | Out-Null
    $scroll = New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility = 'Auto'; $scroll.Content = $outer
    return $scroll
}

function New-AgencyBody {
    $m = Get-HomeModel -Now $script:TonyNow
    $body = New-Object Windows.Controls.WrapPanel
    foreach ($metric in $m.agencyMetrics.items) {
        $card = New-Object Windows.Controls.Border
        $card.Background = New-Brush $script:Col.CardBg; $card.CornerRadius = New-Object Windows.CornerRadius 10
        $card.BorderBrush = New-Brush $script:Col.Line; $card.BorderThickness = New-Object Windows.Thickness 1
        $card.Padding = New-Object Windows.Thickness (18, 14, 18, 14); $card.Margin = New-Object Windows.Thickness (0, 0, 12, 12); $card.Width = 180
        $sp = New-Object Windows.Controls.StackPanel
        $sp.Children.Add((New-Text -Text $metric.value -Size 28 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
        $sp.Children.Add((New-Text -Text $metric.label -Size 12 -Color $script:Col.Muted)) | Out-Null
        $card.Child = $sp; $body.Children.Add($card) | Out-Null
    }
    return $body
}
function New-AgencyView { return New-ComingSoonView -Title 'Agency Overview' -Subtitle 'Your book of business at a glance' -Body (New-AgencyBody) }

function New-AppointmentsBody {
    $m = Get-HomeModel -Now $script:TonyNow
    $body = New-Object Windows.Controls.StackPanel
    foreach ($ap in $m.appointments.items) {
        $row = New-Object Windows.Controls.Border
        $row.Background = New-Brush $script:Col.CardBg; $row.CornerRadius = New-Object Windows.CornerRadius 10
        $row.BorderBrush = New-Brush $script:Col.Line; $row.BorderThickness = New-Object Windows.Thickness 1
        $row.Padding = New-Object Windows.Thickness (14, 10, 14, 10); $row.Margin = New-Object Windows.Thickness (0, 0, 0, 8)
        $dp = New-Object Windows.Controls.DockPanel
        $time = New-Text -Text $ap.time -Size 13 -Weight 'Bold' -Color $script:Col.AccentInk; $time.Width = 90
        [Windows.Controls.DockPanel]::SetDock($time, 'Left'); $dp.Children.Add($time) | Out-Null
        $info = New-Object Windows.Controls.StackPanel
        $info.Children.Add((New-Text -Text $ap.title -Size 13 -Weight 'SemiBold' -Wrap $true)) | Out-Null
        $info.Children.Add((New-Text -Text $ap.who -Size 11.5 -Color $script:Col.Muted)) | Out-Null
        $dp.Children.Add($info) | Out-Null; $row.Child = $dp; $body.Children.Add($row) | Out-Null
    }
    return $body
}
function New-AppointmentsView { return New-ComingSoonView -Title 'Upcoming Appointments' -Subtitle 'Your day, from the GIOK calendar' -Body (New-AppointmentsBody) }

function New-RecommendationsBody {
    $m = Get-HomeModel -Now $script:TonyNow
    $body = New-Object Windows.Controls.StackPanel
    foreach ($r in $m.tonyRecommends) {
        $row = New-Object Windows.Controls.Border
        $row.Background = New-Brush $script:Col.CardBg; $row.CornerRadius = New-Object Windows.CornerRadius 10
        $row.BorderBrush = New-Brush $script:Col.Line; $row.BorderThickness = New-Object Windows.Thickness 1
        $row.Padding = New-Object Windows.Thickness (14, 10, 14, 10); $row.Margin = New-Object Windows.Thickness (0, 0, 0, 8)
        $dp = New-Object Windows.Controls.DockPanel
        $tag = if ($r.source -eq 'live') { New-Chip -Text 'live' -Bg '#DEF7EC' -Fg '#03543F' } else { New-Chip -Text 'sample' -Bg '#FEF3C7' -Fg '#92400E' }
        $tag.VerticalAlignment = 'Top'; [Windows.Controls.DockPanel]::SetDock($tag, 'Left'); $dp.Children.Add($tag) | Out-Null
        $txt = New-Text -Text $r.text -Size 13 -Wrap $true; $txt.Margin = New-Object Windows.Thickness (4, 1, 0, 0)
        $dp.Children.Add($txt) | Out-Null; $row.Child = $dp; $body.Children.Add($row) | Out-Null
    }
    return $body
}
function New-RecommendationsView { return New-ComingSoonView -Title 'Tony Recommends' -Subtitle "Tony's suggestions for today" -Body (New-RecommendationsBody) -RelatedTab 'Action Items' -RelatedLabel 'Go to Action Items' }

# read-only Action Items snapshot (for popout windows / Mission Control - no shared state)
function New-ActionItemsSnapshot {
    param([int]$Max = 0)
    $items = @((Get-ActionItemsData).items | Where-Object { -not $_.archived })
    if ($Max -gt 0) { $items = @($items | Select-Object -First $Max) }
    $list = New-Object Windows.Controls.StackPanel
    if ($items.Count -eq 0) { $list.Children.Add((New-Text -Text 'No open action items.' -Size 12.5 -Color $script:Col.Muted)) | Out-Null; return $list }
    foreach ($it in $items) {
        $row = New-Object Windows.Controls.DockPanel; $row.Margin = New-Object Windows.Thickness (0, 0, 0, 5)
        $mk = New-Text -Text $(if ($it.done) { '[x]' } else { '[ ]' }) -Size 12.5 -Weight 'SemiBold' -Color $script:Col.Accent; $mk.Margin = New-Object Windows.Thickness (0, 0, 6, 0); $mk.VerticalAlignment = 'Top'
        [Windows.Controls.DockPanel]::SetDock($mk, 'Left'); $row.Children.Add($mk) | Out-Null
        $txt = New-Text -Text ("{0}  {1}" -f $it.id, $it.title) -Size 12.5 -Wrap $true -Color $(if ($it.done) { $script:Col.Muted } else { $script:Col.Ink })
        if ($it.done) { $txt.TextDecorations = [System.Windows.TextDecorations]::Strikethrough }
        $row.Children.Add($txt) | Out-Null; $list.Children.Add($row) | Out-Null
    }
    return $list
}

# =====================  VIEW: AGENTS  =====================
function New-AgentCard {
    param([Parameter(Mandatory)] $Agent)
    $a = $Agent
    $card = New-Object Windows.Controls.Border
    $card.Background = New-Brush $script:Col.CardBg; $card.CornerRadius = New-Object Windows.CornerRadius 10
    $card.BorderBrush = New-Brush $script:Col.Line; $card.BorderThickness = New-Object Windows.Thickness 1
    $card.Padding = New-Object Windows.Thickness 14; $card.Margin = New-Object Windows.Thickness (0, 0, 0, 10)
    $stack = New-Object Windows.Controls.StackPanel

    $head = New-Object Windows.Controls.DockPanel
    $chips = New-Object Windows.Controls.StackPanel; $chips.Orientation = 'Horizontal'; $chips.HorizontalAlignment = 'Right'
    $sc = Get-StatusChipColors $a.status;  $chips.Children.Add((New-Chip -Text $a.status -Bg $sc[0] -Fg $sc[1])) | Out-Null
    $pc = Get-PriorityChipColors $a.priority; $chips.Children.Add((New-Chip -Text $a.priority -Bg $pc[0] -Fg $pc[1])) | Out-Null
    $chips.Children.Add((New-Chip -Text $a.owner -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk)) | Out-Null
    [Windows.Controls.DockPanel]::SetDock($chips, 'Right'); $head.Children.Add($chips) | Out-Null
    $titleWrap = New-Object Windows.Controls.StackPanel; $titleWrap.Orientation = 'Horizontal'
    $titleWrap.Children.Add((New-Chip -Text $a.stable_id -Bg $script:Col.Primary -Fg $script:Col.OnPrimary)) | Out-Null
    $nm = New-Text -Text $a.name -Size 15 -Weight 'Bold'; $nm.VerticalAlignment = 'Center'; $nm.Margin = New-Object Windows.Thickness (2, 0, 0, 6)
    $titleWrap.Children.Add($nm) | Out-Null; $head.Children.Add($titleWrap) | Out-Null
    $stack.Children.Add($head) | Out-Null

    $deps    = if (@($a.dependencies).Count -gt 0) { ($a.dependencies -join ', ') } else { '-' }
    $lastRun = if ($null -eq $a.last_run) { '-' } else { [string]$a.last_run }
    $health  = if ($null -eq $a.health_score) { '-' } else { "$($a.health_score)%" }
    $issues  = if (@($a.issues).Count -gt 0) { ($a.issues -join '; ') } else { 'None' }
    $notes   = if ([string]::IsNullOrWhiteSpace($a.notes)) { '-' } else { $a.notes }

    $grid = New-Object Windows.Controls.Grid; $grid.Margin = New-Object Windows.Thickness (0, 4, 0, 0)
    foreach ($i in 0..1) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = [Windows.GridLength]::new(1, 'Star'); $grid.ColumnDefinitions.Add($cd) | Out-Null }
    $pairs = @(@('Schedule', $a.schedule), @('Last run', $lastRun), @('Health score', $health), @('Dependencies', $deps))
    for ($i = 0; $i -lt $pairs.Count; $i++) {
        $r = [int][math]::Floor($i / 2); $c = $i % 2
        if ($c -eq 0) { $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = [Windows.GridLength]::Auto; $grid.RowDefinitions.Add($rd) | Out-Null }
        $cell = New-Object Windows.Controls.StackPanel; $cell.Orientation = 'Horizontal'; $cell.Margin = New-Object Windows.Thickness (0, 0, 12, 4)
        $cell.Children.Add((New-Text -Text ("{0}: " -f $pairs[$i][0]) -Size 12.5 -Color $script:Col.Muted)) | Out-Null
        $cell.Children.Add((New-Text -Text ([string]$pairs[$i][1]) -Size 12.5 -Weight 'SemiBold')) | Out-Null
        [Windows.Controls.Grid]::SetRow($cell, $r); [Windows.Controls.Grid]::SetColumn($cell, $c); $grid.Children.Add($cell) | Out-Null
    }
    $stack.Children.Add($grid) | Out-Null

    $ig = New-Object Windows.Controls.StackPanel; $ig.Orientation = 'Horizontal'; $ig.Margin = New-Object Windows.Thickness (0, 4, 0, 0)
    $ig.Children.Add((New-Text -Text 'Issues: ' -Size 12.5 -Color $script:Col.Muted)) | Out-Null
    $ig.Children.Add((New-Text -Text $issues -Size 12.5 -Weight 'SemiBold' -Color $(if ($issues -eq 'None') { '#34D399' } else { '#F87171' }))) | Out-Null
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
    $head.Children.Add((New-Text -Text 'Agents' -Size 24 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
    $head.Children.Add((New-Text -Text ("{0} registered agents - live from agents_registry.json" -f @($Agents).Count) -Size 13 -Color $script:Col.Muted)) | Out-Null
    $list = New-Object Windows.Controls.StackPanel; $list.Margin = New-Object Windows.Thickness (4, 0, 4, 0)
    foreach ($a in $Agents) { $list.Children.Add((New-AgentCard -Agent $a)) | Out-Null }
    $scroll = New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility = 'Auto'; $scroll.Content = $list
    $outer = New-Object Windows.Controls.DockPanel
    [Windows.Controls.DockPanel]::SetDock($head, 'Top'); $outer.Children.Add($head) | Out-Null; $outer.Children.Add($scroll) | Out-Null
    return $outer
}

# =====================  VIEW: ACTION ITEMS (interactive)  =====================
$script:ActionArchiveMode = $false
$script:ActionInputBox = $null

function Refresh-ActionItems { $script:TonyBody.Child = New-ActionItemsView }

function New-ActionRow {
    param([Parameter(Mandatory)] $Item, [bool]$ArchiveMode)
    $row = New-Object Windows.Controls.Border
    $row.Background = New-Brush $script:Col.CardBg; $row.CornerRadius = New-Object Windows.CornerRadius 8
    $row.BorderBrush = New-Brush $script:Col.Line; $row.BorderThickness = New-Object Windows.Thickness 1
    $row.Padding = New-Object Windows.Thickness (12, 8, 12, 8); $row.Margin = New-Object Windows.Thickness (0, 0, 0, 6)
    $dp = New-Object Windows.Controls.DockPanel

    $btns = New-Object Windows.Controls.StackPanel; $btns.Orientation = 'Horizontal'; $btns.HorizontalAlignment = 'Right'
    if ($ArchiveMode) {
        $btns.Children.Add((New-MiniButton -Text 'Restore' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -Tag $Item.id -OnClick {
            param($s, $e); $d = Get-ActionItemsData; Set-ActionItemArchived -Data $d -Id $s.Tag -Archived $false | Out-Null; Save-ActionItemsData $d; Refresh-ActionItems })) | Out-Null
    }
    $btns.Children.Add((New-MiniButton -Text 'Delete' -Bg '#FDE2E1' -Fg '#9B1C1C' -Tag $Item.id -OnClick {
        param($s, $e); $d = Get-ActionItemsData; Remove-ActionItem -Data $d -Id $s.Tag | Out-Null; Save-ActionItemsData $d; Refresh-ActionItems })) | Out-Null
    [Windows.Controls.DockPanel]::SetDock($btns, 'Right'); $dp.Children.Add($btns) | Out-Null

    if (-not $ArchiveMode) {
        $cb = New-Object Windows.Controls.CheckBox
        $cb.IsChecked = [bool]$Item.done; $cb.Tag = $Item.id; $cb.VerticalAlignment = 'Center'; $cb.Margin = New-Object Windows.Thickness (0, 0, 10, 0)
        $cb.Add_Click({ param($s, $e); $d = Get-ActionItemsData; Set-ActionItemDone -Data $d -Id $s.Tag -Done ([bool]$s.IsChecked) | Out-Null; Save-ActionItemsData $d; Refresh-ActionItems }) | Out-Null
        [Windows.Controls.DockPanel]::SetDock($cb, 'Left'); $dp.Children.Add($cb) | Out-Null
    }

    $content = New-Object Windows.Controls.StackPanel; $content.Orientation = 'Horizontal'
    $content.Children.Add((New-Chip -Text $Item.id -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk)) | Out-Null
    $title = New-Text -Text $Item.title -Size 13 -Wrap $true -Color $(if ($Item.done) { $script:Col.Muted } else { $script:Col.Ink })
    $title.VerticalAlignment = 'Center'; $title.Margin = New-Object Windows.Thickness (2, 0, 0, 0)
    if ($Item.done) { $title.TextDecorations = [System.Windows.TextDecorations]::Strikethrough }
    $content.Children.Add($title) | Out-Null; $dp.Children.Add($content) | Out-Null
    $row.Child = $dp
    return $row
}

function New-ActionItemsView {
    $data = Get-ActionItemsData
    $items = @($data.items)
    $active   = @($items | Where-Object { -not $_.archived })
    $archived = @($items | Where-Object { $_.archived })
    $mode = [bool]$script:ActionArchiveMode
    $shown = if ($mode) { $archived } else { $active }

    $outer = New-Object Windows.Controls.DockPanel
    $head = New-Object Windows.Controls.StackPanel; $head.Margin = New-Object Windows.Thickness (4, 0, 4, 10)
    $head.Children.Add((New-Text -Text 'Action Items' -Size 24 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
    $head.Children.Add((New-Text -Text 'Interactive - source of truth: action_items.json' -Size 12.5 -Color $script:Col.Muted)) | Out-Null
    $toggle = New-Object Windows.Controls.StackPanel; $toggle.Orientation = 'Horizontal'; $toggle.Margin = New-Object Windows.Thickness (0, 8, 0, 0)
    $activeBtn = New-MiniButton -Text ("Active ({0})" -f $active.Count) -Bg $(if (-not $mode) { $script:Col.Accent } else { $script:Col.AccentSoft }) -Fg $(if (-not $mode) { $script:Col.OnPrimary } else { $script:Col.AccentInk }) -OnClick { param($s, $e); $script:ActionArchiveMode = $false; Refresh-ActionItems }
    $activeBtn.Margin = New-Object Windows.Thickness (0, 0, 0, 0)
    $archBtn = New-MiniButton -Text ("Archived ({0})" -f $archived.Count) -Bg $(if ($mode) { $script:Col.Accent } else { $script:Col.AccentSoft }) -Fg $(if ($mode) { $script:Col.OnPrimary } else { $script:Col.AccentInk }) -OnClick { param($s, $e); $script:ActionArchiveMode = $true; Refresh-ActionItems }
    $toggle.Children.Add($activeBtn) | Out-Null; $toggle.Children.Add($archBtn) | Out-Null; $head.Children.Add($toggle) | Out-Null
    [Windows.Controls.DockPanel]::SetDock($head, 'Top'); $outer.Children.Add($head) | Out-Null

    if (-not $mode) {
        $bar = New-Object Windows.Controls.DockPanel; $bar.Margin = New-Object Windows.Thickness (4, 0, 4, 10)
        $addBtn = New-MiniButton -Text '+ Add' -Bg $script:Col.Accent -Fg $script:Col.OnPrimary -OnClick {
            param($s, $e); $t = $script:ActionInputBox.Text
            if (-not [string]::IsNullOrWhiteSpace($t)) { $d = Get-ActionItemsData; Add-ActionItem -Data $d -Title $t | Out-Null; Save-ActionItemsData $d; $script:ActionArchiveMode = $false; Refresh-ActionItems }
        }
        [Windows.Controls.DockPanel]::SetDock($addBtn, 'Right'); $bar.Children.Add($addBtn) | Out-Null
        $archComplete = New-MiniButton -Text 'Archive completed' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -OnClick {
            param($s, $e); $d = Get-ActionItemsData; [void](Invoke-ArchiveCompleted -Data $d); Save-ActionItemsData $d; Refresh-ActionItems
        }
        [Windows.Controls.DockPanel]::SetDock($archComplete, 'Right'); $bar.Children.Add($archComplete) | Out-Null
        $tb = New-Object Windows.Controls.TextBox
        $tb.FontFamily = New-Object Windows.Media.FontFamily $script:Font; $tb.FontSize = 13
        $tb.Padding = New-Object Windows.Thickness (8, 6, 8, 6); $tb.VerticalContentAlignment = 'Center'; $tb.BorderBrush = New-Brush $script:Col.Line
        $tb.Background = New-Brush $script:Col.PrimaryMid; $tb.Foreground = New-Brush $script:Col.Ink; $tb.CaretBrush = New-Brush $script:Col.Accent
        $tb.Add_KeyDown({ param($s, $e); if ($e.Key -eq 'Return' -and -not [string]::IsNullOrWhiteSpace($s.Text)) { $d = Get-ActionItemsData; Add-ActionItem -Data $d -Title $s.Text | Out-Null; Save-ActionItemsData $d; $script:ActionArchiveMode = $false; Refresh-ActionItems } })
        $script:ActionInputBox = $tb; $bar.Children.Add($tb) | Out-Null
        [Windows.Controls.DockPanel]::SetDock($bar, 'Top'); $outer.Children.Add($bar) | Out-Null
    }

    $list = New-Object Windows.Controls.StackPanel; $list.Margin = New-Object Windows.Thickness (4, 0, 4, 0)
    if ($shown.Count -eq 0) {
        $list.Children.Add((New-Text -Text $(if ($mode) { 'No archived items yet.' } else { 'No action items. Add one above.' }) -Size 13 -Color $script:Col.Muted)) | Out-Null
    } else { foreach ($it in $shown) { $list.Children.Add((New-ActionRow -Item $it -ArchiveMode $mode)) | Out-Null } }
    $scroll = New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility = 'Auto'; $scroll.Content = $list
    $outer.Children.Add($scroll) | Out-Null
    return $outer
}

# =====================  VIEW: MARKDOWN DOC  =====================
function New-MarkdownView {
    param([string]$Title, [string]$Text)
    $stack = New-Object Windows.Controls.StackPanel; $stack.Margin = New-Object Windows.Thickness (4, 0, 4, 0)
    foreach ($raw in ($Text -split "`r?`n")) {
        $line = $raw.TrimEnd()
        if ($line -match '^#\s+(.+)')       { $stack.Children.Add((New-Text -Text $Matches[1] -Size 22 -Weight 'Bold' -Color $script:Col.Heading -Wrap $true -Margin (New-Object Windows.Thickness (0, 8, 0, 4)))) | Out-Null; continue }
        if ($line -match '^##\s+(.+)')      { $stack.Children.Add((New-Text -Text $Matches[1] -Size 16 -Weight 'Bold' -Color $script:Col.Heading -Wrap $true -Margin (New-Object Windows.Thickness (0, 10, 0, 3)))) | Out-Null; continue }
        if ($line -match '^###\s+(.+)')     { $stack.Children.Add((New-Text -Text $Matches[1] -Size 13.5 -Weight 'SemiBold' -Color $script:Col.Accent -Wrap $true -Margin (New-Object Windows.Thickness (0, 6, 0, 2)))) | Out-Null; continue }
        if ($line -match '^\s*[-*]\s+(.+)') { $stack.Children.Add((New-Text -Text ("- " + ($Matches[1] -replace '\*\*', '' -replace '`', '')) -Size 12.5 -Wrap $true -Margin (New-Object Windows.Thickness (12, 1, 0, 1)))) | Out-Null; continue }
        if ($line -match '^\s*\|')          { $stack.Children.Add((New-Text -Text ($line -replace '\|', '  ') -Size 12 -Color $script:Col.Muted -Wrap $true)) | Out-Null; continue }
        if ($line -match '^---+$' -or $line -eq '') { continue }
        $stack.Children.Add((New-Text -Text ($line -replace '\*\*', '' -replace '`', '') -Size 12.5 -Wrap $true -Margin (New-Object Windows.Thickness (0, 1, 0, 1)))) | Out-Null
    }
    $scroll = New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility = 'Auto'; $scroll.Content = $stack
    $outer = New-Object Windows.Controls.DockPanel
    $hd = New-Object Windows.Controls.StackPanel; $hd.Margin = New-Object Windows.Thickness (4, 0, 4, 8)
    $hd.Children.Add((New-Text -Text $Title -Size 24 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
    [Windows.Controls.DockPanel]::SetDock($hd, 'Top'); $outer.Children.Add($hd) | Out-Null; $outer.Children.Add($scroll) | Out-Null
    return $outer
}

# =====================  VIEW: MISSION CONTROL  =====================
function New-McPanelBody { param([scriptblock]$Build) return (& $Build) }

function New-MissionControlView {
    $m = Get-HomeModel -Now $script:TonyNow
    $reg = Get-Registry
    $iss = @(Get-IssuesSummary)
    $openAI = @((Get-ActionItemsData).items | Where-Object { -not $_.archived -and -not $_.done })
    $h = $m.agentHealth

    $outer = New-Object Windows.Controls.StackPanel
    $outer.Children.Add((New-Text -Text 'Mission Control' -Size 26 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
    $rule = New-Object Windows.Controls.Border; $rule.Background = New-Brush $script:Col.Accent; $rule.Height = 3; $rule.Width = 72; $rule.HorizontalAlignment = 'Left'; $rule.CornerRadius = New-Object Windows.CornerRadius 2; $rule.Margin = New-Object Windows.Thickness (0, 5, 0, 6)
    $outer.Children.Add($rule) | Out-Null
    $outer.Children.Add((New-Text -Text 'Full-screen second-screen overview - live from GIOK sources' -Size 12.5 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 0, 0, 12)))) | Out-Null

    $grid = New-Object Windows.Controls.Grid; $grid.MinHeight = 640
    foreach ($i in 0..3) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = [Windows.GridLength]::new(1, 'Star'); $grid.ColumnDefinitions.Add($cd) | Out-Null }
    foreach ($i in 0..1) { $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = [Windows.GridLength]::new(1, 'Star'); $grid.RowDefinitions.Add($rd) | Out-Null }

    # Agent Health
    $b = New-Object Windows.Controls.StackPanel
    $bigp = New-Object Windows.Controls.StackPanel; $bigp.Orientation = 'Horizontal'
    $bigp.Children.Add((New-Text -Text ([string]$h.total) -Size 28 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
    $bigp.Children.Add((New-Text -Text 'agents' -Size 12 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (6, 13, 0, 0)))) | Out-Null
    $b.Children.Add($bigp) | Out-Null
    $sw = New-Object Windows.Controls.WrapPanel; $sw.Margin = New-Object Windows.Thickness (0, 4, 0, 4)
    foreach ($k in $h.byStatus.Keys) { $n = $h.byStatus[$k]; if ($n -gt 0) { $cc = Get-StatusChipColors $k; $sw.Children.Add((New-Chip -Text ("{0} {1}" -f $k, $n) -Bg $cc[0] -Fg $cc[1])) | Out-Null } }
    $b.Children.Add($sw) | Out-Null
    $b.Children.Add((New-KeyValueRow -Key 'Health measured' -Value $h.healthCoverage)) | Out-Null
    $b.Children.Add((New-KeyValueRow -Key 'With issues' -Value ([string]$h.withIssues))) | Out-Null
    $grid.Children.Add((New-Card -Title 'Agent Health' -Body $b -Col 0 -Row 0)) | Out-Null

    # Open Issues
    $b = New-Object Windows.Controls.StackPanel
    $b.Children.Add((New-Text -Text ("{0} open flags" -f $iss.Count) -Size 15 -Weight 'Bold' -Margin (New-Object Windows.Thickness (0, 0, 0, 6)))) | Out-Null
    foreach ($x in ($iss | Select-Object -First 6)) {
        $r = New-Object Windows.Controls.DockPanel; $r.Margin = New-Object Windows.Thickness (0, 0, 0, 4)
        $cp = New-Chip -Text $x.id -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk; $cp.VerticalAlignment = 'Top'; [Windows.Controls.DockPanel]::SetDock($cp, 'Left'); $r.Children.Add($cp) | Out-Null
        $tx = New-Text -Text $x.title -Size 11.5 -Wrap $true; $tx.Margin = New-Object Windows.Thickness (4, 2, 0, 0); $r.Children.Add($tx) | Out-Null
        $b.Children.Add($r) | Out-Null
    }
    $grid.Children.Add((New-Card -Title 'Open Issues' -Body $b -Col 1 -Row 0)) | Out-Null

    # Action Items
    $b = New-Object Windows.Controls.StackPanel
    $b.Children.Add((New-Text -Text ("{0} open" -f $openAI.Count) -Size 15 -Weight 'Bold' -Margin (New-Object Windows.Thickness (0, 0, 0, 6)))) | Out-Null
    $b.Children.Add((New-ActionItemsSnapshot -Max 6)) | Out-Null
    $grid.Children.Add((New-Card -Title 'Action Items' -Body $b -Col 2 -Row 0)) | Out-Null

    # Current Sprint
    $b = New-Object Windows.Controls.StackPanel
    $b.Children.Add((New-Text -Text $m.sprint -Size 14 -Weight 'SemiBold' -Wrap $true)) | Out-Null
    $b.Children.Add((New-Chip -Text 'Active' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk)) | Out-Null
    $grid.Children.Add((New-Card -Title 'Current Sprint' -Body $b -Col 3 -Row 0)) | Out-Null

    # Tony Recommendations
    $b = New-Object Windows.Controls.StackPanel
    foreach ($rc in $m.tonyRecommends) {
        $r = New-Object Windows.Controls.DockPanel; $r.Margin = New-Object Windows.Thickness (0, 0, 0, 6)
        $dot = New-Text -Text '*' -Size 14 -Weight 'Bold' -Color $script:Col.Accent; $dot.Margin = New-Object Windows.Thickness (0, 0, 6, 0); $dot.VerticalAlignment = 'Top'; [Windows.Controls.DockPanel]::SetDock($dot, 'Left'); $r.Children.Add($dot) | Out-Null
        $r.Children.Add((New-Text -Text $rc.text -Size 11.5 -Wrap $true)) | Out-Null
        $b.Children.Add($r) | Out-Null
    }
    $grid.Children.Add((New-Card -Title 'Tony Recommendations' -Body $b -Col 0 -Row 1)) | Out-Null

    # Agency Overview (placeholder)
    $b = New-Object Windows.Controls.StackPanel
    foreach ($mt in $m.agencyMetrics.items) { $b.Children.Add((New-KeyValueRow -Key $mt.label -Value $mt.value)) | Out-Null }
    $grid.Children.Add((New-Card -Title 'Agency Overview' -Body $b -Tag 'SAMPLE' -Col 1 -Row 1)) | Out-Null

    # Upcoming Appointments (placeholder)
    $b = New-Object Windows.Controls.StackPanel
    foreach ($ap in $m.appointments.items) {
        $b.Children.Add((New-Text -Text ("{0}  {1}" -f $ap.time, $ap.title) -Size 12 -Weight 'SemiBold' -Wrap $true)) | Out-Null
        $b.Children.Add((New-Text -Text $ap.who -Size 11 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 0, 0, 6)))) | Out-Null
    }
    $grid.Children.Add((New-Card -Title 'Upcoming Appointments' -Body $b -Tag 'SAMPLE' -Col 2 -Row 1)) | Out-Null

    # System Status
    $b = New-Object Windows.Controls.StackPanel
    $b.Children.Add((New-KeyValueRow -Key 'Registry' -Value ("v{0}" -f $reg.meta.version))) | Out-Null
    $b.Children.Add((New-KeyValueRow -Key 'Verified vs scheduler' -Value $(if ($h.verified) { 'Yes' } else { 'No' }) -ValueColor $(if ($h.verified) { '#34D399' } else { '#F87171' }))) | Out-Null
    $b.Children.Add((New-KeyValueRow -Key 'Health measured' -Value $h.healthCoverage)) | Out-Null
    $b.Children.Add((New-KeyValueRow -Key 'Open issues' -Value ([string]$m.issueCount))) | Out-Null
    $b.Children.Add((New-KeyValueRow -Key 'Registry updated' -Value $reg.meta.last_updated)) | Out-Null
    $b.Children.Add((New-KeyValueRow -Key 'As of' -Value ("{0}  {1}" -f $m.dateText, $m.timeText))) | Out-Null
    $grid.Children.Add((New-Card -Title 'System Status' -Body $b -Col 3 -Row 1)) | Out-Null

    $outer.Children.Add($grid) | Out-Null
    $scroll = New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility = 'Auto'; $scroll.Content = $outer
    return $scroll
}

# =====================  MULTI-WINDOW ("Mission Control" popouts)  =====================
$script:OpenWindows = @()

function New-PopoutSection {
    param([string]$Title, [string]$Subtitle, [Windows.UIElement]$Body)
    $sp = New-Object Windows.Controls.StackPanel
    $sp.Children.Add((New-Text -Text $Title -Size 22 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
    if ($Subtitle) { $sp.Children.Add((New-Text -Text $Subtitle -Size 12 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 0, 0, 10)))) | Out-Null }
    $sp.Children.Add($Body) | Out-Null
    $scroll = New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility = 'Auto'; $scroll.Content = $sp
    return $scroll
}

# Builds a self-contained, read-only live view for a separate window (no shared state).
function New-WindowContent {
    param([Parameter(Mandatory)][string]$Name)
    $root = New-Object Windows.Controls.DockPanel

    # branded header strip
    $hdr = New-Object Windows.Controls.Border; $hdr.Background = New-Brush $script:Col.Primary; $hdr.Padding = New-Object Windows.Thickness (18, 12, 18, 12)
    $hdrDock = New-Object Windows.Controls.DockPanel
    $left = New-Object Windows.Controls.StackPanel; $left.Orientation = 'Horizontal'
    $logoSrc = New-ImageSource $script:Theme.logoPath
    if ($logoSrc) {
        $img = New-Object Windows.Controls.Image; $img.Source = $logoSrc; $img.Height = 26; $img.Width = 26; $img.Margin = New-Object Windows.Thickness (0, 0, 10, 0)
        $lb = New-Object Windows.Controls.Border; $lb.CornerRadius = New-Object Windows.CornerRadius 6; $lb.ClipToBounds = $true; $lb.Child = $img; $lb.VerticalAlignment = 'Center'; $left.Children.Add($lb) | Out-Null
    }
    $left.Children.Add((New-Text -Text 'GIOK' -Size 15 -Weight 'Bold' -Color $script:Col.OnPrimary)) | Out-Null
    $left.Children.Add((New-Text -Text (' - ' + $Name) -Size 15 -Weight 'SemiBold' -Color $script:Col.Accent)) | Out-Null
    $left2 = $left; $left2.VerticalAlignment = 'Center'
    [Windows.Controls.DockPanel]::SetDock($left, 'Left'); $hdrDock.Children.Add($left) | Out-Null
    $stamp = New-Text -Text ('{0}  -  {1}' -f (Get-Date).ToString('ddd, MMM d'), (Get-Date).ToString('h:mm tt')) -Size 11.5 -Color $script:Col.OnPrimaryMuted; $stamp.HorizontalAlignment = 'Right'; $stamp.VerticalAlignment = 'Center'
    $hdrDock.Children.Add($stamp) | Out-Null
    $hdr.Child = $hdrDock
    [Windows.Controls.DockPanel]::SetDock($hdr, 'Top'); $root.Children.Add($hdr) | Out-Null

    # body
    $bodyBorder = New-Object Windows.Controls.Border; $bodyBorder.Background = New-Brush $script:Col.AppBg; $bodyBorder.Padding = New-Object Windows.Thickness (20, 16, 20, 18)
    $content = switch ($Name) {
        'Mission Control' { New-MissionControlView }
        'Agents'          { New-AgentsView -Agents (Get-AgentsList) }
        'Issues'          { New-MarkdownView -Title 'Open Issues'   -Text (Get-DocText 'issues_log.md') }
        'Weekly Review'   { New-MarkdownView -Title 'Weekly Review' -Text (Get-DocText 'weekly_status.md') }
        'Roadmap'         { New-MarkdownView -Title 'Roadmap'       -Text (Get-DocText 'ROADMAP.md') }
        'Action Items'    { New-PopoutSection -Title 'Action Items'         -Subtitle 'Live view - edit in the main window' -Body (New-ActionItemsSnapshot) }
        'Recommendations' { New-PopoutSection -Title 'Tony Recommends'      -Subtitle 'Live signals + sample nudges'        -Body (New-RecommendationsBody) }
        'Agency'          { New-PopoutSection -Title 'Agency Overview'      -Subtitle 'Coming soon - sample data'           -Body (New-AgencyBody) }
        'Appointments'    { New-PopoutSection -Title 'Upcoming Appointments'-Subtitle 'Coming soon - sample data'           -Body (New-AppointmentsBody) }
        default           { New-MissionControlView }
    }
    $bodyBorder.Child = $content
    $root.Children.Add($bodyBorder) | Out-Null
    return $root
}

function Open-TonyWindow {
    param([Parameter(Mandatory)][string]$Name)
    # Home/Settings don't have a meaningful standalone popout -> use Mission Control
    $target = if ($Name -in @('Home', 'Settings')) { 'Mission Control' } else { $Name }
    $win = New-Object Windows.Window
    $win.Title = "GIOK - $target"
    $win.WindowStartupLocation = 'CenterScreen'
    if ($target -eq 'Mission Control') { $win.Width = 1400; $win.Height = 900 } else { $win.Width = 1000; $win.Height = 780 }
    $win.MinWidth = 720; $win.MinHeight = 520
    $win.Background = New-Brush $script:Col.AppBg
    if ($script:Theme.logoPath -and (Test-Path $script:Theme.logoPath)) {
        $ico = New-Object Windows.Media.Imaging.BitmapImage; $ico.BeginInit(); $ico.CacheOption = 'OnLoad'; $ico.UriSource = New-Object Uri($script:Theme.logoPath); $ico.EndInit(); $win.Icon = $ico
    }
    $win.Content = New-WindowContent -Name $target
    $script:OpenWindows += $win
    $win.Add_Closed({ param($s, $e) $script:OpenWindows = @($script:OpenWindows | Where-Object { $_ -ne $s }) }) | Out-Null
    $null = $win.Show()
    return $win
}

# =====================  NAV + SHELL  =====================
function Set-ActiveView {
    param([Parameter(Mandatory)][string]$Name)
    $script:TonyActiveView = $Name
    foreach ($n in $script:TonyNav) {
        if ($n.Name -eq $Name) { $n.Border.Background = New-Brush $script:Col.Accent; $n.Text.Foreground = New-Brush $script:Col.OnPrimary }
        else { $n.Border.Background = New-Brush $script:Col.Primary; $n.Text.Foreground = New-Brush $script:Col.OnPrimaryMuted }
    }
    $body = switch ($Name) {
        'Home'         { New-HomeView       -Model (Get-HomeModel -Now $script:TonyNow) }
        'Agents'       { New-AgentsView     -Agents (Get-AgentsList) }
        'Issues'       { New-MarkdownView   -Title 'Open Issues'   -Text (Get-DocText 'issues_log.md') }
        'Action Items' { New-ActionItemsView }
        'Weekly Review'{ New-MarkdownView   -Title 'Weekly Review' -Text (Get-DocText 'weekly_status.md') }
        'Roadmap'      { New-MarkdownView   -Title 'Roadmap'       -Text (Get-DocText 'ROADMAP.md') }
        'Settings'     { New-SettingsView }
        'Agency'         { New-AgencyView }
        'Appointments'   { New-AppointmentsView }
        'Recommendations'{ New-RecommendationsView }
        'Mission Control'{ New-MissionControlView }
        default        { New-HomeView       -Model (Get-HomeModel -Now $script:TonyNow) }
    }
    $script:TonyBody.Child = $body
}

function New-SidebarNavItem {
    param([string]$Name)
    $b = New-Object Windows.Controls.Border
    $b.CornerRadius = New-Object Windows.CornerRadius 8; $b.Padding = New-Object Windows.Thickness (12, 9, 12, 9)
    $b.Margin = New-Object Windows.Thickness (0, 0, 0, 4); $b.Cursor = 'Hand'; $b.Tag = $Name; $b.HorizontalAlignment = 'Stretch'
    $t = New-Text -Text $Name -Size 13 -Weight 'SemiBold' -Color $script:Col.OnPrimaryMuted
    $b.Child = $t
    $b.Add_MouseLeftButtonUp({ param($s, $e) Set-ActiveView $s.Tag }) | Out-Null
    return [pscustomobject]@{ Name = $Name; Border = $b; Text = $t }
}

function New-TonyShell {
    param([string]$InitialView = 'Home', [datetime]$Now = (Get-Date), [Parameter(Mandatory)] $Theme)
    Initialize-TonyTheme -Theme $Theme
    $script:TonyNow = $Now
    $script:TonyNav = @()

    $root = New-Object Windows.Controls.Grid
    $cSide = New-Object Windows.Controls.ColumnDefinition; $cSide.Width = [Windows.GridLength]::new(238); $root.ColumnDefinitions.Add($cSide) | Out-Null
    $cMain = New-Object Windows.Controls.ColumnDefinition; $cMain.Width = [Windows.GridLength]::new(1, 'Star'); $root.ColumnDefinitions.Add($cMain) | Out-Null

    # ---------- sidebar ----------
    $side = New-Object Windows.Controls.Border; $side.Background = New-Brush $script:Col.Primary
    [Windows.Controls.Grid]::SetColumn($side, 0); $root.Children.Add($side) | Out-Null
    $sideGrid = New-Object Windows.Controls.Grid; $sideGrid.Margin = New-Object Windows.Thickness (16, 18, 16, 16)
    foreach ($h in 'Auto', 'Auto', '*', 'Auto', 'Auto', 'Auto') {
        $rd = New-Object Windows.Controls.RowDefinition
        $rd.Height = if ($h -eq '*') { [Windows.GridLength]::new(1, 'Star') } else { [Windows.GridLength]::Auto }
        $sideGrid.RowDefinitions.Add($rd) | Out-Null
    }
    $side.Child = $sideGrid

    # logo + wordmark
    $logoRow = New-Object Windows.Controls.StackPanel; $logoRow.Orientation = 'Horizontal'
    $logoSrc = New-ImageSource $Theme.logoPath
    if ($logoSrc) {
        $img = New-Object Windows.Controls.Image; $img.Source = $logoSrc; $img.Height = 34; $img.Width = 34; $img.Margin = New-Object Windows.Thickness (0, 0, 10, 0)
        $lb = New-Object Windows.Controls.Border; $lb.CornerRadius = New-Object Windows.CornerRadius 7; $lb.ClipToBounds = $true; $lb.Child = $img; $lb.VerticalAlignment = 'Center'
        $logoRow.Children.Add($lb) | Out-Null
    }
    $wmStack = New-Object Windows.Controls.StackPanel; $wmStack.VerticalAlignment = 'Center'
    $wmRow = New-Object Windows.Controls.StackPanel; $wmRow.Orientation = 'Horizontal'
    $wm = $Theme.companyWordmark -split ' ', 2
    $wmRow.Children.Add((New-Text -Text $wm[0] -Size 16 -Weight 'Bold' -Color $script:Col.OnPrimary)) | Out-Null
    if ($wm.Count -gt 1) { $wmRow.Children.Add((New-Text -Text (' ' + $wm[1]) -Size 16 -Weight 'Bold' -Color $script:Col.Accent)) | Out-Null }
    $wmStack.Children.Add($wmRow) | Out-Null
    $wmStack.Children.Add((New-Text -Text 'Tony - AI Chief of Staff' -Size 10.5 -Color $script:Col.OnPrimaryMuted)) | Out-Null
    $logoRow.Children.Add($wmStack) | Out-Null
    [Windows.Controls.Grid]::SetRow($logoRow, 0); $sideGrid.Children.Add($logoRow) | Out-Null

    # profile block
    $prof = New-Object Windows.Controls.StackPanel; $prof.Margin = New-Object Windows.Thickness (0, 20, 0, 16); $prof.HorizontalAlignment = 'Left'
    $profSrc = New-ImageSource $Theme.profilePath
    if ($profSrc) {
        $ell = New-Object Windows.Shapes.Ellipse; $ell.Width = 66; $ell.Height = 66; $ell.HorizontalAlignment = 'Left'
        $ib = New-Object Windows.Media.ImageBrush; $ib.ImageSource = $profSrc; $ib.Stretch = 'UniformToFill'
        $ell.Fill = $ib; $ell.Stroke = New-Brush $script:Col.Accent; $ell.StrokeThickness = 2.5; $ell.Margin = New-Object Windows.Thickness (0, 0, 0, 8)
        $prof.Children.Add($ell) | Out-Null
    }
    if ($Theme.profileName) { $prof.Children.Add((New-Text -Text $Theme.profileName -Size 15 -Weight 'Bold' -Color $script:Col.OnPrimary)) | Out-Null }
    $prof.Children.Add((New-Text -Text 'Licensed Insurance Agent' -Size 11 -Color $script:Col.OnPrimaryMuted -Wrap $true)) | Out-Null
    $prof.Children.Add((New-Text -Text $Theme.companyWordmark -Size 11 -Weight 'SemiBold' -Color $script:Col.Accent -Margin (New-Object Windows.Thickness (0, 1, 0, 0)))) | Out-Null
    [Windows.Controls.Grid]::SetRow($prof, 1); $sideGrid.Children.Add($prof) | Out-Null

    # nav
    $nav = New-Object Windows.Controls.StackPanel; $nav.VerticalAlignment = 'Top'
    foreach ($name in @('Home', 'Mission Control', 'Agents', 'Issues', 'Action Items', 'Weekly Review', 'Roadmap')) {
        $item = New-SidebarNavItem -Name $name; $script:TonyNav += $item; $nav.Children.Add($item.Border) | Out-Null
    }
    [Windows.Controls.Grid]::SetRow($nav, 2); $sideGrid.Children.Add($nav) | Out-Null

    # settings (row 3)
    $setItem = New-SidebarNavItem -Name 'Settings'; $script:TonyNav += $setItem
    [Windows.Controls.Grid]::SetRow($setItem.Border, 3); $sideGrid.Children.Add($setItem.Border) | Out-Null

    # clock (row 4)
    $clock = New-Text -Text ('{0}  -  {1}' -f $Now.ToString('ddd, MMM d'), $Now.ToString('h:mm tt')) -Size 11 -Color $script:Col.OnPrimaryMuted -Margin (New-Object Windows.Thickness (2, 8, 0, 0))
    [Windows.Controls.Grid]::SetRow($clock, 4); $sideGrid.Children.Add($clock) | Out-Null

    # version (row 5)
    $ver = New-Text -Text ("v{0}" -f $Theme.version) -Size 10.5 -Color $script:Col.OnPrimaryMuted -Margin (New-Object Windows.Thickness (2, 4, 0, 0))
    [Windows.Controls.Grid]::SetRow($ver, 5); $sideGrid.Children.Add($ver) | Out-Null

    # ---------- main body: persistent toolbar + swappable view host ----------
    $bodyOuter = New-Object Windows.Controls.Border; $bodyOuter.Background = New-Brush $script:Col.AppBg
    [Windows.Controls.Grid]::SetColumn($bodyOuter, 1); $root.Children.Add($bodyOuter) | Out-Null
    $bodyDock = New-Object Windows.Controls.DockPanel; $bodyOuter.Child = $bodyDock

    $toolbar = New-Object Windows.Controls.Border; $toolbar.Padding = New-Object Windows.Thickness (22, 12, 22, 6)
    $tbDock = New-Object Windows.Controls.DockPanel
    $tbBtns = New-Object Windows.Controls.StackPanel; $tbBtns.Orientation = 'Horizontal'; $tbBtns.HorizontalAlignment = 'Right'
    $tbBtns.Children.Add((New-MiniButton -Text 'Open Mission Control' -Bg $script:Col.Accent -Fg $script:Col.OnPrimary -OnClick { param($s, $e) Open-TonyWindow -Name 'Mission Control' | Out-Null })) | Out-Null
    $tbBtns.Children.Add((New-MiniButton -Text 'Open in New Window' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -OnClick { param($s, $e) Open-TonyWindow -Name $script:TonyActiveView | Out-Null })) | Out-Null
    [Windows.Controls.DockPanel]::SetDock($tbBtns, 'Right'); $tbDock.Children.Add($tbBtns) | Out-Null
    $toolbar.Child = $tbDock
    [Windows.Controls.DockPanel]::SetDock($toolbar, 'Top'); $bodyDock.Children.Add($toolbar) | Out-Null

    $viewHost = New-Object Windows.Controls.Border; $viewHost.Padding = New-Object Windows.Thickness (22, 8, 22, 18)
    $bodyDock.Children.Add($viewHost) | Out-Null
    $script:TonyBody = $viewHost

    Set-ActiveView $InitialView
    return [pscustomobject]@{ Root = $root; ClockBlock = $clock }
}
