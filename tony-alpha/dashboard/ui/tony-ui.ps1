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
$script:CmdPlaceholder = 'Quick command...   open agents   -   add task: call the Millers   -   press Ctrl+K to Talk with Tony'

function New-CommandBar {
    $wrap = New-Object Windows.Controls.Border
    $wrap.Background = New-Brush $script:Col.CardBg; $wrap.CornerRadius = New-Object Windows.CornerRadius 10
    $wrap.BorderBrush = New-Brush $script:Col.Accent; $wrap.BorderThickness = New-Object Windows.Thickness 1
    $wrap.Padding = New-Object Windows.Thickness (14, 9, 14, 9); $wrap.Margin = New-Object Windows.Thickness (0, 0, 0, 14)

    $dp = New-Object Windows.Controls.DockPanel
    $label = New-Text -Text 'Quick Command' -Size 13 -Weight 'Bold' -Color $script:Col.Accent; $label.VerticalAlignment = 'Center'; $label.Margin = New-Object Windows.Thickness (0, 0, 12, 0)
    [Windows.Controls.DockPanel]::SetDock($label, 'Left'); $dp.Children.Add($label) | Out-Null
    $hint = New-Text -Text 'Ctrl+K  Talk with Tony' -Size 11 -Weight 'SemiBold' -Color $script:Col.Muted; $hint.VerticalAlignment = 'Center'; $hint.Margin = New-Object Windows.Thickness (10, 0, 0, 0)
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
            'capture'  { $d = Get-CaptureData; Add-Capture -Data $d -Text $res.text -CreatedFrom 'command-bar' | Out-Null; Save-CaptureData $d; $script:CommandResult = ("Captured to Inbox: {0}" -f $res.text); Set-ActiveView 'Home' }
            'unknown'  {
                # Not a quick command -> a general question. Open the conversation
                # window and let Tony answer there (a real conversation, not a one-off).
                $q = $s.Text
                $s.Text = $script:CmdPlaceholder; $s.Foreground = New-Brush $script:Col.Muted; $s.Tag = 'placeholder'
                if (Get-Command Open-TonyConversation -ErrorAction SilentlyContinue) { Open-TonyConversation -Seed $q | Out-Null }
                elseif (Get-Command Invoke-TonyBrain -ErrorAction SilentlyContinue) { $brain = Invoke-TonyBrain -UserInput $q -CurrentWorkspace $script:TonyActiveView; $script:CommandResult = ("Tony: {0}" -f $brain.message); Set-ActiveView 'Home' }
            }
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

# =====================  TALK WITH TONY (conversation window)  =====================
# The primary AI interaction: a dedicated window that feels like messaging
# your Chief of Staff, not a search box. History persists (conversation.json);
# closing the window never erases it. Quick commands still execute instantly;
# general questions go to Tony Brain.
$script:TonyActiveProject = $null   # current project context (future); null until projects exist
$script:ConvWindow        = $null
$script:ConvMessagesPanel = $null
$script:ConvScroll        = $null
$script:ConvInput         = $null
$script:ConvThinkingRow   = $null
$script:ConvInputPlaceholder = 'Message Tony...   (Enter to send, Shift+Enter for a new line)'

# One chat bubble: user (accent, right) or Tony (card, left). New bubbles
# fade + slide in for a calm, executive feel.
function New-ConvBubble {
    param([ValidateSet('user', 'tony')][string]$Role, [string]$Text, [string]$Time = '', [bool]$Animate = $false)
    $isUser = ($Role -eq 'user')
    $bubble = New-Object Windows.Controls.Border
    $bubble.CornerRadius = New-Object Windows.CornerRadius 14
    $bubble.Padding = New-Object Windows.Thickness (14, 10, 14, 10)
    $bubble.MaxWidth = 430
    if ($isUser) { $bubble.Background = New-Brush $script:Col.Accent }
    else { $bubble.Background = New-Brush $script:Col.CardBg; $bubble.BorderBrush = New-Brush $script:Col.Line; $bubble.BorderThickness = New-Object Windows.Thickness 1 }

    $inner = New-Object Windows.Controls.StackPanel
    if (-not $isUser) { $inner.Children.Add((New-Text -Text 'TONY' -Size 9.5 -Weight 'Bold' -Color $script:Col.Accent -Margin (New-Object Windows.Thickness (0, 0, 0, 3)))) | Out-Null }
    $fg = if ($isUser) { $script:Col.OnPrimary } else { $script:Col.Ink }
    $inner.Children.Add((New-Text -Text $Text -Size 13.5 -Color $fg -Wrap $true)) | Out-Null
    if ($Time) {
        $tcol = if ($isUser) { $script:Col.OnPrimaryMuted } else { $script:Col.Muted }
        $inner.Children.Add((New-Text -Text $Time -Size 9.5 -Color $tcol -Margin (New-Object Windows.Thickness (0, 4, 0, 0)))) | Out-Null
    }
    $bubble.Child = $inner

    $row = New-Object Windows.Controls.StackPanel
    $row.Margin = New-Object Windows.Thickness (0, 0, 0, 10)
    $row.HorizontalAlignment = if ($isUser) { 'Right' } else { 'Left' }
    $row.Children.Add($bubble) | Out-Null

    if ($Animate) {
        $row.Opacity = 0
        $tt = New-Object Windows.Media.TranslateTransform; $tt.Y = 10; $row.RenderTransform = $tt
        $ease = New-Object Windows.Media.Animation.CubicEase; $ease.EasingMode = 'EaseOut'
        $fade = New-Object Windows.Media.Animation.DoubleAnimation(0, 1, (New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(260)))); $fade.EasingFunction = $ease
        $slide = New-Object Windows.Media.Animation.DoubleAnimation(10, 0, (New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(260)))); $slide.EasingFunction = $ease
        $row.BeginAnimation([Windows.UIElement]::OpacityProperty, $fade)
        $tt.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $slide)
    }
    return $row
}

function Add-ConvBubble {
    param([string]$Role, [string]$Text, [string]$Time = '', [bool]$Animate = $true)
    if (-not $script:ConvMessagesPanel) { return }
    $script:ConvMessagesPanel.Children.Add((New-ConvBubble -Role $Role -Text $Text -Time $Time -Animate $Animate)) | Out-Null
    if ($script:ConvScroll) { $script:ConvScroll.ScrollToEnd() }
}

function Show-ConvThinking {
    if (-not $script:ConvMessagesPanel) { return }
    $bubble = New-Object Windows.Controls.Border
    $bubble.CornerRadius = New-Object Windows.CornerRadius 14; $bubble.Padding = New-Object Windows.Thickness (14, 10, 14, 10)
    $bubble.Background = New-Brush $script:Col.CardBg; $bubble.BorderBrush = New-Brush $script:Col.Line; $bubble.BorderThickness = New-Object Windows.Thickness 1
    $bubble.Child = (New-Text -Text 'Tony is thinking...' -Size 13 -Color $script:Col.Muted)
    $row = New-Object Windows.Controls.StackPanel; $row.Margin = New-Object Windows.Thickness (0, 0, 0, 10); $row.HorizontalAlignment = 'Left'
    $row.Children.Add($bubble) | Out-Null
    $pulse = New-Object Windows.Media.Animation.DoubleAnimation(0.45, 1.0, (New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(700))))
    $pulse.AutoReverse = $true; $pulse.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
    $bubble.BeginAnimation([Windows.UIElement]::OpacityProperty, $pulse)
    $script:ConvThinkingRow = $row
    $script:ConvMessagesPanel.Children.Add($row) | Out-Null
    if ($script:ConvScroll) { $script:ConvScroll.ScrollToEnd() }
}

function Hide-ConvThinking {
    if ($script:ConvThinkingRow -and $script:ConvMessagesPanel) {
        $script:ConvMessagesPanel.Children.Remove($script:ConvThinkingRow) | Out-Null
    }
    $script:ConvThinkingRow = $null
}

# Send a turn: persist + show the user bubble, execute quick commands
# instantly, otherwise ask Tony Brain (deferred so the thinking indicator
# paints before any blocking call).
# ---- memory permission prompt (D12): Tony asks, never assumes ----
$script:MemPromptInner = $null
$script:MemPromptCandidate = $null
$script:MemEditPromptBox = $null

function New-MemChoiceChip {
    param([string]$Text, [scriptblock]$OnClick, [bool]$Primary = $false)
    $b = New-Object Windows.Controls.Border
    $b.CornerRadius = New-Object Windows.CornerRadius 9; $b.Padding = New-Object Windows.Thickness (11, 5, 11, 5); $b.Margin = New-Object Windows.Thickness (0, 0, 7, 7); $b.Cursor = 'Hand'
    if ($Primary) { $b.Background = New-Brush $script:Col.Accent; $fg = $script:Col.OnPrimary } else { $b.Background = New-Brush $script:Col.AccentSoft; $fg = $script:Col.AccentInk }
    $b.Child = (New-Text -Text $Text -Size 12 -Weight 'SemiBold' -Color $fg)
    if ($OnClick) { $b.Add_MouseLeftButtonUp($OnClick) | Out-Null }
    return $b
}

# Replace the live prompt content with a short confirmation once resolved.
function Set-MemPromptDone {
    param([string]$Msg)
    if (-not $script:MemPromptInner) { return }
    $script:MemPromptInner.Children.Clear()
    $script:MemPromptInner.Children.Add((New-Text -Text 'TONY' -Size 9.5 -Weight 'Bold' -Color $script:Col.Accent -Margin (New-Object Windows.Thickness (0, 0, 0, 3)))) | Out-Null
    $script:MemPromptInner.Children.Add((New-Text -Text $Msg -Size 13.5 -Color $script:Col.Ink -Wrap $true)) | Out-Null
    $script:MemPromptInner = $null; $script:MemPromptCandidate = $null; $script:MemEditPromptBox = $null
    if ($script:ConvScroll) { $script:ConvScroll.ScrollToEnd() }
}

# "Edit" turns the prompt into an editable value + Save, so the user
# remembers exactly what they mean - Tony still only saves on Save.
function Build-MemPromptEdit {
    $inner = $script:MemPromptInner; $c = $script:MemPromptCandidate
    if (-not $inner -or -not $c) { return }
    $inner.Children.Clear()
    $inner.Children.Add((New-Text -Text 'TONY' -Size 9.5 -Weight 'Bold' -Color $script:Col.Accent -Margin (New-Object Windows.Thickness (0, 0, 0, 3)))) | Out-Null
    $inner.Children.Add((New-Text -Text 'Adjust what I should remember, then save it:' -Size 13 -Color $script:Col.Ink -Wrap $true)) | Out-Null
    $tb = New-Object Windows.Controls.TextBox
    $tb.FontFamily = New-Object Windows.Media.FontFamily $script:Font; $tb.FontSize = 13; $tb.AcceptsReturn = $true; $tb.TextWrapping = 'Wrap'; $tb.MinHeight = 44
    $tb.Padding = New-Object Windows.Thickness (9, 6, 9, 6); $tb.Background = New-Brush $script:Col.PrimaryMid; $tb.Foreground = New-Brush $script:Col.Ink; $tb.BorderBrush = New-Brush $script:Col.Accent; $tb.CaretBrush = New-Brush $script:Col.Accent
    $tb.Text = [string]$c.value; $tb.Margin = New-Object Windows.Thickness (0, 6, 0, 6)
    $script:MemEditPromptBox = $tb
    $inner.Children.Add($tb) | Out-Null
    $wrap = New-Object Windows.Controls.WrapPanel
    $wrap.Children.Add((New-MemChoiceChip -Text 'Save to memory' -Primary $true -OnClick { param($s, $e) $c = $script:MemPromptCandidate; $val = if ($script:MemEditPromptBox) { $script:MemEditPromptBox.Text } else { $c.value }; Approve-Memory -Category $c.category -Value $val -Why $c.why -Source 'talk-with-tony' | Out-Null; Set-MemPromptDone 'Saved - I''ll remember that. You can change or remove it anytime in Memory.' })) | Out-Null
    $wrap.Children.Add((New-MemChoiceChip -Text 'Cancel' -OnClick { param($s, $e) Set-MemPromptDone 'No problem - I won''t keep that.' })) | Out-Null
    $inner.Children.Add($wrap) | Out-Null
    if ($script:ConvScroll) { $script:ConvScroll.ScrollToEnd() }
}

function New-MemoryPromptRow {
    param($Candidate)
    $bubble = New-Object Windows.Controls.Border
    $bubble.CornerRadius = New-Object Windows.CornerRadius 14; $bubble.Padding = New-Object Windows.Thickness (14, 10, 14, 12); $bubble.MaxWidth = 440
    $bubble.Background = New-Brush $script:Col.CardBg; $bubble.BorderBrush = New-Brush $script:Col.Accent; $bubble.BorderThickness = New-Object Windows.Thickness 1
    $inner = New-Object Windows.Controls.StackPanel
    $script:MemPromptInner = $inner; $script:MemPromptCandidate = $Candidate
    $inner.Children.Add((New-Text -Text 'TONY' -Size 9.5 -Weight 'Bold' -Color $script:Col.Accent -Margin (New-Object Windows.Thickness (0, 0, 0, 3)))) | Out-Null
    $prompt = New-MemoryPermissionPrompt $Candidate
    $inner.Children.Add((New-Text -Text $prompt.question -Size 13.5 -Color $script:Col.Ink -Wrap $true)) | Out-Null
    $inner.Children.Add((New-Text -Text ("[{0}]  {1}" -f $Candidate.category, $Candidate.value) -Size 12 -Weight 'SemiBold' -Color $script:Col.AccentInk -Wrap $true -Margin (New-Object Windows.Thickness (0, 5, 0, 0)))) | Out-Null
    $wrap = New-Object Windows.Controls.WrapPanel; $wrap.Margin = New-Object Windows.Thickness (0, 8, 0, 0)
    $wrap.Children.Add((New-MemChoiceChip -Text 'Remember' -Primary $true -OnClick { param($s, $e) $c = $script:MemPromptCandidate; Approve-Memory -Category $c.category -Value $c.value -Why $c.why -Source 'talk-with-tony' | Out-Null; Set-MemPromptDone 'Done - I''ll remember that. You can edit or remove it anytime in Memory.' })) | Out-Null
    $wrap.Children.Add((New-MemChoiceChip -Text 'Edit' -OnClick { param($s, $e) Build-MemPromptEdit })) | Out-Null
    $wrap.Children.Add((New-MemChoiceChip -Text 'Not Now' -OnClick { param($s, $e) Set-MemPromptDone 'No problem - I won''t keep that.' })) | Out-Null
    $wrap.Children.Add((New-MemChoiceChip -Text 'Never Ask Again' -OnClick { param($s, $e) $c = $script:MemPromptCandidate; Set-MemoryNeverAsk -Value $c.value -Category $c.category | Out-Null; Set-MemPromptDone 'Understood - I won''t ask about that again.' })) | Out-Null
    $inner.Children.Add($wrap) | Out-Null
    $bubble.Child = $inner
    $row = New-Object Windows.Controls.StackPanel; $row.Margin = New-Object Windows.Thickness (0, 0, 0, 10); $row.HorizontalAlignment = 'Left'
    $row.Children.Add($bubble) | Out-Null
    return $row
}

# After a reply, if the user's message contains something worth remembering
# (and Tony hasn't been told to stop asking), surface the permission prompt.
# Tony ASKS - he never saves on his own.
function Add-MemoryPromptIfAny {
    param([string]$Text)
    if (-not $script:ConvMessagesPanel) { return }
    if (-not (Get-Command Find-MemoryCandidates -ErrorAction SilentlyContinue)) { return }
    $c = @(Find-MemoryCandidates -Text $Text)
    if ($c.Count -eq 0) { return }
    if (-not (Test-MemoryShouldAsk $c[0])) { return }
    $script:ConvMessagesPanel.Children.Add((New-MemoryPromptRow -Candidate $c[0])) | Out-Null
    if ($script:ConvScroll) { $script:ConvScroll.ScrollToEnd() }
}

function Send-TonyMessage {
    param([string]$Text)
    $t = ''; if ($null -ne $Text) { $t = $Text.Trim() }
    if ($t -eq '') { return }

    # Capture the PRIOR turns BEFORE saving this one, so Tony gets the recent
    # conversation without the current question duplicated (keeps user/assistant
    # turns alternating for the provider).
    $priorHistory = @()
    if (Get-Command Get-RecentConversation -ErrorAction SilentlyContinue) { $priorHistory = @(Get-RecentConversation -Count 8) }

    $data = Get-ConversationLog
    Add-ConversationMessage -Data $data -Role 'user' -Text $t | Out-Null
    Save-ConversationLog -Data $data
    Add-ConvBubble -Role 'user' -Text $t -Time (Get-Date).ToString('h:mm tt') -Animate $true
    if ($script:ConvInput) { $script:ConvInput.Text = ''; $script:ConvInput.Tag = '' }

    # Quick commands still execute instantly - Tony confirms in a bubble.
    $reply = $null
    $cmd = Invoke-TonyCommand -Text $t
    switch ($cmd.type) {
        'navigate' { Set-ActiveView $cmd.target; $reply = "Opening $($cmd.target) in your dashboard." }
        'addtask'  { $d = Get-ActionItemsData; Add-ActionItem -Data $d -Title $cmd.title | Out-Null; Save-ActionItemsData $d; $reply = "Added to your Action Items: ""$($cmd.title)""." }
        'capture'  { $d = Get-CaptureData; Add-Capture -Data $d -Text $cmd.text -CreatedFrom 'talk-with-tony' | Out-Null; Save-CaptureData $d; $reply = "Captured to your inbox: ""$($cmd.text)""." }
    }
    if ($reply) {
        $rd = Get-ConversationLog; Add-ConversationMessage -Data $rd -Role 'tony' -Text $reply -Provider 'quick-command' | Out-Null; Save-ConversationLog -Data $rd
        Add-ConvBubble -Role 'tony' -Text $reply -Time (Get-Date).ToString('h:mm tt') -Animate $true
        Add-MemoryPromptIfAny -Text $t
        return
    }

    # General question -> Tony Brain (context: workspace + recent conversation).
    Show-ConvThinking
    $work = $script:TonyActiveView
    $respond = {
        $msg = 'I hear you.'; $provider = 'tony'
        if (Get-Command Invoke-TonyBrain -ErrorAction SilentlyContinue) {
            try {
                $brain = Invoke-TonyBrain -UserInput $t -CurrentWorkspace $work -History $priorHistory
                if ($brain.message) { $msg = $brain.message }
                if ($brain.provider) { $provider = $brain.provider }
            } catch { $msg = 'Something went sideways on my end - give me another try.' }
        }
        Hide-ConvThinking
        $rd = Get-ConversationLog; Add-ConversationMessage -Data $rd -Role 'tony' -Text $msg -Provider $provider | Out-Null; Save-ConversationLog -Data $rd
        Add-ConvBubble -Role 'tony' -Text $msg -Time (Get-Date).ToString('h:mm tt') -Animate $true
        Add-MemoryPromptIfAny -Text $t
    }.GetNewClosure()

    if ($script:ConvWindow) { $script:ConvWindow.Dispatcher.BeginInvoke([Action]$respond, [Windows.Threading.DispatcherPriority]::Background) | Out-Null }
    else { & $respond }
}

function New-ConvStarterChip {
    param([string]$Text)
    $b = New-Object Windows.Controls.Border
    $b.CornerRadius = New-Object Windows.CornerRadius 9; $b.Padding = New-Object Windows.Thickness (11, 6, 11, 6); $b.Margin = New-Object Windows.Thickness (0, 0, 7, 7); $b.Cursor = 'Hand'; $b.Tag = $Text
    $b.Background = New-Brush $script:Col.AccentSoft
    $b.Child = (New-Text -Text $Text -Size 12 -Weight 'SemiBold' -Color $script:Col.AccentInk)
    $b.Add_MouseLeftButtonUp({ param($s, $e) Send-TonyMessage -Text $s.Tag }) | Out-Null
    return $b
}

