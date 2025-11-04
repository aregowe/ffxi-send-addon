_addon.version = '1.2'
_addon.name = 'Send'
_addon.command = 'send'
_addon.author = 'Byrth, Lili'

local debug = false

require('functions')
require('chat')

-- OPTIMIZATION: Define target prefix constants for clarity and performance
local TARGET_PREFIX = {
    DEBUG = '@debug',
    ALL = '@all',
    PARTY = '@party',
    ZONE = '@zone',
    OTHERS = '@others'
}

-- OPTIMIZATION: Pre-define party member keys to avoid string concatenation in loops
local PARTY_KEYS = {'p0', 'p1', 'p2', 'p3', 'p4', 'p5'}

windower.register_event('addon command', function(target, ...)
    if not target then
        error('No target provided.')
        return
    end

    if not ... then
        error('No command provided.')
        return
    end

    -- OPTIMIZATION: Convert to lowercase once at the start
    local target_lower = target:lower()

    -- OPTIMIZATION: Fix error() logic bug - error() doesn't return a value
    if target_lower == TARGET_PREFIX.DEBUG then
        local arg = ...
        if arg ~= 'on' and arg ~= 'off' then
            error('Invalid argument. Usage: send @debug <on|off>')
            return
        end
        debug = (arg == 'on')
        return windower.add_to_chat(55, 'send: debug ' .. tostring(debug))
    end

    -- OPTIMIZATION: Single-pass string processing with early exit for patterns
    -- Check if command contains <> patterns before expensive gsub
    local raw_command = T{...}:map(string.strip_format .. windower.convert_auto_trans):map(function(str)
        return str:find(' ', string.encoding.shift_jis, true) and str:enclose('"') or str
    end):sconcat()
    
    local command
    if raw_command:find('<', 1, true) then
        -- Only perform gsub if command contains '<' character
        command = raw_command:gsub('<(%a+)id>', function(target_string)
            local entity = windower.ffxi.get_mob_by_target(target_string)
            return entity and entity.id or '<' .. target_string .. 'id>'
        end)
    else
        command = raw_command
    end

    -- OPTIMIZATION: Single player lookup for entire function
    local player = windower.ffxi.get_player()
    if not player then return end
    
    local player_name_lower = player.name:lower()
    local player_job_lower = player.main_job:lower()

    -- OPTIMIZATION: Consolidate target validation into cleaner logic
    local should_execute = false
    local modified_target = target_lower
    
    if target_lower == player_name_lower then
        -- Direct name match
        should_execute = true
    elseif target_lower == TARGET_PREFIX.ALL or target_lower == '@' .. player_job_lower then
        -- @all or @job match
        should_execute = true
    elseif target_lower == TARGET_PREFIX.PARTY then
        -- @party - execute and modify target
        should_execute = true
        modified_target = target_lower .. player.name
    elseif target_lower == TARGET_PREFIX.ZONE then
        -- @zone - execute and modify target
        should_execute = true
        modified_target = target_lower .. windower.ffxi.get_info().zone
    end
    
    if should_execute then
        execute_command(command)
    end
    
    -- Only send IPC if we didn't match direct name (to avoid sending to self only)
    if target_lower ~= player_name_lower then
        command = 'send ' .. modified_target .. ' ' .. command

        if debug then
            windower.add_to_chat(207, 'send (debug): ' .. command)
        end

        windower.send_ipc_message(command)
    end
end)

windower.register_event('ipc message', function (msg)
    if debug then
        windower.add_to_chat(207, 'send receive (debug): ' .. msg)
    end

    local info = windower.ffxi.get_info()
    if not info.logged_in then
        return
    end

    local split = msg:split(' ', string.encoding.shift_jis, 3, false, true)
    if #split < 3 or split[1] ~= 'send' then
        return
    end

    local target = split[2]
    local command = split[3]

    -- OPTIMIZATION: Single player lookup for receive handler
    local player = windower.ffxi.get_player()
    if not player then return end
    
    local player_name_lower = player.name:lower()
    local player_job_lower = player.main_job:lower()
    local target_lower = target:lower()

    if target_lower == player_name_lower then
        execute_command(command)
    elseif target_lower:startswith('@') then
        local arg = target_lower:sub(2)

        if arg == player_job_lower or arg == TARGET_PREFIX.ALL:sub(2) or arg == TARGET_PREFIX.OTHERS:sub(2) then
            execute_command(command)
        elseif arg:startswith('party') then
            local sender = arg:sub(6, #arg):lower()
            local party = windower.ffxi.get_party()
            
            -- OPTIMIZATION: Iterate party members with pre-built keys to avoid string concat
            -- Check all 6 party slots (p0-p5) using PARTY_KEYS constant
            for _, key in ipairs(PARTY_KEYS) do
                local member = party[key]
                if member and member.name:lower() == sender then
                    execute_command(command)
                    return
                end
            end
        elseif arg:startswith('zone') then
            if tonumber(arg:sub(5)) == info.zone then
                execute_command(command)
            end
        end
    end
end)

function execute_command(msg)
    if msg:sub(1, 2) == '//' then
        windower.send_command(msg:sub(3))
    elseif msg:sub(1, 1) == '/' then
        windower.send_command('input '..msg)
    elseif msg:sub(1, 3) == 'atc' then
        windower.add_to_chat(55, msg:sub(5))
    else
        windower.send_command(msg)
    end
end
