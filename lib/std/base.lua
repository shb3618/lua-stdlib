--[[--
 Prevent dependency loops with key function implementations.

 A few key functions are used in several stdlib modules; we implement those
 functions in this internal module to prevent dependency loops in the first
 instance, and to minimise coupling between modules where the use of one of
 these functions might otherwise load a whole selection of other supporting
 modules unnecessarily.

 Although the implementations are here for logistical reasons, we re-export
 them from their respective logical modules so that the api is not affected
 as far as client code is concerned. The functions in this file do not make
 use of `argcheck` or similar, because we know that they are only called by
 other stdlib functions which have already performed the necessary checking
 and neither do we want to slow everything down by recheckng those argument
 types here.

 This implies that when re-exporting from another module when argument type
 checking is in force, we must export a wrapper function that can check the
 user's arguments fully at the API boundary.

 @module std.base
]]


local _ARGCHECK = require "std.debug_init"._ARGCHECK

local typeof = type

local toomanyarg_fmt = "too many arguments to '%s' (no more than %d expected, got %d)"

-- Doc-commented in object.lua
local function prototype (o)
  return (getmetatable (o) or {})._type or io.type (o) or type (o)
end


--- Split a string at a given separator.
-- Separator is a Lua pattern, so you have to escape active characters,
-- `^$()%.[]*+-?` with a `%` prefix to match a literal character in *s*.
-- @function split
-- @string s to split
-- @string[opt="%s+"] sep separator pattern
-- @return list of strings
local function split (s, sep)
  sep = sep or "%s+"
  local b, len, t, patt = 0, #s, {}, "(.-)" .. sep
  if sep == "" then patt = "(.)"; t[#t + 1] = "" end
  while b <= len do
    local e, n, m = string.find (s, patt, b + 1)
    t[#t + 1] = m or s:sub (b + 1, len)
    b = n or len + 1
  end
  return t
end


local argcheck, argerror, argscheck

if _ARGCHECK then

  --- Concatenate a table of strings using ", " and " or " delimiters.
  -- @tparam table alternatives a table of strings
  -- @treturn string string of elements from alternatives delimited by ", "
  --   and " or "
  local function concat (alternatives)
    local t, i = {}, 1
    while i < #alternatives do
      t[i] = alternatives[i]
      i = i + 1
    end
    if #alternatives > 1 then
      t[#t] = t[#t] .. " or " .. alternatives[#alternatives]
    else
      t = alternatives
    end
    return table.concat (t, ", ")
  end


  -- Doc-commented in debug.lua
  function argcheck (name, i, expected, actual, level)
    level = level or 2
    expected = split (expected, "|")

    -- Strip trailing "?" but add "nil" to expected when a "?" is found.
    local add_nil = nil
    for i, v in ipairs (expected) do
      local m, q = v:match "^(.*)(%?)$"
      if m then
	expected[i] = m
        if add_nil == nil and q == "?" then
          add_nil = true
        end
      end
      if m == "nil" then add_nil = false end
    end
    if add_nil then
      expected[#expected + 1] = "nil"
    end

    -- Check actual has one of the types from expected
    local ok, actualtype = false, prototype (actual)
    for i, check in ipairs (expected) do
      if check == "#table" then
        if actualtype == "table" and next (actual) then
          ok = true
        end

      elseif check == "any" then
        expected[i] = "any value"
        if actual ~= nil then
          ok = true
        end

      elseif check == "file" then
        if io.type (actual) == "file" then
          ok = true
        end

      elseif check == "function" or check == "func" then
        expected[i] = "function"
        if actualtype == "function" or
            (getmetatable (actual) or {}).__call ~= nil
        then
           ok = true
        end

      elseif check == "int" then
        if actualtype == "number" and actual == math.floor (actual) then
          ok = true
        end

      elseif check == "list" or check == "#list" then
        if actualtype == "table" then
          local len, count = #actual, 0
	  local i = next (actual)
	  repeat
	    if i ~= nil then count = count + 1 end
            i = next (actual, i)
          until i == nil or count > len
	  if count == len and (check == "list" or count > 0) then
            ok = true
	  end
        end

      elseif check == "object" then
        if actualtype ~= "table" and typeof (actual) == "table" then
          ok = true
        end

      elseif typeof (check) == "string" and check:sub (1, 1) == ":" then
	if check == actual then
	  ok = true
	elseif actualtype == "string" and actual:sub (1, 1) == ":" then
	  actualtype = actual
	end

      elseif check == actualtype then
        ok = true
      end

      if ok then break end
    end

    if not ok then
      if actualtype == "nil" then
        actualtype = "no value"
      elseif type (actual) == "table" and next (actual) == nil then
	local expectedstr = "," .. table.concat (expected, ",") .. ","
        if actualtype == "table" and expectedstr == ",#list," then
          actualtype = "empty list"
	elseif actualtype == "table" or expectedstr:match ",#" then
          actualtype = "empty " .. actualtype
	end
      end
      expected = concat (expected):
                 gsub ("#table", "non-empty table"):
		 gsub ("#list", "non-empty list")
      argerror (name, i, expected .. " expected, got " .. actualtype, level + 1)
    end
  end


  -- Doc-commented in debug.lua
  function argscheck (name, expected, actual)
    if typeof (expected) ~= "table" then expected = {expected} end
    if typeof (actual) ~= "table" then actual = {actual} end

    for i, v in ipairs (expected) do
      argcheck (name, i, expected[i], actual[i], 3)
    end
  end

else

  local function nop () end

  -- Turn off argument checking if _DEBUG is false, or a table containing
  -- a false valued `argcheck` field.

  argcheck  = nop
  argscheck = nop

end


-- Doc-commented in debug.lua...
-- This function is not disabled by setting _DEBUG.
function argerror (name, i, extramsg, level)
  level = level or 1
  local s = string.format ("bad argument #%d to '%s'", i, name)
  if extramsg ~= nil then
    s = s .. " (" .. extramsg .. ")"
  end
  error (s, level + 1)
end


--- Write a deprecation warning to stderr on first call.
-- @func fn deprecated function
-- @string[opt] name function name for automatic warning message.
-- @string[opt] warnmsg full specified warning message (overrides *name*)
-- @return a function to show the warning on first call, and hand off to *fn*
-- @usage funcname = deprecate (function (...) ... end, "funcname")
local function deprecate (fn, name, warnmsg)
  argscheck ("std.base.deprecate", {"function", "string?", "string?"},
             {fn, name, warnmsg})

  if not (name or warnmsg) then
    error ("missing argument to 'std.base.deprecate' (2 or 3 arguments expected)", 2)
  end

  warnmsg = warnmsg or (name .. " is deprecated, and will go away in a future release.")
  local warnp = true
  return function (...)
    if warnp then
      local _, where = pcall (function () error ("", 4) end)
      io.stderr:write ((string.gsub (where, "(^w%*%.%w*%:%d+)", "%1")))
      io.stderr:write (warnmsg .. "\n")
      warnp = false
    end
    return fn (...)
  end
end


--- Export a function definition, optionally with argument type checking.
-- In addition to checking that each argument type matches the corresponding
-- element in the *types* table with `argcheck`, if the final element of
-- *types* ends with an asterisk, remaining unchecked arguments are checked
-- against that type.
-- @function export
-- @tparam table M module table
-- @string decl function type declaration string
-- @func fn value to store at *name* in *M*
-- @usage
-- export (M, "round (number, int?)", std.math.round)
local function export (M, decl, fn, ...)
  local inner = fn

  -- Parse "fname (argtype, argtype, argtype...)".
  local name, types
  if decl then
    name, types = decl:match "([%w_][%d%w_]*)%s+%((.*)%)"
  end

  -- When argument checking is enabled, wrap in type checking function.
  if _ARGCHECK then
    local fname = "std.base.export"
    local args = {M, decl, fn, ...}
    argscheck (fname, {"table", "string", "function"}, args)

    -- Check for other argument errors.
    if types == "" then
      types = {}
    elseif types then
      types = split (types, ",%s+")
    else
      name = decl:match "([%w_][%d%w_]*)"
    end
    if #args > 3 then
      error (string.format (toomanyarg_fmt, fname, 3, #args), 2)
    elseif type (M[1]) ~= "string" then
      argerror (fname, 1, "module name at index 1 expected, got no value")
    elseif name == nil then
      argerror (fname, 2, "function name expected")
    elseif types == nil then
      argerror (fname, 2, "argument type specifications expected")
    elseif #types < 1 then
      argerror (fname, 2, "at least 1 argument type expected, got 0")
    end

    local name = M[1] .. "." .. name

    local max, fin = #types, types[#types]:match "^(.+)%*$"
    if fin then
      max = math.huge
      types[#types] = fin
    end

    fn = function (...)
      local args = {...}
      local typec, argc = #types, #args
      for i = 1, typec do
        argcheck (name, i, types[i], args[i])
      end
      if max == math.huge then
        for i = typec + 1, argc do
          argcheck (name, i, types[typec], args[i])
	end
      end

      if argc > max then
        error (string.format (toomanyarg_fmt, name, max, argc), 2)
      end

      return inner (...)
    end
  end

  M[name] = fn

  return inner
end


--- An iterator over the integer keyed elements of a table.
-- @tparam table t a table
-- @treturn function iterator function
-- @treturn *t*
-- @return `true`
local function ielems (t)
  local n = 0
  return function (t)
           n = n + 1
           if n <= #t then
             return t[n]
           end
         end,
  t, true
end


--- Iterator returning leaf nodes from nested tables.
-- @tparam function it table iterator function
-- @tparam tree|table tr tree or tree-like table
-- @treturn function iterator function
-- @treturn tree|table the tree `tr`
local function leaves (it, tr)
  local function visit (n)
    if type (n) == "table" then
      for _, v in it (n) do
        visit (v)
      end
    else
      coroutine.yield (n)
    end
  end
  return coroutine.wrap (visit), tr
end


--- Return given metamethod, if any, or nil.
-- @tparam std.object x object to get metamethod of
-- @string n name of metamethod to get
-- @treturn function|nil metamethod function or `nil` if no metamethod or
--   not a function
-- @usage lookup = getmetamethod (require "std.object", "__index")
local function getmetamethod (x, n)
  local _, m = pcall (function (x)
                        return getmetatable (x)[n]
                      end,
                      x)
  if type (m) ~= "function" then
    m = nil
  end
  return m
end


local M = {
  argcheck      = argcheck,
  argerror      = argerror,
  argscheck     = argscheck,
  deprecate     = deprecate,
  export        = export,
  getmetamethod = getmetamethod,
  ielems        = ielems,
  leaves        = leaves,
  prototype     = prototype,
  split         = split,
}


return M
