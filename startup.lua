-- How to use:
-- 1. attach an Advanced Peripherals Chat Box to the computer
-- 2. set ADMIN_USERNAME to your Minecraft username
-- 3. set BANK_USERNAME to your BoCC username
-- 4. set BANK_PIN to your BoCC PIN
-- 5. enable secure mode (after configation has been done and that it's working)
-- 6. type '!pay <username> <amount>' in chat
--    for example: '!pay TKB_Studios 50'
--    you can also do '$!pay <username> <amount>' for an anonymous payment (won't be put in chat)

--- CONFIG ---
local ADMIN_USERNAME = "changeme"        -- your MC username
local BANK_USERNAME = "changeme"         -- your BoCC username
local BANK_PIN = "1234"                     -- your BoCC PIN
local PAY_THRESHOLD = 500                   -- maximum amount of money allowed to send through chat
local CHAT_PREFIX = "!"                     -- prefix for all chat commands (ex. !pay where ! is the prefix), cannot be $
-- if you want to use $ as the prefix, set CHAT_PREFIX to "" (Advanced Peripherals hides your message by default with $)

-- after enabling secure mode, you won't be able to terminate the program
-- thus you won't be able to modify this config
-- and will need to run `$!quickpay securemode off` to turn it off until next reboot.
local SECURE_MODE = true
--- CONFIG ---

if SECURE_MODE then
    os.pullEvent = os.pullEventRaw
end

os.loadAPI("logging")
local chatbox = peripheral.find("chatBox")

-- base routes
local BASE_CCBANK_URL = "https://ccbank.tkbstudios.com"
local BASE_CCBANK_WS_URL = "wss://ccbank.tkbstudios.com"

-- API routes
local base_api_url = BASE_CCBANK_URL .. "/api/v1"
local server_login_url = base_api_url .. "/login"
local new_transaction_url = base_api_url .. "/transactions/new"

-- Websocket
local transactions_websocket_url = BASE_CCBANK_WS_URL .. "/websockets/transactions"

-- Session
local username = nil
local session_token = nil

-- Web stuff
local base_headers = {
    ["Session-Token"] = session_token
}

-- funcs

local function split(string_to_split, pattern)
    local Table = {}
    local fpat = "(.-)" .. pattern
    local last_end = 1
    local s, e, cap = string_to_split:find(fpat, 1)
    while s do
        if s ~= 1 or cap ~= "" then
            table.insert(Table, cap)
        end
        last_end = e + 1
        s, e, cap = string_to_split:find(fpat, last_end)
    end
    if last_end <= #string_to_split then
        cap = string_to_split:sub(last_end)
        table.insert(Table, cap)
    end
    return Table
end

local function login()
    if string.len(BANK_USERNAME) > 15 or string.len(BANK_PIN) > 8 or string.len(BANK_USERNAME) < 3 or string.len(BANK_PIN) < 4 then
        return {success = false, message = "Invalid username or PIN length"}
    end

    local postData = {
        username = BANK_USERNAME,
        pin = BANK_PIN
    }
    local postHeaders = {
        ["Content-Type"] = "application/json"
    }
    local response = http.post(server_login_url, textutils.serializeJSON(postData), postHeaders)
    if not response then
        return
    end

    local responseBody = response.readAll()
    if not responseBody then
        return
    end

    local decodedResponse = textutils.unserializeJSON(responseBody)
    if not decodedResponse then
        return
    end

    if decodedResponse.success then
        session_token = decodedResponse.session_token
        logging.success("Logged in successfully as " .. BANK_USERNAME)
        base_headers["Session-Token"] = session_token
    else
        logging.error("Login failed for user '" .. username .. "': " .. decodedResponse.message)
    end

    return true
end

local function create_transaction(target_username, amount)
    if string.len(target_username) > 15 or amount <= 0 then
        return {success = false, message = "Invalid target username or amount"}
    end

    local headers = {
        ["Content-Type"] = "application/json",
        ["Session-Token"] = session_token
    }

    local postData = {
        username = target_username,
        amount = amount
    }

    local response = http.post(new_transaction_url, textutils.serializeJSON(postData), headers)
    if not response then
        return {success = false, message = "Failed to connect to server"}
    end

    local responseBody = response.readAll()
    if not responseBody then
        return {success = false, message = "Empty response from server"}
    end

    local decodedResponse = textutils.unserializeJSON(responseBody)
    if not decodedResponse then
        return {success = false, message = "Failed to parse server response"}
    end

    return decodedResponse
end

local function commandHelp(args)
    local helpMessage = [[
Available commands:
- !pay <username> <amount> : Send money to another player (must be the BoCC username)
- !quickpay                : Display QuickPay commands
- !quickpay help           : Display this help message
- !quickpay setlimit <amount> : Set the maximum amount of money you can send until next reboot
- !quickpay securemode (on|off) : Enable or disable secure mode until next reboot
- !quickpay reboot          : Reboot the QuickPay computer
- !quickpay autodestruct  : Deletes all files associated with BoCC QuickPay
    ]]
    helpMessage = helpMessage:gsub("!", CHAT_PREFIX)

    if args[2] == nil then
        chatbox.sendMessageToPlayer(helpMessage, ADMIN_USERNAME, "BoCC QuickPay")
    elseif args[2] == "quickpay" then
        local subHelpMessage = [[
Subcommands for '!quickpay':
- setlimit <amount> : Set the maximum amount a player can send
- securemode (on|off) : Enable or disable secure mode
- reboot             : Reboot the computer
        ]]
        subHelpMessage = helpMessage:gsub("!", CHAT_PREFIX)

        if args[3] == "setlimit" then
            chatbox.sendMessageToPlayer("Set Limit:\n- setlimit <amount>", ADMIN_USERNAME, "BoCC QuickPay")
        elseif args[3] == "reboot" then
            chatbox.sendMessageToPlayer("Reboot:\n- reboot", ADMIN_USERNAME, "BoCC QuickPay")
        elseif args[3] == "securemode" then
            chatbox.sendMessageToPlayer("Secure Mode:\n- securemode on\n- securemode off", ADMIN_USERNAME, "BoCC QuickPay")
        elseif args[3] == "autodestruct" then
            chatbox.sendMessageToPlayer("Auto Destruct:\n- autodestruct", ADMIN_USERNAME, "BoCC QuickPay")
        else
            chatbox.sendMessageToPlayer(subHelpMessage, ADMIN_USERNAME, "BoCC QuickPay")
        end
    end
end


local function handleChatCommand(args)
    if args[1] == CHAT_PREFIX .. "pay" then
        local target = args[2]
        if target == nil then
            chatbox.sendToastToPlayer("Invalid target", "BoCC QuickPay", ADMIN_USERNAME, "&4&lerror", "()", "&c&l")
        else
            local success, amount = pcall(tonumber, args[3])
            if not success or amount == nil then
                chatbox.sendToastToPlayer("Invalid amount", "BoCC QuickPay", ADMIN_USERNAME, "&4&lerror", "()", "&c&l")
            elseif amount <= 0 then
                chatbox.sendToastToPlayer("Amount must be greater than 0", "BoCC QuickPay", ADMIN_USERNAME, "&4&lerror", "()", "&c&l")
            elseif amount > PAY_THRESHOLD then
                chatbox.sendToastToPlayer("Amount must be less than " .. PAY_THRESHOLD .. " (defined in your config)", "BoCC QuickPay", ADMIN_USERNAME, "&4&lerror", "()", "&c&l")
            else
                local transaction_response = create_transaction(target, amount)
                if not transaction_response.success then
                    logging.error(transaction_response)
                    chatbox.sendToastToPlayer("Could not send the money! error: " .. transaction_response, "BoCC QuickPay", ADMIN_USERNAME, "&4&lerror", "()", "&c&l")
                else
                    if transaction_response.success then
                        logging.success("sent " .. amount .. " to " .. target .. " with transaction ID: " .. transaction_response.transaction_id)
                        chatbox.sendToastToPlayer("sent " .. amount .. "$ to " .. target .. " ID: " .. transaction_response.transaction_id, "BoCC QuickPay", ADMIN_USERNAME, "&c&2success", "()", "&c&2")
                    else
                        logging.error(textutils.unserializeJSON(transaction_response))
                        chatbox.sendToastToPlayer("Could not send the money! response: " .. textutils.serializeJSON(transaction_response), "BoCC QuickPay", ADMIN_USERNAME, "&4&lerror", "()", "&c&l")
                    end
                end
            end
        end
    elseif args[1] == CHAT_PREFIX .. "quickpay" then
        if args[2] == "reboot" then
            chatbox.sendToastToPlayer("Rebooting", "BoCC QuickPay", ADMIN_USERNAME, "&c&2success", "()", "&c&2")
            logging.warning("Rebooting after player command.")
            os.reboot()
        elseif args[2] == "securemode" then
            if args[3] == "on" then
                SECURE_MODE = true
                chatbox.sendToastToPlayer("Secure mode enabled", "BoCC QuickPay", ADMIN_USERNAME, "&c&2success", "()", "&c&2")
            elseif args[3] == "off" then
                SECURE_MODE = false
                chatbox.sendToastToPlayer("Secure mode disabled", "BoCC QuickPay", ADMIN_USERNAME, "&c&2success", "()", "&c&2")
            end
        elseif args[2] == "setlimit" then
            -- player passes a number in list index 3
            -- example: "!quickpay setlimit 1000"
            if args[3] ~= nil then
                local success, amount = pcall(tonumber, args[3])
                if not success or amount == nil then
                    chatbox.sendToastToPlayer("Invalid amount", "BoCC QuickPay", ADMIN_USERNAME, "&4&lerror", "()", "&c&l")
                else
                    PAY_THRESHOLD = amount
                    chatbox.sendToastToPlayer("Limit raised to " .. args[3], "BoCC QuickPay", ADMIN_USERNAME, "&c&2success", "()", "&c&2")
                end
            end
        elseif args[2] == "autodestruct" then
            logging.warning("Autodestructing...")
            chatbox.sendToastToPlayer("Auto destructing", "BoCC QuickPay", ADMIN_USERNAME, "&4&lwarning", "()", "&c&l")
            fs.delete("logs.txt")
            fs.delete("logging")
            fs.delete("startup.lua")
            os.reboot()
        end
    elseif args[1] == CHAT_PREFIX .. "help" then
        commandHelp(args)
    end
end

local function main()
    login()

    -- init websocket
    local transactions_ws, ws_error_msg = http.websocket(transactions_websocket_url, base_headers)
    if not transactions_ws or ws_error_msg ~= nil then
        logging.error("Failed to open websocket: " .. (ws_error_msg or "Unknown"))
        os.shutdown()
        return -- so that lua language server doesn't complain
    else
        logging.success("Websocket opened successfully")
    end

    local eventData
    while true do
        eventData = { os.pullEvent() }
        -- eventData[1] = event
        if eventData[1] == "chat" then
            -- eventData[2] = username
            -- eventData[3] = message
            -- eventData[4] = uuid
            -- eventData[5] = is hidden
            if eventData[2] == ADMIN_USERNAME then
                local args = split(eventData[3], " ")
                handleChatCommand(args)
            end
        elseif eventData[1] == "websocket_message" then
            local transaction_json = textutils.unserializeJSON(eventData[3])
            if transaction_json.to_user == BANK_USERNAME then
                chatbox.sendToastToPlayer("received " .. transaction_json.amount .. "$ from " .. transaction_json.from_user, "BoCC QuickPay", ADMIN_USERNAME, "&c&2success", "()", "&c&2")
            end
        elseif eventData[1] == "websocket_failure" or eventData[1] == "websocket_closed" then
            logging.error("Websocket failed: " .. eventData[2])
            chatbox.sendToastToPlayer("Websocket failed: " .. eventData[2], "BoCC QuickPay", ADMIN_USERNAME, "&4&lINTERNAL ERROR", "()", "&c&l")
            os.reboot()
            return
        elseif eventData[1] == "terminate" then
            if SECURE_MODE then
                logging.warning("SECURE mode prevents termination.")
                logging.warning("You can send `$" .. CHAT_PREFIX .. "quickpay securemode off` in the chat to turn it off temporarely.")
            else
                logging.warning("Exiting cleanly.")
                error("terminate", 999)
                return
            end
        else
            logging.debug(textutils.serializeJSON(eventData))
        end
    end
end

-- startup
term.clear()
term.setCursorPos(1, 1)
print("Bank Of ComputerCraft QuickPay")
print("Secure mode: " .. tostring(SECURE_MODE))
logging.init(1, true, "logs.txt")

local success, result = pcall(main)

if not success then
    if result == "terminate" then
        return
    end
    local success2, result2 = pcall(function()
        logging.error(debug.traceback())
    end)
    if not success2 then
        logging.error("Failed to log error: " .. result2)
    end
    local success3, result3 = pcall(function()
        chatbox.sendToastToPlayer("Internal error. Logs in logs.txt", "BoCC QuickPay", ADMIN_USERNAME, "&4&lINTERNAL ERROR", "()", "&c&l")
    end)
    if not success3 then
        logging.error("Failed to send error toast: " .. result3)
    end
    os.sleep(0.5)
    os.reboot()
end
