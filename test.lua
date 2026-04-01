#!/data/data/com.termux/files/usr/bin/lua

--[[
NOKA.lua - Roblox Auto-Rejoin Manager for Termux
Author: Expert Lua Developer
Version: 1.0.0
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

-- Simple JSON encoder/decoder (built-in, no dependencies)
local json = {}

function json.encode_table(t, indent)
    indent = indent or ""
    local result = {}
    local is_array = true
    local i = 1
    
    -- Check if it's an array
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
            result[#result+1] = json.encode_value(v, indent .. "  ")
        end
        result[#result+1] = "]"
    else
        result[#result+1] = "{"
        local first = true
        for k, v in pairs(t) do
            if not first then result[#result+1] = "," end
            result[#result+1] = string.format('%s  "%s": %s', indent, k, json.encode_value(v, indent .. "  "))
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
    local function parse_string()
        local start = string.find(str, '"', pos + 1)
        if not start then error("Invalid JSON: unterminated string") end
        local s = string.sub(str, pos + 1, start - 1)
        pos = start
        return s
    end
    
    -- Simple decoder for basic JSON
    local result, _ = load("return " .. str:gsub('"', '"'):gsub("'", '"'))
    if result then
        local success, val = pcall(result)
        if success then
            return val
        end
    end
    return nil
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
    -- Create directories with proper permissions
    os.execute("mkdir -p " .. home .. "/NOKA 2>/dev/null")
    os.execute("mkdir -p " .. HEARTBEAT_DIR .. " 2>/dev/null")
    os.execute("chmod 755 " .. home .. "/NOKA 2>/dev/null")
    os.execute("chmod 755 " .. HEARTBEAT_DIR .. " 2>/dev/null")
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
        return nil
    end
    
    local success, result = pcall(function()
        return json.decode(content)
    end)
    
    if not success or not result then
        log("Failed to parse config.json: " .. tostring(result), "ERROR")
        return nil
    end
    
    return result
end

local function save_config(cfg)
    ensure_directories()
    
    -- Backup existing config if it exists
    if os.rename(CONFIG_PATH, CONFIG_PATH .. ".backup") then
        log("Created backup of existing config", "INFO")
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
    
    -- Set proper permissions
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
║           ROOBLOX AUTO-REJOIN MANAGER v1.0               ║
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

local function find_roblox_packages()
    io.write(colors.yellow .. "\nScanning for Roblox packages...\n" .. colors.reset)
    
    local all_packages = {}
    local handle = io.popen("pm list packages 2>/dev/null")
    if not handle then
        io.write(colors.red .. "Failed to run pm command. Make sure you have proper permissions.\n" .. colors.reset)
        return nil
    end
    
    local all_output = handle:read("*a")
    handle:close()
    
    -- Search for any Roblox-related packages
    for line in all_output:gmatch("[^\r\n]+") do
        local pkg = line:match("^package:(.+)$")
        if pkg and (pkg:lower():match("roblox") or pkg:lower():match("rblx")) then
            table.insert(all_packages, pkg)
        end
    end
    
    -- Display found packages
    if #all_packages > 0 then
        io.write(colors.green .. "\nFound " .. #all_packages .. " Roblox package(s):\n" .. colors.reset)
        for i, pkg in ipairs(all_packages) do
            io.write(string.format("  %d) %s%s%s\n", i, colors.cyan, pkg, colors.reset))
        end
        return all_packages
    else
        io.write(colors.red .. "\nNo Roblox packages found!\n" .. colors.reset)
        io.write(colors.yellow .. "Common Roblox package names to try:\n" .. colors.reset)
        io.write("  - com.roblox.client\n")
        io.write("  - com.roblox.client2\n")
        io.write("  - com.roblox.clien\n")
        io.write("  - com.rblx.client\n\n")
        
        -- Try to show all packages for debugging
        io.write(colors.yellow .. "Would you like to see all installed packages? (y/n): " .. colors.reset)
        local show_all = io.read():lower()
        if show_all == "y" then
            local debug_handle = io.popen("pm list packages | head -30")
            local debug_output = debug_handle:read("*a")
            debug_handle:close()
            io.write(colors.gray .. debug_output .. colors.reset)
            io.write(colors.white .. "\nPress Enter to continue..." .. colors.reset)
            io.read()
        end
        
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
    
    -- Try partial match
    local partial_check = io.popen("pm list packages | grep -i '" .. package_name:gsub("%.", "\\.") .. "' | head -1")
    local partial_result = partial_check:read("*a")
    partial_check:close()
    
    if partial_result and partial_result ~= "" then
        local found_pkg = partial_result:match("^package:(.+)$")
        if found_pkg then
            io.write(colors.yellow .. "Found similar package: " .. found_pkg .. "\n" .. colors.reset)
            io.write(colors.white .. "Use this instead? (y/n): " .. colors.reset)
            local choice = io.read():lower()
            if choice == "y" then
                return found_pkg
            end
        end
    end
    
    return false
end

local function select_packages(packages_list)
    io.write(colors.yellow .. "\nPackage selection:\n" .. colors.reset)
    io.write("  1) " .. colors.green .. "All packages\n" .. colors.reset)
    io.write("  2) " .. colors.cyan .. "Manual selection\n" .. colors.reset)
    io.write(colors.white .. "  Choose: " .. colors.reset)
    
    local choice = io.read()
    
    if choice == "1" then
        return packages_list
    elseif choice == "2" then
        io.write(colors.yellow .. "Enter package numbers (comma-separated, e.g., 1,2): " .. colors.reset)
        local selection = io.read()
        local selected = {}
        for num in selection:gmatch("%d+") do
            local index = tonumber(num)
            if index and index >= 1 and index <= #packages_list then
                table.insert(selected, packages_list[index])
            end
        end
        if #selected == 0 then
            io.write(colors.red .. "No valid packages selected, using all packages\n" .. colors.reset)
            return packages_list
        end
        return selected
    else
        io.write(colors.red .. "Invalid choice, using all packages\n" .. colors.reset)
        return packages_list
    end
end

local function configure_webhook()
    io.write(colors.yellow .. "\nEnable Discord webhook? (1=Yes, 2=No): " .. colors.reset)
    local enable = io.read()
    
    if enable == "1" then
        io.write(colors.cyan .. "Enter Discord webhook URL: " .. colors.reset)
        local url = io.read()
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
    io.write("  1) " .. colors.green .. "Automatic (recommended)\n")
    io.write("  2) " .. colors.cyan .. "Manual\n")
    io.write(colors.white .. "  Choose: " .. colors.reset)
    local method = io.read()
    
    local packages_list = nil
    
    if method == "1" then
        packages_list = find_roblox_packages()
        if not packages_list or #packages_list == 0 then
            io.write(colors.red .. "\nAutomatic detection failed.\n" .. colors.reset)
            io.write(colors.yellow .. "Would you like to switch to manual mode? (y/n): " .. colors.reset)
            local switch = io.read():lower()
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
        io.write(colors.gray .. "Examples: com.roblox.client, com.roblox.client2, com.roblox.clien\n" .. colors.reset)
        
        while true do
            io.write(colors.white .. "Package " .. (#packages_list + 1) .. ": " .. colors.reset)
            local pkg_name = io.read()
            
            if pkg_name == "" then
                if #packages_list == 0 then
                    io.write(colors.red .. "At least one package is required!\n" .. colors.reset)
                else
                    break
                end
            else
                local verified = verify_package_exists(pkg_name)
                if verified then
                    if type(verified) == "string" then
                        table.insert(packages_list, verified)
                        io.write(colors.green .. "✓ Package added: " .. verified .. "\n" .. colors.reset)
                    else
                        table.insert(packages_list, pkg_name)
                        io.write(colors.green .. "✓ Package added: " .. pkg_name .. "\n" .. colors.reset)
                    end
                else
                    io.write(colors.red .. "✗ Package not found: " .. pkg_name .. "\n" .. colors.reset)
                    io.write(colors.yellow .. "Would you like to add it anyway? (y/n): " .. colors.reset)
                    local force = io.read():lower()
                    if force == "y" then
                        table.insert(packages_list, pkg_name)
                        io.write(colors.yellow .. "✓ Package added (unverified): " .. pkg_name .. "\n" .. colors.reset)
                    end
                end
            end
            
            io.write(colors.white .. "Add another package? (y/n): " .. colors.reset)
            local add_more = io.read():lower()
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
    
    io.write(colors.cyan .. "\nEnter Roblox game URL: " .. colors.reset)
    local game_url = io.read()
    
    if not game_url or game_url == "" then
        io.write(colors.red .. "Game URL is required!\n" .. colors.reset)
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
    
    local start_interval = 120
    if interval_choice == "1" then
        io.write(colors.cyan .. "Enter interval (seconds): " .. colors.reset)
        start_interval = tonumber(io.read()) or 120
        if start_interval < 1 then start_interval = 1 end
    end
    
    io.write(colors.yellow .. "\nEnable auto-restart? (1=Yes, 2=No): " .. colors.reset)
    local restart_enabled = io.read()
    
    local restart_config = { enabled = false }
    if restart_enabled == "1" then
        io.write(colors.cyan .. "Restart interval (minutes): " .. colors.reset)
        local interval_min = tonumber(io.read()) or 60
        
        io.write(colors.yellow .. "Restart type:\n" .. colors.reset)
        io.write("  1) " .. colors.green .. "Game restart (full package restart)\n")
        io.write("  2) " .. colors.cyan .. "Server rejoin (rejoin game)\n")
        io.write(colors.white .. "  Choose: " .. colors.reset)
        local type_choice = io.read()
        
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
        version = "1.0"
    }
    
    -- Debug: Show what we're about to save
    io.write(colors.gray .. "\nSaving configuration...\n" .. colors.reset)
    
    if save_config(config) then
        clear_screen()
        print_banner()
        io.write(colors.green .. "\n✅ Configuration completed successfully!\n" .. colors.reset)
        io.write(colors.cyan .. "\nConfigured packages:\n" .. colors.reset)
        for i, pkg in ipairs(selected_packages) do
            io.write(string.format("  %d) %s%s%s\n", i, colors.yellow, pkg, colors.reset))
        end
        io.write(colors.green .. "\nGame URL: " .. colors.cyan .. game_url .. colors.reset .. "\n")
        io.write(colors.white .. "\nPress Enter to return to main menu..." .. colors.reset)
        io.read()
        return true
    else
        io.write(colors.red .. "\n❌ Failed to save configuration!\n" .. colors.reset)
        io.write(colors.yellow .. "Checking directory permissions...\n" .. colors.reset)
        
        -- Diagnostic info
        local home = os.getenv("HOME")
        os.execute("ls -la " .. home .. "/NOKA/ 2>&1")
        
        io.write(colors.white .. "\nPress Enter to continue..." .. colors.reset)
        io.read()
        return false
    end
end

local function launch_package(package_name, game_url)
    local intent = "am start -a android.intent.action.VIEW -d '" .. game_url .. "' " .. package_name
    local result = os.execute(intent .. " > /dev/null 2>&1")
    return result == 0
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
    if not config or not config.packages or #config.packages == 0 then
        clear_screen()
        print_banner()
        io.write(colors.red .. "\n❌ No configuration found! Please run first-time configuration first.\n" .. colors.reset)
        io.write(colors.white .. "Press Enter to return to main menu..." .. colors.reset)
        io.read()
        return
    end
    
    clear_screen()
    print_banner()
    io.write(colors.green .. "\n=== AUTO-REJOIN ACTIVE ===\n" .. colors.reset)
    io.write(colors.yellow .. "Press Ctrl+C to stop\n\n" .. colors.reset)
    
    local package_states = {}
    
    for i, pkg in ipairs(config.packages) do
        package_states[pkg] = {
            status = "pending",
            uptime = 0,
            last_action = 0,
            launch_time = 0,
            line_num = 8 + i
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
                os.execute("sleep " .. config.start_interval)
                launch_next_package(index + 1)
            end
        else
            package_states[pkg].status = "failed"
            update_dashboard_line(package_states[pkg].line_num,
                string.format("  %s%-30s%s %sFailed to launch%s", colors.cyan, pkg, colors.reset, colors.red, colors.reset))
            log("Failed to launch " .. pkg, "ERROR")
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
                local status = check_package_status(pkg)
                
                if status == "crashed" and state.status ~= "crashed" and state.status ~= "restarting" and state.status ~= "pending" then
                    state.status = "crashed"
                    log(pkg .. " has crashed", "WARN")
                    
                    if config.restart.enabled then
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
            last_heartbeat_check = current_time
        end
        
        if config.webhook.enabled and current_time - last_webhook >= config.webhook.interval then
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
        
        if config.restart.enabled then
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
    
    if config and config.webhook then
        io.write(colors.cyan .. "Current webhook status: " .. (config.webhook.enabled and "Enabled" or "Disabled") .. "\n" .. colors.reset)
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
            io.write(colors.green .. "\n✅ Webhook configuration updated!\n" .. colors.reset)
        else
            io.write(colors.red .. "\n❌ Failed to save webhook configuration!\n" .. colors.reset)
        end
    else
        io.write(colors.red .. "\n❌ No configuration loaded. Please run first-time configuration first.\n" .. colors.reset)
    end
    
    io.write(colors.white .. "\nPress Enter to return to main menu..." .. colors.reset)
    io.read()
end

local function update_url()
    clear_screen()
    print_banner()
    io.write(colors.green .. "\n=== UPDATE GAME URL ===\n" .. colors.reset)
    
    if not config then
        io.write(colors.red .. "\n❌ No configuration loaded. Please run first-time configuration first.\n" .. colors.reset)
        io.write(colors.white .. "Press Enter to return to main menu..." .. colors.reset)
        io.read()
        return
    end
    
    io.write(colors.cyan .. "Current URL: " .. config.game_url .. "\n" .. colors.reset)
    io.write(colors.cyan .. "Enter new Roblox game URL: " .. colors.reset)
    local new_url = io.read()
    
    if new_url and new_url ~= "" then
        config.game_url = new_url
        if save_config(config) then
            io.write(colors.green .. "\n✅ URL updated successfully!\n" .. colors.reset)
        else
            io.write(colors.red .. "\n❌ Failed to save URL!\n" .. colors.reset)
        end
    else
        io.write(colors.red .. "\n❌ Invalid URL. No changes made.\n" .. colors.reset)
    end
    
    io.write(colors.white .. "\nPress Enter to return to main menu..." .. colors.reset)
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
    
    if choice == "1" then
        io.write(colors.cyan .. "Enter export path (default: ~/NOKA/config_export.json): " .. colors.reset)
        local export_path = io.read()
        if export_path == "" then
            export_path = os.getenv("HOME") .. "/NOKA/config_export.json"
        end
        
        local cmd = "cp " .. CONFIG_PATH .. " " .. export_path .. " 2>/dev/null"
        local result = os.execute(cmd)
        if result then
            io.write(colors.green .. "\n✅ Config exported to: " .. export_path .. "\n" .. colors.reset)
        else
            io.write(colors.red .. "\n❌ Failed to export config!\n" .. colors.reset)
        end
        
    elseif choice == "2" then
        io.write(colors.cyan .. "Enter import file path: " .. colors.reset)
        local import_path = io.read()
        
        local file = io.open(import_path, "r")
        if file then
            file:close()
            local cmd = "cp " .. import_path .. " " .. CONFIG_PATH .. " 2>/dev/null"
            local result = os.execute(cmd)
            if result then
                config = load_config()
                io.write(colors.green .. "\n✅ Config imported successfully!\n" .. colors.reset)
            else
                io.write(colors.red .. "\n❌ Failed to import config!\n" .. colors.reset)
            end
        else
            io.write(colors.red .. "\n❌ File not found: " .. import_path .. "\n" .. colors.reset)
        end
    end
    
    io.write(colors.white ..