# Build the conversation window content: header, message history, typing area.
function New-ConversationView {
    $root = New-Object Windows.Controls.DockPanel; $root.LastChildFill = $true

    # ---- branded header ----
    $hdr = New-Object Windows.Controls.Border; $hdr.Background = New-Brush $script:Col.Primary; $hdr.Padding = New-Object Windows.Thickness (18, 13, 18, 13)
    $hdrRow = New-Object Windows.Controls.StackPanel; $hdrRow.Orientation = 'Horizontal'
    $logoSrc = New-ImageSource $script:Theme.logoPath
    if ($logoSrc) {
        $img = New-Object Windows.Controls.Image; $img.Source = $logoSrc; $img.Height = 30; $img.Width = 30; $img.Margin = New-Object Windows.Thickness (0, 0, 11, 0)
        $lb = New-Object Windows.Controls.Border; $lb.CornerRadius = New-Object Windows.CornerRadius 7; $lb.ClipToBounds = $true; $lb.Child = $img; $lb.VerticalAlignment = 'Center'; $hdrRow.Children.Add($lb) | Out-Null
    }
    $hdrText = New-Object Windows.Controls.StackPanel; $hdrText.VerticalAlignment = 'Center'
    $hdrText.Children.Add((New-Text -Text 'Talk with Tony' -Size 16 -Weight 'Bold' -Color $script:Col.OnPrimary)) | Out-Null
    $hdrText.Children.Add((New-Text -Text 'Your AI Chief of Staff' -Size 11 -Color $script:Col.Accent)) | Out-Null
    $hdrRow.Children.Add($hdrText) | Out-Null
    $hdr.Child = $hdrRow
    [Windows.Controls.DockPanel]::SetDock($hdr, 'Top'); $root.Children.Add($hdr) | Out-Null

    # ---- typing area (docked bottom) ----
    $inputWrap = New-Object Windows.Controls.Border; $inputWrap.Background = New-Brush $script:Col.Primary; $inputWrap.Padding = New-Object Windows.Thickness (14, 12, 14, 14)
    $inputDock = New-Object Windows.Controls.DockPanel
    $sendBtn = New-PrimaryButton -Text 'Send' -Size 13 -OnClick { param($s, $e) if ($script:ConvInput) { Send-TonyMessage -Text $script:ConvInput.Text } }
    $sendBtn.VerticalAlignment = 'Bottom'; $sendBtn.Margin = New-Object Windows.Thickness (10, 0, 0, 0)
    [Windows.Controls.DockPanel]::SetDock($sendBtn, 'Right'); $inputDock.Children.Add($sendBtn) | Out-Null

    $tb = New-Object Windows.Controls.TextBox
    $tb.FontFamily = New-Object Windows.Media.FontFamily $script:Font; $tb.FontSize = 13.5
    $tb.AcceptsReturn = $true; $tb.TextWrapping = 'Wrap'; $tb.MaxHeight = 120; $tb.MinHeight = 40; $tb.VerticalScrollBarVisibility = 'Auto'
    $tb.Padding = New-Object Windows.Thickness (11, 9, 11, 9)
    $tb.Background = New-Brush $script:Col.PrimaryMid; $tb.BorderBrush = New-Brush $script:Col.Line; $tb.BorderThickness = New-Object Windows.Thickness 1
    $tb.CaretBrush = New-Brush $script:Col.Accent
    $tb.Text = $script:ConvInputPlaceholder; $tb.Foreground = New-Brush $script:Col.Muted; $tb.Tag = 'placeholder'
    $tb.Add_GotFocus({ param($s, $e) if ($s.Tag -eq 'placeholder') { $s.Text = ''; $s.Foreground = New-Brush $script:Col.Ink; $s.Tag = '' } }) | Out-Null
    $tb.Add_LostFocus({ param($s, $e) if ([string]::IsNullOrEmpty($s.Text)) { $s.Text = $script:ConvInputPlaceholder; $s.Foreground = New-Brush $script:Col.Muted; $s.Tag = 'placeholder' } }) | Out-Null
    $tb.Add_PreviewKeyDown({
        param($s, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Return -and -not ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift)) {
            if ($s.Tag -ne 'placeholder') { Send-TonyMessage -Text $s.Text }
            $e.Handled = $true
        }
    }) | Out-Null
    $script:ConvInput = $tb
    $inputDock.Children.Add($tb) | Out-Null
    $inputWrap.Child = $inputDock
    [Windows.Controls.DockPanel]::SetDock($inputWrap, 'Bottom'); $root.Children.Add($inputWrap) | Out-Null

    # ---- message history (fills the middle) ----
    $panel = New-Object Windows.Controls.StackPanel; $panel.Margin = New-Object Windows.Thickness (16, 16, 16, 8)
    $script:ConvMessagesPanel = $panel

    # greeting is chrome, not a stored message
    $projName = if ($script:TonyActiveProject) { $script:TonyActiveProject } else { '' }
    $greet = Get-TonyConversationGreeting -Name $script:Theme.profileName -CurrentWorkspace $script:TonyActiveView -CurrentProject $projName -Now (Get-Date)
    $panel.Children.Add((New-ConvBubble -Role 'tony' -Text $greet -Animate $false)) | Out-Null

    # persisted history
    $log = Get-ConversationLog
    $hist = @($log.messages)
    if ($hist.Count -eq 0) {
        $chips = New-Object Windows.Controls.WrapPanel; $chips.Margin = New-Object Windows.Thickness (2, 2, 0, 6)
        foreach ($s in @('What should I focus on today?', 'Review my priorities', 'What did I capture recently?', 'Help me plan my day')) { $chips.Children.Add((New-ConvStarterChip -Text $s)) | Out-Null }
        $panel.Children.Add($chips) | Out-Null
    } else {
        foreach ($m in $hist) {
            $stamp = ''
            if ($m.timestamp) { try { $stamp = ([datetime]$m.timestamp).ToString('h:mm tt') } catch { } }
            $panel.Children.Add((New-ConvBubble -Role $m.role -Text $m.text -Time $stamp -Animate $false)) | Out-Null
        }
    }

    $scroll = New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility = 'Auto'; $scroll.HorizontalScrollBarVisibility = 'Disabled'; $scroll.Content = $panel
    $scroll.Background = New-Brush $script:Col.AppBg; $scroll.Padding = New-Object Windows.Thickness (2, 0, 2, 0)
    $script:ConvScroll = $scroll
    $root.Children.Add($scroll) | Out-Null   # LastChildFill -> fills remaining space

    return $root
}

# Open (or focus) the dedicated Tony Conversation window. Optional -Seed
# sends an opening message immediately (used when a general question is
# typed into the quick-command bar).
function Open-TonyConversation {
    param([string]$Seed = '')
    if ($script:ConvWindow) {
        $script:ConvWindow.Activate() | Out-Null
        if ($script:ConvInput) { $script:ConvInput.Focus() | Out-Null }
        if ($Seed) { Send-TonyMessage -Text $Seed }
        return $script:ConvWindow
    }
    $win = New-Object Windows.Window
    $win.Title = 'GIOK - Talk with Tony'
    $win.Width = 560; $win.Height = 760; $win.MinWidth = 420; $win.MinHeight = 560
    $win.WindowStartupLocation = 'CenterScreen'
    $win.Background = New-Brush $script:Col.AppBg
    if ($script:Theme.logoPath -and (Test-Path $script:Theme.logoPath)) {
        $ico = New-Object Windows.Media.Imaging.BitmapImage; $ico.BeginInit(); $ico.CacheOption = 'OnLoad'; $ico.UriSource = New-Object Uri($script:Theme.logoPath); $ico.EndInit(); $win.Icon = $ico
    }
    $win.Content = New-ConversationView
    $script:ConvWindow = $win
    $win.Add_Closed({ param($s, $e) $script:ConvWindow = $null; $script:ConvMessagesPanel = $null; $script:ConvScroll = $null; $script:ConvInput = $null; $script:ConvThinkingRow = $null }) | Out-Null
    $null = $win.Show()
    if ($script:ConvScroll) { $script:ConvScroll.ScrollToEnd() }
    if ($script:ConvInput) { $script:ConvInput.Focus() | Out-Null }
    if ($Seed) { Send-TonyMessage -Text $Seed }
    return $win
}

# =====================  MORNING EXPERIENCE (the "first minute")  =====================
# Built from independent, replaceable section components. Each New-ME* function
# renders one section from the model; New-MorningExperience composes them. Any
# section can be swapped without touching the others.
function New-MECenteredText {
    param([string]$Text, [double]$Size = 13, [string]$Weight = 'Normal', [string]$Color = $null, [bool]$Wrap = $true, [Windows.Thickness]$Margin = (New-Object Windows.Thickness 0))
    $t = New-Text -Text $Text -Size $Size -Weight $Weight -Color $Color -Wrap $Wrap -Margin $Margin
    $t.TextAlignment = 'Center'; $t.HorizontalAlignment = 'Center'
    return $t
}
function New-MELabel { param([string]$Text) return (New-MECenteredText -Text $Text -Size 10 -Weight 'Bold' -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 0, 0, 3))) }

function New-MEGreeting {
    param($M)
    $sp = New-Object Windows.Controls.StackPanel
    $sp.Children.Add((New-MECenteredText -Text $M.greeting -Size 34 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
    $sp.Children.Add((New-MECenteredText -Text $M.dateText -Size 13 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 2, 0, 0)))) | Out-Null
    return $sp
}

function New-MEPrinciple {
    param($M)
    $sp = New-Object Windows.Controls.StackPanel; $sp.HorizontalAlignment = 'Center'
    $pill = New-Object Windows.Controls.Border; $pill.Background = New-Brush $script:Col.AccentSoft; $pill.CornerRadius = New-Object Windows.CornerRadius 20; $pill.Padding = New-Object Windows.Thickness (16, 6, 16, 6); $pill.HorizontalAlignment = 'Center'
    $pill.Child = (New-MECenteredText -Text $M.dailyPrinciple -Size 12.5 -Weight 'SemiBold' -Color $script:Col.AccentInk)
    $sp.Children.Add((New-MELabel -Text "TODAY'S PRINCIPLE")) | Out-Null
    $sp.Children.Add($pill) | Out-Null
    return $sp
}

function New-METhought {
    param($M)
    $t = $M.thought
    $card = New-Object Windows.Controls.Border
    $card.Background = New-Brush $script:Col.CardBg; $card.CornerRadius = New-Object Windows.CornerRadius 14
    $card.BorderBrush = New-Brush $script:Col.Line; $card.BorderThickness = New-Object Windows.Thickness 1
    $card.Padding = New-Object Windows.Thickness (28, 22, 28, 22)
    $sp = New-Object Windows.Controls.StackPanel
    $sp.Children.Add((New-MECenteredText -Text '"' -Size 34 -Weight 'Bold' -Color $script:Col.Accent -Margin (New-Object Windows.Thickness (0, -6, 0, 0)))) | Out-Null
    $sp.Children.Add((New-MECenteredText -Text $t.quote -Size 20 -Weight 'SemiBold' -Color $script:Col.Heading)) | Out-Null
    $sp.Children.Add((New-MECenteredText -Text ("- {0}" -f $t.author) -Size 13.5 -Weight 'SemiBold' -Color $script:Col.AccentInk -Margin (New-Object Windows.Thickness (0, 10, 0, 0)))) | Out-Null
    $sp.Children.Add((New-MECenteredText -Text ("{0}  -  {1}  -  {2}" -f $t.theme, $t.category, $t.source) -Size 10.5 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 4, 0, 0)))) | Out-Null
    $card.Child = $sp
    return $card
}

function New-MEWhy {
    param($M)
    $sp = New-Object Windows.Controls.StackPanel; $sp.HorizontalAlignment = 'Center'
    $sp.Children.Add((New-MELabel -Text 'WHY THIS TODAY')) | Out-Null
    $sp.Children.Add((New-MECenteredText -Text $M.whyThisToday.text -Size 13 -Color $script:Col.Ink)) | Out-Null
    return $sp
}

function New-MEFocus {
    param($M)
    $sp = New-Object Windows.Controls.StackPanel; $sp.HorizontalAlignment = 'Center'
    $sp.Children.Add((New-MELabel -Text "TODAY'S FOCUS")) | Out-Null
    $sp.Children.Add((New-MECenteredText -Text $M.todaysFocus.text -Size 17 -Weight 'SemiBold' -Color $script:Col.Heading)) | Out-Null
    return $sp
}

function New-MEPriorities {
    param($M)
    $sp = New-Object Windows.Controls.StackPanel; $sp.HorizontalAlignment = 'Center'
    $sp.Children.Add((New-MELabel -Text "TODAY'S PRIORITIES")) | Out-Null
    if (@($M.topPriorities).Count -eq 0) { $sp.Children.Add((New-MECenteredText -Text 'All clear - no open priorities.' -Size 12.5 -Color $script:Col.Muted)) | Out-Null }
    else {
        $i = 1
        foreach ($p in $M.topPriorities) {
            $sp.Children.Add((New-MECenteredText -Text ("{0}.  {1}" -f $i, $p.title) -Size 13 -Color $script:Col.Ink -Margin (New-Object Windows.Thickness (0, 1, 0, 1)))) | Out-Null
            $i++
        }
    }
    return $sp
}

function New-MERecommendation {
    param($M)
    if (-not $M.recommendation) { return (New-Object Windows.Controls.StackPanel) }
    $sp = New-Object Windows.Controls.StackPanel; $sp.HorizontalAlignment = 'Center'
    $sp.Children.Add((New-MELabel -Text 'TONY RECOMMENDS')) | Out-Null
    $sp.Children.Add((New-MECenteredText -Text $M.recommendation.text -Size 13.5 -Weight 'SemiBold' -Color $script:Col.AccentInk)) | Out-Null
    return $sp
}

function New-MEBeginButton {
    $b = New-PrimaryButton -Text 'Begin My Day' -Size 16 -OnClick { param($s, $e) Set-ActiveView 'Home' }
    $b.HorizontalAlignment = 'Center'; $b.Padding = New-Object Windows.Thickness (30, 13, 30, 13)
    return $b
}

function New-MorningExperience {
    param([Parameter(Mandatory)] $Model)
    $col = New-Object Windows.Controls.StackPanel; $col.MaxWidth = 720; $col.HorizontalAlignment = 'Center'; $col.Margin = New-Object Windows.Thickness (0, 24, 0, 24)

    # each section is an independent component with its own spacing
    $sections = @(
        @{ el = (New-MEGreeting -M $Model);       gap = 18 }
        @{ el = (New-MEPrinciple -M $Model);      gap = 22 }
        @{ el = (New-METhought -M $Model);        gap = 20 }
        @{ el = (New-MEWhy -M $Model);            gap = 22 }
        @{ el = (New-MEFocus -M $Model);          gap = 22 }
        @{ el = (New-MEPriorities -M $Model);     gap = 22 }
        @{ el = (New-MERecommendation -M $Model); gap = 26 }
        @{ el = (New-MEBeginButton);              gap = 0  }
    )
    foreach ($s in $sections) {
        $s.el.Margin = New-Object Windows.Thickness (0, 0, 0, $s.gap)
        $col.Children.Add($s.el) | Out-Null
    }

    $scroll = New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility = 'Auto'; $scroll.HorizontalScrollBarVisibility = 'Disabled'; $scroll.Content = $col
    return $scroll
}

# =====================  MORNING BRIEFING  =====================
# Renders ONLY from the Morning Brief model (core/morning-brief.ps1). No
# dashboard logic here - purely presentation of Tony's prepared briefing.
function New-MorningBriefing {
    param([Parameter(Mandatory)] $Model)
    $m = $Model
    $wrap = New-Object Windows.Controls.StackPanel; $wrap.Margin = New-Object Windows.Thickness (0, 0, 0, 14)

    # ---- header: briefing tag + greeting + date  |  weather + prepared-by ----
    $hdr = New-Object Windows.Controls.DockPanel
    $right = New-Object Windows.Controls.StackPanel; $right.HorizontalAlignment = 'Right'
    $w = $m.weather
    $wbox = New-Object Windows.Controls.Border; $wbox.Background = New-Brush $script:Col.AccentSoft; $wbox.CornerRadius = New-Object Windows.CornerRadius 8; $wbox.Padding = New-Object Windows.Thickness (10, 6, 10, 6); $wbox.HorizontalAlignment = 'Right'
    $wbox.Child = (New-Text -Text ("{0}   {1}   -   {2}" -f $w.temp, $w.condition, $w.location) -Size 12.5 -Weight 'SemiBold' -Color $script:Col.AccentInk)
    $right.Children.Add($wbox) | Out-Null
    $pb = New-Text -Text ("Prepared by {0} - {1}" -f $m.preparedBy, $m.timeText) -Size 10.5 -Color $script:Col.Muted; $pb.HorizontalAlignment = 'Right'; $pb.Margin = New-Object Windows.Thickness (0, 6, 0, 0)
    $right.Children.Add($pb) | Out-Null
    [Windows.Controls.DockPanel]::SetDock($right, 'Right'); $hdr.Children.Add($right) | Out-Null
    $left = New-Object Windows.Controls.StackPanel
    $left.Children.Add((New-Text -Text "TONY'S MORNING BRIEFING" -Size 11 -Weight 'Bold' -Color $script:Col.Accent)) | Out-Null
    $left.Children.Add((New-Text -Text $m.greeting -Size 30 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
    $left.Children.Add((New-Text -Text $m.dateText -Size 12.5 -Color $script:Col.Muted)) | Out-Null
    $hdr.Children.Add($left) | Out-Null
    $wrap.Children.Add($hdr) | Out-Null

    # ---- daily principle ----
    $pr = New-Object Windows.Controls.Border; $pr.Background = New-Brush $script:Col.AccentSoft; $pr.CornerRadius = New-Object Windows.CornerRadius 8; $pr.Padding = New-Object Windows.Thickness (12, 8, 12, 8); $pr.Margin = New-Object Windows.Thickness (0, 10, 0, 12)
    $prSp = New-Object Windows.Controls.StackPanel
    $prSp.Children.Add((New-Text -Text "TODAY'S PRINCIPLE" -Size 9.5 -Weight 'Bold' -Color $script:Col.Muted)) | Out-Null
    $prSp.Children.Add((New-Text -Text ('"{0}"' -f $m.dailyPrinciple) -Size 15 -Weight 'SemiBold' -Color $script:Col.AccentInk -Wrap $true)) | Out-Null
    $pr.Child = $prSp
    $wrap.Children.Add($pr) | Out-Null

    # ---- briefing grid: Today's Priorities | Tony Recommends | Snapshot ----
    $g = New-Object Windows.Controls.Grid
    foreach ($i in 0..2) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = [Windows.GridLength]::new(1, 'Star'); $g.ColumnDefinitions.Add($cd) | Out-Null }

    # Today's Priorities
    $tp = New-Object Windows.Controls.StackPanel
    if (@($m.topPriorities).Count -eq 0) { $tp.Children.Add((New-Text -Text 'All clear - no open priorities.' -Size 13 -Color $script:Col.Muted)) | Out-Null }
    else {
        $i = 1
        foreach ($p in $m.topPriorities) {
            $row = New-Object Windows.Controls.DockPanel; $row.Margin = New-Object Windows.Thickness (0, 0, 0, 8)
            $badge = New-NumBadge -N $i; [Windows.Controls.DockPanel]::SetDock($badge, 'Left'); $row.Children.Add($badge) | Out-Null
            $iw = New-Object Windows.Controls.StackPanel
            $iw.Children.Add((New-Text -Text $p.title -Size 13.5 -Weight 'SemiBold' -Wrap $true)) | Out-Null
            $iw.Children.Add((New-Text -Text $p.id -Size 10.5 -Color $script:Col.Muted)) | Out-Null
            $row.Children.Add($iw) | Out-Null; $tp.Children.Add($row) | Out-Null; $i++
        }
    }
    $tp.Children.Add((New-Text -Text ("{0} open action items  -  {1} unprocessed captures" -f $m.openActionCount, $m.captureUnprocessed) -Size 11 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 4, 0, 0)))) | Out-Null
    $g.Children.Add((New-Card -Title "Today's Priorities" -Body $tp -Col 0 -NavTo 'Action Items')) | Out-Null

    # Tony Recommends
    $tr = New-Object Windows.Controls.StackPanel
    foreach ($r in $m.tonyRecommendations) {
        $row = New-Object Windows.Controls.DockPanel; $row.Margin = New-Object Windows.Thickness (0, 0, 0, 7)
        $dot = New-Text -Text '*' -Size 15 -Weight 'Bold' -Color $script:Col.Accent; $dot.Margin = New-Object Windows.Thickness (0, 0, 8, 0); $dot.VerticalAlignment = 'Top'
        [Windows.Controls.DockPanel]::SetDock($dot, 'Left'); $row.Children.Add($dot) | Out-Null
        $txt = New-Text -Text $r.text -Size 12 -Wrap $true
        if ($r.source -in @('goals', 'placeholder')) { $txt.Text = $r.text + '  (sample)' }
        $row.Children.Add($txt) | Out-Null; $tr.Children.Add($row) | Out-Null
    }
    $g.Children.Add((New-Card -Title 'Tony Recommends' -Body $tr -Col 1 -NavTo 'Recommendations')) | Out-Null

    # Snapshot: scores + notifications
    $sn = New-Object Windows.Controls.StackPanel
    foreach ($sc in @(@('Life Score', $m.lifeScore), @('Business Score', $m.businessScore))) {
        $dp = New-Object Windows.Controls.DockPanel; $dp.Margin = New-Object Windows.Thickness (0, 0, 0, 5)
        [Windows.Controls.DockPanel]::SetDock(($k = New-Text -Text $sc[0] -Size 12.5 -Color $script:Col.Muted), 'Left'); $dp.Children.Add($k) | Out-Null
        $vwrap = New-Object Windows.Controls.StackPanel; $vwrap.Orientation = 'Horizontal'; $vwrap.HorizontalAlignment = 'Right'
        $vwrap.Children.Add((New-Text -Text ([string]$sc[1].value) -Size 18 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
        $arrow = switch ($sc[1].trend) { 'up' { @('^', '#34D399') } 'down' { @('v', '#F87171') } default { @('-', $script:Col.Muted) } }
        $vwrap.Children.Add((New-Text -Text (' ' + $arrow[0]) -Size 14 -Weight 'Bold' -Color $arrow[1] -Margin (New-Object Windows.Thickness (4, 2, 0, 0)))) | Out-Null
        $dp.Children.Add($vwrap) | Out-Null; $sn.Children.Add($dp) | Out-Null
    }
    $sn.Children.Add((New-Text -Text 'NOTIFICATIONS' -Size 9.5 -Weight 'Bold' -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 6, 0, 3)))) | Out-Null
    foreach ($n in (@($m.notifications) | Select-Object -First 4)) {
        $row = New-Object Windows.Controls.DockPanel; $row.Margin = New-Object Windows.Thickness (0, 0, 0, 3)
        $dot = New-Text -Text '-' -Size 12 -Weight 'Bold' -Color $script:Col.Accent; $dot.Margin = New-Object Windows.Thickness (0, 0, 6, 0); $dot.VerticalAlignment = 'Top'
        [Windows.Controls.DockPanel]::SetDock($dot, 'Left'); $row.Children.Add($dot) | Out-Null
        $txt = New-Text -Text $n.text -Size 11.5 -Wrap $true; if ($n.source -eq 'placeholder') { $txt.Text = $n.text + '  (sample)' }
        $row.Children.Add($txt) | Out-Null; $sn.Children.Add($row) | Out-Null
    }
    $g.Children.Add((New-Card -Title "Today's Snapshot" -Body $sn -Tag 'SAMPLE' -Col 2 -NavTo 'Mission Control')) | Out-Null

    $wrap.Children.Add($g) | Out-Null
    return $wrap
}

