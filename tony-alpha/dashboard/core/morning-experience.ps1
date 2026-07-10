# =====================================================================
# morning-experience.ps1  —  GIOK's "first minute" model (business logic)
# ---------------------------------------------------------------------
# The Morning Experience is the premium welcome moment when Jake opens
# GIOK: greeting, a thought, why it was chosen, the day's principle and
# focus, priorities, one Tony recommendation, and "Begin My Day".
#
# Dedicated model; the UI renders from it and is composed of independent,
# replaceable components. Local data only - no external APIs or internet
# retrieval. Placeholders are clearly marked (source='placeholder').
# =====================================================================

$ErrorActionPreference = 'Stop'

# Local quote library (no internet). Each quote carries full attribution.
function Get-MorningThoughtLibrary {
    return @(
        [pscustomobject]@{ quote = 'Discipline is the bridge between goals and accomplishment.'; author = 'Jim Rohn'; theme = 'Discipline'; category = 'Motivation'; source = 'Local library' }
        [pscustomobject]@{ quote = 'You have power over your mind - not outside events. Realize this, and you will find strength.'; author = 'Marcus Aurelius'; theme = 'Mindset'; category = 'Stoicism'; source = 'Local library' }
        [pscustomobject]@{ quote = 'The best time to plant a tree was twenty years ago. The second best time is now.'; author = 'Chinese Proverb'; theme = 'Action'; category = 'Wisdom'; source = 'Local library' }
        [pscustomobject]@{ quote = 'We are what we repeatedly do. Excellence, then, is not an act, but a habit.'; author = 'Will Durant (summarizing Aristotle)'; theme = 'Habits'; category = 'Philosophy'; source = 'Local library' }
        [pscustomobject]@{ quote = 'Do the hard thing while it is easy; do the great thing while it is small.'; author = 'Lao Tzu, Tao Te Ching'; theme = 'Consistency'; category = 'Philosophy'; source = 'Local library' }
        [pscustomobject]@{ quote = 'Protect your family the way you protect your future - on purpose.'; author = 'GIOK'; theme = 'Ownership'; category = 'GIOK Principle'; source = 'GIOK' }
        [pscustomobject]@{ quote = 'Small, consistent, boring decisions beat dramatic ones made too late.'; author = 'GIOK'; theme = 'Consistency'; category = 'GIOK Principle'; source = 'GIOK' }
        [pscustomobject]@{ quote = 'Take care of the people, and the numbers take care of themselves.'; author = 'GIOK'; theme = 'People'; category = 'GIOK Principle'; source = 'GIOK' }
    )
}

function Get-MorningThought {
    param([datetime]$Now = (Get-Date))
    $lib = Get-MorningThoughtLibrary
    return $lib[($Now.DayOfYear % $lib.Count)]
}

# Why Tony chose today's thought. Placeholder reasoning today; future versions
# will use goals, health, life/business score, patterns, capture history, audits.
function Get-WhyThisToday {
    param([datetime]$Now = (Get-Date), $Thought)
    $openAI = if (Get-Command Get-ActionItemsData -ErrorAction SilentlyContinue) { @((Get-ActionItemsData).items | Where-Object { -not $_.archived -and -not $_.done }).Count } else { 0 }
    $unproc = if (Get-Command Get-CaptureStats -ErrorAction SilentlyContinue) { (Get-CaptureStats).unprocessed } else { 0 }
    $theme = if ($Thought) { $Thought.theme } else { 'discipline' }
    return [pscustomobject]@{
        text   = ("Tony chose a thought on {0} today. With {1} open action items and {2} captures waiting, staying consistent - not busy - is what moves the day forward." -f $theme.ToLower(), $openAI, $unproc)
        source = 'placeholder'
    }
}

# One-sentence focus for the day. Placeholder rotation today; future AI-generated.
function Get-TodaysFocus {
    param([datetime]$Now = (Get-Date))
    $focuses = @(
        "Today's biggest opportunity is consistent follow-up.",
        "Today, protect your deep-work time before the noise arrives.",
        "Today, one honest Checkup beats ten new leads.",
        "Today, capture everything and decide later.",
        "Today, do the boring thing on time."
    )
    return [pscustomobject]@{ text = $focuses[($Now.DayOfYear % $focuses.Count)]; source = 'placeholder' }
}

function Get-MorningExperience {
    param([datetime]$Now = (Get-Date))
    $thought = Get-MorningThought -Now $Now

    $openAI = if (Get-Command Get-ActionItemsData -ErrorAction SilentlyContinue) { @((Get-ActionItemsData).items | Where-Object { -not $_.archived -and -not $_.done }) } else { @() }
    $topPriorities = @($openAI | Select-Object -First 3 | ForEach-Object { [pscustomobject]@{ id = $_.id; title = $_.title } })

    $topRec = $null
    if (Get-Command Get-TonyRecommendations -ErrorAction SilentlyContinue) { $topRec = @(Get-TonyRecommendations -Max 1)[0] }

    return [pscustomobject]@{
        greeting       = (Get-Greeting -Now $Now)
        dateText       = $Now.ToString('dddd, MMMM d, yyyy')
        thought        = $thought
        whyThisToday   = (Get-WhyThisToday -Now $Now -Thought $thought)
        dailyPrinciple = (Get-DailyPrinciple -Now $Now)
        todaysFocus    = (Get-TodaysFocus -Now $Now)
        topPriorities  = $topPriorities
        recommendation = $topRec
    }
}
