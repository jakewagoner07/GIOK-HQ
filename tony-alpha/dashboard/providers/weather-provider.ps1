# =====================================================================
# weather-provider.ps1  —  Tony's FIRST live information provider
# ---------------------------------------------------------------------
# Weather is the proof of concept. The real deliverable is the permanent
# provider architecture (core/live-providers.ps1) that every future live
# service will follow. Tony remains the interface; this provider is an
# implementation detail and can be replaced without touching Tony Brain.
#
# Source: Open-Meteo (https://open-meteo.com) - free, no API key. Location
# defaults to Ogden, UT and is overridable via env (GIOK_WEATHER_LAT/LON/
# NAME) or a gitignored weather.config.json. Returns structured weather
# with its own provider status and timestamp. No duplicate storage, no
# hidden state - every call fetches live.
# =====================================================================

$ErrorActionPreference = 'Stop'

function Get-WeatherConfig {
    $lat = 41.223; $lon = -111.973; $name = 'Ogden, UT'; $source = 'default (Ogden, UT)'
    if ($env:GIOK_WEATHER_LAT -and $env:GIOK_WEATHER_LON) {
        $lat = [double]$env:GIOK_WEATHER_LAT; $lon = [double]$env:GIOK_WEATHER_LON
        if ($env:GIOK_WEATHER_NAME) { $name = $env:GIOK_WEATHER_NAME }
        $source = 'environment'
    }
    $cfg = Join-Path $PSScriptRoot 'weather.config.json'
    if (Test-Path $cfg) {
        try {
            $c = Get-Content $cfg -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $c.latitude -and $null -ne $c.longitude) { $lat = [double]$c.latitude; $lon = [double]$c.longitude; if ($c.name) { $name = $c.name }; $source = 'weather.config.json' }
        } catch { }
    }
    return [pscustomobject]@{ latitude = $lat; longitude = $lon; name = $name; source = $source; endpoint = 'https://api.open-meteo.com/v1/forecast'; provider = 'open-meteo' }
}

# WMO weather code -> plain-language conditions.
function Get-WeatherCodeText {
    param([int]$Code)
    switch ($Code) {
        0 { 'clear skies' } 1 { 'mostly clear' } 2 { 'partly cloudy' } 3 { 'overcast' }
        45 { 'foggy' } 48 { 'freezing fog' }
        51 { 'light drizzle' } 53 { 'drizzle' } 55 { 'heavy drizzle' } 56 { 'freezing drizzle' } 57 { 'freezing drizzle' }
        61 { 'light rain' } 63 { 'rain' } 65 { 'heavy rain' } 66 { 'freezing rain' } 67 { 'freezing rain' }
        71 { 'light snow' } 73 { 'snow' } 75 { 'heavy snow' } 77 { 'snow grains' }
        80 { 'light rain showers' } 81 { 'rain showers' } 82 { 'heavy rain showers' }
        85 { 'snow showers' } 86 { 'heavy snow showers' }
        95 { 'thunderstorms' } 96 { 'thunderstorms with hail' } 99 { 'severe thunderstorms' }
        default { 'unsettled' }
    }
}

function Get-WindCompass {
    param([double]$Deg)
    $dirs = @('N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW')
    return $dirs[([int]([math]::Round($Deg / 22.5)) % 16)]
}

# The ONLY network call in this provider. UTF-8 decoded explicitly.
function Invoke-OpenMeteo {
    param($Config)
    $url = ('{0}?latitude={1}&longitude={2}&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=auto&forecast_days=2' -f $Config.endpoint, $Config.latitude, $Config.longitude)
    $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15
    return (([System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())) | ConvertFrom-Json)
}