# =====================  VIEW: HOME (executive)  =====================
# =====================  TONY'S OBSERVATIONS (D9)  =====================
# Observation cards: what Tony has quietly noticed. Max 3, highest impact
# first. Celebrate / guide / (low-confidence) question - never criticize.
function Get-ObsConfidenceColors {
    param([string]$C)
    switch ($C) {
        'High'   { @('#DEF7EC', '#03543F') }
        'Medium' { @($script:Col.AccentSoft, $script:Col.AccentInk) }
        default  { @('#FDF6B2', '#8E4B10') }   # Low
    }
}
function Get-ObsToneColor {
    param([string]$T)
    switch ($T) {
        'celebrate' { $script:Col.Accent }
        'guide'     { $script:Col.AccentInk }
        default     { $script:Col.Muted }      # question
    }
}

function New-ObservationCard {
    param($Obs)
    $card = New-Object Windows.Controls.Border
    $card.Background = New-Brush $script:Col.CardBg
    $card.BorderBrush = New-Brush $script:Col.Line; $card.BorderThickness = New-Object Windows.Thickness 1
    $card.CornerRadius = New-Object Windows.CornerRadius 14
    $card.Padding = New-Object Windows.Thickness (16, 13, 16, 14); $card.Margin = New-Object Windows.Thickness (0, 0, 10, 0)

    $sp = New-Object Windows.Controls.StackPanel

    # header: category (tone-colored) + confidence pill
    $hdr = New-Object Windows.Controls.DockPanel
    $cc = Get-ObsConfidenceColors $Obs.confidence
    $pill = New-Chip -Text $Obs.confidence -Bg $cc[0] -Fg $cc[1]; $pill.Margin = New-Object Windows.Thickness 0; $pill.HorizontalAlignment = 'Right'
    [Windows.Controls.DockPanel]::SetDock($pill, 'Right'); $hdr.Children.Add($pill) | Out-Null
    $cat = New-Text -Text ($Obs.category.ToUpper()) -Size 9.5 -Weight 'Bold' -Color (Get-ObsToneColor $Obs.tone); $cat.VerticalAlignment = 'Center'
    $hdr.Children.Add($cat) | Out-Null
    $sp.Children.Add($hdr) | Out-Null

    $sp.Children.Add((New-Text -Text $Obs.headline -Size 15 -Weight 'Bold' -Color $script:Col.Heading -Wrap $true -Margin (New-Object Windows.Thickness (0, 7, 0, 0)))) | Out-Null
    $sp.Children.Add((New-Text -Text $Obs.message -Size 12.5 -Color $script:Col.Ink -Wrap $true -Margin (New-Object Windows.Thickness (0, 6, 0, 0)))) | Out-Null

    $why = New-Object Windows.Controls.StackPanel; $why.Margin = New-Object Windows.Thickness (0, 10, 0, 0)
    $why.Children.Add((New-Text -Text 'WHY THIS MATTERS' -Size 8.5 -Weight 'Bold' -Color $script:Col.Muted)) | Out-Null
    $why.Children.Add((New-Text -Text $Obs.why -Size 11 -Color $script:Col.Muted -Wrap $true -Margin (New-Object Windows.Thickness (0, 2, 0, 0)))) | Out-Null
    $sp.Children.Add($why) | Out-Null

    $card.Child = $sp
    return $card
}

function New-ObservationsSection {
    $obs = @()
    if (Get-Command Get-TopObservations -ErrorAction SilentlyContinue) { try { $obs = @(Get-TopObservations -Max 3) } catch { } }
    if ($obs.Count -eq 0) { return $null }

    $wrap = New-Object Windows.Controls.StackPanel; $wrap.Margin = New-Object Windows.Thickness (0, 0, 0, 14)
    $head = New-Object Windows.Controls.StackPanel; $head.Margin = New-Object Windows.Thickness (2, 0, 0, 8)
    $head.Children.Add((New-Text -Text ((New-Emoji @(0x1F441, 0xFE0F)) + "  TONY'S OBSERVATIONS") -Size 11 -Weight 'Bold' -Color $script:Col.Accent)) | Out-Null
    $head.Children.Add((New-Text -Text "What I've been noticing lately - not reminders, just observations." -Size 11 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 1, 0, 0)))) | Out-Null
    $wrap.Children.Add($head) | Out-Null

    $grid = New-Object Windows.Controls.Grid
    for ($i = 0; $i -lt $obs.Count; $i++) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = [Windows.GridLength]::new(1, 'Star'); $grid.ColumnDefinitions.Add($cd) | Out-Null }
    for ($i = 0; $i -lt $obs.Count; $i++) {
        $c = New-ObservationCard -Obs $obs[$i]
        if ($i -eq $obs.Count - 1) { $c.Margin = New-Object Windows.Thickness 0 }
        [Windows.Controls.Grid]::SetColumn($c, $i); $grid.Children.Add($c) | Out-Null
    }
    $wrap.Children.Add($grid) | Out-Null
    return $wrap
}

# =====================  EXECUTIVE BRIEFING (D11)  =====================
# The centerpiece of Home: a calm morning letter from Tony, composed by
# core/executive-briefing.ps1 from the single Executive Context. Reads
# top-to-bottom like a letter - greeting, summary, top three, one
# observation, focus, and a short sign-off. Never a dashboard.
function New-BriefingLabel {
    param([string]$Text)
    return (New-Text -Text $Text -Size 10 -Weight 'Bold' -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 18, 0, 6)))
}
function New-BriefingHairline {
    $b = New-Object Windows.Controls.Border; $b.Height = 1; $b.Background = New-Brush $script:Col.Line; $b.Margin = New-Object Windows.Thickness (0, 18, 0, 0)
    return $b
}

function New-ExecutiveBriefingCard {
    param([Parameter(Mandatory)] $Model)
    $m = $Model

    $card = New-Object Windows.Controls.Border
    $card.Background = New-Brush $script:Col.CardBg
    $card.BorderBrush = New-Brush $script:Col.Accent; $card.BorderThickness = New-Object Windows.Thickness 1
    $card.CornerRadius = New-Object Windows.CornerRadius 16
    $card.Padding = New-Object Windows.Thickness (30, 24, 30, 26); $card.Margin = New-Object Windows.Thickness (0, 0, 0, 16)

    $sp = New-Object Windows.Controls.StackPanel

    # header: label (left) + date/time (right)
    $hdr = New-Object Windows.Controls.DockPanel
    $stamp = New-Text -Text ("{0}  -  {1}" -f $m.dateText, $m.timeText) -Size 11 -Color $script:Col.Muted
    $stamp.HorizontalAlignment = 'Right'; [Windows.Controls.DockPanel]::SetDock($stamp, 'Right'); $hdr.Children.Add($stamp) | Out-Null
    $hdr.Children.Add((New-Text -Text "TONY'S EXECUTIVE BRIEFING" -Size 11 -Weight 'Bold' -Color $script:Col.Accent)) | Out-Null
    $sp.Children.Add($hdr) | Out-Null

    # greeting + summary (the lede)
    $sp.Children.Add((New-Text -Text $m.greeting -Size 30 -Weight 'Bold' -Color $script:Col.Heading -Margin (New-Object Windows.Thickness (0, 8, 0, 0)))) | Out-Null
    $sp.Children.Add((New-Text -Text $m.summary.text -Size 14.5 -Color $script:Col.Ink -Wrap $true -Margin (New-Object Windows.Thickness (0, 8, 0, 0)))) | Out-Null

    # today's schedule (only when a live calendar signal was provided)
    if ($m.PSObject.Properties.Name -contains 'schedule' -and $m.schedule) {
        $sp.Children.Add((New-BriefingLabel -Text "TODAY'S SCHEDULE")) | Out-Null
        $sp.Children.Add((New-Text -Text $m.schedule.line -Size 13.5 -Color $script:Col.Ink -Wrap $true)) | Out-Null
        if ($m.schedule.guidance) { $sp.Children.Add((New-Text -Text $m.schedule.guidance -Size 12 -Color $script:Col.Muted -Wrap $true -Margin (New-Object Windows.Thickness (0, 3, 0, 0)))) | Out-Null }
    }

    # today's email - the Executive Email Summary (only when a live email signal
    # was provided). What deserves attention; the rest can wait. Never a list.
    if ($m.PSObject.Properties.Name -contains 'emailSummary' -and $m.emailSummary) {
        $es = $m.emailSummary
        $sp.Children.Add((New-BriefingLabel -Text "TODAY'S EMAIL")) | Out-Null
        $sp.Children.Add((New-Text -Text $es.summaryText -Size 13.5 -Color $script:Col.Ink -Wrap $true)) | Out-Null
        if ($es.guidance) { $sp.Children.Add((New-Text -Text $es.guidance -Size 12 -Color $script:Col.Muted -Wrap $true -Margin (New-Object Windows.Thickness (0, 3, 0, 0)))) | Out-Null }
    }

    # today's top three, each with its WHY
    if (@($m.priorities).Count -gt 0) {
        $sp.Children.Add((New-BriefingLabel -Text 'TODAY''S TOP THREE')) | Out-Null
        foreach ($p in $m.priorities) {
            $row = New-Object Windows.Controls.DockPanel; $row.Margin = New-Object Windows.Thickness (0, 0, 0, 11)
            $badge = New-NumBadge -N $p.rank; [Windows.Controls.DockPanel]::SetDock($badge, 'Left'); $row.Children.Add($badge) | Out-Null
            $col = New-Object Windows.Controls.StackPanel
            $col.Children.Add((New-Text -Text $p.title -Size 14 -Weight 'SemiBold' -Color $script:Col.Heading -Wrap $true)) | Out-Null
            $col.Children.Add((New-Text -Text $p.why -Size 12 -Color $script:Col.Muted -Wrap $true -Margin (New-Object Windows.Thickness (0, 1, 0, 0)))) | Out-Null
            $row.Children.Add($col) | Out-Null
            $sp.Children.Add($row) | Out-Null
        }
    }

    # exactly one observation
    if ($m.observation) {
        $o = $m.observation
        $sp.Children.Add((New-BriefingLabel -Text 'TONY''S OBSERVATION')) | Out-Null
        $toneCol = if (Get-Command Get-ObsToneColor -ErrorAction SilentlyContinue) { Get-ObsToneColor $o.tone } else { $script:Col.AccentInk }
        $sp.Children.Add((New-Text -Text $o.headline -Size 14 -Weight 'Bold' -Color $toneCol -Wrap $true)) | Out-Null
        $sp.Children.Add((New-Text -Text $o.message -Size 12.5 -Color $script:Col.Ink -Wrap $true -Margin (New-Object Windows.Thickness (0, 3, 0, 0)))) | Out-Null
        if ($o.why) { $sp.Children.Add((New-Text -Text $o.why -Size 11 -Color $script:Col.Muted -Wrap $true -Margin (New-Object Windows.Thickness (0, 4, 0, 0)))) | Out-Null }
    }

    # over time - the Executive Timeline (D19): a few calm notes about what is
    # new / aging / overdue / waiting / expiring. Only shown when there's
    # something worth noticing (no noise).
    if (($m.PSObject.Properties.Name -contains 'timeline') -and $m.timeline -and @($m.timeline.notes).Count -gt 0) {
        $sp.Children.Add((New-BriefingLabel -Text 'OVER TIME')) | Out-Null
        foreach ($note in @($m.timeline.notes)) { $sp.Children.Add((New-Text -Text ('-  ' + $note) -Size 12.5 -Color $script:Col.Muted -Wrap $true -Margin (New-Object Windows.Thickness (0, 0, 0, 3)))) | Out-Null }
    }

    # today's focus
    $sp.Children.Add((New-BriefingLabel -Text "TODAY'S FOCUS")) | Out-Null
    $sp.Children.Add((New-Text -Text $m.focus -Size 15 -Weight 'SemiBold' -Color $script:Col.AccentInk -Wrap $true)) | Out-Null

    # encouragement sign-off
    $sp.Children.Add((New-BriefingHairline)) | Out-Null
    $sp.Children.Add((New-Text -Text $m.encouragement -Size 14 -Weight 'SemiBold' -Color $script:Col.Accent -Wrap $true -Margin (New-Object Windows.Thickness (0, 14, 0, 0)))) | Out-Null
    $sp.Children.Add((New-Text -Text '- Tony' -Size 12 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 3, 0, 0)))) | Out-Null

    $card.Child = $sp
    return $card
}

