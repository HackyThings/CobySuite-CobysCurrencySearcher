-------------------------------------------------------------------------------
-- CobysCurrencySearcher Favorites
--
-- The currencies the user starred, on any currency row (Blizzard's list or
-- the search results). Stored account-wide in
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
  if type(COBYS_CURRENCY_SEARCHER_FAVORITES) ~= "table" then
    COBYS_CURRENCY_SEARCHER_FAVORITES = {}
  end
  return COBYS_CURRENCY_SEARCHER_FAVORITES
end

-- A Verify scene's sample favorites (the search's BeginPreview), read in
-- place of the saved set while a scene shows one; never written, memory
-- only. Set and ClearAll still write the saved set.
local previewSet

function Favorites.SetPreview(set)
  previewSet = set
end

function Favorites.IsFavorite(currencyID)
  return currencyID ~= nil and (previewSet or Store())[currencyID] == true
end

function Favorites.Set(currencyID, on)
  if not currencyID then return end
  Store()[currencyID] = on and true or nil
  Debug.Log("FAVORITES", "%s currency %d", on and "Starred" or "Unstarred", currencyID)
  CobysCurrencySearcher.EventBus:Fire(CobysCurrencySearcher.Events.FavoritesChanged, currencyID)
end

-- Every star at once (the settings window's Clear all favorites, after its
-- confirmation): one write and one event, so the search refreshes once.
-- Returns how many were removed.
function Favorites.ClearAll()
  local removed = 0   -- the saved set, even while a preview shows another
  for _ in pairs(Store()) do removed = removed + 1 end
  wipe(Store())
  Debug.Log("FAVORITES", "Cleared all %d favorites", removed)
  CobysCurrencySearcher.EventBus:Fire(CobysCurrencySearcher.Events.FavoritesChanged, nil)
  return removed
end

function Favorites.Count()
  local n = 0
  for _ in pairs(previewSet or Store()) do
    n = n + 1
  end
  return n
end
