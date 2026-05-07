local Scheduler = {}

Scheduler.ASYNC = {}

local function noop() end

local function default_schedule(callback)
    callback()
end

function Scheduler.run(items, options)
    options = options or {}
    items = items or {}

    local state = {
        index = 1,
        running = 0,
        completed = 0,
        total = #items,
        cancelled = false,
    }

    local max_concurrent = math.max(1, tonumber(options.max_concurrent) or 1)
    local schedule = options.schedule or default_schedule
    local worker = options.worker or noop
    local on_result = options.on_result or noop
    local on_finish = options.on_finish or noop

    local launch
    local finished = false

    local function finish_if_done()
        if finished or state.cancelled then
            return
        end
        if state.completed >= state.total and state.running == 0 then
            finished = true
            on_finish(state)
        end
    end

    local function schedule_launch()
        schedule(launch, 0)
    end

    launch = function()
        if state.cancelled then
            return
        end

        while state.running < max_concurrent and state.index <= state.total do
            local item_index = state.index
            local item = items[item_index]
            state.index = state.index + 1
            state.running = state.running + 1

            local item_finished = false
            local function complete(result)
                if item_finished then
                    return
                end
                item_finished = true
                state.running = state.running - 1
                state.completed = state.completed + 1
                on_result(item, result, state, item_index)
                if state.completed < state.total then
                    schedule_launch()
                else
                    finish_if_done()
                end
            end

            local ok, result = pcall(worker, item, complete, state, item_index)
            if not ok then
                complete({ error = result })
            elseif result ~= Scheduler.ASYNC then
                complete(result)
            end
        end

        finish_if_done()
    end

    schedule_launch()
    return state
end

function Scheduler.cancel(state)
    if state then
        state.cancelled = true
    end
end

return Scheduler
