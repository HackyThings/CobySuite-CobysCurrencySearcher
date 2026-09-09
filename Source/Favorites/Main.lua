-------------------------------------------------------------------------------
-- CobysCurrencySearcher Favorites
--
-- The currencies the user starred on result rows. Stored account-wide in
-- COBYS_CURRENCY_SEARCHER_FAVORITES as { [currencyID] = true }. A favorite
-- never changes the order of anything: the Favorites filter only narrows
-- the list to starred currencies.
-------------------------------------------------------------------------------

local Debug = CobysCurrencySearcher.Debug

local Favorites = {}
CobysCurrencySearcher.Favorites = Favorites

-- The SavedVariable is created on ADDON_LOADED (Config.InitializeData), long
-- before any result row can exist; the guard only keeps a stray early call
-- safe.
local function Store()
  if COBYS_CURRENCY_SEARCHER_FAVORITES == nil then
    COBYS_CURRENCY_SEARCHER_FAVORITES = {}
  end
  return COBYS_CURRENCY_SEARCHER_FAVORITES
end

function Favorites.IsFavorite(currencyID)
  return currencyID ~= nil and Store()[currencyID] == true
end

function Favorites.Set(currencyID, on)
  if not currencyID then return end
  Store()[currencyID] = on and true or nil
  Debug.Log("FAVORITES", "%s currency %d", on and "Starred" or "Unstarred", currencyID)
end

function Favorites.Count()
  local n = 0
  for _ in pairs(Store()) do
    n = n + 1
  end
  return n
end
