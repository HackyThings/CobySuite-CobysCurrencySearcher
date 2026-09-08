-- CobySuite.EventBus — shared pub/sub constructor
-- Each addon gets its own independent instance via New()

local EventBus = CobySuite.EventBus

function EventBus.New()
  local bus = {}
  local listeners = {}

  function bus:Register(listener, eventNames)
    for _, eventName in ipairs(eventNames) do
      if not listeners[eventName] then
        listeners[eventName] = {}
      end
      listeners[eventName][listener] = true
    end
    return self
  end

  function bus:Unregister(listener, eventNames)
    for _, eventName in ipairs(eventNames) do
      if listeners[eventName] then
        listeners[eventName][listener] = nil
      end
    end
    return self
  end

  function bus:Fire(eventName, ...)
    local bucket = listeners[eventName]
    if not bucket then return self end

    -- Iterate directly — no snapshot allocation.
    -- pairs() is safe here: Lua 5.1 guarantees that deleting keys during
    -- pairs() iteration won't crash; the guard re-checks the key is still
    -- registered before dispatching (handles mid-iteration Unregister).
    for listener in pairs(bucket) do
      if bucket[listener] then
        listener:ReceiveEvent(eventName, ...)
      end
    end
    return self
  end

  return bus
end
