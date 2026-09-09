---------------------------------------------------------------------------
-- CobySuite.Slash: slash command registrar
--
-- Registers an addon's slash aliases and routes "/cmd <name> <rest>" to a
-- command table, generating the help and version commands from it:
--
--   CobySuite.Slash.Register({
--     key      = "COBYSCURRENCYSEARCHER",          -- SlashCmdList key
--     slashes  = { "/ccs", "/cobyscurrencysearcher" },
--     title    = "Coby's Currency Searcher",
--     version  = "1.0.0",
--     message  = Message,                          -- the addon's chat printer
--     commands = {
--       { name = "settings", aliases = { "config" }, help = "open the settings window",
--         run = function(rest, input) ... end },
--       { usage = "<text>", help = "search for <text>" },   -- help line only
--     },
--     fallback = function(input, cmd, rest) ... end,   -- unknown command; default prints a hint
--     onEmpty  = function() ... end,                   -- bare "/ccs"; default prints the help
--     footer   = { "(Everything else lives in the settings window.)" },  -- extra help lines, optional
--     help     = function() ... end,                   -- replaces the generated help entirely
--   })
--
-- "/ccs help" prints the help (bare "/ccs" too, unless onEmpty is given);
-- "/ccs version" prints the version. Command names and aliases are matched
-- case-insensitively; `rest` is the trimmed text after the command, `input`
-- the whole trimmed line. Register returns the handler so an addon can call
-- it directly (tests, keybinds). `message` is captured at registration:
-- when the addon's printer is defined in a later file, pass a wrapper that
-- resolves it per call.
---------------------------------------------------------------------------
CobySuite.Slash = CobySuite.Slash or {}
local Slash = CobySuite.Slash
local U = CobySuite.Utilities

function Slash.Register(opts)
  assert(opts and opts.key, "Slash.Register needs opts.key")
  assert(opts.slashes and opts.slashes[1], "Slash.Register needs at least one slash alias")
  local message = opts.message or print
  local commands = opts.commands or {}
  local primary = opts.slashes[1]

  local byName = {}
  for _, def in ipairs(commands) do
    if def.name and def.run then
      byName[strlower(def.name)] = def
      for _, alias in ipairs(def.aliases or {}) do
        byName[strlower(alias)] = def
      end
    end
  end

  local function PrintHelp()
    if opts.help then
      opts.help()
      return
    end
    local heading = (opts.title or opts.key) .. (opts.version and (" v" .. opts.version) or "")
    message(U.WrapColor("FFFFFF", heading) .. " slash commands:")
    for _, def in ipairs(commands) do
      local usage = def.usage or def.name
      if usage and def.help then
        message("  " .. primary .. " " .. usage .. ": " .. def.help)
      end
    end
    if opts.version then
      message("  " .. primary .. " version: Print the addon version")
    end
    message("  " .. primary .. " help: Show this help")
    for _, line in ipairs(opts.footer or {}) do
      message(line)
    end
  end

  local function Handle(input)
    input = strtrim(input or "")
    local cmd, rest = input:match("^(%S+)%s*(.-)$")
    cmd = strlower(cmd or "")
    rest = rest or ""

    if cmd == "" then
      if opts.onEmpty then opts.onEmpty() else PrintHelp() end
      return
    end
    if cmd == "help" then
      PrintHelp()
      return
    end
    if cmd == "version" and opts.version then
      message("v" .. opts.version)
      return
    end
    local def = byName[cmd]
    if def then
      def.run(rest, input)
      return
    end
    if opts.fallback then
      opts.fallback(input, cmd, rest)
    else
      message(("Unknown command '%s'. Type %s help for the list."):format(cmd, primary))
    end
  end

  for i, slash in ipairs(opts.slashes) do
    _G["SLASH_" .. opts.key .. i] = slash
  end
  SlashCmdList[opts.key] = Handle
  return Handle
end
