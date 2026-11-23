AddCSLuaFile()

local SysTime = SysTime
local Frame = CLIENT and FrameNumber or engine.TickCount
local UNIT = CLIENT and "frame" or "tick"
local COMMAND = CLIENT and "luaprof" or "luaprof_sv"
local SELF = debug.getinfo(1, "S").short_src

local session

local function Resolve(path)
    local meta, method = string.match(path, "^([%w_]+):([%w_]+)$")
    if meta then return FindMetaTable(meta), method end

    local tbl, keys = _G, string.Explode(".", path)
    for i = 1, #keys - 1 do
        tbl = tbl[keys[i]]
        if not istable(tbl) then return end
    end

    return tbl, keys[#keys]
end

local function Caller()
    for level = 2, 16 do
        local info = debug.getinfo(level, "Sl")
        if not info then break end

        local src = info.short_src
        if info.currentline > 0 and src ~= SELF and not string.find(src, "lua/includes/", 1, true) then
            return src .. ":" .. info.currentline
        end
    end

    return "?"
end

local function Finish(stat, start, ...)
    local took = SysTime() - start
    stat.calls = stat.calls + 1
    stat.total = stat.total + took
    if took > stat.worst then stat.worst = took end

    local from = Caller()
    stat.callers[from] = (stat.callers[from] or 0) + 1
    return ...
end

local function Watch(path)
    local tbl, key = Resolve(path)
    local fn = tbl and tbl[key]
    if not isfunction(fn) then return false end

    local stat = { name = path, calls = 0, total = 0, worst = 0, callers = {} }
    local wrapped = function(...) return Finish(stat, SysTime(), fn(...)) end

    tbl[key] = wrapped
    session.stats[#session.stats + 1] = stat
    session.restore[#session.restore + 1] = function()
        if tbl[key] == wrapped then tbl[key] = fn end
    end

    return true
end

local function Stop()
    timer.Remove("luaprof")
    if not session then return end

    for i = #session.restore, 1, -1 do session.restore[i]() end

    local frames = math.max(Frame() - session.frame, 1)
    print(string.format("[luaprof] %.1fs, %d %ss", SysTime() - session.start, frames, UNIT))

    for _, stat in ipairs(session.stats) do
        print(string.format("  %s: %d calls, %.2f/%s, %.3f ms/%s, %.1f us/call, worst %.3f ms",
            stat.name, stat.calls, stat.calls / frames, UNIT, stat.total * 1000 / frames, UNIT,
            stat.calls > 0 and stat.total * 1e6 / stat.calls or 0, stat.worst * 1000))

        local callers = {}
        for from, count in pairs(stat.callers) do callers[#callers + 1] = { from, count } end
        table.sort(callers, function(a, b) return a[2] > b[2] end)

        for i = 1, math.min(#callers, 8) do
            print(string.format("    %8d  %s", callers[i][2], callers[i][1]))
        end
    end

    session = nil
end

concommand.Add(COMMAND, function(ply, _, args)
    if SERVER and IsValid(ply) and not ply:IsSuperAdmin() then return end

    Stop()

    local seconds = tonumber(args[1])
    if seconds then table.remove(args, 1) end
    if #args == 0 then
        print("[luaprof] " .. COMMAND .. " [seconds] <function> [function ...]")
        return
    end

    session = { stats = {}, restore = {}, start = SysTime(), frame = Frame() }
    for _, path in ipairs(args) do
        if not Watch(path) then print("[luaprof] not a function: " .. path) end
    end

    if #session.stats == 0 then
        session = nil
        return
    end

    seconds = seconds or 5
    print(string.format("[luaprof] watching %d function(s) for %gs", #session.stats, seconds))
    timer.Create("luaprof", seconds, 1, Stop)
end)

concommand.Add(COMMAND .. "_stop", function(ply)
    if SERVER and IsValid(ply) and not ply:IsSuperAdmin() then return end
    Stop()
end)