function New-HomeView {
    param([Parameter(Mandatory)] $Model)
    $stack = New-Object Windows.Controls.StackPanel; $stack.Margin = New-Object Windows.Thickness (4, 0, 4, 0)

    # resume banner if the first conversation isn't finished
    if ((Get-Command Get-ConversationState -ErrorAction SilentlyContinue) -and (-not (Get-ConversationState).completed)) {
        $rb = New-Object Windows.Controls.Border
        $rb.Background = New-Brush $script:Col.AccentSoft; $rb.CornerRadius = New-Object Windows.CornerRadius 10; $rb.Padding = New-Object Windows.Thickness (14, 9, 14, 9); $rb.Margin = New-Object Windows.Thickness (0, 0, 0, 12); $rb.Cursor = 'Hand'
        $rb.Child = (New-Text -Text 'Finish your first conversation with Tony  ->' -Size 12.5 -Weight 'SemiBold' -Color $script:Col.AccentInk)
        $rb.Add_MouseLeftButtonUp({ param($s, $e) Set-ActiveView 'First Conversation' }) | Out-Null
        $stack.Children.Add($rb) | Out-Null
    }

    # global command bar ("Ask Tony")
    $stack.Children.Add((New-CommandBar)) | Out-Null
    if ($script:CommandResult) {
        $stack.Children.Add((New-Text -Text $script:CommandResult -Size 12.5 -Weight 'SemiBold' -Color $script:Col.AccentInk -Margin (New-Object Windows.Thickness (2, 0, 0, 12)))) | Out-Null
        $script:CommandResult = $null
    }

    # Executive Briefing - THE centerpiece of Home: a calm morning letter from
    # Tony (D11), composed from the single Executive Context. It surfaces the
    # one observation that matters, so the separate observations row is retired
    # here to keep Home calm and letter-centered. Falls back to the Morning
    # Briefing if the engine isn't available.
    $briefName = if ($script:Theme -and $script:Theme.profileName) { $script:Theme.profileName } else { 'Jake' }
    # The briefing may request a calendar signal - a sanctioned trigger - but ONLY
    # when Calendar is already connected (no fetch, no network when disconnected).
    $briefCal = $null
    if ((Get-Command Get-GCalStatus -ErrorAction SilentlyContinue) -and (Get-Command Get-Calendar -ErrorAction SilentlyContinue)) {
        try { if ((Get-GCalStatus).state -eq 'connected') { $briefCal = Get-Calendar -When 'today' -Now $script:TonyNow } } catch { $briefCal = $null }
    }
    # Likewise the briefing may request an email signal - but ONLY when Gmail is
    # already connected (no fetch, no network when disconnected).
    $briefEmail = $null
    if ((Get-Command Get-GmailStatus -ErrorAction SilentlyContinue) -and (Get-Command Get-Email -ErrorAction SilentlyContinue)) {
        try { if ((Get-GmailStatus).state -eq 'connected') { $briefEmail = Get-Email -When 'today' -Now $script:TonyNow } } catch { $briefEmail = $null }
    }
    $briefing = if (Get-Command Get-TonyExecutiveBriefing -ErrorAction SilentlyContinue) { Get-TonyExecutiveBriefing -CurrentWorkspace 'Home' -Now $script:TonyNow -Name $briefName -Calendar $briefCal -Email $briefEmail } else { $null }
    if ($briefing) { $stack.Children.Add((New-ExecutiveBriefingCard -Model $briefing)) | Out-Null }
    else { $stack.Children.Add((New-MorningBriefing -Model (Get-MorningBrief -Now $script:TonyNow))) | Out-Null }

    # ---- Capture banner: prominent "+ Capture Something" + Today's / Unprocessed / Recent ----
    $cap = Get-CaptureStats
    $capB = New-Object Windows.Controls.Border
    $capB.Background = New-Brush $script:Col.CardBg; $capB.BorderBrush = New-Brush $script:Col.Accent; $capB.BorderThickness = New-Object Windows.Thickness 1
    $capB.CornerRadius = New-Object Windows.CornerRadius 12; $capB.Padding = New-Object Windows.Thickness (16, 14, 16, 14); $capB.Margin = New-Object Windows.Thickness (0, 0, 0, 14)
    $capDock = New-Object Windows.Controls.DockPanel
    # left: big button + subtitle
    $capLeft = New-Object Windows.Controls.StackPanel; $capLeft.VerticalAlignment = 'Center'
    $capLeft.Children.Add((New-PrimaryButton -Text '+ Capture Something' -Size 15 -OnClick { param($s, $e) Open-CaptureWindow | Out-Null })) | Out-Null
    $capLeft.Children.Add((New-Text -Text 'Capture first, organize later - your brain is for thinking, not remembering.' -Size 11.5 -Color $script:Col.Muted -Wrap $true -Margin (New-Object Windows.Thickness (2, 8, 0, 0)))) | Out-Null
    [Windows.Controls.DockPanel]::SetDock($capLeft, 'Left'); $capDock.Children.Add($capLeft) | Out-Null
    # right: stats + recent + open inbox
    $capRight = New-Object Windows.Controls.StackPanel; $capRight.HorizontalAlignment = 'Right'; $capRight.VerticalAlignment = 'Center'; $capRight.Margin = New-Object Windows.Thickness (16, 0, 0, 0)
    $statsRow = New-Object Windows.Controls.StackPanel; $statsRow.Orientation = 'Horizontal'; $statsRow.HorizontalAlignment = 'Right'
    foreach ($pair in @(@('Today', $cap.today), @('Unprocessed', $cap.unprocessed))) {
        $st = New-Object Windows.Controls.StackPanel; $st.Margin = New-Object Windows.Thickness (16, 0, 0, 0)
        $st.Children.Add((New-Text -Text ([string]$pair[1]) -Size 22 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
        $st.Children.Add((New-Text -Text $pair[0] -Size 10.5 -Color $script:Col.Muted)) | Out-Null
        $statsRow.Children.Add($st) | Out-Null
    }
    $capRight.Children.Add($statsRow) | Out-Null
    if (@($cap.recent).Count -gt 0) {
        $capRight.Children.Add((New-Text -Text 'RECENT' -Size 9.5 -Weight 'Bold' -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 8, 0, 2)))) | Out-Null
        foreach ($rc in (@($cap.recent) | Select-Object -First 2)) {
            $rt = New-Text -Text $rc.text -Size 11 -Color $script:Col.Ink -Margin (New-Object Windows.Thickness (0, 0, 0, 1)); $rt.HorizontalAlignment = 'Right'; $rt.TextTrimming = 'CharacterEllipsis'; $rt.MaxWidth = 260
            $capRight.Children.Add($rt) | Out-Null
        }
    }
    $openInbox = New-Text -Text 'Open Inbox >' -Size 11.5 -Weight 'SemiBold' -Color $script:Col.Accent -Margin (New-Object Windows.Thickness (0, 6, 0, 0))
    $openInbox.HorizontalAlignment = 'Right'; $openInbox.Cursor = 'Hand'; $openInbox.Add_MouseLeftButtonUp({ param($s, $e) Set-ActiveView 'Capture' }) | Out-Null
    $capRight.Children.Add($openInbox) | Out-Null
    [Windows.Controls.DockPanel]::SetDock($capRight, 'Right'); $capDock.Children.Add($capRight) | Out-Null
    $capB.Child = $capDock
    $stack.Children.Add($capB) | Out-Null

    # (Today's Priorities + Tony Recommends now live inside the Morning Briefing above.)

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
    foreach ($lnk in @('End of Day Audit', 'Action Items', 'Issues', 'Weekly Review', 'Roadmap')) {
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
# ---- provider status (Tony's reasoning) for Settings ----
$script:ProvStatusPill = $null; $script:ProvStatusPillText = $null; $script:ProvStatusDetail = $null; $script:ProvStatusSource = $null

function Get-ProviderStateColors {
    param([string]$State)
    switch ($State) {
        'connected'      { @('#DEF7EC', '#03543F') }
        'configured'     { @($script:Col.AccentSoft, $script:Col.AccentInk) }
        'not-configured' { @('#FDF6B2', '#8E4B10') }
        'rate-limited'   { @('#FDF6B2', '#8E4B10') }
        default          { @('#FDE2E1', '#9B1C1C') }   # auth-failed / network-error / server-error / error
    }
}

function Set-ProviderStatusDisplay {
    param($Status)
    if (-not $script:ProvStatusPill) { return }
    $cols = Get-ProviderStateColors $Status.state
    $script:ProvStatusPill.Background = New-Brush $cols[0]
    $script:ProvStatusPillText.Text = $Status.label
    $script:ProvStatusPillText.Foreground = New-Brush $cols[1]
    if ($script:ProvStatusDetail) { $script:ProvStatusDetail.Text = $Status.detail }
    if ($script:ProvStatusSource) { $script:ProvStatusSource.Text = ('Key source: {0}' -f $Status.source) }
}

function New-ProviderStatusCard {
    $body = New-Object Windows.Controls.StackPanel

    if (Get-Command Get-ClaudeStatus -ErrorAction SilentlyContinue) { $status = Get-ClaudeStatus } else { $status = [pscustomobject]@{ name = 'Claude'; state = 'not-configured'; label = 'Claude Not Configured'; detail = 'Provider unavailable.'; source = 'none' } }

    $body.Children.Add((New-KeyValueRow -Key 'Provider' -Value 'Claude (Anthropic)')) | Out-Null

    $body.Children.Add((New-Text -Text 'STATUS' -Size 9.5 -Weight 'Bold' -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 8, 0, 4)))) | Out-Null
    $pill = New-Object Windows.Controls.Border; $pill.CornerRadius = New-Object Windows.CornerRadius 9; $pill.Padding = New-Object Windows.Thickness (11, 5, 11, 5); $pill.HorizontalAlignment = 'Left'
    $pillText = New-Text -Text $status.label -Size 12.5 -Weight 'Bold' -Color '#03543F'
    $pill.Child = $pillText
    $script:ProvStatusPill = $pill; $script:ProvStatusPillText = $pillText
    $body.Children.Add($pill) | Out-Null

    $detail = New-Text -Text $status.detail -Size 12 -Color $script:Col.Ink -Wrap $true -Margin (New-Object Windows.Thickness (0, 8, 0, 0))
    $script:ProvStatusDetail = $detail; $body.Children.Add($detail) | Out-Null
    $src = New-Text -Text ('Key source: {0}' -f $status.source) -Size 11 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 4, 0, 0))
    $script:ProvStatusSource = $src; $body.Children.Add($src) | Out-Null

    $btn = New-MiniButton -Text 'Test Connection' -Bg $script:Col.Accent -Fg $script:Col.OnPrimary -OnClick { param($s, $e) if (Get-Command Get-ClaudeStatus -ErrorAction SilentlyContinue) { Set-ProviderStatusDisplay (Get-ClaudeStatus -Live) } }
    $btn.Margin = New-Object Windows.Thickness (0, 14, 0, 0); $btn.HorizontalAlignment = 'Left'; $body.Children.Add($btn) | Out-Null

    $tail = @(); if (Get-Command Get-TonyDiagTail -ErrorAction SilentlyContinue) { $tail = @(Get-TonyDiagTail -Count 6) }
    if ($tail.Count -gt 0) {
        $body.Children.Add((New-Text -Text 'RECENT ACTIVITY' -Size 9.5 -Weight 'Bold' -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 14, 0, 4)))) | Out-Null
        foreach ($ln in $tail) { $body.Children.Add((New-Text -Text $ln -Size 10.5 -Color $script:Col.Muted -Wrap $true)) | Out-Null }
    }

    $note = New-Text -Text 'Tony never shows placeholder answers. With no key configured, he tells you honestly; when connected, he answers through the provider. The model name stays inside the provider.' -Size 11.5 -Color $script:Col.Muted -Wrap $true -Margin (New-Object Windows.Thickness (0, 14, 0, 0))
    $body.Children.Add($note) | Out-Null

    Set-ProviderStatusDisplay $status
    $card = New-Card -Title "Tony's Reasoning" -Body $body
    $card.HorizontalAlignment = 'Left'; $card.MaxWidth = 560; $card.Margin = New-Object Windows.Thickness (0, 14, 0, 0)
    return $card
}

# ---- live provider status (Weather, and future providers) for Settings ----
$script:WxPill = $null; $script:WxPillText = $null; $script:WxDetail = $null; $script:WxUpdated = $null

function Get-WxStateColors {
    param([string]$State)
    switch ($State) {
        'connected'    { @('#DEF7EC', '#03543F') }
        'ready'        { @($script:Col.AccentSoft, $script:Col.AccentInk) }
        'disconnected' { @('#FDF6B2', '#8E4B10') }
        default        { @('#FDE2E1', '#9B1C1C') }   # error / network-error
    }
}
function Get-WxStateLabel {
    param([string]$State)
    switch ($State) {
        'connected'    { 'Weather Connected' }
        'ready'        { 'Weather Ready' }
        'disconnected' { 'Weather Disconnected' }
        default        { 'Weather Error' }
    }
}
function Set-WxStatusDisplay {
    param($Status)
    if (-not $script:WxPill) { return }
    $cols = Get-WxStateColors $Status.state
    $script:WxPill.Background = New-Brush $cols[0]
    $script:WxPillText.Text = (Get-WxStateLabel $Status.state); $script:WxPillText.Foreground = New-Brush $cols[1]
    if ($script:WxDetail) { $script:WxDetail.Text = $Status.detail }
    if ($script:WxUpdated) { $script:WxUpdated.Text = ('Last updated: {0}' -f $(if ($Status.lastUpdated) { $Status.lastUpdated } else { 'not checked yet' })) }
}

function New-LiveProvidersCard {
    $body = New-Object Windows.Controls.StackPanel
    $body.Children.Add((New-KeyValueRow -Key 'Provider' -Value 'Weather (Open-Meteo)')) | Out-Null

    if (Get-Command Get-WeatherStatus -ErrorAction SilentlyContinue) { $st = Get-WeatherStatus } else { $st = [pscustomobject]@{ state = 'error'; detail = 'Weather provider not loaded.'; lastUpdated = $null } }

    $body.Children.Add((New-Text -Text 'STATUS' -Size 9.5 -Weight 'Bold' -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 8, 0, 4)))) | Out-Null
    $pill = New-Object Windows.Controls.Border; $pill.CornerRadius = New-Object Windows.CornerRadius 9; $pill.Padding = New-Object Windows.Thickness (11, 5, 11, 5); $pill.HorizontalAlignment = 'Left'
    $pillText = New-Text -Text (Get-WxStateLabel $st.state) -Size 12.5 -Weight 'Bold' -Color '#03543F'
    $pill.Child = $pillText; $script:WxPill = $pill; $script:WxPillText = $pillText
    $body.Children.Add($pill) | Out-Null

    $detail = New-Text -Text $st.detail -Size 12 -Color $script:Col.Ink -Wrap $true -Margin (New-Object Windows.Thickness (0, 8, 0, 0)); $script:WxDetail = $detail; $body.Children.Add($detail) | Out-Null
    $upd = New-Text -Text 'Last updated: not checked yet' -Size 11 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 4, 0, 0)); $script:WxUpdated = $upd; $body.Children.Add($upd) | Out-Null

    $btn = New-MiniButton -Text 'Check Weather' -Bg $script:Col.Accent -Fg $script:Col.OnPrimary -OnClick { param($s, $e) if (Get-Command Get-WeatherStatus -ErrorAction SilentlyContinue) { Set-WxStatusDisplay (Get-WeatherStatus -Live) } }
    $btn.Margin = New-Object Windows.Thickness (0, 14, 0, 0); $btn.HorizontalAlignment = 'Left'; $body.Children.Add($btn) | Out-Null

    $note = New-Text -Text 'Weather is Tony''s first live provider. Calendar, email, maps, news and more will follow the same architecture - Tony explains them; you never talk to a weather app.' -Size 11.5 -Color $script:Col.Muted -Wrap $true -Margin (New-Object Windows.Thickness (0, 14, 0, 0))
    $body.Children.Add($note) | Out-Null

    Set-WxStatusDisplay $st
    $card = New-Card -Title 'Live Providers' -Body $body
    $card.HorizontalAlignment = 'Left'; $card.MaxWidth = 560; $card.Margin = New-Object Windows.Thickness (0, 14, 0, 0)
    return $card
}

# ---- Google Calendar (read-only) status card ----
$script:CalPill = $null; $script:CalPillText = $null; $script:CalDetail = $null; $script:CalAccount = $null; $script:CalRefresh = $null; $script:CalError = $null
function Get-CalStateColors {
    param([string]$State)
    switch ($State) {
        'connected'      { @('#DEF7EC', '#03543F') }
        'not-connected'  { @($script:Col.AccentSoft, $script:Col.AccentInk) }
        'not-configured' { @('#FDF6B2', '#8E4B10') }
        default          { @('#FDE2E1', '#9B1C1C') }   # needs-attention / denied / error / network-error
    }
}
function Get-CalStateLabel {
    param([string]$State)
    switch ($State) {
        'connected'      { 'Connected' }
        'not-connected'  { 'Not Connected' }
        'not-configured' { 'Not Configured' }
        'needs-attention' { 'Needs Attention' }
        'denied'         { 'Access Denied' }
        default          { 'Needs Attention' }
    }
}
# Render the connected-accounts list into a panel: each row shows the account
# email, a per-account state pill, and a Disconnect button. Read-only; never
# shows tokens. OnDisconnect/Refresh are provider-specific scriptblocks.
function Update-GoogleAccountsPanel {
    param($Panel, $Status, [scriptblock]$OnDisconnect, [scriptblock]$Refresh)
    if (-not $Panel) { return }
    $Panel.Children.Clear()
    $accts = @($Status.accounts)
    if ($accts.Count -eq 0) { $Panel.Children.Add((New-Text -Text 'No accounts connected yet.' -Size 12 -Color $script:Col.Muted)) | Out-Null; return }
    foreach ($a in $accts) {
        $capturedEmail = [string]$a.email
        $row = New-Object Windows.Controls.DockPanel; $row.Margin = New-Object Windows.Thickness (0, 0, 0, 6); $row.LastChildFill = $true
        $btn = New-MiniButton -Text 'Disconnect' -Bg '#FDE2E1' -Fg '#9B1C1C' -OnClick ({ param($s, $e) & $OnDisconnect $capturedEmail; & $Refresh }.GetNewClosure())
        [Windows.Controls.DockPanel]::SetDock($btn, 'Right'); $row.Children.Add($btn) | Out-Null
        $cols = Get-CalStateColors $a.state
        $pill = New-Object Windows.Controls.Border; $pill.CornerRadius = New-Object Windows.CornerRadius 8; $pill.Padding = New-Object Windows.Thickness (8, 3, 8, 3); $pill.Margin = New-Object Windows.Thickness (8, 0, 8, 0); $pill.VerticalAlignment = 'Center'; $pill.Background = New-Brush $cols[0]
        $pill.Child = (New-Text -Text (Get-CalStateLabel $a.state) -Size 10.5 -Weight 'Bold' -Color $cols[1])
        [Windows.Controls.DockPanel]::SetDock($pill, 'Right'); $row.Children.Add($pill) | Out-Null
        $em = New-Text -Text $capturedEmail -Size 12.5 -Color $script:Col.Ink; $em.VerticalAlignment = 'Center'
        $row.Children.Add($em) | Out-Null
        $Panel.Children.Add($row) | Out-Null
    }
}
function Set-CalStatusDisplay {
    param($Status)
    if ($script:CalDetail) { $script:CalDetail.Text = $Status.detail }
    Update-GoogleAccountsPanel -Panel $script:CalAcctPanel -Status $Status `
        -OnDisconnect { param($email) if (Get-Command Disconnect-GoogleCalendar -ErrorAction SilentlyContinue) { Disconnect-GoogleCalendar -Account $email | Out-Null } } `
        -Refresh { Set-CalStatusDisplay (Get-GCalStatus) }
}
function New-CalendarProviderCard {
    $body = New-Object Windows.Controls.StackPanel
    $body.Children.Add((New-KeyValueRow -Key 'Provider' -Value 'Google Calendar (read-only)')) | Out-Null
    if (Get-Command Get-GCalStatus -ErrorAction SilentlyContinue) { $st = Get-GCalStatus } else { $st = [pscustomobject]@{ state = 'not-configured'; detail = 'Calendar provider not loaded.'; account = $null; accounts = @() } }

    $detail = New-Text -Text $st.detail -Size 12 -Color $script:Col.Ink -Wrap $true -Margin (New-Object Windows.Thickness (0, 8, 0, 0)); $script:CalDetail = $detail; $body.Children.Add($detail) | Out-Null
    $body.Children.Add((New-Text -Text 'Access: read-only (Tony can view your schedule, never change it)' -Size 11 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 4, 0, 6)))) | Out-Null
    $body.Children.Add((New-Text -Text 'CONNECTED ACCOUNTS' -Size 9.5 -Weight 'Bold' -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 6, 0, 4)))) | Out-Null
    $acctPanel = New-Object Windows.Controls.StackPanel; $script:CalAcctPanel = $acctPanel; $body.Children.Add($acctPanel) | Out-Null

    $btns = New-Object Windows.Controls.WrapPanel; $btns.Margin = New-Object Windows.Thickness (0, 12, 0, 0)
    $btns.Children.Add((New-MiniButton -Text 'Add a Google account' -Bg $script:Col.Accent -Fg $script:Col.OnPrimary -OnClick { param($s, $e) if (Get-Command Connect-GoogleCalendar -ErrorAction SilentlyContinue) { Connect-GoogleCalendar | Out-Null; Set-CalStatusDisplay (Get-GCalStatus -Live) } })) | Out-Null
    $btns.Children.Add((New-MiniButton -Text 'Test all accounts' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -OnClick { param($s, $e) if (Get-Command Get-GCalStatus -ErrorAction SilentlyContinue) { Set-CalStatusDisplay (Get-GCalStatus -Live) } })) | Out-Null
    $body.Children.Add($btns) | Out-Null

    $note = New-Text -Text 'Setup: create a Google Cloud OAuth client (Desktop app), enable the Calendar API, and put its id/secret in providers\calendar.config.json. Connect one or more accounts - sign-in happens in your browser; Tony never sees your password and requests only read-only access.' -Size 11 -Color $script:Col.Muted -Wrap $true -Margin (New-Object Windows.Thickness (0, 12, 0, 0))
    $body.Children.Add($note) | Out-Null

    Set-CalStatusDisplay $st
    $card = New-Card -Title 'Google Calendar' -Body $body
    $card.HorizontalAlignment = 'Left'; $card.MaxWidth = 560; $card.Margin = New-Object Windows.Thickness (0, 14, 0, 0)
    return $card
}

