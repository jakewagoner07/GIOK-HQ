# The Weather Provider

## Weather is the proof; the architecture is the point

*Project Diamond, Sprint D13. Tony's first live information provider - and the template for every
live service that follows.*

Implementation: `tony-alpha/dashboard/providers/weather-provider.ps1`, on the reusable registry
`tony-alpha/dashboard/core/live-providers.ps1`.

## Purpose

The purpose of this sprint was never weather. It was to establish the **permanent provider
architecture** that Calendar, Gmail, GoHighLevel, Maps, News, Stocks, Documents, and Search will
all follow. Weather is simply the first, keyless, verifiable proof of concept.

**Tony remains the interface.** The Weather Provider is an implementation detail. The user never
feels like they're talking to a weather app - they're talking to Tony, who happens to know the
weather.

## Architecture

```
Tony Brain (core/tony-brain.ps1)
  decides WHEN a live signal is needed
  -> Get-RelevantLiveSignals(text)   (core/live-providers.ps1)
       asks each registered provider "is this relevant?"; queries only the relevant ones
  -> weather signal flows into the request context
  -> the AI provider explains it naturally, in Tony's voice (answer first, ground second)

Live Provider registry (core/live-providers.ps1)  <-- the permanent seam
  Register-LiveProvider / Get-LiveProviders / Invoke-LiveProvider / Get-LiveProviderStatus
  a provider = { name; description; relevant(text); query(options); status(live) }

Weather Provider (providers/weather-provider.ps1)  <-- one implementation
  Get-Weather -> the structured Weather contract (or an honest failure)
  Get-WeatherStatus -> Connected / Ready / Disconnected + Last Updated (for Settings)
  registers itself with the registry
```

**Replaceable without touching Tony Brain.** The Brain talks only to the registry and reads the
contract; swapping the weather source (or the whole provider) changes nothing upstream.

## Provider contract

`Get-Weather` returns structured information - never prose, never a guess:

- **Current conditions**, **temperature**, **feels like**, **humidity**, **wind** (mph + direction)
- **Forecast** (today or tomorrow): conditions, **high**, **low**, **rain chance**
- **Sunrise**, **sunset**
- **Weather alerts** (array)
- **Provider status** (`connected` / `disconnected` / `network-error`) and a **timestamp**
- **Location** and an **ok** flag

On failure it returns `ok = $false` with an honest status detail - the caller says exactly why and
never invents a forecast.

## Data flow

1. Jake asks "What's the weather tomorrow?" in Talk with Tony (or anywhere the Brain runs).
2. Tony Brain calls `Get-RelevantLiveSignals`; the Weather Provider says "relevant" and is queried
   for `tomorrow`. A non-weather question queries nothing - no wasted network.
3. The structured weather flows into the request context; the AI provider **answers the weather
   first, naturally and specifically, then reconnects to Jake's day only if it fits** ("...morning
   before the heat spikes is your window - sunrise's at 6:04 AM").
4. If the fetch fails, the context carries the honest failure and Tony says he can't retrieve live
   weather right now and will answer automatically once the provider reconnects.

## Executive Context

Weather is another **signal**, not a new architecture. When it's relevant to the question, the
Brain passes the fetched weather into `Get-TonyExecutiveContext -Weather`, which folds a one-line
weather note into the executive summary - so Tony can connect it to the day ("You planned to visit
referral partners; the weather looks excellent for driving"). It is **never auto-fetched** on every
turn (no per-turn network, no hidden state), and the Executive Context architecture is unchanged -
just an additive, optional input.

## Failure behavior

Honest, always. If weather can't be retrieved, Tony says so plainly and never guesses:

> "I'm not able to retrieve live weather right now. Once the provider reconnects I'll answer these
> automatically."

## Settings

Settings gains a **Live Providers** card: Weather's provider, a status pill (Connected / Ready /
Disconnected), the location, **Last Updated**, and a **Check Weather** button that runs a real
fetch. Future providers appear here the same way.

## Future providers

Calendar, Gmail, GoHighLevel, Maps, News, Stocks, Documents, Search - **all follow this identical
architecture**: implement `relevant`, `query`, and `status`; register with the live-provider
registry; return a structured contract with its own status and timestamp; let Tony explain the
result. No provider ever talks to the user directly, and none requires changing Tony Brain.

## Constraints honored

No duplicate storage, no hidden state (every call fetches live), no direct UI dependency in the
provider, no changes to the Executive Context architecture, and the provider is replaceable without
touching Tony Brain. The location config is per-user and gitignored; Open-Meteo needs no key or
cloud account.

## Related
- [Tony_Brain.md](Tony_Brain.md) - decides when a live signal is needed.
- [Executive_Context_Engine.md](Executive_Context_Engine.md) - consumes weather as an optional signal.
- [Tony_AI_Provider_Contract.md](Tony_AI_Provider_Contract.md) - the AI provider that explains the weather in Tony's voice.
- [12_Future_Architecture.md](12_Future_Architecture.md) - the long-horizon integrations this seam enables.
