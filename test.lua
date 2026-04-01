#!/data/data/com.termux/files/usr/bin/lua

--[[
NOKA.lua - Roblox Auto-Rejoin Manager for Termux
Author: Expert Lua Developer
Version: 1.0.0
--]]

-- Configuration
local CONFIG_PATH = os.getenv("HOME") .. "/NOKA/config.json"
local HEARTBEAT_FILE = os.getenv("HOME") .. "/NOKA/heartbeat.lock"
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
    bg_black = "\27[40m",
    clear = "\27[2J\27[H",
    save_cursor = "\27[s",
    restore_cursor = "\27[u",
    cursor_up = "\27[1A",
    cursor_down = "\27[1B",
    cursor_right = "\27[1C",
    cursor_left = "\27[1D",
    erase_line = "\27[2K",
    erase_down = "\27[J"
}

-- Global state
local config = nil
local running = false
local packages = {}
local heartbeats = {}
local dashboard_lines = {}

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
end

local function load_config()
    ensure_directories()
    local file = io.open(CONFIG_PATH, "r")
    if not file then
        return nil
    end
    
    local content = file:read("*all")
    file:close()
    
    local success, result = pcall(function()
        return require("json").decode(content)
    end)
    
    if not success then
        log("Failed to parse config.json: " .. tostring(result), "ERROR")
        return nil
    end
    
    return result
end

local function save_config(cfg)
    ensure_directories()
    local file = io.open(CONFIG_PATH, "w")
    if not file then
        log("Failed to open config.json for writing", "ERROR")
        return false
    end
    
    local success, json = pcall(function()
        return require("json").encode(cfg, { indent = true })
    end)
    
    if not success then
        log("Failed to encode config to JSON: " .. tostring(json), "ERROR")
        file:close()
        return false
    end
    
    file:write(json)
    file:close()
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

local function input(prompt, is_password)
    io.write(colors.cyan .. prompt .. colors.reset)
    io.flush()
    if is_password then
        os.execute("stty -echo")
    end
    local result = io.read()
    if is_password then
        os.execute("stty echo")
        io.write("\n")
    end
    return result
end

