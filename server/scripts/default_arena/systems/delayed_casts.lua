-- Delayed Casts System (Authoritative Server)
-- Agenda efeitos de habilidade com impacto retardado (ex.: meteor_strike com aviso visual,
-- earthquake_slam que resolve no tick de aterrissagem do salto).
-- Cada entrada é { execute_tick, fn }; fn é chamada sem argumentos no primeiro tick >= execute_tick.

local DelayedCasts = {}

-- Fila determinística (array) processada em update_tick. O sandbox restringe `pairs`,
-- então a fila é iterada com ipairs de trás para frente para remoção segura.
local pending = {}

--- Agenda uma função para executar no tick indicado (ou imediatamente se já vencido).
function DelayedCasts.schedule(execute_tick, fn)
    assert(type(fn) == "function", "DelayedCasts.schedule expects a function")
    table.insert(pending, {
        execute_tick = tonumber(execute_tick) or 0,
        fn = fn,
    })
end

--- Executa todos os efeitos agendados cujo tick já chegou.
function DelayedCasts.update_tick(current_tick)
    current_tick = tonumber(current_tick) or 0
    for i = #pending, 1, -1 do
        local entry = pending[i]
        if current_tick >= entry.execute_tick then
            table.remove(pending, i)
            local ok, err = pcall(entry.fn)
            if not ok and Loci and Loci.Log then
                Loci.Log.error("[DelayedCasts] Falha ao executar efeito agendado: " .. tostring(err))
            end
        end
    end
end

--- Quantidade de efeitos ainda pendentes (útil para testes).
function DelayedCasts.pending_count()
    return #pending
end

--- Limpa a fila (útil para testes).
function DelayedCasts.clear()
    pending = {}
end

return DelayedCasts
