-- Base

require "std.table"
require "std.string.string"


-- @func metamethod: Return given metamethod, if any, or nil
--   @param x: object to get metamethod of
--   @param n: name of metamethod to get
-- returns
--   @param m: metamethod function or nil if no metamethod or not a
--   function
function metamethod (x, n)
  local _, m = pcall (function (x)
                        return getmetatable (x)[n]
                      end,
                      x)
  if type (m) ~= "function" then
    m = nil
  end
  return m
end

-- print: Make print use tostring, so that improvements to tostring
-- are picked up
--   @param arg: objects to print
local _print = print
function print (...)
  for i, v in ipairs (arg) do
    arg[i] = tostring (v)
  end
  _print (unpack (arg))
end

-- @func tostring: Extend tostring to work better on tables
--   @param x: object to convert to string
-- returns
--   @param s: string representation
local _tostring = tostring
function tostring (x)
  if type (x) == "table" and (not metamethod (x, "__tostring")) then
    local s, sep = "{", ""
    for i, v in pairs (x) do
      s = s .. sep .. tostring (i) .. "=" .. tostring (v)
      sep = ","
    end
    s = s .. "}"
    return s
  else
    return _tostring (x)
  end
end

-- @func totable: Turn an object into a table according to __totable
-- metamethod
--   @param x: object to turn into a table
-- returns
--   @param t: table or nil
function totable (x)
  local m = metamethod (x, "__totable")
  if m then
    return m (x)
  elseif type (x) == "table" then
    return x
  else
    return nil
  end
end

-- @func pickle: Convert a value to a string
-- The string can be passed to dostring to retrieve the value
-- Does not work for recursive tables
--   @param x: object to pickle
-- returns
--   @param s: string such that eval (s) is the same value as x
function pickle (x)
  if type (x) == "nil" then
    return "nil"
  elseif type (x) == "number" then
    return tostring (x)
  elseif type (x) == "string" then
    return format ("%q", x)
  else
    x = totable (x) or x
    if type (x) == "table" then
      local s, sep = "{", ""
      for i, v in pairs (x) do
        s = s .. sep .. "[" .. pickle (i) .. "]=" .. pickle (v)
        sep = ","
      end
      s = s .. "}"
      return s
    else
      die ("can't pickle " .. tostring (x))
    end
  end
end

-- id: Identity
--   x: object
-- returns
--   x: same object
function id (x)
  return x
end

-- pack: Turn a tuple into a list
--   ...: tuple
-- returns
--   l: list
function pack (...)
  return arg
end

-- curry: Partially apply a function
--   f: function to apply partially
--   a1 ... an: arguments to fix
-- returns
--   g: function with ai fixed
function curry (f, ...)
  local fix = arg
  return function (...)
           return f (table.merge (unpack (fix), unpack (arg)))
         end
end

-- compose: Compose some functions
--   f1 ... fn: functions to compose
-- returns
--   g: composition of f1 ... fn
--     args: arguments
--   returns
--     f1 (...fn (args)...)
function compose (...)
  local fns, n = arg, table.getn (arg)
  return function (...)
           for i = n, 1, -1 do
             arg = pack (fns[i](unpack (arg)))
           end
           return unpack (arg)
         end
end

-- eval: Evaluate a string
--   s: string
-- returns
--   v: value of string
function eval (s)
  return loadstring ("return " .. s)()
end