# Gmail (read-only) Settings card. Reuses the shared connection-state colors,
# labels, and the account-list panel - state strings are provider-neutral.
function Set-GmailStatusDisplay {
    param($Status)
    if ($script:GmailDetail) { $script:GmailDetail.Text = $Status.detail }
    Update-GoogleAccountsPanel -Panel $script:GmailAcctPanel -Status $Status `
        -OnDisconnect { param($email) if (Get-Command Disconnect-Gmail -ErrorAction SilentlyContinue) { Disconnect-Gmail -Account $email | Out-Null } } `
        -Refresh { Set-GmailStatusDisplay (Get-GmailStatus) }
}
function New-GmailProviderCard {
    $body = New-Object Windows.Controls.StackPanel
    $body.Children.Add((New-KeyValueRow -Key 'Provider' -Value 'Gmail (read-only)')) | Out-Null
    if (Get-Command Get-GmailStatus -ErrorAction SilentlyContinue) { $st = Get-GmailStatus } else { $st = [pscustomobject]@{ state = 'not-configured'; detail = 'Gmail provider not loaded.'; account = $null; accounts = @() } }

    $detail = New-Text -Text $st.detail -Size 12 -Color $script:Col.Ink -Wrap $true -Margin (New-Object Windows.Thickness (0, 8, 0, 0)); $script:GmailDetail = $detail; $body.Children.Add($detail) | Out-Null
    $body.Children.Add((New-Text -Text 'Access: read-only (Tony reads to summarize what needs you - never sends, replies, or deletes)' -Size 11 -Color $script:Col.Muted -Wrap $true -Margin (New-Object Windows.Thickness (0, 4, 0, 6)))) | Out-Null
    $body.Children.Add((New-Text -Text 'CONNECTED ACCOUNTS' -Size 9.5 -Weight 'Bold' -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 6, 0, 4)))) | Out-Null
    $acctPanel = New-Object Windows.Controls.StackPanel; $script:GmailAcctPanel = $acctPanel; $body.Children.Add($acctPanel) | Out-Null

    $btns = New-Object Windows.Controls.WrapPanel; $btns.Margin = New-Object Windows.Thickness (0, 12, 0, 0)
    $btns.Children.Add((New-MiniButton -Text 'Add a Google account' -Bg $script:Col.Accent -Fg $script:Col.OnPrimary -OnClick { param($s, $e) if (Get-Command Connect-Gmail -ErrorAction SilentlyContinue) { Connect-Gmail | Out-Null; Set-GmailStatusDisplay (Get-GmailStatus -Live) } })) | Out-Null
    $btns.Children.Add((New-MiniButton -Text 'Test all accounts' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -OnClick { param($s, $e) if (Get-Command Get-GmailStatus -ErrorAction SilentlyContinue) { Set-GmailStatusDisplay (Get-GmailStatus -Live) } })) | Out-Null
    $body.Children.Add($btns) | Out-Null

    $note = New-Text -Text 'Setup: reuse your Google Cloud project, enable the Gmail API, and put a Desktop-app client id/secret in providers\gmail.config.json (optionally list important contacts / client domains for smarter triage). Connect one or more accounts - sign-in happens in your browser; Tony never sees your password and requests only read-only access.' -Size 11 -Color $script:Col.Muted -Wrap $true -Margin (New-Object Windows.Thickness (0, 12, 0, 0))
    $body.Children.Add($note) | Out-Null

    Set-GmailStatusDisplay $st
    $card = New-Card -Title 'Gmail' -Body $body
    $card.HorizontalAlignment = 'Left'; $card.MaxWidth = 560; $card.Margin = New-Object Windows.Thickness (0, 14, 0, 0)
    return $card
}

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
    $restart = New-MiniButton -Text 'Restart First Conversation' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -OnClick { param($s, $e); Reset-Conversation; Set-ActiveView 'First Conversation' }
    $restart.Margin = New-Object Windows.Thickness (0, 14, 0, 0); $restart.HorizontalAlignment = 'Left'; $body.Children.Add($restart) | Out-Null

    $card = New-Card -Title 'Workspace' -Body $body
    $card.HorizontalAlignment = 'Left'; $card.MaxWidth = 560; $card.Margin = New-Object Windows.Thickness (0, 0, 0, 0)
    $outer.Children.Add($card) | Out-Null

    # Tony's Reasoning - live provider status (Claude Connected / Not Configured / ...)
    $outer.Children.Add((New-ProviderStatusCard)) | Out-Null

    # Live Providers - Weather (and future live services)
    $outer.Children.Add((New-LiveProvidersCard)) | Out-Null

    # Google Calendar (read-only) - Connect / Test / Disconnect
    $outer.Children.Add((New-CalendarProviderCard)) | Out-Null

    # Gmail (read-only) - Connect / Test / Disconnect
    $outer.Children.Add((New-GmailProviderCard)) | Out-Null

    $scroll = New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility = 'Auto'; $scroll.HorizontalScrollBarVisibility = 'Disabled'; $scroll.Content = $outer
    return $scroll
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

# =====================  CAPTURE + TONY MEMORY  =====================
$script:CaptureTextBox  = $null
$script:CaptureCategory = 'Note'
$script:CaptureCatChips = @()
$script:CaptureFilter   = 'Unprocessed'
$script:CaptureWindow   = $null

function New-PrimaryButton {
    param([string]$Text, [scriptblock]$OnClick, [string]$Bg, [string]$Fg, [double]$Size = 14)
    if (-not $Bg) { $Bg = $script:Col.Accent }; if (-not $Fg) { $Fg = $script:Col.OnPrimary }
    $b = New-Object Windows.Controls.Border
    $b.Background = New-Brush $Bg; $b.CornerRadius = New-Object Windows.CornerRadius 9
    $b.Padding = New-Object Windows.Thickness (18, 11, 18, 11); $b.Cursor = 'Hand'; $b.HorizontalAlignment = 'Left'
    $b.Child = (New-Text -Text $Text -Size $Size -Weight 'Bold' -Color $Fg)
    if ($OnClick) { $b.Add_MouseLeftButtonUp($OnClick) | Out-Null }
    return $b
}

function Set-CaptureCategory {
    param([string]$Name)
    $script:CaptureCategory = $Name
    foreach ($c in $script:CaptureCatChips) {
        if ($c.Name -eq $Name) { $c.Border.Background = New-Brush $script:Col.Accent; $c.Text.Foreground = New-Brush $script:Col.OnPrimary }
        else { $c.Border.Background = New-Brush $script:Col.AccentSoft; $c.Text.Foreground = New-Brush $script:Col.AccentInk }
    }
}

function New-CaptureForm {
    $sp = New-Object Windows.Controls.StackPanel
    $sp.Children.Add((New-Text -Text "What's on your mind?" -Size 14 -Weight 'SemiBold' -Color $script:Col.Heading -Margin (New-Object Windows.Thickness (0, 0, 0, 6)))) | Out-Null

    $tb = New-Object Windows.Controls.TextBox
    $tb.FontFamily = New-Object Windows.Media.FontFamily $script:Font; $tb.FontSize = 14
    $tb.AcceptsReturn = $true; $tb.TextWrapping = 'Wrap'; $tb.Height = 140; $tb.VerticalScrollBarVisibility = 'Auto'
    $tb.Padding = New-Object Windows.Thickness (10, 8, 10, 8)
    $tb.Background = New-Brush $script:Col.PrimaryMid; $tb.Foreground = New-Brush $script:Col.Ink
    $tb.BorderBrush = New-Brush $script:Col.Line; $tb.CaretBrush = New-Brush $script:Col.Accent
    $sp.Children.Add($tb) | Out-Null
    $script:CaptureTextBox = $tb

    $sp.Children.Add((New-Text -Text 'Category (optional)' -Size 11.5 -Weight 'Bold' -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 12, 0, 5)))) | Out-Null
    $wrap = New-Object Windows.Controls.WrapPanel
    $script:CaptureCatChips = @()
    foreach ($cat in (Get-CaptureCategories)) {
        $b = New-Object Windows.Controls.Border
        $b.CornerRadius = New-Object Windows.CornerRadius 9; $b.Padding = New-Object Windows.Thickness (10, 4, 10, 4); $b.Margin = New-Object Windows.Thickness (0, 0, 6, 6); $b.Cursor = 'Hand'; $b.Tag = $cat
        $t = New-Text -Text $cat -Size 11.5 -Weight 'SemiBold' -Color $script:Col.AccentInk
        $b.Background = New-Brush $script:Col.AccentSoft; $b.Child = $t
        $b.Add_MouseLeftButtonUp({ param($s, $e) Set-CaptureCategory $s.Tag }) | Out-Null
        $wrap.Children.Add($b) | Out-Null
        $script:CaptureCatChips += [pscustomobject]@{ Name = $cat; Border = $b; Text = $t }
    }
    $sp.Children.Add($wrap) | Out-Null
    Set-CaptureCategory $script:CaptureCategory

    $btns = New-Object Windows.Controls.StackPanel; $btns.Orientation = 'Horizontal'; $btns.Margin = New-Object Windows.Thickness (0, 14, 0, 0)
    $save = New-PrimaryButton -Text 'Save to Inbox' -OnClick {
        param($s, $e)
        $txt = $script:CaptureTextBox.Text
        if (-not [string]::IsNullOrWhiteSpace($txt)) {
            $d = Get-CaptureData; Add-Capture -Data $d -Text $txt -Category $script:CaptureCategory -CreatedFrom 'capture-window' | Out-Null; Save-CaptureData $d
            Update-AfterCapture
        }
        if ($script:CaptureWindow) { $script:CaptureWindow.Close() }
    }
    $btns.Children.Add($save) | Out-Null
    $cancel = New-MiniButton -Text 'Cancel' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -OnClick { param($s, $e) if ($script:CaptureWindow) { $script:CaptureWindow.Close() } }
    $cancel.Padding = New-Object Windows.Thickness (16, 10, 16, 10); $btns.Children.Add($cancel) | Out-Null
    $sp.Children.Add($btns) | Out-Null
    $sp.Children.Add((New-Text -Text 'No required fields. Type anything - Tony will help organize it later.' -Size 11 -Color $script:Col.Muted -Wrap $true -Margin (New-Object Windows.Thickness (0, 10, 0, 0)))) | Out-Null
    return $sp
}

function New-CaptureWindowContent {
    $root = New-Object Windows.Controls.DockPanel
    $hdr = New-Object Windows.Controls.Border; $hdr.Background = New-Brush $script:Col.Primary; $hdr.Padding = New-Object Windows.Thickness (18, 12, 18, 12)
    $hd = New-Object Windows.Controls.StackPanel; $hd.Orientation = 'Horizontal'
    $logoSrc = New-ImageSource $script:Theme.logoPath
    if ($logoSrc) { $img = New-Object Windows.Controls.Image; $img.Source = $logoSrc; $img.Height = 24; $img.Width = 24; $img.Margin = New-Object Windows.Thickness (0, 0, 10, 0); $lb = New-Object Windows.Controls.Border; $lb.CornerRadius = New-Object Windows.CornerRadius 6; $lb.ClipToBounds = $true; $lb.Child = $img; $lb.VerticalAlignment = 'Center'; $hd.Children.Add($lb) | Out-Null }
    $hd.Children.Add((New-Text -Text 'Capture Something' -Size 15 -Weight 'Bold' -Color $script:Col.OnPrimary)) | Out-Null
    $hdr.Child = $hd
    [Windows.Controls.DockPanel]::SetDock($hdr, 'Top'); $root.Children.Add($hdr) | Out-Null
    $body = New-Object Windows.Controls.Border; $body.Background = New-Brush $script:Col.AppBg; $body.Padding = New-Object Windows.Thickness (20, 16, 20, 18)
    $body.Child = (New-CaptureForm)
    $root.Children.Add($body) | Out-Null
    return $root
}

function Open-CaptureWindow {
    $win = New-Object Windows.Window
    $win.Title = 'GIOK - Capture'; $win.Width = 560; $win.Height = 580; $win.WindowStartupLocation = 'CenterScreen'
    $win.Background = New-Brush $script:Col.AppBg
    if ($script:Theme.logoPath -and (Test-Path $script:Theme.logoPath)) { $ico = New-Object Windows.Media.Imaging.BitmapImage; $ico.BeginInit(); $ico.CacheOption = 'OnLoad'; $ico.UriSource = New-Object Uri($script:Theme.logoPath); $ico.EndInit(); $win.Icon = $ico }
    $script:CaptureWindow = $win
    $win.Content = New-CaptureWindowContent
    $script:OpenWindows += $win
    $win.Add_ContentRendered({ if ($script:CaptureTextBox) { $script:CaptureTextBox.Focus() | Out-Null } }) | Out-Null
    $win.Add_Closed({ param($s, $e) $script:OpenWindows = @($script:OpenWindows | Where-Object { $_ -ne $s }) }) | Out-Null
    $null = $win.Show()
    return $win
}

function Update-AfterCapture {
    if ($script:TonyActiveView -eq 'Capture') { $script:TonyBody.Child = New-CaptureView }
    elseif ($script:TonyActiveView -eq 'Home') { $script:TonyBody.Child = New-HomeView -Model (Get-HomeModel -Now $script:TonyNow) }
}
function Refresh-Capture { $script:TonyBody.Child = New-CaptureView }

function New-CaptureCard {
    param([Parameter(Mandatory)] $Item)
    $c = $Item
    $card = New-Object Windows.Controls.Border
    $card.Background = New-Brush $script:Col.CardBg; $card.CornerRadius = New-Object Windows.CornerRadius 10
    $card.BorderBrush = New-Brush $script:Col.Line; $card.BorderThickness = New-Object Windows.Thickness 1
    $card.Padding = New-Object Windows.Thickness (14, 10, 14, 10); $card.Margin = New-Object Windows.Thickness (0, 0, 0, 8)
    $sp = New-Object Windows.Controls.StackPanel

    $top = New-Object Windows.Controls.DockPanel
    $meta = New-Text -Text ("{0}  -  {1}" -f $c.timestamp, $c.createdFrom) -Size 10.5 -Color $script:Col.Muted
    $meta.HorizontalAlignment = 'Right'; [Windows.Controls.DockPanel]::SetDock($meta, 'Right'); $top.Children.Add($meta) | Out-Null
    $chips = New-Object Windows.Controls.StackPanel; $chips.Orientation = 'Horizontal'
    $chips.Children.Add((New-Chip -Text $c.id -Bg $script:Col.Primary -Fg $script:Col.OnPrimary)) | Out-Null
    $chips.Children.Add((New-Chip -Text $c.category -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk)) | Out-Null
    $stColors = switch ($c.status) { 'processed' { @('#DEF7EC', '#03543F') } 'archived' { @('#E5E7EB', '#374151') } default { @('#FDF6B2', '#8E4B10') } }
    $chips.Children.Add((New-Chip -Text $c.status -Bg $stColors[0] -Fg $stColors[1])) | Out-Null
    $top.Children.Add($chips) | Out-Null
    $sp.Children.Add($top) | Out-Null

    $sp.Children.Add((New-Text -Text $c.text -Size 13.5 -Wrap $true -Margin (New-Object Windows.Thickness (0, 4, 0, 2)))) | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($c.notes)) { $sp.Children.Add((New-Text -Text $c.notes -Size 11 -Color $script:Col.Muted -Wrap $true)) | Out-Null }

    $acts = New-Object Windows.Controls.WrapPanel; $acts.Margin = New-Object Windows.Thickness (0, 8, 0, 0)
    $soft = $script:Col.AccentSoft; $softInk = $script:Col.AccentInk
    if ($c.status -eq 'new') {
        $acts.Children.Add((New-MiniButton -Text 'Mark Processed' -Bg $soft -Fg $softInk -Tag $c.id -OnClick { param($s, $e); $d = Get-CaptureData; Set-CaptureProcessed -Data $d -Id $s.Tag -Processed $true | Out-Null; Save-CaptureData $d; Refresh-Capture })) | Out-Null
        $acts.Children.Add((New-MiniButton -Text '-> Action Item' -Bg $script:Col.Accent -Fg $script:Col.OnPrimary -Tag $c.id -OnClick { param($s, $e); $d = Get-CaptureData; Convert-Capture -Data $d -Id $s.Tag -To 'action-item' | Out-Null; Save-CaptureData $d; Refresh-Capture })) | Out-Null
        $acts.Children.Add((New-MiniButton -Text '-> Goal' -Bg $soft -Fg $softInk -Tag $c.id -OnClick { param($s, $e); $d = Get-CaptureData; Convert-Capture -Data $d -Id $s.Tag -To 'goal' | Out-Null; Save-CaptureData $d; Refresh-Capture })) | Out-Null
        $acts.Children.Add((New-MiniButton -Text '-> Reminder' -Bg $soft -Fg $softInk -Tag $c.id -OnClick { param($s, $e); $d = Get-CaptureData; Convert-Capture -Data $d -Id $s.Tag -To 'reminder' | Out-Null; Save-CaptureData $d; Refresh-Capture })) | Out-Null
        $acts.Children.Add((New-MiniButton -Text 'Archive' -Bg $soft -Fg $softInk -Tag $c.id -OnClick { param($s, $e); $d = Get-CaptureData; Set-CaptureArchived -Data $d -Id $s.Tag | Out-Null; Save-CaptureData $d; Refresh-Capture })) | Out-Null
    } elseif ($c.status -eq 'processed') {
        $acts.Children.Add((New-MiniButton -Text 'Restore' -Bg $soft -Fg $softInk -Tag $c.id -OnClick { param($s, $e); $d = Get-CaptureData; Set-CaptureProcessed -Data $d -Id $s.Tag -Processed $false | Out-Null; Save-CaptureData $d; Refresh-Capture })) | Out-Null
        $acts.Children.Add((New-MiniButton -Text 'Archive' -Bg $soft -Fg $softInk -Tag $c.id -OnClick { param($s, $e); $d = Get-CaptureData; Set-CaptureArchived -Data $d -Id $s.Tag | Out-Null; Save-CaptureData $d; Refresh-Capture })) | Out-Null
    } else {
        $acts.Children.Add((New-MiniButton -Text 'Restore' -Bg $soft -Fg $softInk -Tag $c.id -OnClick { param($s, $e); $d = Get-CaptureData; Restore-Capture -Data $d -Id $s.Tag | Out-Null; Save-CaptureData $d; Refresh-Capture })) | Out-Null
    }
    $acts.Children.Add((New-MiniButton -Text 'Delete' -Bg '#FDE2E1' -Fg '#9B1C1C' -Tag $c.id -OnClick { param($s, $e); $d = Get-CaptureData; Remove-Capture -Data $d -Id $s.Tag | Out-Null; Save-CaptureData $d; Refresh-Capture })) | Out-Null
    $sp.Children.Add($acts) | Out-Null

    $card.Child = $sp
    return $card
}

