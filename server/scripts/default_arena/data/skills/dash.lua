-- Dash Skill Data
-- Habilidade de movimento rápido em linha reta (teleporte instantâneo)
local function get_coords(pos)
    if not pos then return 0, 0 end
    if type(pos.x_float) == "function" then
        return pos:x_float(), pos:y_float()
    elseif pos.x and pos.y then
        return pos.x, pos.y
    end
    return 0, 0
end

return {
    id = "dash",
    name = "Dash",
    description = "Movimento rápido em linha reta",
    mana_cost = 0,
    cooldown = 30, -- 1s a 30Hz
    range = 25, -- Distância do dash em unidades
    damage = 0,
    damage_type = nil,

    on_execute = function(entity_id, aim_x, aim_y, skill_data)
        local pos = Loci.get_entity_position(entity_id)
        local caster_x, caster_y = get_coords(pos)

        -- Normalizar direção
        local len = math.sqrt(aim_x * aim_x + aim_y * aim_y)
        if len < 0.01 then
            return false, "Direção inválida para dash"
        end
        local dir_x = aim_x / len
        local dir_y = aim_y / len

        -- Calcular nova posição
        local new_x = caster_x + dir_x * skill_data.range
        local new_y = caster_y + dir_y * skill_data.range

        -- Teleportar jogador
        Loci.Commands.set_position(entity_id, { x = new_x, y = new_y })

        Loci.Log.info(string.format("[Dash] Executado por %s: (%.1f, %.1f) -> (%.1f, %.1f)", 
            tostring(entity_id), caster_x, caster_y, new_x, new_y))
        return true
    end
}