local function find_roblox_packages()
    io.write(colors.yellow .. "\nScanning for Roblox packages...\n" .. colors.reset)
    
    -- More comprehensive search for any Roblox-related packages
    local patterns = {
        "com\\.roblox\\.client",
        "com\\.roblox\\.clien",  -- For incomplete package names
        "com\\.roblox\\.",
        "roblox",
        "com\\.rblx",
        "com\\.roblox"
    }
    
    local all_packages = {}
    local handle = io.popen("pm list packages")
    local all_output = handle:read("*a")
    handle:close()
    
    -- Search with multiple patterns
    for _, pattern in ipairs(patterns) do
        for line in all_output:gmatch("[^\r\n]+") do
            local pkg = line:match("^package:(.+)$")
            if pkg and pkg:lower():match(pattern) then
                local found = false
                for _, existing in ipairs(all_packages) do
                    if existing == pkg then
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(all_packages, pkg)
                end
            end
        end
    end
    
    -- If still no packages found, try a direct search with grep
    if #all_packages == 0 then
        io.write(colors.yellow .. "Trying alternative detection method...\n" .. colors.reset)
        local grep_handle = io.popen("pm list packages | grep -i roblox | sed 's/^package://'")
        local grep_output = grep_handle:read("*a")
        grep_handle:close()
        
        for line in grep_output:gmatch("[^\r\n]+") do
            if line ~= "" then
                table.insert(all_packages, line)
            end
        end
    end
    
    -- Manual fallback if still nothing found
    if #all_packages == 0 then
        io.write(colors.red .. "No Roblox packages found automatically.\n" .. colors.reset)
        io.write(colors.yellow .. "Would you like to enter package names manually? (y/n): " .. colors.reset)
        local manual_choice = io.read():lower()
        
        if manual_choice == "y" then
            io.write(colors.cyan .. "Enter package names (comma-separated, e.g., com.roblox.client,com.roblox.client2):\n" .. colors.reset)
            io.write(colors.white .. "> " .. colors.reset)
            local manual_input = io.read()
            
            for pkg in manual_input:gmatch("[^,]+") do
                local trimmed = pkg:gsub("^%s+", ""):gsub("%s+$", "")
                if trimmed ~= "" then
                    table.insert(all_packages, trimmed)
                end
            end
        end
    end
    
    -- Display found packages
    if #all_packages > 0 then
        io.write(colors.green .. "\nFound " .. #all_packages .. " Roblox package(s):\n" .. colors.reset)
        for i, pkg in ipairs(all_packages) do
            -- Highlight the package name with colors
            local display_pkg = pkg
            if pkg:match("clien[^t]") or pkg:match("clien$") then
                -- Special highlighting for incomplete package names
                io.write(string.format("  %d) %s%s%s %s\n", 
                    i, 
                    colors.yellow, 
                    display_pkg, 
                    colors.reset,
                    colors.gray .. "(Note: This appears to be a truncated package name)" .. colors.reset
                ))
            else
                io.write(string.format("  %d) %s%s%s\n", i, colors.cyan, display_pkg, colors.reset))
            end
        end
        io.write(colors.white .. "\n")  -- Add spacing
        return all_packages
    else
        io.write(colors.red .. "\nNo Roblox packages found!\n" .. colors.reset)
        io.write(colors.yellow .. "Common Roblox package names to try:\n" .. colors.reset)
        io.write("  - com.roblox.client\n")
        io.write("  - com.roblox.client2\n")
        io.write("  - com.roblox.clien\n")
        io.write("  - com.rblx.client\n")
        io.write("  - com.roblox.enterprise\n\n")
        return nil
    end
end

-- Improved manual package verification
local function verify_package_exists(package_name)
    if not package_name or package_name == "" then
        return false
    end
    
    -- Trim whitespace
    package_name = package_name:gsub("^%s+", ""):gsub("%s+$", "")
    
    -- Check if package exists
    local check = io.popen("pm list packages | grep -q '" .. package_name .. "' && echo found")
    local result = check:read("*a")
    check:close()
    
    if result:match("found") then
        return true
    end
    
    -- If exact match fails, try partial match
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

-- Updated first-time configuration with better package handling
local function first_time_config()
    clear_screen()
    print_banner()
    io.write(colors.green .. "\n=== FIRST TIME CONFIGURATION ===\n" .. colors.reset)
    
    -- Method selection
    io.write(colors.yellow .. "\nMethod for fetching Roblox packages:\n" .. colors.reset)
    io.write("  1) " .. colors.green .. "Automatic (recommended)\n")
    io.write("  2) " .. colors.cyan .. "Manual\n")
    io.write("  3) " .. colors.magenta .. "Debug mode (show all packages)\n")
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
    
    if method == "3" then
        -- Debug mode - show all packages for troubleshooting
        io.write(colors.yellow .. "\n=== DEBUG MODE ===\n" .. colors.reset)
        local debug_handle = io.popen("pm list packages | head -50")
        local debug_output = debug_handle:read("*a")
        debug_handle:close()
        io.write(colors.gray .. debug_output .. colors.reset)
        io.write(colors.white .. "\nPress Enter to continue with manual mode..." .. colors.reset)
        io.read()
        method = "2"
    end
    
    if method == "2" then
        packages_list = {}
        io.write(colors.cyan .. "\nEnter Roblox package name(s):\n" .. colors.reset)
        io.write(colors.gray .. "Examples: com.roblox.client, com.roblox.client2, com.roblox.clien\n" .. colors.reset)
        
        local continue = true
        while continue do
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
    
    -- Verify we have at least one package
    if not packages_list or #packages_list == 0 then
        io.write(colors.red .. "\nNo packages selected!\n" .. colors.reset)
        io.write(colors.white .. "Press Enter to continue..." .. colors.reset)
        io.read()
        return false
    end
    
    -- Package selection (if multiple packages found)
    local selected_packages = packages_list
    if #packages_list > 1 then
        selected_packages = select_packages(packages_list)
    end
    
    -- Server URL
    io.write(colors.cyan .. "\nEnter Roblox game URL: " .. colors.reset)
    local game_url = io.read()
    
    -- Webhook configuration
    local webhook = configure_webhook()
    
    -- Start interval
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
    
    -- Restart configuration
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
    
    -- Save configuration
    config = {
        packages = selected_packages,
        game_url = game_url,
        webhook = webhook,
        start_interval = start_interval,
        restart = restart_config,
        version = "1.0"
    }
    
    if save_config(config) then
        clear_screen()
        print_banner()
        io.write(colors.green .. "\n✅ Configuration completed successfully!\n" .. colors.reset)
        io.write(colors.cyan .. "\nConfigured packages:\n" .. colors.reset)
        for i, pkg in ipairs(selected_packages) do
            io.write(string.format("  %d) %s%s%s\n", i, colors.yellow, pkg, colors.reset))
        end
        io.write(colors.white .. "\nPress Enter to return to main menu..." .. colors.reset)
        io.read()
        return true
    else
        io.write(colors.red .. "\n❌ Failed to save configuration!\n" .. colors.reset)
        io.write(colors.white .. "Press Enter to continue..." .. colors.reset)
        io.read()
        return false
    end
end
    
    clear_screen()
    print_banner()
    io.write(colors.green .. "\n=== AUTO-REJOIN ACTIVE ===\n" .. colors.reset)
    io.write(colors.yellow .. "Press Ctrl+C to stop\n\n" .. colors.reset)
    
    -- Initialize packages state
    local package_states = {}
    local start_time = os.time()
    
    for i, pkg in ipairs(config.packages) do
        package_states[pkg] = {
            status = "pending",
            uptime = 0,
            last_action = 0,
            launch_time = 0,
            line_num = 5 + i
        }
    end
    
    -- Launch first package
    local function launch_next_package(index)
        if index > #config.packages then
            return
        end
        
        local pkg = config.packages[index]
        io.write(string.format(colors.cyan .. "Launching %s...\n" .. colors.reset, pkg))
        
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
            log("Failed to launch " .. pkg, "ERROR")
        end
    end
    
    -- Start launch sequence
    launch_next_package(1)
    
    -- Main monitoring loop
    running = true
    local last_webhook = 0
    local last_heartbeat_check = 0
    
    while running do
        local current_time = os.time()
        
        -- Update dashboard
        for pkg, state in pairs(package_states) do
            if state.status == "ingame" then
                state.uptime = current_time - state.launch_time
            end
            
            local status_color = colors.green
            if state.status == "crashed" then
                status_color = colors.red
            elseif state.status == "launching" then
                status_color = colors.yellow
            elseif state.status == "restarting" then
                status_color = colors.magenta
            end
            
            local status_text = string.format(
                "  %s%-20s%s  %s%-12s%s  %s%-8s%s  %s%s",
                colors.cyan, pkg:sub(1, 20), colors.reset,
                status_color, string.upper(state.status), colors.reset,
                colors.white, state.uptime .. "s", colors.reset,
                colors.gray, os.date("%H:%M:%S", state.last_action)
            )
            
            update_dashboard_line(state.line_num, status_text)
        end
        
        -- Check package status every 5 seconds
        if current_time - last_heartbeat_check >= 5 then
            for pkg, state in pairs(package_states) do
                local status = check_package_status(pkg)
                
                if status == "crashed" and state.status ~= "crashed" and state.status ~= "restarting" then
                    state.status = "crashed"
                    log(pkg .. " has crashed", "WARN")
                    
                    -- Send webhook notification
                    if config.webhook.enabled then
                        -- Would send crash notification
                    end
                    
                    -- Handle restart if enabled
                    if config.restart.enabled then
                        state.status = "restarting"
                        if config.restart.type == "game" then
                            os.execute("am force-stop " .. pkg)
                            os.execute("sleep 5")
                            launch_package(pkg, config.game_url)
                            state.launch_time = os.time()
                            state.status = "launching"
                        else
                            launch_package(pkg, config.game_url)
                            state.launch_time = os.time()
                            state.status = "launching"
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
        
        -- Send periodic webhook
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
        
        -- Check for restart interval
        if config.restart.enabled then
            for pkg, state in pairs(package_states) do
                if state.status == "ingame" and (current_time - state.launch_time) >= config.restart.interval then
                    state.status = "restarting"
                    if config.restart.type == "game" then
                        os.execute("am force-stop " .. pkg)
                        os.execute("sleep 5")
                        launch_package(pkg, config.game_url)
                        state.launch_time = os.time()
                        state.status = "ingame"
                    else
                        launch_package(pkg, config.game_url)
                        state.launch_time = os.time()
                        state.status = "ingame"
                    end
                    state.last_action = os.time()
                    log(pkg .. " restarted due to interval", "INFO")
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
        save_config(config)
        io.write(colors.green .. "\n✅ Webhook configuration updated!\n" .. colors.reset)
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
        save_config(config)
        io.write(colors.green .. "\n✅ URL updated successfully!\n" .. colors.reset)
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
        
        local cmd = "cp " .. CONFIG_PATH .. " " .. export_path
        os.execute(cmd)
        io.write(colors.green .. "\n✅ Config exported to: " .. export_path .. "\n" .. colors.reset)
        
    elseif choice == "2" then
        io.write(colors.cyan .. "Enter import file path: " .. colors.reset)
        local import_path = io.read()
        
        local file = io.open(import_path, "r")
        if file then
            file:close()
            local cmd = "cp " .. import_path .. " " .. CONFIG_PATH
            os.execute(cmd)
            config = load_config()
            io.write(colors.green .. "\n✅ Config imported successfully!\n" .. colors.reset)
        else
            io.write(colors.red .. "\n❌ File not found: " .. import_path .. "\n" .. colors.reset)
        end
    end
    
    io.write(colors.white .. "\nPress Enter to return to main menu..." .. colors.reset)
    io.read()
end

local function exit_tool()
    clear_screen()
    io.write(colors.green .. "\nThank you for using NOKA Auto-Rejoin Manager!\n" .. colors.reset)
    io.write(colors.cyan .. "Goodbye!\n\n" .. colors.reset)
    running = false
    os.exit(0)
end

-- Main program
local function main()
    -- Load existing config
    config = load_config()
    
    -- Main menu loop
    while true do
        clear_screen()
        print_banner()
        print_menu()
        
        local choice = io.read()
        
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
            io.write(colors.red .. "\nInvalid option. Press Enter to continue..." .. colors.reset)
            io.read()
        end
    end
end

-- Start the program
main()