function New-CaptureView {
    $items = @((Get-CaptureData).items)
    $filter = $script:CaptureFilter
    $sel = switch ($filter) {
        'Processed' { @($items | Where-Object { $_.status -eq 'processed' }) }
        'Archived'  { @($items | Where-Object { $_.status -eq 'archived' }) }
        'All'       { @($items) }
        default     { @($items | Where-Object { $_.status -eq 'new' }) }
    }
    $sel = @($sel | Sort-Object { $_.id } -Descending)
    $counts = @{ Unprocessed = @($items | Where-Object { $_.status -eq 'new' }).Count; Processed = @($items | Where-Object { $_.status -eq 'processed' }).Count; Archived = @($items | Where-Object { $_.status -eq 'archived' }).Count; All = $items.Count }

    $head = New-Object Windows.Controls.StackPanel; $head.Margin = New-Object Windows.Thickness (4, 0, 4, 10)
    $head.Children.Add((New-Text -Text 'Capture - Inbox' -Size 24 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
    $head.Children.Add((New-Text -Text 'Everything lands here first. Capture first, organize later - nothing is auto-deleted.' -Size 12.5 -Color $script:Col.Muted)) | Out-Null
    $bigBtn = New-PrimaryButton -Text '+ Capture Something' -OnClick { param($s, $e) Open-CaptureWindow | Out-Null }
    $bigBtn.Margin = New-Object Windows.Thickness (0, 10, 0, 8); $head.Children.Add($bigBtn) | Out-Null
    $filt = New-Object Windows.Controls.StackPanel; $filt.Orientation = 'Horizontal'
    foreach ($f in @('Unprocessed', 'Processed', 'Archived', 'All')) {
        $active = ($f -eq $filter)
        $btn = New-MiniButton -Text ("{0} ({1})" -f $f, $counts[$f]) -Bg $(if ($active) { $script:Col.Accent } else { $script:Col.AccentSoft }) -Fg $(if ($active) { $script:Col.OnPrimary } else { $script:Col.AccentInk }) -Tag $f -OnClick { param($s, $e); $script:CaptureFilter = $s.Tag; Refresh-Capture }
        if ($f -eq 'Unprocessed') { $btn.Margin = New-Object Windows.Thickness (0, 0, 0, 0) }
        $filt.Children.Add($btn) | Out-Null
    }
    $head.Children.Add($filt) | Out-Null

    $list = New-Object Windows.Controls.StackPanel; $list.Margin = New-Object Windows.Thickness (4, 0, 4, 0)
    if ($sel.Count -eq 0) { $list.Children.Add((New-Text -Text 'Nothing here. Capture something above.' -Size 13 -Color $script:Col.Muted)) | Out-Null }
    else { foreach ($it in $sel) { $list.Children.Add((New-CaptureCard -Item $it)) | Out-Null } }
    $scroll = New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility = 'Auto'; $scroll.Content = $list

    $outer = New-Object Windows.Controls.DockPanel
    [Windows.Controls.DockPanel]::SetDock($head, 'Top'); $outer.Children.Add($head) | Out-Null; $outer.Children.Add($scroll) | Out-Null
    return $outer
}

# =====================  MEMORY REVIEW (D12: memory with permission)  =====================
# Everything Tony remembers - only with the user's permission. The user
# owns all of it: edit, disable, delete, export. The Memory Manager is the
# only write path; this view just calls into it.
$script:MemoryEditId  = $null
$script:MemoryEditBox = $null
$script:MemoryNotice  = $null

function Refresh-MemoryReview { Set-ActiveView 'Tony Memory' }

function New-MemoryRow {
    param($Mem)
    $disabled = ($Mem.status -ne 'active')
    $card = New-Object Windows.Controls.Border
    $card.Background = New-Brush $script:Col.CardBg; $card.BorderBrush = New-Brush $script:Col.Line; $card.BorderThickness = New-Object Windows.Thickness 1
    $card.CornerRadius = New-Object Windows.CornerRadius 12; $card.Padding = New-Object Windows.Thickness (16, 12, 16, 13); $card.Margin = New-Object Windows.Thickness (0, 0, 0, 10)
    $sp = New-Object Windows.Controls.StackPanel

    # header: category chip (+ disabled tag) on the left, actions on the right
    $top = New-Object Windows.Controls.DockPanel
    $actions = New-Object Windows.Controls.StackPanel; $actions.Orientation = 'Horizontal'; $actions.HorizontalAlignment = 'Right'
    if ($script:MemoryEditId -eq $Mem.id) {
        $actions.Children.Add((New-MiniButton -Text 'Save' -Bg $script:Col.Accent -Fg $script:Col.OnPrimary -Tag $Mem.id -OnClick { param($s, $e) if ($script:MemoryEditBox) { Update-Memory -Id $s.Tag -Value $script:MemoryEditBox.Text | Out-Null }; $script:MemoryEditId = $null; Refresh-MemoryReview })) | Out-Null
        $actions.Children.Add((New-MiniButton -Text 'Cancel' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -OnClick { param($s, $e) $script:MemoryEditId = $null; Refresh-MemoryReview })) | Out-Null
    } else {
        $actions.Children.Add((New-MiniButton -Text 'Edit' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -Tag $Mem.id -OnClick { param($s, $e) $script:MemoryEditId = $s.Tag; Refresh-MemoryReview })) | Out-Null
        $toggle = if ($disabled) { 'Enable' } else { 'Disable' }
        $newStatus = if ($disabled) { 'active' } else { 'disabled' }
        $tb2 = New-MiniButton -Text $toggle -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -Tag ($Mem.id + '|' + $newStatus) -OnClick { param($s, $e) $parts = $s.Tag -split '\|'; Set-MemoryStatus -Id $parts[0] -Status $parts[1] | Out-Null; Refresh-MemoryReview }
        $actions.Children.Add($tb2) | Out-Null
        $actions.Children.Add((New-MiniButton -Text 'Delete' -Bg '#FDE2E1' -Fg '#9B1C1C' -Tag $Mem.id -OnClick { param($s, $e) Remove-Memory -Id $s.Tag | Out-Null; if ($script:MemoryEditId -eq $s.Tag) { $script:MemoryEditId = $null }; Refresh-MemoryReview })) | Out-Null
    }
    [Windows.Controls.DockPanel]::SetDock($actions, 'Right'); $top.Children.Add($actions) | Out-Null
    $chips = New-Object Windows.Controls.StackPanel; $chips.Orientation = 'Horizontal'
    $chips.Children.Add((New-Chip -Text $Mem.category -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk)) | Out-Null
    if ($disabled) { $chips.Children.Add((New-Chip -Text 'DISABLED' -Bg '#E5E7EB' -Fg '#4B5563')) | Out-Null }
    $top.Children.Add($chips) | Out-Null
    $sp.Children.Add($top) | Out-Null

    # value - editable when this row is in edit mode
    if ($script:MemoryEditId -eq $Mem.id) {
        $tb = New-Object Windows.Controls.TextBox
        $tb.FontFamily = New-Object Windows.Media.FontFamily $script:Font; $tb.FontSize = 14; $tb.AcceptsReturn = $true; $tb.TextWrapping = 'Wrap'; $tb.MinHeight = 46
        $tb.Padding = New-Object Windows.Thickness (10, 7, 10, 7); $tb.Background = New-Brush $script:Col.PrimaryMid; $tb.Foreground = New-Brush $script:Col.Ink; $tb.BorderBrush = New-Brush $script:Col.Accent; $tb.CaretBrush = New-Brush $script:Col.Accent
        $tb.Text = [string]$Mem.value; $tb.Margin = New-Object Windows.Thickness (0, 6, 0, 0)
        $script:MemoryEditBox = $tb
        $sp.Children.Add($tb) | Out-Null
    } else {
        $valCol = if ($disabled) { $script:Col.Muted } else { $script:Col.Heading }
        $sp.Children.Add((New-Text -Text $Mem.value -Size 14.5 -Weight 'SemiBold' -Color $valCol -Wrap $true -Margin (New-Object Windows.Thickness (0, 6, 0, 0)))) | Out-Null
    }

    # meta + why + source
    $sp.Children.Add((New-Text -Text ("Remembered {0}  -  from {1}" -f $Mem.created, $Mem.source) -Size 10.5 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 6, 0, 0)))) | Out-Null
    if ($Mem.why) { $sp.Children.Add((New-Text -Text ("Why Tony remembers it: {0}" -f $Mem.why) -Size 11 -Color $script:Col.Muted -Wrap $true -Margin (New-Object Windows.Thickness (0, 2, 0, 0)))) | Out-Null }

    $card.Child = $sp
    return $card
}

