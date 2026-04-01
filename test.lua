-- ============================================================
--  NOKA [REWRITE] [BETA] [STABLE]
--  Optimized Build v3.1 | Rooted Device | Server Logic
-- ============================================================

local CFG_DIR  = "/sdcard/noka"
local CFG_PATH = "/sdcard/noka/config.json"
local TMP_PATH = "/sdcard/noka/ui_dump.xml"

local C = {
    CYAN   = "\27[1;36m",
    GREEN  = "\27[1;32m",
    BLUE   = "\27[1;34m",
    RED    = "\27[1;31m",
    YELLOW = "\27[1;33m",
    RESET  = "\27[0m"
}

-- ============================================================
--  PRIMITIVES
-- ============================================================

local function OUT(text)
    io.write((text or "") .. "\n")
    io.flush()
end

local function SLEEP(n)
    os.execute("sleep " .. tonumber(n))
end

local function FIX_TTY()
    os.execute("stty sane 2>/dev/null")
end

local function PROMPT(msg)
    FIX_TTY()
    io.write(msg)
    io.flush()
    local res = io.read("*l") or ""
    return res:gsub("^%s*(.-)%s*$", "%1")
end

-- Root shell wrapper
local function SH(cmd)
    local ok, res = pcall(function()
        local h = io.popen("timeout 8 su -c '" .. cmd .. "' 2>/dev/null")
        local r = h and h:read("*a") or ""
        if h then h:close() end
        return r:gsub("\r", ""):gsub("%s+$", "")
    end)
    return ok and res or ""
end

-- Unprivileged shell
local function SHU(cmd)
    local ok, res = pcall(function()
        local h = io.popen("timeout 5 " .. cmd .. " 2>/dev/null")
        local r = h and h:read("*a") or ""
        if h then h:close() end
        return r:gsub("\r", ""):gsub("%s+$", "")
    end)
    return ok and res or ""
end

local function CLS()
    io.write("\27[2J\27[H")
    io.flush()
end

-- ============================================================
--  JSON ENGINE (Minimal)
-- ============================================================
local JSON = {}
function JSON.encode(v)
    local t = type(v)
    if t == "nil" then return "null"
    elseif t == "boolean" then return v and "true" or "false"
    elseif t == "number" then return tostring(v)
    elseif t == "string" then return '"'..v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r')..'"'
    elseif t == "table" then
        local parts, is_arr, n = {}, true, 0
        for k in pairs(v) do n = n + 1; if type(k) ~= "number" then is_arr = false end end
        if is_arr and n > 0 then
            for i=1,n do table.insert(parts, JSON.encode(v[i])) end
            return "["..table.concat(parts, ",").."]"
        else
            for k, val in pairs(v) do table.insert(parts, '"'..tostring(k)..'":'..JSON.encode(val)) end
            return "{"..table.concat(parts, ",").."}"
        end
    end
    return "null"
end

function JSON.decode(s)
    if not s or s == "" then return nil end
    local pos = 1
    local function skip() while pos <= #s and s:sub(pos,pos):match("%s") do pos = pos + 1 end end
    local function val()
        skip(); local c = s:sub(pos,pos)
        if c == '"' then
            pos = pos + 1; local r = ""
            while pos <= #s do
                local ch = s:sub(pos,pos); if ch == '"' then pos = pos + 1; break end
                if ch == "\\" then pos = pos + 1; ch = s:sub(pos,pos) end
                r = r .. ch; pos = pos + 1
            end
            return r
        elseif c == '{' then
            pos = pos + 1; local o = {}; skip()
            if s:sub(pos,pos) == '}' then pos = pos + 1; return o end
            while true do
                local k = val(); skip(); pos = pos + 1; o[k] = val(); skip()
                if s:sub(pos,pos) == '}' then pos = pos + 1; break end
                pos = pos + 1
            end
            return o
        elseif c == '[' then
            pos = pos + 1; local a = {}; skip()
            if s:sub(pos,pos) == ']' then pos = pos + 1; return a end
            while true do
                table.insert(a, val()); skip()
                if s:sub(pos,pos) == ']' then pos = pos + 1; break end
                pos = pos + 1
            end
            return a
        elseif s:sub(pos,pos+3) == "true" then pos = pos + 4; return true
        elseif s:sub(pos,pos+4) == "false" then pos = pos + 5; return false
        elseif s:sub(pos,pos+3) == "null" then pos = pos + 4; return nil
        else
            local n = s:match("^-?%d+%.?%d*", pos); if n then pos = pos + #n; return tonumber(n) end
        end
    end
    local ok, res = pcall(val)
    return ok and res or nil
