#!/data/data/com.termux/files/usr/bin/lua

--[[
NOKA.lua - Roblox Auto-Rejoin Manager for Termux
Version: 1.1.0 (Improved Public & Private Server Join Logic)
--]]

-- Configuration
local CONFIG_PATH = os.getenv("HOME") .. "/NOKA/config.json"
local HEARTBEAT_DIR = os.getenv("HOME") .. "/NOKA/heartbeats/"
local LOG_FILE = os.getenv("HOME") .. "/NOKA/noka.log"

-- ANSI Color Codes
local colors = {
    reset = "\27[0m",
    bold = "\27[1m",
    cyan = "\27[36m",
    green = "\27[32m",
    yellow = "\27[33m",
    red = "\27[31m",
    magenta = "\27[35m",
    white = "\27[37m",
    gray = "\27[90m",
    clear = "\27[2J\27[H",
    save_cursor = "\27[s",
    restore_cursor = "\27[u",
    erase_line = "\27[2K"
}

-- Global state
local config = nil
local running = false

-- Simple JSON encoder/decoder
local json = {}

function json.encode_table(t, indent)
    indent = indent or ""
    local result = {}
    local is_array = true
    local i = 1
   
    for k, v in pairs(t) do
        if type(k) ~= "number" or k ~= i then
            is_array = false
            break
        end
        i = i + 1
    end
   
    if is_array then
        result[#result+1] = "["
        for k, v in ipairs(t) do
            if k > 1 then result[#result+1] = "," end
            result[#result+1] = json.encode_value(v, indent .. " ")
        end
        result[#result+1] = "]"
    else
        result[#result+1] = "{"
        local first = true
        for k, v in pairs(t) do
            if not first then result[#result+1] = "," end
            result[#result+1] = string.format('%s "%s": %s', indent, k, json.encode_value(v, indent .. " "))
            first = false
        end
        result[#result+1] = indent .. "}"
    end
   
    return table.concat(result)
end

function json.encode_value(value, indent)
    local t = type(value)
    if t == "string" then
        return string.format('"%s"', value:gsub('"', '\\"'):gsub("\n", "\\n"))
    elseif t == "number" then
        return tostring(value)
    elseif t == "boolean" then
        return value and "true" or "false"
    elseif t == "table" then
        return json.encode_table(value, indent)
    else
        return "null"
    end
end

function json.encode(data)
    return json.encode_value(data, "")
end

function json.decode(str)
    if not str or str == "" then
        return nil
    end
   
    str = str:gsub("[\n\r\t]", " ")
   
    local function parse_value(pos)
        pos = pos or 1
        local ch = str:sub(pos, pos)
       
        while ch and ch:match("%s") do
            pos = pos + 1
            ch = str:sub(pos, pos)
        end
       
        if ch == '"' then
            local start = pos + 1
            local end_pos = start
            while end_pos <= #str do
                if str:sub(end_pos, end_pos) == '"' and str:sub(end_pos-1, end_pos-1) ~= '\\' then
                    break
                end
                end_pos = end_pos + 1
            end
            local value = str:sub(start, end_pos - 1)
            return value, end_pos + 1
        elseif ch == '{' then
            local obj = {}
            pos = pos + 1
            while true do
                local next_ch = str:sub(pos, pos)
                while next_ch and next_ch:match("%s") do
                    pos = pos + 1
                    next_ch = str:sub(pos, pos)
                end
               
                if next_ch == '}' then
                    pos = pos + 1
                    break
                end
               
                local key, new_pos = parse_value(pos)
                pos = new_pos
               
                while str:sub(pos, pos):match("%s") do pos = pos + 1 end
                if str:sub(pos, pos) == ':' then pos = pos + 1 end
               
                local val, new_pos = parse_value(pos)
                pos = new_pos
                obj[key] = val
               
                while str:sub(pos, pos):match("%s") do pos = pos + 1 end
                if str:sub(pos, pos) == ',' then
                    pos = pos + 1
                elseif str:sub(pos, pos) == '}' then
                    pos = pos + 1
                    break
                end
            end
            return obj, pos
        elseif ch == '[' then
            local arr = {}
            pos = pos + 1
            local index = 1
            while true do
                local next_ch = str:sub(pos, pos)
                while next_ch and next_ch:match("%s") do
                    pos = pos + 1
                    next_ch = str:sub(pos, pos)
                end
               
                if next_ch == ']' then
                    pos = pos + 1
                    break
                end
               
                local val, new_pos = parse_value(pos)
                pos = new_pos
                arr[index] = val
                index = index + 1
               
                while str:sub(pos, pos):match("%s") do pos = pos + 1 end
                if str:sub(pos, pos) == ',' then
                    pos = pos + 1
                elseif str:sub(pos, pos) == ']' then
                    pos = pos + 1
                    break
                end
            end
            return arr, pos
        elseif ch:match("%d") or ch == '-' then
            local start = pos
            while pos <= #str and (str:sub(pos, pos):match("[%d%.%-]")) do
                pos = pos + 1
            end
            local num_str = str:sub(start, pos - 1)
            local num = tonumber(num_str)
            return num, pos
        elseif ch == 't' and str:sub(pos, pos+3) == "true" then
            return true, pos + 4
        elseif ch == 'f' and str:sub(pos, pos+4) == "false" then
            return false, pos + 5
        elseif ch == 'n' and str:sub(pos, pos+3) == "null" then
            return nil, pos + 4
        else
            return nil, pos
        end
    end
   
    local result, _ = parse_value(1)
    return result
end

-- Utility Functions
local function log(message, level)
    level = level or "INFO"
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local log_line = string.format("[%s] [%s] %s\n", timestamp, level, message)
    local file = io.open(LOG_FILE, "a")
    if file then
        file:write(log_line)
        file:close()
    end
end

local function ensure_directories()
    local home = os.getenv("HOME")
    os.execute("mkdir -p " .. home .. "/NOKA 2>/dev/null")
    os.execute("mkdir -p " .. HEARTBEAT_DIR .. " 2>/dev/null")
    os.execute("chmod 755 " .. home .. "/NOKA 2>/dev/null")
end

-- ====================== NEW SERVER JOIN LOGIC ======================
local function RESOLVE_LINK(url)
    if url:match("^https?://") then
        return url
    end
    if url:match("^roblox://") then
        return url
    end
    -- Private Server: PLACEID:CODE
    local pid, code = url:match("^(%d+):([%w%-]+)$")
    if pid and code then
        return string.format("roblox://placeId=%s&accessCode=%s", pid, code)
    end
    -- Bare Place ID
    local bare_id = url:match("^(%d+)$")
    if bare_id then
        return "roblox://placeId=" .. bare_id
    end
    -- Extract from /games/ link
    local game_id = url:match("/games/(%d+)")
    if game_id then
        return "roblox://placeId=" .. game_id
    end
    return "roblox://placeId=" .. url
end

local function JOIN_SERVER(package, raw_input)
    local deep_link = RESOLVE_LINK(raw_input)
   
    local activity = "com.roblox.client.ActivityProtocolLaunch"
   
    local cmd = string.format('am start -n %s/%s -a android.intent.action.VIEW -d "%s"', 
                              package, activity, deep_link)
   
    log("Joining server with command: " .. cmd, "DEBUG")
    -- Execute under root
    local success = os.execute("su -c '" .. cmd .. "' 2>/dev/null")
    return success == 0 or success == true
end

-- Updated launch function (now uses new logic)
local function launch_package(package_name, game_url)
    return JOIN_SERVER(package_name, game_url)
end

local function load_config()
    ensure_directories()
   
    local file = io.open(CONFIG_PATH, "r")
    if not file then
        log("No config file found", "INFO")
        return nil
    end
   
    local content = file:read("*all")
    file:close()
   
    if not content or content == "" then
        log("Config file is empty", "INFO")
        return nil
    end
   
    log("Loading config: " .. content:sub(1, 100), "DEBUG")
   
    local success, result = pcall(function()
        return json.decode(content)
    end)
   
    if not success then
        log("Failed to parse config.json: " .. tostring(result), "ERROR")
        return nil
    end
   
    if not result then
        log("Config decoded to nil", "ERROR")
        return nil
    end
   
    if not result.packages or not result.game_url then
        log("Config missing required fields", "ERROR")
        return nil
    end
   
    log("Config loaded successfully with " .. #result.packages .. " packages", "INFO")
    return result
end

local function save_config(cfg)
    ensure_directories()
   
    if not cfg then
        log("Attempted to save nil config", "ERROR")
        return false
    end
   
    local file = io.open(CONFIG_PATH, "w")
    if not file then
        log("Failed to open config.json for writing", "ERROR")
        return false
    end
   
    local success, json_str = pcall(function()
        return json.encode(cfg)
    end)
   
    if not success then
        log("Failed to encode config to JSON: " .. tostring(json_str), "ERROR")
        file:close()
        return false
    end
   
    file:write(json_str)
    file:close()
    os.execute("chmod 644 " .. CONFIG_PATH .. " 2>/dev/null")
   
    log("Configuration saved successfully", "INFO")
    return true
end

local function clear_screen()
    io.write(colors.clear)
    io.flush()
end

local function print_banner()
    io.write(colors.cyan .. colors.bold .. [[
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║    ███╗   ██╗ ██████╗ ██╗  ██╗ █████╗                     ║
║    ████╗  ██║██╔═══██╗██║ ██╔╝██╔══██╗                    ║
║    ██╔██╗ ██║██║   ██║█████╔╝ ███████║                    ║
║    ██║╚██╗██║██║   ██║██╔═██╗ ██╔══██║                    ║
║    ██║ ╚████║╚██████╔╝██║  ██╗██║  ██║                    ║
║    ╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝                    ║
║                                                           ║
║           ROBLOX AUTO-REJOIN MANAGER v1.1.0               ║
╚═══════════════════════════════════════════════════════════╝
]] .. colors.reset)
end

local function print_menu()
    io.write(colors.yellow .. "\n═══════════════════════════════════════════════════════════\n" .. colors.reset)
    io.write(colors.green .. "  MAIN MENU\n" .. colors.reset)
    io.write(colors.yellow .. "═══════════════════════════════════════════════════════════\n" .. colors.reset)
    io.write(colors.white .. "  1) " .. colors.cyan .. "First time configuration\n")
    io.write(colors.white .. "  2) " .. colors.green .. "Start auto-rejoin\n")
    io.write(colors.white .. "  3) " .. colors.magenta .. "Webhook configuration\n")
    io.write(colors.white .. "  4) " .. colors.yellow .. "Update URL\n")
    io.write(colors.white .. "  5) " .. colors.cyan .. "Export/Import config\n")
    io.write(colors.white .. "  6) " .. colors.red .. "Exit\n")
    io.write(colors.yellow .. "═══════════════════════════════════════════════════════════\n" .. colors.reset)
    io.write(colors.white .. "  Choose option: " .. colors.reset)
end

local function get_input(prompt)
    io.write(colors.cyan .. prompt .. colors.reset)
    io.flush()
    local input = io.read()
    if input then
        input = input:gsub("^%s+", ""):gsub("%s+$", "")
    end
    return input
end

local function find_roblox_packages()
    io.write(colors.yellow .. "\nScanning for Roblox packages...\n" .. colors.reset)
   
    local all_packages = {}
    local handle = io.popen("pm list packages 2>/dev/null")
    if not handle then
        io.write(colors.red .. "Failed to run pm command.\n" .. colors.reset)
        return nil
    end
   
    local all_output = handle:read("*a")
    handle:close()
   
    for line in all_output:gmatch("[^\r\n]+") do
        local pkg = line:match("^package:(.+)$")
        if pkg and (pkg:lower():match("roblox") or pkg:lower():match("rblx")) then
            table.insert(all_packages, pkg)
        end
    end
   
    if #all_packages > 0 then
        io.write(colors.green .. "\nFound " .. #all_packages .. " Roblox package(s):\n" .. colors.reset)
        for i, pkg in ipairs(all_packages) do
            io.write(string.format("  %d) %s%s%s\n", i, colors.cyan, pkg, colors.reset))
        end
        return all_packages
    else
        io.write(colors.red .. "\nNo Roblox packages found!\n" .. colors.reset)
        return nil
    end
end

local function verify_package_exists(package_name)
    if not package_name or package_name == "" then
        return false
    end
   
    package_name = package_name:gsub("^%s+", ""):gsub("%s+$", "")
   
    local check = io.popen("pm list packages | grep -q '" .. package_name .. "' && echo 'found'")
    local result = check:read("*a")
    check:close()
   
    if result and result:match("found") then
        return true
    end
   
    return false
end

local function select_packages(packages_list)
    io.write(colors.yellow .. "\nPackage selection:\n" .. colors.reset)
    io.write("  1) " .. colors.green .. "All packages\n" .. colors.reset)
    io.write("  2) " .. colors.cyan .. "Manual selection\n" .. colors.reset)
    io.write(colors.white .. "  Choose: " .. colors.reset)
   
    local choice = io.read()
    choice = choice and choice:gsub("^%s+", ""):gsub("%s+$", "") or ""
   
    if choice == "1" then
        return packages_list
    elseif choice == "2" then
        io.write(colors.yellow .. "Enter package numbers (comma-separated): " .. colors.reset)
        local selection = io.read()
        selection = selection and selection:gsub("^%s+", ""):gsub("%s+$", "") or ""
        local selected = {}
        for num in selection:gmatch("%d+") do
            local index = tonumber(num)
            if index and index >= 1 and index <= #packages_list then
                table.insert(selected, packages_list[index])
            end
        end
        if #selected == 0 then
            return packages_list
        end
        return selected
    else
        return packages_list
    end
end

local function configure_webhook()
    io.write(colors.yellow .. "\nEnable Discord webhook? (1=Yes, 2=No): " .. colors.reset)
    local enable = io.read()
    enable = enable and enable:gsub("^%s+", ""):gsub("%s+$", "") or ""
   
    if enable == "1" then
        local url = get_input("Enter Discord webhook URL: ")
        io.write(colors.cyan .. "Enter message interval (seconds, min 30): " .. colors.reset)
        local interval = tonumber(io.read()) or 60
        if interval < 30 then interval = 30 end
       
        return {
            enabled = true,
            url = url,
            interval = interval,
            last_sent = 0
        }
    end
   
    return { enabled = false }
end

local function first_time_config()
    clear_screen()
    print_banner()
    io.write(colors.green .. "\n=== FIRST TIME CONFIGURATION ===\n" .. colors.reset)
   
    io.write(colors.yellow .. "\nMethod for fetching Roblox packages:\n" .. colors.reset)
    io.write("  1) " .. colors.green .. "Automatic\n")
    io.write("  2) " .. colors.cyan .. "Manual\n")
    io.write(colors.white .. "  Choose: " .. colors.reset)
    local method = io.read()
    method = method and method:gsub("^%s+", ""):gsub("%s+$", "") or ""
   
    local packages_list = nil
   
    if method == "1" then
        packages_list = find_roblox_packages()
        if not packages_list or #packages_list == 0 then
            io.write(colors.red .. "\nAutomatic detection failed.\n" .. colors.reset)
            io.write(colors.yellow .. "Switch to manual mode? (y/n): " .. colors.reset)
            local switch = io.read()
            switch = switch and switch:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
            if switch == "y" then
                method = "2"
            else
                io.write(colors.white .. "Press Enter to continue..." .. colors.reset)
                io.read()
                return false
            end
        end
    end
   
    if method == "2" then
        packages_list = {}
        io.write(colors.cyan .. "\nEnter Roblox package name(s):\n" .. colors.reset)
        io.write(colors.gray .. "Example: com.roblox.client\n" .. colors.reset)
       
        while true do
            io.write(colors.white .. "Package " .. (#packages_list + 1) .. ": " .. colors.reset)
            local pkg_name = io.read()
            if pkg_name then
                pkg_name = pkg_name:gsub("^%s+", ""):gsub("%s+$", "")
            end
           
            if not pkg_name or pkg_name == "" then
                if #packages_list == 0 then
                    io.write(colors.red .. "At least one package required!\n" .. colors.reset)
                else
                    break
                end
            else
                if verify_package_exists(pkg_name) then
                    table.insert(packages_list, pkg_name)
                    io.write(colors.green .. "✓ Package added\n" .. colors.reset)
                else
                    io.write(colors.red .. "✗ Package not found\n" .. colors.reset)
                    io.write(colors.yellow .. "Add anyway? (y/n): " .. colors.reset)
                    local force = io.read()
                    force = force and force:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
                    if force == "y" then
                        table.insert(packages_list, pkg_name)
                        io.write(colors.yellow .. "✓ Added unverified\n" .. colors.reset)
                    end
                end
            end
           
            io.write(colors.white .. "Add another? (y/n): " .. colors.reset)
            local add_more = io.read()
            add_more = add_more and add_more:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
            if add_more ~= "y" then
                break
            end
        end
    end
   
    if not packages_list or #packages_list == 0 then
        io.write(colors.red .. "\nNo packages selected!\n" .. colors.reset)
        io.write(colors.white .. "Press Enter to continue..." .. colors.reset)
        io.read()
        return false
    end
   
    local selected_packages = packages_list
    if #packages_list > 1 then
        selected_packages = select_packages(packages_list)
    end
   
    local game_url = get_input("\nEnter Roblox game URL: ")
   
    if not game_url or game_url == "" then
        io.write(colors.red .. "URL required!\n" .. colors.reset)
        io.write(colors.white .. "Press Enter to continue..." .. colors.reset)
        io.read()
        return false
    end
   
    local webhook = configure_webhook()
   
    io.write(colors.yellow .. "\nStart interval between packages:\n" .. colors.reset)
    io.write("  1) " .. colors.green .. "Custom\n")
    io.write("  2) " .. colors.cyan .. "Default (120 seconds)\n")
    io.write(colors.white .. "  Choose: " .. colors.reset)
    local interval_choice = io.read()
    interval_choice = interval_choice and interval_choice:gsub("^%s+", ""):gsub("%s+$", "") or ""
   
    local start_interval = 120
    if interval_choice == "1" then
        io.write(colors.cyan .. "Enter interval (seconds): " .. colors.reset)
        start_interval = tonumber(io.read()) or 120
        if start_interval < 1 then start_interval = 1 end
    end
   
    io.write(colors.yellow .. "\nEnable auto-restart? (1=Yes, 2=No): " .. colors.reset)
    local restart_enabled = io.read()
    restart_enabled = restart_enabled and restart_enabled:gsub("^%s+", ""):gsub("%s+$", "") or ""
   
    local restart_config = { enabled = false }
    if restart_enabled == "1" then
        io.write(colors.cyan .. "Restart interval (minutes): " .. colors.reset)
        local interval_min = tonumber(io.read()) or 60
       
        io.write(colors.yellow .. "Restart type:\n" .. colors.reset)
        io.write("  1) " .. colors.green .. "Game restart\n")
        io.write("  2) " .. colors.cyan .. "Server rejoin\n")
        io.write(colors.white .. "  Choose: " .. colors.reset)
        local type_choice = io.read()
        type_choice = type_choice and type_choice:gsub("^%s+", ""):gsub("%s+$", "") or ""
       
        restart_config = {
            enabled = true,
            interval = interval_min * 60,
            type = type_choice == "1" and "game" or "rejoin"
        }
    end
   
    config = {
        packages = selected_packages,
        game_url = game_url,
        webhook = webhook,
        start_interval = start_interval,
        restart = restart_config,
        version = "1.1"
    }
   
    io.write(colors.yellow .. "\nSaving configuration...\n" .. colors.reset)
   
    if save_config(config) then
        clear_screen()
        print_banner()
        io.write(colors.green .. "\n✅ Configuration completed!\n" .. colors.reset)
        io.write(colors.cyan .. "\nSaved packages:\n" .. colors.reset)
        for i, pkg in ipairs(selected_packages) do
            io.write(string.format("  %d) %s%s%s\n", i, colors.yellow, pkg, colors.reset))
        end
        io.write(colors.green .. "\nGame URL: " .. colors.cyan .. game_url .. colors.reset .. "\n")
        io.write(colors.white .. "\nPress Enter to return..." .. colors.reset)
        io.read()
        return true
    else
        io.write(colors.red .. "\n❌ Failed to save configuration!\n" .. colors.reset)
        io.write(colors.white .. "Press Enter to continue..." .. colors.reset)
        io.read()
        return false
    end
end

local function check_package_status(package_name)
    local check = io.popen("pidof " .. package_name .. " 2>/dev/null")
    local pid = check:read("*a"):gsub("%s+", "")
    check:close()
   
    if pid == "" then
        return "crashed"
    end
   
    local heartbeat_file = HEARTBEAT_DIR .. package_name:gsub("%.", "_") .. ".heartbeat"
    local file = io.open(heartbeat_file, "r")
    if file then
        local timestamp = tonumber(file:read("*a"))
        file:close()
        if timestamp and (os.time() - timestamp) < 30 then
            return "ingame"
        end
    end
   
    return "running"
end

local function send_webhook(status_data)
    if not config or not config.webhook or not config.webhook.enabled then
        return
    end
   
    local screenshot_path = os.getenv("HOME") .. "/NOKA/screenshot.png"
    os.execute("screencap -p " .. screenshot_path .. " 2>/dev/null")
   
    log("Webhook would be sent to: " .. config.webhook.url, "INFO")
   
    config.webhook.last_sent = os.time()
    save_config(config)
end

local function update_dashboard_line(line_num, content)
    io.write(colors.save_cursor)
    io.write(string.format("\27[%d;1H", line_num))
    io.write(colors.erase_line)
    io.write(content)
    io.write(colors.restore_cursor)
    io.flush()
end

local function start_auto_rejoin()
    config = load_config()
   
    if not config then
        clear_screen()
        print_banner()
        io.write(colors.red .. "\n❌ No configuration found!\n" .. colors.reset)
        io.write(colors.yellow .. "Please run option 1 (First time configuration) first.\n" .. colors.reset)
        io.write(colors.white .. "\nPress Enter to return..." .. colors.reset)
        io.read()
        return
    end
   
    if not config.packages or #config.packages == 0 then
        clear_screen()
        print_banner()
        io.write(colors.red .. "\n❌ No packages configured!\n" .. colors.reset)
        io.write(colors.yellow .. "Please run option 1 first.\n" .. colors.reset)
        io.write(colors.white .. "\nPress Enter to return..." .. colors.reset)
        io.read()
        return
    end
   
    if not config.game_url or config.game_url == "" then
        clear_screen()
        print_banner()
        io.write(colors.red .. "\n❌ No game URL configured!\n" .. colors.reset)
        io.write(colors.yellow .. "Please run option 1 or 4 to update URL.\n" .. colors.reset)
        io.write(colors.white .. "\nPress Enter to return..." .. colors.reset)
        io.read()
        return
    end
   
    clear_screen()
    print_banner()
    io.write(colors.green .. "\n=== AUTO-REJOIN ACTIVE (New Join Logic) ===\n" .. colors.reset)
    io.write(colors.cyan .. "Game URL: " .. config.game_url .. "\n" .. colors.reset)
    io.write(colors.yellow .. "Press Ctrl+C to stop\n\n" .. colors.reset)
   
    local package_states = {}
   
    for i, pkg in ipairs(config.packages) do
        package_states[pkg] = {
            status = "pending",
            uptime = 0,
            last_action = 0,
            launch_time = 0,
            line_num = 10 + i
        }
        io.write(string.format("  %s%s%s - %sPending%s\n", colors.cyan, pkg, colors.reset, colors.yellow, colors.reset))
    end
    io.write("\n")
   
    local function launch_next_package(index)
        if index > #config.packages then
            return
        end
       
        local pkg = config.packages[index]
        update_dashboard_line(package_states[pkg].line_num,
            string.format("  %s%-30s%s %sLaunching...%s", colors.cyan, pkg, colors.reset, colors.yellow, colors.reset))
       
        if launch_package(pkg, config.game_url) then
            package_states[pkg].status = "launching"
            package_states[pkg].last_action = os.time()
            package_states[pkg].launch_time = os.time()
           
            if index < #config.packages then
                os.execute("sleep " .. (config.start_interval or 120))
                launch_next_package(index + 1)
            end
        else
            package_states[pkg].status = "failed"
            update_dashboard_line(package_states[pkg].line_num,
                string.format("  %s%-30s%s %sFailed%s", colors.cyan, pkg, colors.reset, colors.red, colors.reset))
        end
    end
   
    launch_next_package(1)
   
    running = true
    local last_webhook = 0
    local last_heartbeat_check = 0
   
    while running do
        local current_time = os.time()
       
        for pkg, state in pairs(package_states) do
            if state.status == "ingame" then
                state.uptime = current_time - state.launch_time
            end
           
            local status_color = colors.green
            local status_text_display = "INGAME"
            if state.status == "crashed" then
                status_color = colors.red
                status_text_display = "CRASHED"
            elseif state.status == "launching" then
                status_color = colors.yellow
                status_text_display = "LAUNCHING"
            elseif state.status == "restarting" then
                status_color = colors.magenta
                status_text_display = "RESTARTING"
            elseif state.status == "pending" then
                status_color = colors.gray
                status_text_display = "PENDING"
            elseif state.status == "failed" then
                status_color = colors.red
                status_text_display = "FAILED"
            end
           
            local status_text = string.format(
                "  %s%-30s%s  %s%-10s%s  %s%-8s%s",
                colors.cyan, pkg:sub(1, 30), colors.reset,
                status_color, status_text_display, colors.reset,
                colors.white, state.uptime .. "s", colors.reset
            )
           
            update_dashboard_line(state.line_num, status_text)
        end
       
        if current_time - last_heartbeat_check >= 5 then
            for pkg, state in pairs(package_states) do
                if state.status ~= "failed" and state.status ~= "pending" then
                    local status = check_package_status(pkg)
                   
                    if status == "crashed" and state.status ~= "crashed" and state.status ~= "restarting" then
                        state.status = "crashed"
                        log(pkg .. " has crashed", "WARN")
                       
                        if config.restart and config.restart.enabled then
                            state.status = "restarting"
                            update_dashboard_line(state.line_num,
                                string.format("  %s%-30s%s %sRESTARTING...%s", colors.cyan, pkg, colors.reset, colors.magenta, colors.reset))
                           
                            if config.restart.type == "game" then
                                os.execute("am force-stop " .. pkg .. " 2>/dev/null")
                                os.execute("sleep 3")
                            end
                           
                            if launch_package(pkg, config.game_url) then
                                state.launch_time = os.time()
                                state.status = "launching"
                                log(pkg .. " restarted successfully", "INFO")
                            else
                                state.status = "crashed"
                                log(pkg .. " failed to restart", "ERROR")
                            end
                            state.last_action = os.time()
                        end
                    elseif status == "ingame" then
                        if state.status ~= "ingame" then
                            state.status = "ingame"
                            state.launch_time = current_time
                            log(pkg .. " is now in-game", "INFO")
                        end
                    end
                end
            end
            last_heartbeat_check = current_time
        end
       
        if config.webhook and config.webhook.enabled and current_time - last_webhook >= config.webhook.interval then
            local status_data = {}
            for pkg, state in pairs(package_states) do
                table.insert(status_data, {
                    package = pkg,
                    status = state.status,
                    uptime = state.uptime
                })
            end
            send_webhook(status_data)
            last_webhook = current_time
        end
       
        if config.restart and config.restart.enabled then
            for pkg, state in pairs(package_states) do
                if state.status == "ingame" and (current_time - state.launch_time) >= config.restart.interval then
                    state.status = "restarting"
                    update_dashboard_line(state.line_num,
                        string.format("  %s%-30s%s %sRESTARTING (interval)%s", colors.cyan, pkg, colors.reset, colors.magenta, colors.reset))
                   
                    if config.restart.type == "game" then
                        os.execute("am force-stop " .. pkg .. " 2>/dev/null")
                        os.execute("sleep 3")
                    end
                   
                    if launch_package(pkg, config.game_url) then
                        state.launch_time = os.time()
                        state.status = "ingame"
                        log(pkg .. " restarted due to interval", "INFO")
                    end
                    state.last_action = os.time()
                end
            end
        end
       
        os.execute("sleep 1")
    end
end

local function webhook_config()
    clear_screen()
    print_banner()
    io.write(colors.green .. "\n=== WEBHOOK CONFIGURATION ===\n" .. colors.reset)
   
    config = load_config()
   
    if config and config.webhook then
        io.write(colors.cyan .. "Current status: " .. (config.webhook.enabled and "Enabled" or "Disabled") .. "\n" .. colors.reset)
        if config.webhook.enabled then
            io.write("  URL: " .. config.webhook.url .. "\n")
            io.write("  Interval: " .. config.webhook.interval .. " seconds\n")
        end
        io.write("\n")
    end
   
    local new_webhook = configure_webhook()
    if config then
        config.webhook = new_webhook
        if save_config(config) then
            io.write(colors.green .. "\n✅ Updated!\n" .. colors.reset)
        else
            io.write(colors.red .. "\n❌ Failed to save!\n" .. colors.reset)
        end
    else
        io.write(colors.red .. "\n❌ No config loaded!\n" .. colors.reset)
    end
   
    io.write(colors.white .. "\nPress Enter to return..." .. colors.reset)
    io.read()
end

local function update_url()
    clear_screen()
    print_banner()
    io.write(colors.green .. "\n=== UPDATE GAME URL ===\n" .. colors.reset)
   
    if not config then
        io.write(colors.red .. "\n❌ No config loaded!\n" .. colors.reset)
        io.write(colors.white .. "Press Enter to return..." .. colors.reset)
        io.read()
        return
    end
   
    io.write(colors.cyan .. "Current URL: " .. config.game_url .. "\n" .. colors.reset)
    local new_url = get_input("Enter new URL: ")
   
    if new_url and new_url ~= "" then
        config.game_url = new_url
        if save_config(config) then
            io.write(colors.green .. "\n✅ URL updated!\n" .. colors.reset)
        else
            io.write(colors.red .. "\n❌ Failed to save!\n" .. colors.reset)
        end
    end
   
    io.write(colors.white .. "\nPress Enter to return..." .. colors.reset)
    io.read()
end

local function export_import_config()
    clear_screen()
    print_banner()
    io.write(colors.green .. "\n=== EXPORT/IMPORT CONFIGURATION ===\n" .. colors.reset)
    io.write("  1) " .. colors.cyan .. "Export config\n")
    io.write("  2) " .. colors.magenta .. "Import config\n")
    io.write(colors.white .. "  Choose: " .. colors.reset)
   
    local choice = io.read()
    choice = choice and choice:gsub("^%s+", ""):gsub("%s+$", "") or ""
   
    if choice == "1" then
        local export_path = get_input("Export path: ")
        if export_path == "" then
            export_path = os.getenv("HOME") .. "/NOKA/config_export.json"
        end
       
        os.execute("cp " .. CONFIG_PATH .. " " .. export_path .. " 2>/dev/null")
        io.write(colors.green .. "\n✅ Exported to: " .. export_path .. "\n" .. colors.reset)
       
    elseif choice == "2" then
        local import_path = get_input("Import path: ")
       
        local file = io.open(import_path, "r")
        if file then
            file:close()
            os.execute("cp " .. import_path .. " " .. CONFIG_PATH .. " 2>/dev/null")
            config = load_config()
            io.write(colors.green .. "\n✅ Imported successfully!\n" .. colors.reset)
        else
            io.write(colors.red .. "\n❌ File not found!\n" .. colors.reset)
        end
    end
   
    io.write(colors.white .. "\nPress Enter to return..." .. colors.reset)
    io.read()
end

local function exit_tool()
    clear_screen()
    io.write(colors.green .. "\nThank you for using NOKA!\n" .. colors.reset)
    io.write(colors.cyan .. "Goodbye!\n\n" .. colors.reset)
    running = false
    os.exit(0)
end

-- Main program
local function main()
    ensure_directories()
    config = load_config()
   
    while true do
        clear_screen()
        print_banner()
        print_menu()
       
        local choice = io.read()
        if choice then
            choice = choice:gsub("^%s+", ""):gsub("%s+$", "")
        else
            choice = ""
        end
       
        if choice == "1" then
            first_time_config()
            config = load_config()
        elseif choice == "2" then
            start_auto_rejoin()
        elseif choice == "3" then
            webhook_config()
        elseif choice == "4" then
            update_url()
        elseif choice == "5" then
            export_import_config()
        elseif choice == "6" then
            exit_tool()
        else
            io.write(colors.red .. "\nInvalid option: '" .. choice .. "'\n" .. colors.reset)
            io.write(colors.white .. "Press Enter to continue..." .. colors.reset)
            io.read()
        end
    end
end

-- Start the program
main()