function New-TonyMemoryView {
    $head = New-Object Windows.Controls.StackPanel; $head.Margin = New-Object Windows.Thickness (4, 0, 4, 10)
    $headRow = New-Object Windows.Controls.DockPanel
    $exportBtn = New-MiniButton -Text 'Export' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -OnClick { param($s, $e) if (Get-Command Export-Memories -ErrorAction SilentlyContinue) { $p = Export-Memories; $script:MemoryNotice = ('Exported your memories to ' + (Split-Path $p -Leaf)); Refresh-MemoryReview } }
    $exportBtn.VerticalAlignment = 'Center'; [Windows.Controls.DockPanel]::SetDock($exportBtn, 'Right'); $headRow.Children.Add($exportBtn) | Out-Null
    $titleCol = New-Object Windows.Controls.StackPanel
    $titleCol.Children.Add((New-Text -Text 'Memory' -Size 24 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
    $titleCol.Children.Add((New-Text -Text 'Everything Tony remembers - and he only remembers with your permission.' -Size 12.5 -Color $script:Col.Muted)) | Out-Null
    $headRow.Children.Add($titleCol) | Out-Null
    $head.Children.Add($headRow) | Out-Null

    $banner = New-Object Windows.Controls.Border; $banner.Background = New-Brush $script:Col.AccentSoft; $banner.CornerRadius = New-Object Windows.CornerRadius 8
    $banner.Padding = New-Object Windows.Thickness (12, 8, 12, 8); $banner.Margin = New-Object Windows.Thickness (0, 8, 0, 12)
    $banner.Child = (New-Text -Text "Tony never saves a permanent memory without asking first. You own all of it - edit it, disable it, delete it, or export it anytime." -Size 12.5 -Weight 'SemiBold' -Color $script:Col.AccentInk -Wrap $true)

    $list = New-Object Windows.Controls.StackPanel
    $list.Children.Add($banner) | Out-Null
    if ($script:MemoryNotice) {
        $list.Children.Add((New-Text -Text $script:MemoryNotice -Size 12 -Weight 'SemiBold' -Color $script:Col.AccentInk -Margin (New-Object Windows.Thickness (2, 0, 0, 10)))) | Out-Null
        $script:MemoryNotice = $null
    }

    $mems = if (Get-Command Get-Memories -ErrorAction SilentlyContinue) { @(Get-Memories -IncludeDisabled) } else { @() }
    if ($mems.Count -eq 0) {
        $empty = New-Object Windows.Controls.Border; $empty.Background = New-Brush $script:Col.CardBg; $empty.BorderBrush = New-Brush $script:Col.Line; $empty.BorderThickness = New-Object Windows.Thickness 1
        $empty.CornerRadius = New-Object Windows.CornerRadius 12; $empty.Padding = New-Object Windows.Thickness (18, 20, 18, 20)
        $es = New-Object Windows.Controls.StackPanel
        $es.Children.Add((New-Text -Text "Tony hasn't been asked to remember anything yet." -Size 14 -Weight 'SemiBold' -Color $script:Col.Heading -Wrap $true)) | Out-Null
        $es.Children.Add((New-Text -Text "When something in a conversation would help him make better recommendations, he'll ask - and it only lands here if you say yes." -Size 12.5 -Color $script:Col.Muted -Wrap $true -Margin (New-Object Windows.Thickness (0, 4, 0, 0)))) | Out-Null
        $empty.Child = $es; $list.Children.Add($empty) | Out-Null
    } else {
        foreach ($m in $mems) { $list.Children.Add((New-MemoryRow -Mem $m)) | Out-Null }
    }

    $scroll = New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility = 'Auto'; $scroll.Content = $list
    $outer = New-Object Windows.Controls.DockPanel
    [Windows.Controls.DockPanel]::SetDock($head, 'Top'); $outer.Children.Add($head) | Out-Null; $outer.Children.Add($scroll) | Out-Null
    return $outer
}

# =====================  IDENTITY WORKSPACE  =====================
$script:IdentitySection = 'Overview'

function New-ProgressBar {
    param([int]$Pct, [double]$Height = 8)
    $Pct = [math]::Max(0, [math]::Min(100, $Pct))
    $track = New-Object Windows.Controls.Border
    $track.Background = New-Brush $script:Col.PrimaryMid; $track.CornerRadius = New-Object Windows.CornerRadius ($Height / 2); $track.Height = $Height; $track.Margin = New-Object Windows.Thickness (0, 4, 0, 0)
    $g = New-Object Windows.Controls.Grid
    $c0 = New-Object Windows.Controls.ColumnDefinition; $c0.Width = [Windows.GridLength]::new($Pct, 'Star'); $g.ColumnDefinitions.Add($c0) | Out-Null
    $c1 = New-Object Windows.Controls.ColumnDefinition; $c1.Width = [Windows.GridLength]::new((100 - $Pct), 'Star'); $g.ColumnDefinitions.Add($c1) | Out-Null
    $fill = New-Object Windows.Controls.Border; $fill.Background = New-Brush $script:Col.Accent; $fill.CornerRadius = New-Object Windows.CornerRadius ($Height / 2)
    [Windows.Controls.Grid]::SetColumn($fill, 0); $g.Children.Add($fill) | Out-Null
    $track.Child = $g
    return $track
}

function Refresh-Identity { $script:TonyBody.Child = New-IdentityView }

function New-IdentityOverviewSection {
    $o = Get-IdentityOverview
    $grid = New-Object Windows.Controls.Grid
    foreach ($i in 0..2) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = [Windows.GridLength]::new(1, 'Star'); $grid.ColumnDefinitions.Add($cd) | Out-Null }
    foreach ($i in 0..2) { $rd = New-Object Windows.Controls.RowDefinition; $rd.Height = [Windows.GridLength]::Auto; $grid.RowDefinitions.Add($rd) | Out-Null }

    # Identity Score
    $b = New-Object Windows.Controls.StackPanel
    $sr = New-Object Windows.Controls.StackPanel; $sr.Orientation = 'Horizontal'
    $sr.Children.Add((New-Text -Text ([string]$o.identityScore.value) -Size 34 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
    $ar = switch ($o.identityScore.trend) { 'up' { @('^', '#34D399') } 'down' { @('v', '#F87171') } default { @('-', $script:Col.Muted) } }
    $sr.Children.Add((New-Text -Text (' ' + $ar[0]) -Size 16 -Weight 'Bold' -Color $ar[1] -Margin (New-Object Windows.Thickness (4, 6, 0, 0)))) | Out-Null
    $b.Children.Add($sr) | Out-Null
    $b.Children.Add((New-Text -Text 'who you are becoming' -Size 11.5 -Color $script:Col.Muted)) | Out-Null
    $grid.Children.Add((New-Card -Title 'Identity Score' -Body $b -Tag 'SAMPLE' -Col 0 -Row 0)) | Out-Null

    # Vision Progress
    $b = New-Object Windows.Controls.StackPanel
    $b.Children.Add((New-Text -Text ("{0}%" -f $o.visionProgress) -Size 26 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
    $b.Children.Add((New-ProgressBar -Pct $o.visionProgress)) | Out-Null
    $grid.Children.Add((New-Card -Title 'Vision Progress' -Body $b -Col 1 -Row 0 -NavTo 'Identity')) | Out-Null

    # Goal Progress
    $b = New-Object Windows.Controls.StackPanel
    $b.Children.Add((New-Text -Text ("{0}%" -f $o.goalProgress) -Size 26 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
    $b.Children.Add((New-ProgressBar -Pct $o.goalProgress)) | Out-Null
    $grid.Children.Add((New-Card -Title 'Goal Progress' -Body $b -Col 2 -Row 0)) | Out-Null

    # Current Annual Theme
    $b = New-Object Windows.Controls.StackPanel
    if ($o.annualTheme) {
        $b.Children.Add((New-Text -Text $o.annualTheme.theme -Size 15 -Weight 'Bold' -Color $script:Col.Heading -Wrap $true)) | Out-Null
        $b.Children.Add((New-Text -Text $o.annualTheme.description -Size 12 -Color $script:Col.Muted -Wrap $true -Margin (New-Object Windows.Thickness (0, 3, 0, 0)))) | Out-Null
    }
    $grid.Children.Add((New-Card -Title 'Current Annual Theme' -Body $b -Col 0 -Row 1)) | Out-Null

    # Core Values
    $b = New-Object Windows.Controls.WrapPanel
    foreach ($v in $o.values) { $b.Children.Add((New-Chip -Text $v.name -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk)) | Out-Null }
    $grid.Children.Add((New-Card -Title 'Core Values' -Body $b -Col 1 -Row 1)) | Out-Null

    # Tony's Reflection
    $b = New-Object Windows.Controls.StackPanel
    if ($o.tonyReflection) { $b.Children.Add((New-Text -Text $o.tonyReflection.text -Size 12.5 -Color $script:Col.Ink -Wrap $true)) | Out-Null }
    $grid.Children.Add((New-Card -Title "Tony's Reflection" -Body $b -Tag 'SAMPLE' -Col 2 -Row 1)) | Out-Null

    # Latest Journal Entry
    $b = New-Object Windows.Controls.StackPanel
    if ($o.latestJournal) {
        $b.Children.Add((New-Text -Text $o.latestJournal.date -Size 11 -Weight 'Bold' -Color $script:Col.AccentInk)) | Out-Null
        $b.Children.Add((New-Text -Text $o.latestJournal.text -Size 12.5 -Color $script:Col.Ink -Wrap $true -Margin (New-Object Windows.Thickness (0, 2, 0, 0)))) | Out-Null
    }
    $grid.Children.Add((New-Card -Title 'Latest Journal Entry' -Body $b -Col 0 -Row 2)) | Out-Null

    # Recent Wins
    $b = New-Object Windows.Controls.StackPanel
    foreach ($w in $o.recentWins) {
        $row = New-Object Windows.Controls.DockPanel
        $dot = New-Text -Text '+' -Size 13 -Weight 'Bold' -Color '#34D399'; $dot.Margin = New-Object Windows.Thickness (0, 0, 6, 0); $dot.VerticalAlignment = 'Top'
        [Windows.Controls.DockPanel]::SetDock($dot, 'Left'); $row.Children.Add($dot) | Out-Null
        $row.Children.Add((New-Text -Text $w -Size 12 -Wrap $true)) | Out-Null
        $b.Children.Add($row) | Out-Null
    }
    $grid.Children.Add((New-Card -Title 'Recent Wins' -Body $b -Col 1 -Row 2)) | Out-Null

    return $grid
}

function New-IdentityVisionSection {
    $v = Get-IdentityVision
    $sp = New-Object Windows.Controls.StackPanel
    if ($v) {
        $sp.Children.Add((New-Text -Text $v.statement -Size 18 -Weight 'SemiBold' -Color $script:Col.Heading -Wrap $true)) | Out-Null
        $sp.Children.Add((New-Text -Text ("Horizon: {0}" -f $v.horizon) -Size 12 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 8, 0, 4)))) | Out-Null
        $sp.Children.Add((New-Text -Text ("Vision progress: {0}%" -f $v.progress) -Size 12.5 -Weight 'SemiBold' -Color $script:Col.AccentInk)) | Out-Null
        $sp.Children.Add((New-ProgressBar -Pct $v.progress)) | Out-Null
    }
    return $sp
}

function New-IdentityGoalsSection {
    $g = Get-IdentityGoals
    $sp = New-Object Windows.Controls.StackPanel
    if ($g) {
        foreach ($goal in $g.goals) {
            $card = New-Object Windows.Controls.Border
            $card.Background = New-Brush $script:Col.CardBg; $card.CornerRadius = New-Object Windows.CornerRadius 10; $card.BorderBrush = New-Brush $script:Col.Line; $card.BorderThickness = New-Object Windows.Thickness 1
            $card.Padding = New-Object Windows.Thickness (14, 10, 14, 10); $card.Margin = New-Object Windows.Thickness (0, 0, 0, 8)
            $b = New-Object Windows.Controls.StackPanel
            $top = New-Object Windows.Controls.DockPanel
            $tgt = New-Text -Text ("Target: {0}   ({1}%)" -f $goal.target, $goal.progress) -Size 11.5 -Color $script:Col.Muted; $tgt.HorizontalAlignment = 'Right'; [Windows.Controls.DockPanel]::SetDock($tgt, 'Right'); $top.Children.Add($tgt) | Out-Null
            $top.Children.Add((New-Text -Text $goal.title -Size 14 -Weight 'SemiBold' -Wrap $true)) | Out-Null
            $b.Children.Add($top) | Out-Null
            $b.Children.Add((New-ProgressBar -Pct $goal.progress)) | Out-Null
            $card.Child = $b; $sp.Children.Add($card) | Out-Null
        }
    }
    return $sp
}

function New-IdentityValuesSection {
    $v = Get-IdentityValues
    $sp = New-Object Windows.Controls.StackPanel
    if ($v) {
        foreach ($val in $v.values) {
            $sp.Children.Add((New-Text -Text $val.name -Size 15 -Weight 'Bold' -Color $script:Col.Heading -Margin (New-Object Windows.Thickness (0, 6, 0, 0)))) | Out-Null
            $sp.Children.Add((New-Text -Text $val.desc -Size 12.5 -Color $script:Col.Muted -Wrap $true)) | Out-Null
        }
    }
    return $sp
}

function New-IdentityStatementSection {
    param([string]$Statement)
    $sp = New-Object Windows.Controls.StackPanel
    $sp.Children.Add((New-Text -Text $Statement -Size 18 -Weight 'SemiBold' -Color $script:Col.Heading -Wrap $true)) | Out-Null
    return $sp
}

function New-IdentityThemeSection {
    $t = Get-IdentityAnnualTheme
    $sp = New-Object Windows.Controls.StackPanel
    if ($t) {
        $sp.Children.Add((New-Text -Text ([string]$t.year) -Size 13 -Weight 'Bold' -Color $script:Col.AccentInk)) | Out-Null
        $sp.Children.Add((New-Text -Text $t.theme -Size 22 -Weight 'Bold' -Color $script:Col.Heading -Wrap $true -Margin (New-Object Windows.Thickness (0, 2, 0, 6)))) | Out-Null
        $sp.Children.Add((New-Text -Text $t.description -Size 13 -Color $script:Col.Muted -Wrap $true)) | Out-Null
    }
    return $sp
}

function New-IdentityJournalSection {
    $j = Get-IdentityJournal
    $sp = New-Object Windows.Controls.StackPanel
    if ($j) {
        foreach ($e in $j.entries) {
            $card = New-Object Windows.Controls.Border
            $card.Background = New-Brush $script:Col.CardBg; $card.CornerRadius = New-Object Windows.CornerRadius 10; $card.BorderBrush = New-Brush $script:Col.Line; $card.BorderThickness = New-Object Windows.Thickness 1
            $card.Padding = New-Object Windows.Thickness (14, 10, 14, 10); $card.Margin = New-Object Windows.Thickness (0, 0, 0, 8)
            $b = New-Object Windows.Controls.StackPanel
            $b.Children.Add((New-Text -Text $e.date -Size 11 -Weight 'Bold' -Color $script:Col.AccentInk)) | Out-Null
            $b.Children.Add((New-Text -Text $e.text -Size 13 -Color $script:Col.Ink -Wrap $true -Margin (New-Object Windows.Thickness (0, 2, 0, 0)))) | Out-Null
            $card.Child = $b; $sp.Children.Add($card) | Out-Null
        }
    }
    return $sp
}

function New-IdentityTimelineSection {
    $t = Get-IdentityTimeline
    $sp = New-Object Windows.Controls.StackPanel
    if ($t) {
        foreach ($m in $t.milestones) {
            $row = New-Object Windows.Controls.DockPanel; $row.Margin = New-Object Windows.Thickness (0, 0, 0, 8)
            $date = New-Text -Text ([string]$m.date) -Size 13 -Weight 'Bold' -Color $script:Col.AccentInk; $date.Width = 70
            [Windows.Controls.DockPanel]::SetDock($date, 'Left'); $row.Children.Add($date) | Out-Null
            $row.Children.Add((New-Text -Text $m.title -Size 13 -Wrap $true)) | Out-Null
            $sp.Children.Add($row) | Out-Null
        }
    }
    return $sp
}

function New-IdentityView {
    $sec = $script:IdentitySection
    $head = New-Object Windows.Controls.StackPanel; $head.Margin = New-Object Windows.Thickness (4, 0, 4, 10)
    $head.Children.Add((New-Text -Text 'Identity' -Size 24 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
    $head.Children.Add((New-Text -Text "Your personal operating system - who you're becoming. Vision and Goals live here." -Size 12.5 -Color $script:Col.Muted)) | Out-Null
    $tabs = New-Object Windows.Controls.WrapPanel; $tabs.Margin = New-Object Windows.Thickness (0, 8, 0, 0)
    foreach ($s in (Get-IdentitySections)) {
        $active = ($s -eq $sec)
        $btn = New-MiniButton -Text $s -Bg $(if ($active) { $script:Col.Accent } else { $script:Col.AccentSoft }) -Fg $(if ($active) { $script:Col.OnPrimary } else { $script:Col.AccentInk }) -Tag $s -OnClick { param($s2, $e); $script:IdentitySection = $s2.Tag; Refresh-Identity }
        $tabs.Children.Add($btn) | Out-Null
    }
    $head.Children.Add($tabs) | Out-Null

    $content = switch ($sec) {
        'Overview'     { New-IdentityOverviewSection }
        'Vision'       { New-IdentityVisionSection }
        'Goals'        { New-IdentityGoalsSection }
        'Core Values'  { New-IdentityValuesSection }
        'Mission'      { $mn = Get-IdentityMission; New-IdentityStatementSection -Statement $(if ($mn) { $mn.statement } else { '' }) }
        'Legacy'       { $lg = Get-IdentityLegacy;  New-IdentityStatementSection -Statement $(if ($lg) { $lg.statement } else { '' }) }
        'Annual Theme' { New-IdentityThemeSection }
        'Journal'      { New-IdentityJournalSection }
        'Timeline'     { New-IdentityTimelineSection }
        default        { New-IdentityOverviewSection }
    }
    $body = New-Object Windows.Controls.StackPanel; $body.Margin = New-Object Windows.Thickness (4, 8, 4, 0); $body.Children.Add($content) | Out-Null
    $scroll = New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility = 'Auto'; $scroll.Content = $body
    $outer = New-Object Windows.Controls.DockPanel
    [Windows.Controls.DockPanel]::SetDock($head, 'Top'); $outer.Children.Add($head) | Out-Null; $outer.Children.Add($scroll) | Out-Null
    return $outer
}

# ---- generic "coming soon" workspace placeholder (for not-yet-built workspaces) ----
function New-WorkspacePlaceholder {
    param([Parameter(Mandatory)][string]$Title, [string]$Belongs)
    $sp = New-Object Windows.Controls.StackPanel; $sp.Margin = New-Object Windows.Thickness (4, 0, 4, 0)
    $sp.Children.Add((New-Text -Text $Title -Size 24 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
    $sp.Children.Add((New-Text -Text 'Workspace' -Size 12.5 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 0, 0, 12)))) | Out-Null
    $banner = New-Object Windows.Controls.Border; $banner.Background = New-Brush $script:Col.AccentSoft; $banner.CornerRadius = New-Object Windows.CornerRadius 8; $banner.Padding = New-Object Windows.Thickness (12, 8, 12, 8); $banner.Margin = New-Object Windows.Thickness (0, 0, 0, 12)
    $banner.Child = (New-Text -Text 'Coming soon - this workspace is scaffolded and will be built in a future sprint.' -Size 12.5 -Weight 'SemiBold' -Color $script:Col.AccentInk -Wrap $true)
    $sp.Children.Add($banner) | Out-Null
    if ($Belongs) {
        $card = New-Object Windows.Controls.StackPanel
        $card.Children.Add((New-Text -Text 'WHAT BELONGS HERE' -Size 10.5 -Weight 'Bold' -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 0, 0, 3)))) | Out-Null
        $card.Children.Add((New-Text -Text $Belongs -Size 13 -Color $script:Col.Ink -Wrap $true)) | Out-Null
        $sp.Children.Add((New-Card -Title $Title -Body $card)) | Out-Null
    }
    return $sp
}

$script:WorkspaceBelongs = @{
    'Non-Negotiables' = 'The bright lines you refuse to cross - your daily disciplines (training, Checkups, family time, honesty) and their streaks.'
    'Family'          = 'The people who matter most - commitments, dates, shared logistics, and memories.'
    'Health'          = 'Training, sleep, nutrition, recovery, and medical upkeep.'
    'Financial'       = 'Budgets, cash flow, targets, and obligations - personal and business.'
    'Home Projects'   = 'The house and physical life admin - projects, maintenance, and purchases.'
    'Learning'        = 'Deliberate growth - courses, books, skills, and industry study.'
}

# =====================  END OF DAY AUDIT  =====================
$script:AuditTab = 'Today'
$script:AuditDate = $null
$script:AuditWinBox = $null

function Refresh-Audit { $script:TonyBody.Child = New-AuditView }

function New-AuditInput {
    param([string]$Text, [bool]$Multi = $false, [double]$Height = 46)
    $tb = New-Object Windows.Controls.TextBox
    $tb.FontFamily = New-Object Windows.Media.FontFamily $script:Font; $tb.FontSize = 13
    $tb.Padding = New-Object Windows.Thickness (8, 6, 8, 6)
    $tb.Background = New-Brush $script:Col.PrimaryMid; $tb.Foreground = New-Brush $script:Col.Ink
    $tb.BorderBrush = New-Brush $script:Col.Line; $tb.CaretBrush = New-Brush $script:Col.Accent
    if ($Multi) { $tb.AcceptsReturn = $true; $tb.TextWrapping = 'Wrap'; $tb.Height = $Height; $tb.VerticalScrollBarVisibility = 'Auto' }
    if ($Text) { $tb.Text = $Text }
    return $tb
}

function New-AuditScoreRow {
    param([string]$Category, [int]$Value)
    $dp = New-Object Windows.Controls.DockPanel; $dp.Margin = New-Object Windows.Thickness (0, 0, 0, 6)
    $stepper = New-Object Windows.Controls.StackPanel; $stepper.Orientation = 'Horizontal'; $stepper.HorizontalAlignment = 'Right'
    $minus = New-MiniButton -Text '-' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -Tag ("{0}|-1" -f $Category) -OnClick { param($s, $e); $p = $s.Tag -split '\|'; Set-AuditScoreDelta -Date $script:AuditDate -Category $p[0] -Delta ([int]$p[1]); Refresh-Audit }
    $minus.Padding = New-Object Windows.Thickness (10, 3, 10, 3); $stepper.Children.Add($minus) | Out-Null
    $val = New-Text -Text ("{0}" -f $Value) -Size 15 -Weight 'Bold' -Color $script:Col.Heading; $val.Width = 34; $val.TextAlignment = 'Center'; $val.VerticalAlignment = 'Center'; $stepper.Children.Add($val) | Out-Null
    $plus = New-MiniButton -Text '+' -Bg $script:Col.Accent -Fg $script:Col.OnPrimary -Tag ("{0}|1" -f $Category) -OnClick { param($s, $e); $p = $s.Tag -split '\|'; Set-AuditScoreDelta -Date $script:AuditDate -Category $p[0] -Delta ([int]$p[1]); Refresh-Audit }
    $plus.Padding = New-Object Windows.Thickness (10, 3, 10, 3); $stepper.Children.Add($plus) | Out-Null
    [Windows.Controls.DockPanel]::SetDock($stepper, 'Right'); $dp.Children.Add($stepper) | Out-Null
    $lbl = New-Text -Text $Category -Size 13 -Color $script:Col.Ink; $lbl.VerticalAlignment = 'Center'; $dp.Children.Add($lbl) | Out-Null
    return $dp
}

function New-AuditScoresCard {
    param($A)
    $b = New-Object Windows.Controls.StackPanel
    $ov = New-Object Windows.Controls.StackPanel; $ov.Orientation = 'Horizontal'; $ov.Margin = New-Object Windows.Thickness (0, 0, 0, 8)
    $ov.Children.Add((New-Text -Text ([string]$A.scores.overall) -Size 34 -Weight 'Bold' -Color $script:Col.Accent)) | Out-Null
    $ov.Children.Add((New-Text -Text '/ 10  Overall Day Score (avg of categories)' -Size 12 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (8, 18, 0, 0)))) | Out-Null
    $b.Children.Add($ov) | Out-Null
    foreach ($c in (Get-AuditScoreCategories)) { $b.Children.Add((New-AuditScoreRow -Category $c -Value ([int]$A.scores.(ConvertTo-ScoreKey $c)))) | Out-Null }
    return (New-Card -Title 'Scores' -Body $b)
}

function New-AuditWinsCard {
    param($A)
    $b = New-Object Windows.Controls.StackPanel
    $bar = New-Object Windows.Controls.DockPanel; $bar.Margin = New-Object Windows.Thickness (0, 0, 0, 8)
    $add = New-MiniButton -Text '+ Add win' -Bg $script:Col.Accent -Fg $script:Col.OnPrimary -OnClick { param($s, $e); if ($script:AuditWinBox -and -not [string]::IsNullOrWhiteSpace($script:AuditWinBox.Text)) { Add-AuditWin -Date $script:AuditDate -Text $script:AuditWinBox.Text; Refresh-Audit } }
    [Windows.Controls.DockPanel]::SetDock($add, 'Right'); $bar.Children.Add($add) | Out-Null
    $tb = New-AuditInput; $script:AuditWinBox = $tb; $bar.Children.Add($tb) | Out-Null
    $b.Children.Add($bar) | Out-Null
    $wins = @($A.wins)
    if ($wins.Count -eq 0) { $b.Children.Add((New-Text -Text 'No wins logged yet - add one above.' -Size 12.5 -Color $script:Col.Muted)) | Out-Null }
    else {
        for ($i = 0; $i -lt $wins.Count; $i++) {
            $row = New-Object Windows.Controls.DockPanel; $row.Margin = New-Object Windows.Thickness (0, 0, 0, 4)
            $del = New-MiniButton -Text 'x' -Bg '#FDE2E1' -Fg '#9B1C1C' -Tag ([string]$i) -OnClick { param($s, $e); Remove-AuditWin -Date $script:AuditDate -Index ([int]$s.Tag); Refresh-Audit }
            [Windows.Controls.DockPanel]::SetDock($del, 'Right'); $row.Children.Add($del) | Out-Null
            $dot = New-Text -Text '+' -Size 13 -Weight 'Bold' -Color '#34D399'; $dot.Margin = New-Object Windows.Thickness (0, 0, 6, 0); $dot.VerticalAlignment = 'Top'
            [Windows.Controls.DockPanel]::SetDock($dot, 'Left'); $row.Children.Add($dot) | Out-Null
            $row.Children.Add((New-Text -Text $wins[$i] -Size 12.5 -Wrap $true)) | Out-Null
            $b.Children.Add($row) | Out-Null
        }
    }
    return (New-Card -Title "Today's Wins" -Body $b)
}

function New-AuditIncompleteCard {
    param($A)
    $b = New-Object Windows.Controls.StackPanel
    $items = @(Get-AuditIncompleteActions)
    $moved = @($A.movedToTomorrow)
    if ($items.Count -eq 0) { $b.Children.Add((New-Text -Text 'Nothing incomplete - great work.' -Size 12.5 -Color $script:Col.Muted)) | Out-Null }
    else {
        foreach ($it in ($items | Select-Object -First 10)) {
            $card = New-Object Windows.Controls.Border; $card.Background = New-Brush $script:Col.PrimaryMid; $card.CornerRadius = New-Object Windows.CornerRadius 8; $card.Padding = New-Object Windows.Thickness (10, 8, 10, 8); $card.Margin = New-Object Windows.Thickness (0, 0, 0, 6)
            $sp = New-Object Windows.Controls.StackPanel
            $tl = New-Object Windows.Controls.StackPanel; $tl.Orientation = 'Horizontal'
            $tl.Children.Add((New-Chip -Text $it.id -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk)) | Out-Null
            $tl.Children.Add((New-Text -Text $it.title -Size 12.5 -Wrap $true -Margin (New-Object Windows.Thickness (2, 1, 0, 0)))) | Out-Null
            if ($moved -contains $it.id) { $tl.Children.Add((New-Chip -Text '-> tomorrow' -Bg '#DEF7EC' -Fg '#03543F')) | Out-Null }
            $sp.Children.Add($tl) | Out-Null
            $acts = New-Object Windows.Controls.WrapPanel; $acts.Margin = New-Object Windows.Thickness (0, 6, 0, 0)
            $acts.Children.Add((New-MiniButton -Text 'Move to tomorrow' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -Tag $it.id -OnClick { param($s, $e); Add-AuditMovedToTomorrow -Date $script:AuditDate -ActionId $s.Tag; Refresh-Audit })) | Out-Null
            $acts.Children.Add((New-MiniButton -Text 'Keep open' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -Tag $it.id -OnClick { param($s, $e); Refresh-Audit })) | Out-Null
            $acts.Children.Add((New-MiniButton -Text 'Archive' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -Tag $it.id -OnClick { param($s, $e); $d = Get-ActionItemsData; Set-ActionItemArchived -Data $d -Id $s.Tag | Out-Null; Save-ActionItemsData $d; Refresh-Audit })) | Out-Null
            $acts.Children.Add((New-MiniButton -Text 'Delete' -Bg '#FDE2E1' -Fg '#9B1C1C' -Tag $it.id -OnClick { param($s, $e); $d = Get-ActionItemsData; Remove-ActionItem -Data $d -Id $s.Tag | Out-Null; Save-ActionItemsData $d; Refresh-Audit })) | Out-Null
            $sp.Children.Add($acts) | Out-Null
            $card.Child = $sp; $b.Children.Add($card) | Out-Null
        }
        if ($items.Count -gt 10) { $b.Children.Add((New-Text -Text ("+ {0} more in Action Items" -f ($items.Count - 10)) -Size 11.5 -Color $script:Col.Muted)) | Out-Null }
    }
    return (New-Card -Title 'Incomplete Items' -Body $b)
}

function New-AuditNonNegotiablesCard {
    param($A)
    $b = New-Object Windows.Controls.WrapPanel
    foreach ($nn in (Get-NonNegotiableDefs)) {
        $cb = New-Object Windows.Controls.CheckBox
        $cb.Content = $nn.name; $cb.Foreground = New-Brush $script:Col.Ink; $cb.IsChecked = [bool]$A.nonNegotiables.($nn.key); $cb.Tag = $nn.key
        $cb.Margin = New-Object Windows.Thickness (0, 0, 18, 8); $cb.FontFamily = New-Object Windows.Media.FontFamily $script:Font; $cb.FontSize = 12.5
        $cb.Add_Click({ param($s, $e); Set-NonNegotiable -Date $script:AuditDate -Key $s.Tag -Done ([bool]$s.IsChecked) }) | Out-Null
        $b.Children.Add($cb) | Out-Null
    }
    $wrap = New-Object Windows.Controls.StackPanel
    $wrap.Children.Add($b) | Out-Null
    $wrap.Children.Add((New-Text -Text '+ Custom non-negotiables (coming soon)' -Size 11 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 2, 0, 0)))) | Out-Null
    return (New-Card -Title 'Non-Negotiables' -Body $wrap)
}

function New-AuditReflectionCard {
    param($A)
    $b = New-Object Windows.Controls.StackPanel
    foreach ($r in (Get-ReflectionDefs)) {
        $b.Children.Add((New-Text -Text $r.label -Size 11.5 -Weight 'SemiBold' -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 6, 0, 3)))) | Out-Null
        $tb = New-AuditInput -Text ([string]$A.reflection.($r.key)) -Multi $true -Height 44
        $tb.Tag = $r.key
        $tb.Add_LostFocus({ param($s, $e); Set-AuditReflection -Date $script:AuditDate -Field $s.Tag -Value $s.Text }) | Out-Null
        $b.Children.Add($tb) | Out-Null
    }
    return (New-Card -Title 'Reflection' -Body $b)
}

function New-AuditTonyCard {
    param($A)
    $b = New-Object Windows.Controls.StackPanel
    $b.Children.Add((New-Text -Text $A.tonyAudit -Size 13 -Color $script:Col.Ink -Wrap $true)) | Out-Null
    return (New-Card -Title "Tony's Audit" -Body $b -Tag 'SAMPLE')
}

