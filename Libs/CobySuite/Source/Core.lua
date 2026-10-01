-- CobySuite: Shared library for all CobySuite addons
-- All shared utilities, UI factories, and infrastructure live here.
-- Individual addons (CobySniper, CobysLinkepedia, etc.) depend on this.

CobySuite_CobysCurrencySearcher = CobySuite_CobysCurrencySearcher or {}

-- Sub-namespace declarations (populated by individual modules)
CobySuite_CobysCurrencySearcher.Utilities = CobySuite_CobysCurrencySearcher.Utilities or {}
CobySuite_CobysCurrencySearcher.UI        = CobySuite_CobysCurrencySearcher.UI or {}
CobySuite_CobysCurrencySearcher.Debug     = CobySuite_CobysCurrencySearcher.Debug or {}
CobySuite_CobysCurrencySearcher.Config    = CobySuite_CobysCurrencySearcher.Config or {}
CobySuite_CobysCurrencySearcher.EventBus  = CobySuite_CobysCurrencySearcher.EventBus or {}
CobySuite_CobysCurrencySearcher.Chat      = CobySuite_CobysCurrencySearcher.Chat or {}
CobySuite_CobysCurrencySearcher.Slash     = CobySuite_CobysCurrencySearcher.Slash or {}
CobySuite_CobysCurrencySearcher.Tests     = CobySuite_CobysCurrencySearcher.Tests or {}

CobySuite_CobysCurrencySearcher.SortDir = { ASC = "asc", DESC = "desc" }

-- Where this copy of the library comes from. The monorepo's CobySuite addon
-- leaves it as is; a standalone build embeds the library under its own name
-- and replaces it from its Build.lua with { embedded = true, host = "<addon>",
-- commit = "<short sha>", dirty = <bool> }.
CobySuite_CobysCurrencySearcher.BuildInfo = CobySuite_CobysCurrencySearcher.BuildInfo or { embedded = false }

-- The library version for reports: "embedded in <host> at <commit>" in a
-- standalone build, else the CobySuite addon's TOC version. The addon name
-- below is the only string literal in shipped shared code that is exactly
-- the library's name (the standalone build checks this; Source/Tests/ is
-- stripped).
function CobySuite_CobysCurrencySearcher.LibraryVersionText()
  local info = CobySuite_CobysCurrencySearcher.BuildInfo
  if info and info.embedded then
    return ("embedded in %s at %s"):format(tostring(info.host or "?"), tostring(info.commit or "?"))
  end
  return C_AddOns.GetAddOnMetadata("CobySuite", "Version") or "?"
end