end

-- ============================================================
--  PERSISTENCE
-- ============================================================

local function SAVE_CONFIG(cfg)
    os.execute("mkdir -p " .. CFG_DIR)
    local f = io.open(CFG_PATH, "w")
    if f then f:write(JSON.encode(cfg)); f:close() return true end
    return false
end

local function LOAD_CONFIG()
    local f = io.open(CFG_PATH, "r")
    if f then
        local raw = f:read("*a"); f:close()
        return JSON.decode(raw)
    end
    return nil
end

-- ============================================================
--  UI & DASHBOARD
-- ============================================================

local function BANNER(silent)
    if silent then
        io.write("\27[H\27[K")
    else
        CLS()
    end
    
    local logo = {
        [[ ███╗   ██╗  ██████╗  ██╗  ██╗  █████╗ ]],
        [[ ████╗  ██║ ██╔═══██╗ ██║ ██╔╝ ██╔══██╗]],
        [[ ██╔██╗ ██║ ██║   ██║ █████╔╝  ███████║]],
        [[ ██║╚██╗██║ ██║   ██║ ██╔═██╗  ██╔══██║]],
        [[ ██║ ╚████║ ╚██████╔╝ ██║  ██╗ ██║  ██╗]],
        [[ ╚═╝  ╚═══╝  ╚═════╝  ╚═╝  ╚═╝ ╚═╝  ╚═╝]],
    }
    
    io.write(C.BLUE)
    for _, line in ipairs(logo) do
        io.write("\27[K" .. line .. "\n")
    end
    io.write(C.CYAN .. " [ MONITOR ] " .. C.YELLOW .. "[ REWRITE ] " .. C.GREEN .. "[ STABLE ]" .. C.RESET .. "\n")
    OUT(C.BLUE .. " ────────────────────────────────────────────────────────────" .. C.RESET)
end

