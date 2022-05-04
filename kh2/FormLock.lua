-- TODO: JP support, ensure game is beatable as forms other than final
local gl = 0x68
local jp = 0x66
local offset = 0x56454E
local now = 0x0714DB8 - offset
local game_version = 0x17D - offset
local slot2_ptr = 0x2A20C58-0x278-0x40 - offset

local dt_addr = 0x715230 - offset
local current_form_addr = 0x9AA5D4 - offset
local player_ptr_addr = 0x2AE7128 - offset

local zero_action_code = 0x3D577B - offset
local add_revert_code = 0x3F072D - offset
local decrease_form_code = 0x3BE45C - offset
local party_remove_drive_code = 0x3FE3FD - offset
local party_remove_load_code = 0x3C07C7 - offset
local forced_growth_code = 0x3FEF00 - offset

local form_delay_timer = 0

local normal_form = 0
local valor_form = 1
local wisdom_form = 2
local limit_form = 3
local master_form = 4
local final_form = 5

local target_form = final_form

local drive_action_table = {
    [valor_form] = 0x0006,
    [wisdom_form] = 0x0007,
    [limit_form] = 0x02A1,
    [master_form] = 0x000B,
    [final_form] = 0x000C,
}

local form_keyblade_table = {
    [normal_form] = 0x9A9560+0x40,
    [valor_form] = 0x9AA364+0x40,
    [wisdom_form] = nil,
    [limit_form] = nil,
    [master_form] = 0x9AA40C+0x40,
    [final_form] = 0x9AA444+0x40,
}

function _OnInit()
    local form_string = {
        [valor_form] = 'Valor Form',
        [wisdom_form] = 'Wisdom Form',
        [limit_form] = 'Limit Form',
        [master_form] = 'Master Form',
        [final_form] = 'Final Form',
    }

    if ReadByte(game_version) ~= gl then
        -- TODO: JP support
        print('FormLock ' .. form_string[target_form] .. ' initialized: JP')
    else
        print('FormLock ' .. form_string[target_form] .. ' initialized: Global')
    end
end

