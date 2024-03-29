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
local BANK_PIN = "changeme"                     -- your BoCC PIN
local PAY_THRESHOLD = 500                   -- maximum amount of money allowed to send through chat
local CHAT_PREFIX = "!"                     -- prefix for all chat commands (ex. !pay where ! is the prefix), cannot be $
-- if you want to use $ as the prefix, set CHAT_PREFIX to "" (Advanced Peripherals hides your message by default with $)

-- after enabling secure mode, you won't be able to terminate the program
-- thus you won't be able to modify this config
-- and will need to run `$!quickpay securemode off` to turn it off until next reboot.
local SECURE_MODE = false
--- CONFIG ---

if SECURE_MODE then
    os.pullEvent = os.pullEventRaw
end

local expect = require("cc.expect").expect
local logging = require("logging")
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

local function split_str(inputstr, sep, split_count)
    expect(1, inputstr, "string")
    expect(2, sep, "string", "nil")
    expect(3, split_count, "number", "nil")
    if sep == nil then
        -- If the separator is nil, we default to whitespace
        sep = "%s"
    end
    if split_count == nil then
        split_count = -1
    end
    local splitted_table = {}
    local splitted_amount = 0
    for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
        if splitted_amount == split_count then
            break
        else
            table.insert(splitted_table, str)
            splitted_amount = splitted_amount + 1
        end
    end
    return splitted_table
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
- !pay <username> <amount>      : Send money to another player (must be the BoCC username)
- !quickpay                     : Display QuickPay commands
- !quickpay help                : Display this help message
- !quickpay help <command>      : Display help for a specific command
- !quickpay setlimit <amount>   : Set the maximum amount of money you can send until next reboot
- !quickpay securemode (on|off) : Enable or disable secure mode until next reboot
- !quickpay reboot              : Reboot the QuickPay computer
- !quickpay autodestruct        : Deletes all files associated with BoCC QuickPay
- !quickpay pastelogs           : Will upload the QuickPay logs to pastebin
    ]]
    helpMessage = helpMessage:gsub("!", CHAT_PREFIX)

    if args[3] == nil then
        chatbox.sendMessageToPlayer(helpMessage, ADMIN_USERNAME, "BoCC QuickPay")
    elseif args[3] == "setlimit" then
        chatbox.sendMessageToPlayer("Set Limit:\n- setlimit <amount>", ADMIN_USERNAME, "BoCC QuickPay")
    elseif args[3] == "reboot" then
        chatbox.sendMessageToPlayer("Reboot:\n- reboot", ADMIN_USERNAME, "BoCC QuickPay")
    elseif args[3] == "securemode" then
        chatbox.sendMessageToPlayer("Secure Mode:\n- securemode on\n- securemode off", ADMIN_USERNAME, "BoCC QuickPay")
    elseif args[3] == "autodestruct" then
        chatbox.sendMessageToPlayer("Auto Destruct:\n- autodestruct", ADMIN_USERNAME, "BoCC QuickPay")
    elseif args[3] == "pastelogs" then
        chatbox.sendMessageToPlayer("Upload logs to pastebin:\n- pastelogs", ADMIN_USERNAME, "BoCC QuickPay")
    end
end

