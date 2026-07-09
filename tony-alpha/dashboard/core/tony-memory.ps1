# =====================================================================
# tony-memory.ps1  —  Tony's STRUCTURED memory (framework only)
# ---------------------------------------------------------------------
# This is NOT conversation memory. It is structured, durable memory that
# Tony builds over time about Jake's world. For now this establishes the
# framework and storage only - categories exist, population comes later.
#
# Source of truth: tony_memory.json. Reads from GIOK's data; it is a lens
# on the world, never a rival copy of the registry/captures.
# =====================================================================

$ErrorActionPreference = 'Stop'

# The structured-memory categories (framework). Populated in later versions.
function Get-TonyMemoryCategories {
    return @(
        [pscustomobject]@{ key = 'people';        name = 'People';        desc = 'Who Jake knows - clients, family, prospects, mentors - and what matters about them.' }
        [pscustomobject]@{ key = 'ideas';         name = 'Ideas';         desc = 'Ideas worth keeping and developing.' }
        [pscustomobject]@{ key = 'preferences';   name = 'Preferences';   desc = "Jake's preferences and how he likes things done." }
        [pscustomobject]@{ key = 'business';      name = 'Business';      desc = 'Durable facts about the agency and how it runs.' }
        [pscustomobject]@{ key = 'family';        name = 'Family';        desc = 'The people closest to Jake and what matters to them.' }
        [pscustomobject]@{ key = 'goals';         name = 'Goals';         desc = "Long-horizon intentions Tony should keep alive." }
        [pscustomobject]@{ key = 'relationships'; name = 'Relationships'; desc = 'Connection history and last-contact for key people.' }
        [pscustomobject]@{ key = 'lessons';       name = 'Lessons';       desc = 'What worked, what did not - lessons learned.' }
        [pscustomobject]@{ key = 'patterns';      name = 'Patterns';      desc = 'Recurring patterns Tony notices over time.' }
    )
}

function Get-TonyMemoryPath { return (Join-Path $PSScriptRoot '..\..\tony_memory.json') }

function Get-TonyMemoryData {
    $p = Get-TonyMemoryPath
    if (Test-Path $p) {
        try { return (Get-Content -Path $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { }
    }
    # framework default: every category present, empty
    $cats = [ordered]@{}
    foreach ($c in (Get-TonyMemoryCategories)) { $cats[$c.key] = @() }
    return [pscustomobject]@{ meta = [pscustomobject]@{ version = '0.1.0'; framework = $true; updated = $null }; categories = [pscustomobject]$cats }
}

function Get-TonyMemoryCount {
    param([Parameter(Mandatory)][string]$Key)
    $data = Get-TonyMemoryData
    if ($data.categories.PSObject.Properties.Name -contains $Key) { return @($data.categories.$Key).Count }
    return 0
}