function New-AuditHistorySection {
    $hist = @(Get-AuditHistory)
    $sp = New-Object Windows.Controls.StackPanel
    if ($hist.Count -eq 0) { $sp.Children.Add((New-Text -Text 'No past audits yet.' -Size 13 -Color $script:Col.Muted)) | Out-Null; return $sp }
    foreach ($h in $hist) {
        $card = New-Object Windows.Controls.Border; $card.Background = New-Brush $script:Col.CardBg; $card.CornerRadius = New-Object Windows.CornerRadius 10; $card.BorderBrush = New-Brush $script:Col.Line; $card.BorderThickness = New-Object Windows.Thickness 1
        $card.Padding = New-Object Windows.Thickness (14, 10, 14, 10); $card.Margin = New-Object Windows.Thickness (0, 0, 0, 8)
        $body = New-Object Windows.Controls.StackPanel
        $top = New-Object Windows.Controls.DockPanel
        $score = New-Text -Text ("Overall {0}/10" -f $h.scores.overall) -Size 13 -Weight 'Bold' -Color $script:Col.Accent; $score.HorizontalAlignment = 'Right'; [Windows.Controls.DockPanel]::SetDock($score, 'Right'); $top.Children.Add($score) | Out-Null
        $top.Children.Add((New-Text -Text $h.date -Size 14 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
        $body.Children.Add($top) | Out-Null
        if ($h.reflection -and $h.reflection.largestWin) { $body.Children.Add((New-Text -Text ("Largest win: {0}" -f $h.reflection.largestWin) -Size 12 -Color $script:Col.Muted -Wrap $true -Margin (New-Object Windows.Thickness (0, 3, 0, 0)))) | Out-Null }
        $body.Children.Add((New-Text -Text ("{0} wins logged" -f @($h.wins).Count) -Size 11.5 -Color $script:Col.Muted)) | Out-Null
        $card.Child = $body; $sp.Children.Add($card) | Out-Null
    }
    return $sp
}

function New-AuditView {
    $script:AuditDate = $script:TonyNow.ToString('yyyy-MM-dd')
    $A = Get-DayAudit -Date $script:AuditDate

    $head = New-Object Windows.Controls.StackPanel; $head.Margin = New-Object Windows.Thickness (4, 0, 4, 10)
    $head.Children.Add((New-Text -Text 'End of Day Audit' -Size 24 -Weight 'Bold' -Color $script:Col.Heading)) | Out-Null
    $head.Children.Add((New-Text -Text ("{0}  -  Did today move you closer to the life you're building?" -f $script:AuditDate) -Size 12.5 -Color $script:Col.Muted)) | Out-Null
    $toggle = New-Object Windows.Controls.StackPanel; $toggle.Orientation = 'Horizontal'; $toggle.Margin = New-Object Windows.Thickness (0, 8, 0, 0)
    foreach ($t in @('Today', 'History')) {
        $active = ($t -eq $script:AuditTab)
        $btn = New-MiniButton -Text $t -Bg $(if ($active) { $script:Col.Accent } else { $script:Col.AccentSoft }) -Fg $(if ($active) { $script:Col.OnPrimary } else { $script:Col.AccentInk }) -Tag $t -OnClick { param($s, $e); $script:AuditTab = $s.Tag; Refresh-Audit }
        if ($t -eq 'Today') { $btn.Margin = New-Object Windows.Thickness (0, 0, 0, 0) }
        $toggle.Children.Add($btn) | Out-Null
    }
    $head.Children.Add($toggle) | Out-Null

    $body = New-Object Windows.Controls.StackPanel; $body.Margin = New-Object Windows.Thickness (0, 4, 0, 0)
    if ($script:AuditTab -eq 'History') {
        $body.Children.Add((New-AuditHistorySection)) | Out-Null
    } else {
        $g = New-Object Windows.Controls.Grid
        foreach ($i in 0..1) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = [Windows.GridLength]::new(1, 'Star'); $g.ColumnDefinitions.Add($cd) | Out-Null }
        $cScores = New-AuditScoresCard -A $A; [Windows.Controls.Grid]::SetColumn($cScores, 0); $g.Children.Add($cScores) | Out-Null
        $cTony = New-AuditTonyCard -A $A; [Windows.Controls.Grid]::SetColumn($cTony, 1); $g.Children.Add($cTony) | Out-Null
        $body.Children.Add($g) | Out-Null

        $g2 = New-Object Windows.Controls.Grid
        foreach ($i in 0..1) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = [Windows.GridLength]::new(1, 'Star'); $g2.ColumnDefinitions.Add($cd) | Out-Null }
        $cWins = New-AuditWinsCard -A $A; [Windows.Controls.Grid]::SetColumn($cWins, 0); $g2.Children.Add($cWins) | Out-Null
        $cInc = New-AuditIncompleteCard -A $A; [Windows.Controls.Grid]::SetColumn($cInc, 1); $g2.Children.Add($cInc) | Out-Null
        $body.Children.Add($g2) | Out-Null

        $body.Children.Add((New-AuditNonNegotiablesCard -A $A)) | Out-Null
        $body.Children.Add((New-AuditReflectionCard -A $A)) | Out-Null
    }
    $scroll = New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility = 'Auto'; $scroll.Content = $body
    $outer = New-Object Windows.Controls.DockPanel
    [Windows.Controls.DockPanel]::SetDock($head, 'Top'); $outer.Children.Add($head) | Out-Null; $outer.Children.Add($scroll) | Out-Null
    return $outer
}

# =====================  FIRST CONVERSATION (onboarding)  =====================
$script:ConvInputBox = $null
$script:ConvStepId = $null

function Refresh-Conversation { $script:TonyBody.Child = New-FirstConversationView }
function Save-ConvCurrentInput { if ($script:ConvInputBox -and $script:ConvStepId) { Set-ConversationAnswer -StepId $script:ConvStepId -Text $script:ConvInputBox.Text } }

function New-TonyBubble {
    param([string]$Text, [bool]$Soft = $false, [double]$Size = 17, [bool]$ShowLabel = $true)
    $b = New-Object Windows.Controls.Border
    $b.Background = New-Brush $(if ($Soft) { $script:Col.AccentSoft } else { $script:Col.CardBg })
    $b.CornerRadius = New-Object Windows.CornerRadius 14; $b.BorderBrush = New-Brush $script:Col.Line; $b.BorderThickness = New-Object Windows.Thickness 1
    $b.Padding = New-Object Windows.Thickness (20, 16, 20, 16); $b.Margin = New-Object Windows.Thickness (0, 0, 0, 14)
    $sp = New-Object Windows.Controls.StackPanel
    if ($ShowLabel) { $sp.Children.Add((New-Text -Text 'TONY' -Size 10.5 -Weight 'Bold' -Color $script:Col.Accent -Margin (New-Object Windows.Thickness (0, 0, 0, 4)))) | Out-Null }
    $t = New-Text -Text $Text -Size $Size -Weight 'SemiBold' -Color $(if ($Soft) { $script:Col.AccentInk } else { $script:Col.Heading }) -Wrap $true
    $sp.Children.Add($t) | Out-Null
    $b.Child = $sp
    return $b
}

function New-FirstConversationView {
    $steps = Get-ConversationSteps
    $state = Get-ConversationState
    $total = $steps.Count
    $idx = [int]$state.currentStep

    $col = New-Object Windows.Controls.StackPanel; $col.MaxWidth = 720; $col.HorizontalAlignment = 'Center'; $col.Margin = New-Object Windows.Thickness (0, 24, 0, 24)
    $col.Children.Add((New-Text -Text "TONY'S FIRST CONVERSATION" -Size 11 -Weight 'Bold' -Color $script:Col.Accent)) | Out-Null

    if ($idx -ge $total) {
        # ---- closing ----
        $col.Children.Add((New-Text -Text 'Complete' -Size 12 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 0, 0, 4)))) | Out-Null
        $col.Children.Add((New-ProgressBar -Pct 100)) | Out-Null
        $col.Children.Add((New-TonyBubble -Text (Get-ConversationClosing) -Size 20 -Margin (New-Object Windows.Thickness (0, 14, 0, 14)))) | Out-Null
        $begin = New-PrimaryButton -Text "Let's build your operating system" -Size 15 -OnClick { param($s, $e); Complete-Conversation; Set-ActiveView 'Home' }
        $begin.HorizontalAlignment = 'Center'; $begin.Padding = New-Object Windows.Thickness (28, 13, 28, 13)
        $col.Children.Add($begin) | Out-Null
        $back = New-MiniButton -Text '< Back' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -OnClick { param($s, $e); Set-ConversationStep ((Get-ConversationState).currentStep - 1); Refresh-Conversation }
        $back.HorizontalAlignment = 'Center'; $back.Margin = New-Object Windows.Thickness (0, 10, 0, 0); $col.Children.Add($back) | Out-Null
    } else {
        $step = $steps[$idx]
        $script:ConvStepId = $step.id
        $label = if ($step.type -eq 'welcome') { 'Welcome' } else { ("Question {0} of {1}" -f ($idx + 1), $total) }
        $col.Children.Add((New-Text -Text $label -Size 12 -Color $script:Col.Muted -Margin (New-Object Windows.Thickness (0, 2, 0, 2)))) | Out-Null
        $col.Children.Add((New-ProgressBar -Pct ([int](($idx + 1) / $total * 100)))) | Out-Null

        # Tony's acknowledgment of the previous answer (natural "responds, then moves forward")
        if ($idx -gt 0) {
            $prevAns = Get-ConversationAnswer $state ($steps[$idx - 1].id)
            $ack = Get-TonyResponse -Index ($idx - 1) -Answer $prevAns
            if ($ack) { $col.Children.Add((New-TonyBubble -Text $ack -Soft $true -Size 13.5 -ShowLabel $false)) | Out-Null }
        }
        # Tony's question
        $col.Children.Add((New-TonyBubble -Text $step.tony -Margin (New-Object Windows.Thickness (0, 4, 0, 12)))) | Out-Null

        # input (questions only)
        if ($step.type -eq 'question') {
            $tb = New-AuditInput -Text (Get-ConversationAnswer $state $step.id) -Multi $true -Height 96
            $script:ConvInputBox = $tb; $col.Children.Add($tb) | Out-Null
        } else { $script:ConvInputBox = $null }

        # Back / Next
        $nav = New-Object Windows.Controls.DockPanel; $nav.Margin = New-Object Windows.Thickness (0, 14, 0, 0)
        $nextText = if ($step.type -eq 'welcome') { 'Begin ->' } elseif ($idx -eq $total - 1) { 'Finish ->' } else { 'Next ->' }
        $next = New-PrimaryButton -Text $nextText -Size 14 -OnClick { param($s, $e); Save-ConvCurrentInput; Set-ConversationStep ((Get-ConversationState).currentStep + 1); Refresh-Conversation }
        $next.HorizontalAlignment = 'Right'; [Windows.Controls.DockPanel]::SetDock($next, 'Right'); $nav.Children.Add($next) | Out-Null
        if ($idx -gt 0) {
            $back = New-MiniButton -Text '< Back' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -OnClick { param($s, $e); Save-ConvCurrentInput; Set-ConversationStep ((Get-ConversationState).currentStep - 1); Refresh-Conversation }
            $back.Padding = New-Object Windows.Thickness (16, 10, 16, 10); $back.Margin = New-Object Windows.Thickness 0; [Windows.Controls.DockPanel]::SetDock($back, 'Left'); $nav.Children.Add($back) | Out-Null
        }
        $col.Children.Add($nav) | Out-Null

        # Save & Exit / Resume Later
        $exit = New-Object Windows.Controls.StackPanel; $exit.Orientation = 'Horizontal'; $exit.HorizontalAlignment = 'Center'; $exit.Margin = New-Object Windows.Thickness (0, 14, 0, 0)
        $se = New-Text -Text 'Save & Exit' -Size 11.5 -Weight 'SemiBold' -Color $script:Col.Muted; $se.Cursor = 'Hand'; $se.Margin = New-Object Windows.Thickness (0, 0, 18, 0)
        $se.Add_MouseLeftButtonUp({ param($s, $e); Save-ConvCurrentInput; Set-ActiveView 'Home' }) | Out-Null; $exit.Children.Add($se) | Out-Null
        $rl = New-Text -Text 'Resume Later' -Size 11.5 -Weight 'SemiBold' -Color $script:Col.Muted; $rl.Cursor = 'Hand'
        $rl.Add_MouseLeftButtonUp({ param($s, $e); Save-ConvCurrentInput; Set-ActiveView 'Home' }) | Out-Null; $exit.Children.Add($rl) | Out-Null
        $col.Children.Add($exit) | Out-Null
    }

    $scroll = New-Object Windows.Controls.ScrollViewer; $scroll.VerticalScrollBarVisibility = 'Auto'; $scroll.HorizontalScrollBarVisibility = 'Disabled'; $scroll.Content = $col
    return $scroll
}

# =====================  NAV + SHELL  =====================
function New-Emoji { param([int[]]$Cp) return (-join ($Cp | ForEach-Object { [char]::ConvertFromUtf32($_) })) }

function Set-ActiveView {
    param([Parameter(Mandatory)][string]$Name)
    $script:TonyActiveView = $Name
    foreach ($n in $script:TonyNav) {
        if ($n.Name -eq $Name) { $n.Border.Background = New-Brush $script:Col.Accent; $n.Text.Foreground = New-Brush $script:Col.OnPrimary }
        else { $n.Border.Background = New-Brush $script:Col.Primary; $n.Text.Foreground = New-Brush $(if ($n.Dim) { '#6B7A93' } else { $script:Col.OnPrimaryMuted }) }
    }
    # immersive views (onboarding, the morning welcome) hide the utility toolbar for focus
    if ($script:TonyToolbar) { $script:TonyToolbar.Visibility = $(if ($Name -in @('First Conversation', 'Morning Experience')) { 'Collapsed' } else { 'Visible' }) }
    $body = switch ($Name) {
        'Morning Experience' { New-MorningExperience -Model (Get-MorningExperience -Now $script:TonyNow) }
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
        'Capture'        { New-CaptureView }
        'Tony Memory'    { New-TonyMemoryView }
        'Identity'       { New-IdentityView }
        'First Conversation' { New-FirstConversationView }
        'End of Day Audit' { New-AuditView }
        'Non-Negotiables'{ New-WorkspacePlaceholder -Title 'Non-Negotiables' -Belongs $script:WorkspaceBelongs['Non-Negotiables'] }
        'Family'         { New-WorkspacePlaceholder -Title 'Family' -Belongs $script:WorkspaceBelongs['Family'] }
        'Health'         { New-WorkspacePlaceholder -Title 'Health' -Belongs $script:WorkspaceBelongs['Health'] }
        'Financial'      { New-WorkspacePlaceholder -Title 'Financial' -Belongs $script:WorkspaceBelongs['Financial'] }
        'Home Projects'  { New-WorkspacePlaceholder -Title 'Home Projects' -Belongs $script:WorkspaceBelongs['Home Projects'] }
        'Learning'       { New-WorkspacePlaceholder -Title 'Learning' -Belongs $script:WorkspaceBelongs['Learning'] }
        default        { New-HomeView       -Model (Get-HomeModel -Now $script:TonyNow) }
    }
    $script:TonyBody.Child = $body
}

function New-SidebarNavItem {
    param([string]$Label, [string]$Key, [bool]$Dim = $false)
    $b = New-Object Windows.Controls.Border
    $b.CornerRadius = New-Object Windows.CornerRadius 8; $b.Padding = New-Object Windows.Thickness (12, 8, 12, 8)
    $b.Margin = New-Object Windows.Thickness (0, 0, 0, 3); $b.Cursor = 'Hand'; $b.Tag = $Key; $b.HorizontalAlignment = 'Stretch'
    $t = New-Text -Text $Label -Size 13 -Weight 'SemiBold' -Color $(if ($Dim) { '#6B7A93' } else { $script:Col.OnPrimaryMuted })
    $b.Child = $t
    $b.Add_MouseLeftButtonUp({ param($s, $e) Set-ActiveView $s.Tag }) | Out-Null
    return [pscustomobject]@{ Name = $Key; Border = $b; Text = $t; Dim = $Dim }
}

function New-TonyShell {
    param([string]$InitialView = 'Morning Experience', [datetime]$Now = (Get-Date), [Parameter(Mandatory)] $Theme)
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

    # nav (emoji built at runtime to keep the source ASCII-safe).
    # Daily tools first; not-yet-built workspaces are dimmed under a "COMING SOON" divider.
    $navDefs = @(
        [pscustomobject]@{ cp = @(0x1F3E0); label = 'Home'; key = 'Home'; dim = $false }
        [pscustomobject]@{ cp = @(0x1F319); label = 'End of Day Audit'; key = 'End of Day Audit'; dim = $false }
        [pscustomobject]@{ cp = @(0x1F4E5); label = 'Capture'; key = 'Capture'; dim = $false }
        [pscustomobject]@{ cp = @(0x1F4CB); label = 'Action Items'; key = 'Action Items'; dim = $false }
        [pscustomobject]@{ cp = @(0x1F9ED); label = 'Identity'; key = 'Identity'; dim = $false }
        [pscustomobject]@{ cp = @(0x1F680); label = 'Mission Control'; key = 'Mission Control'; dim = $false }
        [pscustomobject]@{ cp = @(0x1F916); label = 'AI Workforce'; key = 'Agents'; dim = $false }
        [pscustomobject]@{ cp = @(0x1F4AC); label = 'Tony'; key = 'Tony Memory'; dim = $false }
        [pscustomobject]@{ cp = @(0x2705); label = 'Non-Negotiables'; key = 'Non-Negotiables'; dim = $true }
        [pscustomobject]@{ cp = @(0x1F468, 0x200D, 0x1F469, 0x200D, 0x1F467, 0x200D, 0x1F466); label = 'Family'; key = 'Family'; dim = $true }
        [pscustomobject]@{ cp = @(0x2764, 0xFE0F); label = 'Health'; key = 'Health'; dim = $true }
        [pscustomobject]@{ cp = @(0x1F4B0); label = 'Financial'; key = 'Financial'; dim = $true }
        [pscustomobject]@{ cp = @(0x1F4BC); label = 'Agency'; key = 'Agency'; dim = $true }
        [pscustomobject]@{ cp = @(0x1F3E1); label = 'Home Projects'; key = 'Home Projects'; dim = $true }
        [pscustomobject]@{ cp = @(0x1F4DA); label = 'Learning'; key = 'Learning'; dim = $true }
    )
    $nav = New-Object Windows.Controls.StackPanel; $nav.VerticalAlignment = 'Top'
    $dividerAdded = $false
    foreach ($d in $navDefs) {
        if ($d.dim -and -not $dividerAdded) {
            $nav.Children.Add((New-Text -Text 'COMING SOON' -Size 9 -Weight 'Bold' -Color '#5A6B84' -Margin (New-Object Windows.Thickness (12, 10, 0, 4)))) | Out-Null
            $dividerAdded = $true
        }
        $item = New-SidebarNavItem -Label ((New-Emoji $d.cp) + '   ' + $d.label) -Key $d.key -Dim $d.dim
        $script:TonyNav += $item; $nav.Children.Add($item.Border) | Out-Null
    }
    $navScroll = New-Object Windows.Controls.ScrollViewer; $navScroll.VerticalScrollBarVisibility = 'Auto'; $navScroll.HorizontalScrollBarVisibility = 'Disabled'; $navScroll.Content = $nav
    [Windows.Controls.Grid]::SetRow($navScroll, 2); $sideGrid.Children.Add($navScroll) | Out-Null

    # settings (row 3)
    $setItem = New-SidebarNavItem -Label ((New-Emoji @(0x2699, 0xFE0F)) + '   Settings') -Key 'Settings'; $script:TonyNav += $setItem
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
    $script:TonyToolbar = $toolbar
    $tbDock = New-Object Windows.Controls.DockPanel
    $tbBtns = New-Object Windows.Controls.StackPanel; $tbBtns.Orientation = 'Horizontal'; $tbBtns.HorizontalAlignment = 'Right'
    $tbBtns.Children.Add((New-MiniButton -Text ((New-Emoji @(0x1F4AC)) + '  Talk with Tony') -Bg $script:Col.Accent -Fg $script:Col.OnPrimary -OnClick { param($s, $e) Open-TonyConversation | Out-Null })) | Out-Null
    $tbBtns.Children.Add((New-MiniButton -Text 'Open Mission Control' -Bg $script:Col.AccentSoft -Fg $script:Col.AccentInk -OnClick { param($s, $e) Open-TonyWindow -Name 'Mission Control' | Out-Null })) | Out-Null
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
