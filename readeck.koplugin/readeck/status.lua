local Status = {}

function Status.new_counts(initial)
    local counts = {
        remote_archived = 0,
        remote_deleted = 0,
        remote_progress_updated = 0,
        local_removed = 0,
        failed = 0,
    }
    for key, value in pairs(initial or {}) do
        counts[key] = value
    end
    return counts
end

function Status.add(target, source)
    target = target or Status.new_counts()
    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            target[key] = target[key] or {}
            for item_key, item_value in pairs(value) do
                target[key][item_key] = item_value
            end
        else
            target[key] = (target[key] or 0) + (tonumber(value) or 0)
        end
    end
    return target
end

function Status.total_remote(counts)
    counts = counts or {}
    return (counts.remote_archived or 0) + (counts.remote_deleted or 0)
end

return Status