function _OnFrame()
    local world = ReadByte(now+0x00)
    local room = ReadByte(now+0x01)
    local place = ReadShort(now+0x00)
    local door = ReadShort(now+0x02)
    local map = ReadShort(now+0x04)
    local btl = ReadShort(now+0x06)
    local evt = ReadShort(now+0x08)
    local prevPlace = ReadShort(now+0x30)

    function events(m, b, e)
        return (map == m or not m) and (btl == b or not b) and (evt == e or not e)
    end

    function NeedsFormReset()
        return place == 0x0A02 and events(0x78, 0x78, 0x78) or -- roxas wall minigame
            place == 0x0C02 and events(0x7D, 0x7D, 0x7D) or -- roxas bag minigame
            place == 0x1402 and events(0x89, 0x89, 0x89) or -- stt axel fight
            world == 0x0A -- pride lands loading zones
    end

    function SafeToDrive()
        return place ~= 0x0E07 and -- agrabah ruins
            place ~= 0x0507 and -- agrabah jafar fight
            not (place == 0x1612 and events(0x48, 0x48, 0x48)) and -- dragon xemnas fight
            not (place == 0x0A02 and events(0x78, 0x78, 0x78)) and -- roxas wall minigame
            not (place == 0x0C02 and events(0x7D, 0x7D, 0x7D)) -- roxas bag minigame
    end

    -- Remove Revert button from command menu
    WriteArray(add_revert_code, {0x90, 0x90, 0x90, 0x90, 0x90})

    -- Set Anti-Points to zero
    WriteInt(0x9AA480+0x40-offset, 0)

    local current_form = ReadByte(current_form_addr)
    if current_form == target_form then
        local anim = GetPlayerAnimation()
        if anim == 0 then
            -- If T-stanced, switch to actual animation
            if world == 0x0A and not (room == 0x0F and events(0x3B, 0x3B, 0x3B)) then
                SetPlayerAnimation(65, 2)
            else
                SetPlayerAnimation(5, 2)
            end
        end

        -- Give infinite form gauge in target form
        WriteArray(decrease_form_code, {0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90})
        WriteArray(party_remove_load_code, {0x48, 0x31, 0xC0, 0x90, 0x90})
        WriteArray(forced_growth_code, {0x48, 0x31, 0xC0, 0x90, 0x90})
    else
        WriteArray(decrease_form_code, {0xF3, 0x0F, 0x11, 0x8B, 0xB4, 0x01, 0x00, 0x00})
        WriteArray(party_remove_load_code, {0xE8, 0xB4, 0xD4, 0x03, 0x00})
        WriteArray(forced_growth_code, {0xE8, 0x0B, 0xA7, 0xFA, 0xFF})
    end

    if NeedsFormReset() and ReadLong(player_ptr_addr) == 0 then
        WriteByte(current_form_addr, 0)
    end

    local is_mickey = false
    local ptr = ReadLong(0xABA7A8+0x40-offset)
    if ptr ~= 0 and ReadInt(ptr+0xDE0, true) == 0xB then
        is_mickey = true
    end

    -- Force player into drive form if in normal form and not at an unsafe location
    if current_form == 0 and SafeToDrive() and not is_mickey then
        if form_delay_timer > 0 then
            form_delay_timer = form_delay_timer - ReadFloat(dt_addr)
        else
            SetAction(drive_action_table[target_form])
            WriteArray(zero_action_code, {0x90, 0x90, 0x90})
            WriteArray(party_remove_drive_code, {0x48, 0x31, 0xC0, 0x90, 0x90})
        end
    else
        if is_mickey then
            -- if mickey give longer timer
            form_delay_timer = 4 * 60
        else
            form_delay_timer = 30
        end

        WriteArray(zero_action_code, {0x66, 0x89, 0x01})
        WriteArray(party_remove_drive_code, {0xE8, 0xFE, 0xFD, 0xFF, 0xFF})
    end

    -- Give form a weapon if it doesn't have one
    if GetFormWeapon(target_form) == 0x0000 then
        SetFormWeapon(target_form, 0x0180) -- Set weapon to Struggle Sword
    end

    UnlockForm(target_form)

    if place == 0x1804 then -- If in CoR puzzle room give aerial dodge max
        WriteByte(0x2A20E48+0x40+2-offset, 0x04)
    elseif place == 0x0F0A and events(0x3B, 0x3B, 0x3B) then -- If Groundshaker fight
        -- Give infinite aerial dodge
        WriteByte(0x2A20E48+0x40+2-offset, 0x05)
        -- TODO: Find and set end fight flag instead of funny hack
        -- Kill Groundshaker if 500 HP or lower
        local slot2 = ReadLong(slot2_ptr)
        if slot2 ~= 0 and ReadInt(slot2, true) <= 500 then
            WriteInt(slot2, 0, true)
        end
    end

    -- If Armored Xemnas II fight
    if place == 0x1712 and events(0x49, 0x49, 0x49) then
        if current_form == target_form then
            -- Give max quick run, aerial dodge, glide
            WriteArray(0x2A20E48+0x40-offset, {0x00, 0x05, 0x05, 0x05, 0x00})
        else
            -- Don't give mickey growth abilities
            WriteArray(0x2A20E48+0x40-offset, {0x00, 0x00, 0x00, 0x00, 0x00})
        end
    end

    -- Pride Lands
    if world == 0x0A then
        -- Give Glide 4
        WriteByte(0x2A20E48+0x40+3-offset, 0x04)
    end

    -- Change Roxas skateboards
    WriteString(0x2A37BA0+0x40-offset, "F_TT010_SORA\0")
    WriteString(0x2A37BC0+0x40-offset, "F_TT010_SORA.mset\0")
end

