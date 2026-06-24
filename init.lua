freecam_data = {}

minetest.register_entity("freecam:clone", {
    initial_properties = {
        visual = "mesh",
        mesh = "character.b3d",
        textures = {"character.png"},
        collisionbox = {0,0,0,0,0,0},
        pointable = false,
        static_save = false,
    },
})

local function freeze_clone_pose(player, clone)
    local frame_range, frame_speed, frame_blend, frame_loop = player:get_animation()
    if frame_range then
        clone:set_animation(frame_range, frame_speed, frame_blend, frame_loop)
    end
end

minetest.register_entity("freecam:wield_clone", {
    initial_properties = {
        physical = false,
        collide_with_objects = false,
        pointable = false,
        static_save = false,
        is_visible = true,
        visual = "wielditem",
        textures = {""},
    },
})

local has_wield3d = minetest.get_modpath("wield3d")

local WIELD3D_BONE = "Arm_Right"
local WIELD3D_POS = {x = 0, y = 5.5, z = 3}
local WIELD3D_ROT = {x = -90, y = 225, z = 90}
local WIELD3D_SCALE = tonumber(minetest.settings:get("wield3d_scale")) or 0.25

local function attach_wield_clone(player, clone, data)
    if not has_wield3d then return end

    local stack = player:get_wielded_item()
    local item = stack:get_name()
    if item == "" then return end

    local obj = minetest.add_entity(clone:get_pos(), "freecam:wield_clone")
    if not obj then return end

    obj:set_properties({
        visual_size = {x = WIELD3D_SCALE, y = WIELD3D_SCALE},
        textures = {item},
    })
    obj:set_attach(clone, WIELD3D_BONE, WIELD3D_POS, WIELD3D_ROT)

    data.wield_clone = obj
end

local old_is_protected = minetest.is_protected

function minetest.is_protected(pos, name)
    local data = freecam_data[name]
    if data and data.active then
        return true
    end
    return old_is_protected(pos, name)
end

local old_item_place = minetest.item_place

function minetest.item_place(itemstack, placer, pointed_thing, param2)
    if placer then
        local name = placer:get_player_name()
        if freecam_data[name] and freecam_data[name].active then
            return itemstack, nil
        end
    end
    return old_item_place(itemstack, placer, pointed_thing, param2)
end

minetest.register_on_mods_loaded(function()
    for entity_name, entity_def in pairs(minetest.registered_entities) do

        local old_on_rightclick = entity_def.on_rightclick

        entity_def.on_rightclick = function(self, clicker)
            if clicker and clicker.is_player and clicker:is_player() then
                local name = clicker:get_player_name()
                if freecam_data[name] and freecam_data[name].active then
                    return
                end
            end
            if old_on_rightclick then
                return old_on_rightclick(self, clicker)
            end
        end

        local old_on_punch = entity_def.on_punch

        entity_def.on_punch = function(self, puncher, time_from_last_punch,
                tool_capabilities, dir, damage)
            if puncher and puncher.is_player and puncher:is_player() then
                local name = puncher:get_player_name()
                if freecam_data[name] and freecam_data[name].active then
                    return true
                end
            end
            if old_on_punch then
                return old_on_punch(self, puncher, time_from_last_punch,
                        tool_capabilities, dir, damage)
            end
        end
    end
end)

minetest.register_on_mods_loaded(function()
    for item_name, item_def in pairs(minetest.registered_items) do

        if item_def.on_place then

            local old_on_place = item_def.on_place

            minetest.override_item(item_name, {
                on_place = function(itemstack, placer, pointed_thing)
                    if placer then
                        local name = placer:get_player_name()
                        if freecam_data[name] and freecam_data[name].active then
                            return itemstack
                        end
                    end
                    return old_on_place(itemstack, placer, pointed_thing)
                end
            })
        end
    end
end)

minetest.register_globalstep(function(dtime)
    for name, data in pairs(freecam_data) do
        if data.active then
            local player = minetest.get_player_by_name(name)
            if player then
                minetest.close_formspec(name, "")
            end
        end
    end
end)

minetest.register_on_punchnode(function(pos, node, puncher, pointed_thing)
    if puncher then
        local name = puncher:get_player_name()
        if freecam_data[name] and freecam_data[name].active then
            return true
        end
    end
end)

minetest.register_on_punchplayer(function(player, hitter, time_from_last_punch, tool_capabilities, dir, damage)
    if player and freecam_data[player:get_player_name()] then return true end
    if hitter and freecam_data[hitter:get_player_name()] then return true end
end)

minetest.register_globalstep(function(dtime)
    for name, data in pairs(freecam_data) do
        local player = minetest.get_player_by_name(name)
        if player and data.active then
            player:set_properties({ interaction_range = 0 })
        end
    end
end)

minetest.register_chatcommand("freecam", {
    params = "<player> <true|false>",
    description = "Enable or disable Freecam mode on the server",
    privs = {privs = true},
    func = function(name, param)
        local args = string.split(param, " ")
        local target_name = args[1]
        local action = args[2]

        if not target_name or target_name == "" or not action or action == "" then
            return false, "Usage: /freecam <player> <true|false>"
        end

        local target = minetest.get_player_by_name(target_name)
        if not target then return false, "Player offline or not found." end

        if not freecam_data[target_name] then
            freecam_data[target_name] = {
                active = false,
                pos_corpo = nil,
                clone = nil,
                old_visual_size = nil,
                old_interaction_range = 4
            }
        end

        local data = freecam_data[target_name]

        if action == "true" then
            if data.active then return false, "Freecam is already active for this player." end

            data.active = true
            data.pos_corpo = target:get_pos()
            data.old_visual_size = target:get_properties().visual_size
            data.old_interaction_range = target:get_properties().interaction_range or 4

            local clone = minetest.add_entity(data.pos_corpo, "freecam:clone")
            if clone then
                clone:set_properties({
                    mesh = target:get_properties().mesh,
                    textures = target:get_properties().textures,
                })
                clone:set_yaw(target:get_look_horizontal())
                freeze_clone_pose(target, clone)
                attach_wield_clone(target, clone, data)
                data.clone = clone
            end

            target:set_properties({ visual_size = {x=0, y=0, z=0} })
            target:set_armor_groups({immortal = 1})

            return true, "Freecam mode ENABLED for " .. target_name .. "."

        elseif action == "false" then
            if not data.active then return false, "Freecam is not active for this player." end

            data.active = false

            if data.clone then
                data.clone:remove()
            end

            if data.wield_clone then
                data.wield_clone:remove()
            end

            target:set_pos(data.pos_corpo)

            target:set_properties({
                visual_size = data.old_visual_size or {x=1, y=1, z=1},
                interaction_range = data.old_interaction_range or 4
            })
            target:set_armor_groups({fleshy = 100})

            freecam_data[target_name] = nil
            return true, "Freecam mode DISABLED for " .. target_name .. "."
        else
            return false, "Usage: /freecam <player> <true|false>"
        end
    end
})

minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    if freecam_data[name] then
        if freecam_data[name].clone then freecam_data[name].clone:remove() end
        if freecam_data[name].wield_clone then freecam_data[name].wield_clone:remove() end
        freecam_data[name] = nil
    end
end)

minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    local data = freecam_data[name]
    if data then
        if data.clone then
            data.clone:remove()
        end
        if data.wield_clone then
            data.wield_clone:remove()
        end
        freecam_data[name] = nil
    end
end)