# The structured Weather contract every consumer reads. On failure it
# returns ok=$false with an honest status - never a guessed forecast.
function Get-Weather {
    param([string]$When = 'today')
    $cfg = Get-WeatherConfig
    $now = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $status = [pscustomobject]@{ state = 'disconnected'; detail = ''; lastUpdated = $null }
    try {
        $j = Invoke-OpenMeteo -Config $cfg
        $idx = if ($When -eq 'tomorrow') { 1 } else { 0 }
        $cur = $j.current
        $srT = try { ([datetime]([string]$j.daily.sunrise[$idx])).ToString('h:mm tt') } catch { [string]$j.daily.sunrise[$idx] }
        $ssT = try { ([datetime]([string]$j.daily.sunset[$idx])).ToString('h:mm tt') } catch { [string]$j.daily.sunset[$idx] }
        $status.state = 'connected'; $status.detail = ('Live from Open-Meteo ({0}).' -f $cfg.name); $status.lastUpdated = $now
        return [pscustomobject]@{
            provider    = 'weather'; ok = $true; status = $status; timestamp = $now; location = $cfg.name; when = $When
            current     = [pscustomobject]@{
                conditions  = (Get-WeatherCodeText ([int]$cur.weather_code))
                temperature = [int][math]::Round($cur.temperature_2m)
                feelsLike   = [int][math]::Round($cur.apparent_temperature)
                humidity    = [int]$cur.relative_humidity_2m
                windMph     = [int][math]::Round($cur.wind_speed_10m)
                windDir     = (Get-WindCompass $cur.wind_direction_10m)
            }
            forecast    = [pscustomobject]@{
                when          = $When
                conditions    = (Get-WeatherCodeText ([int]$j.daily.weather_code[$idx]))
                high          = [int][math]::Round($j.daily.temperature_2m_max[$idx])
                low           = [int][math]::Round($j.daily.temperature_2m_min[$idx])
                rainChancePct = [int]$j.daily.precipitation_probability_max[$idx]
            }
            sunrise     = $srT; sunset = $ssT; alerts = @()
        }
    } catch {
        $msg = $_.Exception.Message
        $class = 'network-error'
        if (Get-Command Get-ClaudeErrorInfo -ErrorAction SilentlyContinue) { try { $info = Get-ClaudeErrorInfo -ErrorRecord $_; $class = $info.class; $msg = $info.message } catch { } }
        $state = if ($class -eq 'network-error') { 'disconnected' } else { $class }
        $status.state = $state; $status.detail = ('Could not reach the weather service: {0}' -f $msg)
        return [pscustomobject]@{ provider = 'weather'; ok = $false; status = $status; timestamp = $now; location = $cfg.name; when = $When; current = $null; forecast = $null; sunrise = $null; sunset = $null; alerts = @() }
    }
}

# Status for Settings. Without -Live: ready (configured), no network. With
# -Live: a real fetch -> connected / disconnected, with Last Updated.
function Get-WeatherStatus {
    param([switch]$Live)
    $cfg = Get-WeatherConfig
    if (-not $Live) {
        return [pscustomobject]@{ name = 'Weather'; state = 'ready'; detail = ('Open-Meteo (no key required). Location: {0}. Run a check to confirm live.' -f $cfg.name); lastUpdated = $null; location = $cfg.name }
    }
    $w = Get-Weather -When 'today'
    $state = if ($w.ok) { 'connected' } else { $w.status.state }
    return [pscustomobject]@{ name = 'Weather'; state = $state; detail = $w.status.detail; lastUpdated = $w.status.lastUpdated; location = $cfg.name }
}

# Is a question about the weather? Tony Brain uses this to decide WHEN to fetch.
function Test-WeatherRelevant {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return [bool]($Text -match '(?i)\b(weather|forecast|temperature|how (?:hot|cold|warm)|rain|raining|snow|snowing|sunny|cloudy|wind|windy|humid|umbrella|degrees|nice out|nice outside)\b')
}

# Register with the live-provider registry (the permanent architecture).
if (Get-Command Register-LiveProvider -ErrorAction SilentlyContinue) {
    Register-LiveProvider -Provider ([pscustomobject]@{
            name        = 'weather'
            description = 'Live weather via Open-Meteo (no key). Location is configurable.'
            relevant    = { param($text) Test-WeatherRelevant $text }
            query       = { param($opts) $when = if ($opts -and $opts.When) { $opts.When } else { 'today' }; Get-Weather -When $when }
            status      = { param($live) Get-WeatherStatus -Live:([bool]$live) }
        })
}