local function VISIBLE(s) return s:gsub("\27%[[%d;]*m", "") end
local function PAD(s, w) return s .. string.rep(" ", math.max(0, w - #VISIBLE(s))) end

local COL1, COL2 = 38, 12
local function ROW(left, right)
    OUT(C.BLUE .. "│ " .. C.RESET .. PAD(left, COL1) .. C.BLUE .. " │ " .. C.RESET .. PAD(right, COL2) .. C.BLUE .. " │")
end

local _ram, _ram_time = "0MB", 0
local function GET_RAM()
    local now = os.time()
    if now - _ram_time <= 10 then return _ram end
    local data = SHU("free -m")
    local avail = data:match("Mem:%s+%d+%s+%d+%s+%d+%s+%d+%s+%d+%s+(%d+)") or data:match("Mem:%s+%d+%s+%d+%s+(%d+)")
    _ram = (avail or "0") .. "MB"
    _ram_time = now
    return _ram
end

local function MONITOR_TICK(config, status, sys_msg)
    io.write("\27[H")
    BANNER(true)
    OUT(C.BLUE .. "┌────────────────────────────────────────┬──────────────┐")
    ROW(C.YELLOW .. "NOKA DASHBOARD",        C.YELLOW .. "BETA")
    OUT(C.BLUE .. "├────────────────────────────────────────┼──────────────┤")
    ROW(C.CYAN .. "SYSTEM STATUS   " .. C.RESET .. (sys_msg or "OK"), C.GREEN .. "ONLINE")
    ROW(C.CYAN .. "RAM (FREE)     " .. C.RESET .. GET_RAM(),          "v3.1")
    OUT(C.BLUE .. "├────────────────────────────────────────┼──────────────┤")
    ROW(C.BLUE .. "PACKAGE IDENTITY",       C.BLUE .. "STATUS")
    OUT(C.BLUE .. "├────────────────────────────────────────┼──────────────┤")
    for _, p in ipairs(config.PACKAGES or {}) do
        local st = status[p] or "..."
        local sc = C.YELLOW
        if st == "Online" then sc = C.GREEN elseif st:match("^Off") or st:match("^Stu") then sc = C.RED elseif st:match("^Ini") or st:match("^Lau") then sc = C.CYAN end
        ROW(C.RESET .. (#p > COL1 and p:sub(1, COL1-2)..".." or p), sc .. st .. C.RESET)
    end
    OUT(C.BLUE .. "└────────────────────────────────────────┴──────────────┘")
    io.flush()
end

-- ============================================================
--  SERVER JOIN LOGIC (Public & Private)
-- ============================================================

local function RESOLVE_LINK(url)
    -- 1. If it's already an HTTPS share link, keep it as-is (Roblox handles these best)
    if url:match("^https?://") then
        return url
    end

    -- 2. If it's already a roblox:// deep link
    if url:match("^roblox://") then
        return url
    end

    -- 3. Private Server Access Code (Format: PLACEID:CODE)
    local pid, code = url:match("^(%d+):([%w%-]+)$")
    if pid and code then
        return string.format("roblox://placeId=%s&accessCode=%s", pid, code)
    end

    -- 4. Bare Place ID (e.g., 18526564619)
    local bare_id = url:match("^(%d+)$")
    if bare_id then
        return "roblox://placeId=" .. bare_id
    end

    -- 5. Game Page Extraction (e.g., roblox.com/games/18526564619)
    local game_id = url:match("/games/(%d+)")
    if game_id then
        return "roblox://placeId=" .. game_id
    end

    return "roblox://placeId=" .. url
end

local function DISMISS_POPUPS()
    SH("uiautomator dump " .. TMP_PATH)
    local f = io.open(TMP_PATH, "r")
    if f then
        local xml = f:read("*a"); f:close()
        for _, kw in ipairs({ "Play", "Resume", "Join", "OK", "Continue" }) do
            local bounds = xml:match('text="' .. kw .. '".-bounds="([^"]+)"') or xml:match('content%-desc="[^"]*' .. kw .. '[^"]*".-bounds="([^"]+)"')
            if bounds then
                local x1, y1, x2, y2 = bounds:match("(%d+),(%d+)%D+(%d+),(%d+)")
                if x1 then SH(string.format("input tap %d %d", math.floor((tonumber(x1)+tonumber(x2))/2), math.floor((tonumber(y1)+tonumber(y2))/2))); return end
            end
        end
    end
    for _, pos in ipairs({ "540,1200", "540,1100", "540,960" }) do SH("input tap " .. pos); SLEEP(0.5) end
end

-- ============================================================
--  LAUNCH PIPELINE
-- ============================================================

local function LAUNCH_INSTANCE(p, deep_link, all_pkgs, config, status)
    local idx = 1
    for i, pkg in ipairs(all_pkgs) do if pkg == p then idx = i; break end end
    
    local sw, sh = 1080, 1920
    local s = SHU("wm size"); local ow, oh = s:match("Override size: (%d+)x(%d+)"); local pw, ph = s:match("Physical size: (%d+)x(%d+)")
    sw, sh = tonumber(ow or pw or 1080), tonumber(oh or ph or 1920)
    
    local ls = sw > sh; local cols = 1; if #all_pkgs == 2 then cols = ls and 2 or 1 elseif #all_pkgs > 2 then cols = ls and 3 or 2 end
    local rows = math.ceil(#all_pkgs / cols); local w, h = math.floor(sw/cols), math.floor(sh/rows)
    local x = ((idx-1)%cols)*w; local y = math.floor((idx-1)/cols)*h
    local bounds = string.format("%d,%d,%d,%d", x, y, x+w, y+h)

    SH("am force-stop " .. p); SH("rm -rf /data/data/" .. p .. "/cache/*")
    SH("settings put global enable_freeform_support 1; settings put global force_resizable_activities 1; cmd window set-freeform-windowing-mode 1")

    status[p] = "Launching"
    MONITOR_TICK(config, status, "Applying Layout " .. idx)

    local acts = { "com.roblox.client.ActivityProtocolLaunch", "com.roblox.client.startup.ActivitySplash", "com.roblox.client.ActivityProtocol" }
    local ok = false
    for _, act in ipairs(acts) do
        local cmd = string.format('am start -n %s/%s -a android.intent.action.VIEW -d "%s" --windowingMode 5 --bounds %s', p, act, deep_link, bounds)
        if not SH(cmd):match("[Ee]rror") then ok = true; break end
    end
    if not ok then SH(string.format('am start -a android.intent.action.VIEW -d "%s" -p %s', deep_link, p)) end

    for i = 8, 1, -1 do status[p] = "Init ("..i.."s)"; MONITOR_TICK(config, status, "Initializing Instance"); SLEEP(1) end
    DISMISS_POPUPS()
    status[p] = "Waiting"
end

-- ============================================================
--  EXECUTION
-- ============================================================

local function START_REJOIN()
    local cfg = LOAD_CONFIG()
    if not cfg then OUT(C.RED.."Config not found!"); return end
    local link = RESOLVE_LINK(cfg.URL or "")
    local status = {}
    for i, p in ipairs(cfg.PACKAGES) do
        local t0 = os.time(); LAUNCH_INSTANCE(p, link, cfg.PACKAGES, cfg, status)
        if i < #cfg.PACKAGES then
            local wait = (cfg.DELAY or 30) - (os.time()-t0)
            for s = wait, 1, -1 do if s > 0 then MONITOR_TICK(cfg, status, "Cooldown ("..s.."s)"); SLEEP(1) end end
        end
    end
    while true do
        for i, p in ipairs(cfg.PACKAGES) do
            MONITOR_TICK(cfg, status, "Scanning ["..i.."/"..#cfg.PACKAGES.."]")
            local alive = SHU("ps -A | grep "..p) ~= ""; local ws = string.format("%s/%s/workspace", cfg.BASE_PATH or "", p)
            if alive then
                local hb = string.format("%s/noka_hb_%s.txt", ws, p); local ts = tonumber(SH("stat -c %Y "..hb))
                if ts and (os.time() - ts) < 60 then status[p] = "Online" elseif ts and (os.time()-ts) < 180 then status[p] = "Stuck" else status[p] = "Offline" end
            else status[p] = "Offline" end
            SLEEP(0.2)
        end
        for s = 20, 1, -1 do MONITOR_TICK(cfg, status, "Wait ("..s.."s)"); SLEEP(1) end
        for _, p in ipairs(cfg.PACKAGES) do if status[p] == "Stuck" or status[p] == "Offline" then LAUNCH_INSTANCE(p, link, cfg.PACKAGES, cfg, status) end end
    end
end

local function SETUP()
    BANNER()
    OUT(C.YELLOW.."[ Noka Configuration ]"..C.RESET)
    OUT(" 1) automatic")
    OUT(" 2) manual")
    OUT(C.BLUE .. " ────────────────────────────────────────────────────────────" .. C.RESET)
    local mode = PROMPT(C.CYAN.." Select: "..C.RESET)
    
    local found = {}
    if mode == "1" then
        local list = SH("pm list packages | grep roblox")
        for p in list:gmatch("package:([%w%.%-]+)") do found[#found+1] = p end
    else
        local raw = PROMPT(C.YELLOW.." Packages: "..C.RESET)
        for p in raw:gmatch("([^,]+)") do found[#found+1] = p:gsub("%s+", "") end
    end
    if #found == 0 then OUT(C.RED.."No packages!"); return end
    OUT("\nDetected:")
    for i, p in ipairs(found) do OUT(string.format(" %d) %s", i, p)) end
    local url = PROMPT(C.CYAN.."\n URL / ID / Private (PID:CODE): "..C.RESET)
    local delay = tonumber(PROMPT(C.CYAN.." Delay (30): "..C.RESET)) or 30
    local base_path = PROMPT(C.CYAN.." Executor Path: "..C.RESET)
    for _, pkg in ipairs(found) do
        local exec = base_path.."/"..pkg.."/autoexecute"; SH("mkdir -p "..exec)
        local raw = string.format('_G.NOKA_PKG="%s";loadstring(game:HttpGet("https://raw.githubusercontent.com/lofaif1234/noka/refs/heads/main/noka-script.lua"))()', pkg)
        SH(string.format("echo '%s' | base64 -d > %s/noka.txt", SHU("echo -n '"..raw.."' | base64"), exec))
    end
    SAVE_CONFIG({ PACKAGES=found, URL=url, DELAY=delay, BASE_PATH=base_path })
    OUT(C.GREEN.."Setup Complete!"); SLEEP(2)
end

local function MAIN()
    while true do
        BANNER()
        OUT(" 1) Setup & deploy")
        OUT(" 2) Run Auto-rejoin")
        OUT(" 9) Exit")
        OUT(C.BLUE .. " ────────────────────────────────────────────────────────────" .. C.RESET)
        local c = PROMPT(C.CYAN .. " Select: " .. C.RESET)
        if c == "1" then SETUP() elseif c == "2" then START_REJOIN() elseif c == "9" then break end
    end
end
MAIN()