function ComputeCurrentGrowthLevel(form)
    local growth_param = 0x2A20E68
    local growth_levels = 0x5C7E40

    local offset_table = {
        [valor_form] = 0x00,
        [wisdom_form] = 0x05,
        [master_form] = 0x0A,
        [final_form] = 0x0F,
        [limit_form] = 0x14,
    }

    local level = 4
    while level >= 0 do
        local e = ReadByte(growth_levels + offset_table[form] + level - offset)
        if ((ReadInt(growth_param + ((e >> 5) * 4) - offset) >> (e & 0x1F)) & 1) ~= 0 then
            break
        end
        level = level - 1
    end

    return level + 1
end

function UnlockForm(form)
    local form_bit = {
        [valor_form] = 1 << 1,
        [wisdom_form] = 1 << 2,
        [master_form] = 1 << 6,
        [final_form] = 1 << 4,
    }

    if form == limit_form then
        WriteByte(0x9AA738+0x40-offset, ReadByte(0x9AA738+0x40-offset) | 0x80000)
    else
        WriteByte(0x9AA730+0x40-offset, ReadByte(0x9AA730+0x40-offset) | form_bit[form])
    end
end

function GetFormWeapon(form)
    local addr = form_keyblade_table[form]

    if addr ~= nil then
        return ReadShort(form_keyblade_table[form]-offset)
    else
        return nil
    end
end

function SetFormWeapon(form, weapon)
    local addr = form_keyblade_table[form]
    if addr ~= nil then
        WriteShort(form_keyblade_table[form]-offset, weapon)
    end
end

function GetAction()
    local ptr = ReadLong(0x2A0DD50 - offset)
    if ptr == 0 then
        return nil
    else
        return ReadShort(ptr + 0x8, action, true)
    end
end

function SetAction(action)
    local ptr = ReadLong(0x2A0DD50 - offset)
    if ptr ~= 0 then
        WriteShort(ptr + 0x8, action, true)
    end
end

function GetPlayerAnimation()
    local playerPtr = ReadLong(player_ptr_addr)
    if playerPtr == 0 then return nil end

    return ReadLong(playerPtr+0x170, true)
end

function FindPlayerAnimation(motionId, relativeSlot, onlyFirst)
    local animationFallback = {
        [0] = { 0, 1, 3, 2 },
        [1] = { 1, 0, 2, 3 },
        [2] = { 2, 3, 1, 0 },
        [3] = { 3, 2, 0, 1 },
    }

    local offsetMask = 0x01FFFFFF

    local playerPtr = ReadLong(player_ptr_addr)
    if playerPtr == 0 then return end

    local msetPtr = ReadLongA(playerPtr+0x158)
    if msetPtr == 0 then return end

    local entry
    local subfileName
    local offset
    for _, slot in ipairs(animationFallback[relativeSlot]) do
        entry = ((slot + motionId * 4) + 1) << 4
        subfileName = ReadInt(msetPtr+entry+4, true)
        offset = ReadInt(msetPtr+entry+8, true) & offsetMask

        -- not DUMM
        if subfileName ~= 0x4D4D5544 then
            break
        end
    end

    local msetUpper = msetPtr & (~offsetMask & 0xFFFFFFFFFFFFFFFF)
    local barPtr = msetUpper | offset

    local animPtr = msetUpper | (ReadInt(barPtr + 0x18, true) & offsetMask)
    local animPtr2 = msetUpper | (ReadInt(barPtr + 0x28, true) & offsetMask)

    if onlyFirst == true then
        return animPtr
    else
        return animPtr, animPtr2
    end
end

function SetPlayerAnimation(motionId, relativeSlot)
    local animPtr, animPtr2 = FindPlayerAnimation(motionId, relativeSlot)

    local playerPtr = ReadLong(player_ptr_addr)
    if playerPtr == 0 then return end

    local playerAnimPtr = playerPtr+0x170
    local playerAnimPtr2 = playerPtr+0x178

    WriteLong(playerAnimPtr, animPtr, true)
    WriteLong(playerAnimPtr2, animPtr2, true)
end
