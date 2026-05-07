local Progress = {}

local function round(value)
    return math.floor(value + 0.5)
end

function Progress.percent_finished_to_readeck_progress(percent_finished)
    percent_finished = tonumber(percent_finished)
    if not percent_finished then
        return nil
    end
    local progress
    if percent_finished <= 1 then
        progress = round(percent_finished * 100)
    else
        progress = round(percent_finished)
    end
    return math.max(0, math.min(100, progress))
end

function Progress.readeck_progress_to_percent_finished(read_progress)
    read_progress = tonumber(read_progress)
    if not read_progress then
        return nil
    end
    read_progress = math.max(0, math.min(100, round(read_progress)))
    return read_progress / 100
end

function Progress.should_update_local_percent(local_percent_finished, remote_read_progress)
    local remote_progress = Progress.percent_finished_to_readeck_progress(
        Progress.readeck_progress_to_percent_finished(remote_read_progress)
    )
    if not remote_progress or remote_progress <= 0 or remote_progress >= 100 then
        return false
    end

    local local_progress = Progress.percent_finished_to_readeck_progress(local_percent_finished)
    return not local_progress or remote_progress > local_progress
end

function Progress.should_update_remote_percent(local_percent_finished, remote_read_progress)
    local local_progress = Progress.percent_finished_to_readeck_progress(local_percent_finished)
    if not local_progress or local_progress <= 0 or local_progress >= 100 then
        return false
    end

    local remote_progress = Progress.percent_finished_to_readeck_progress(
        Progress.readeck_progress_to_percent_finished(remote_read_progress)
    )
    return not remote_progress or local_progress > remote_progress
end

return Progress