local function upload_file_to_pastebin(filename)
    local sPath = shell.resolve(filename)
    if not fs.exists(sPath) or fs.isDir(sPath) then
        logging.error("No such file (logs.txt) for upload")
        return nil
    end
    local sName = fs.getName(sPath)
    local file = fs.open(sPath, "r")
    local sText = file.readAll()
    file.close()
    logging.debug("Connecting to pastebin...")
    local key = "0ec2eb25b6166c0c27a394ae118ad829"
    local response = http.post(
        "https://pastebin.com/api/api_post.php",
        "api_option=paste&" ..
        "api_dev_key=" .. key .. "&" ..
        "api_paste_format=lua&" ..
        "api_paste_name=" .. textutils.urlEncode(sName) .. "&" ..
        "api_paste_code=" .. textutils.urlEncode(sText)
    )
    if response then
        logging.success("Successfully uploaded")
        local sResponse = response.readAll()
        response.close()
        local sCode = string.match(sResponse, "[^/]+$")
        return sCode
    else
        logging.error("Failed upload to pastebin")
        return nil
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
                    if transaction_response.message ~= nil then
                        chatbox.sendToastToPlayer("Could not send the money! " .. transaction_response.message, "BoCC QuickPay", ADMIN_USERNAME, "&4&lerror", "()", "&c&l")
                    else
                        chatbox.sendToastToPlayer("Could not send the money! Error in logs.txt", "BoCC QuickPay", ADMIN_USERNAME, "&4&lerror", "()", "&c&l")
                    end
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
        if args[2] == "help" then
            commandHelp(args)
        elseif args[2] == "reboot" then
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
        elseif args[2] == "pastelogs" then
            local pastecode = upload_file_to_pastebin("logs.txt")
            if pastecode ~= nil then
                local message = textutils.serializeJSON({
                    {text = "Logs uploaded to pastebin! ", color = "red"}, 
                    {
                        text = "https://pastebin.com/" .. pastecode,
                        underlined = true,
                        color = "aqua",
                        clickEvent = {
                            action = "open_url",
                            value = "https://pastebin.com/" .. pastecode
                        }
                    },
                })
                
                chatbox.sendFormattedMessageToPlayer(message, ADMIN_USERNAME, "&c&2BoCC QuickPay", "[]", "&c&2")
            else
                chatbox.sendToastToPlayer("Failed pasting logs", "BoCC QuickPay", ADMIN_USERNAME, "&4&lerror", "()", "&c&l")
            end
        end
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
                local args = split_str(eventData[3], " ")
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
        elseif eventData[1] == "disk" then
            local side = eventData[2]
            local disk = peripheral.wrap(side)
            if disk ~= nil then
                local disk_id = disk.getDiskID()
                local mount_path = disk.getMountPath()
                logging.debug(mount_path)
                logging.debug(tostring(disk_id))
                chatbox.sendToastToPlayer("Backing up logs on disk " .. tostring(disk_id), "BoCC QuickPay", ADMIN_USERNAME, "&c&2success", "()", "&c&2")
                
                local success, err = pcall(function()
                    fs.copy("logs.txt", mount_path .. "/logs-bk-" .. os.date("%Y%m%d%H%M%S") .. ".txt")
                end)
                local success2, err2 = pcall(function()
                    fs.delete("logs.txt")
                end)

                os.sleep(1)

                if not success then
                    if string.find(err, "Out of space") then
                        logging.error("Failed to backup logs, the disk has no space left")
                        chatbox.sendToastToPlayer("Disk is full.", "BoCC QuickPay", ADMIN_USERNAME, "&4&lerror", "()", "&c&l")
                    else
                        logging.error("Failed to backup logs: " .. err)
                    end
                    chatbox.sendToastToPlayer("Failed backing up logs, more info in the logs.txt file", "BoCC QuickPay", ADMIN_USERNAME, "&4&lerror", "()", "&c&l")
                end

                if not success2 then
                    logging.error("Failed to delete local logs: " .. err2)
                    chatbox.sendToastToPlayer("Failed deleting local logs, more info in the logs.txt file", "BoCC QuickPay", ADMIN_USERNAME, "&4&lerror", "()", "&c&l")
                end
                
                chatbox.sendToastToPlayer("Backed up logs", "BoCC QuickPay", ADMIN_USERNAME, "&c&2success", "()", "&c&2")
                disk.ejectDisk()
            end
        elseif eventData[1] == "peripheral" then
            local side = eventData[2]
            local wrapped_peripheral = peripheral.wrap(side)
            if wrapped_peripheral ~= nil then
                logging.debug("Attached peripheral: " .. side)
                chatbox.sendToastToPlayer("A peripheral was attached on your QuickPay computer", "BoCC QuickPay", ADMIN_USERNAME, "&c&2warning", "()", "&c&2")
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
        logging.error("Success: " .. tostring(success) .. "; Result: " .. tostring(result))
    end)
    if not success2 then
        logging.error("Failed to log error: " .. tostring(result2))
    end
    local success3, result3 = pcall(function()
        chatbox.sendToastToPlayer("Internal error. Logs in logs.txt", "BoCC QuickPay", ADMIN_USERNAME, "&4&lINTERNAL ERROR", "()", "&c&l")
    end)
    if not success3 then
        logging.error("Failed to send error toast: " .. tostring(result3))
    end
    os.sleep(0.5)
    os.reboot()
end
