local Api = require("readeck.net.api")
local Highlights = require("readeck.annotations.highlights")
local JSON = require("json")

local LinkedSync = {}

function LinkedSync.find_remote_by_id(remote_highlights, annotation_id)
    annotation_id = tostring(annotation_id or "")
    if annotation_id == "" then
        return nil
    end
    for index, remote_highlight in ipairs(remote_highlights or {}) do
        if tostring(remote_highlight.id or "") == annotation_id then
            return remote_highlight, index
        end
    end
    return nil
end

function LinkedSync.replace_remote(remote_highlights, annotation_id, replacement)
    local _, index = LinkedSync.find_remote_by_id(remote_highlights, annotation_id)
    if index and type(replacement) == "table" then
        remote_highlights[index] = replacement
    end
end

function LinkedSync.extract_updated_remote(result, annotation_id)
    if type(result) ~= "table" then
        return nil
    end
    if tostring(result.id or "") == tostring(annotation_id or "") then
        return result
    end
    if type(result.annotations) == "table" then
        return LinkedSync.find_remote_by_id(result.annotations, annotation_id)
    end
    return nil
end

function LinkedSync.patch_remote(plugin, article_id, annotation_id, update_payload)
    local bodyJSON = JSON.encode(update_payload)
    local headers = {
        ["Content-type"] = "application/json",
        ["Accept"] = "application/json, */*",
        ["Content-Length"] = tostring(#bodyJSON),
        ["Authorization"] = "Bearer " .. plugin.access_token,
    }
    return plugin:callAPI("PATCH", Api.paths.annotation(article_id, annotation_id), headers, bodyJSON, "", true)
end

function LinkedSync.apply_plan(local_highlight, plan, profile)
    local changed = false
    local previous_note = local_highlight.readeck_synced_note
    local previous_color = local_highlight.readeck_synced_color

    if plan.local_update then
        if plan.local_update.note ~= nil then
            changed = Highlights.set_local_note(local_highlight, plan.local_update.note) or changed
        end
        if plan.local_update.color ~= nil then
            changed = Highlights.set_local_color(local_highlight, plan.local_update.color) or changed
        end
    end

    Highlights.apply_sync_snapshot(local_highlight, plan.snapshot, profile)
    local snapshot_changed = previous_note ~= local_highlight.readeck_synced_note
        or previous_color ~= local_highlight.readeck_synced_color
    return changed, snapshot_changed
end

local function merge_remote_update(remote_highlight, update_payload)
    local updated_remote = {}
    for key, value in pairs(remote_highlight) do
        updated_remote[key] = value
    end
    for key, value in pairs(update_payload) do
        updated_remote[key] = value
    end
    return updated_remote
end

function LinkedSync.sync(plugin, article_id, local_highlight, remote_highlight, profile, counts, remote_highlights)
    local policy = plugin.highlight_conflict_policy or "merge"
    local plan = Highlights.plan_linked_sync(local_highlight, remote_highlight, profile, policy)

    if plan.remote_update then
        local result = LinkedSync.patch_remote(plugin, article_id, remote_highlight.id, plan.remote_update)
        if result then
            counts.updated_remote = counts.updated_remote + 1
            local updated_remote = LinkedSync.extract_updated_remote(result, remote_highlight.id)
                or merge_remote_update(remote_highlight, plan.remote_update)
            updated_remote.id = updated_remote.id or remote_highlight.id
            LinkedSync.replace_remote(remote_highlights, remote_highlight.id, updated_remote)
        else
            counts.error = counts.error + 1
            return false
        end
    end

    local changed, snapshot_changed = LinkedSync.apply_plan(local_highlight, plan, profile)
    if changed then
        counts.updated_local = counts.updated_local + 1
    end
    if plan.conflict then
        counts.conflicts = counts.conflicts + 1
    end
    return changed or snapshot_changed or plan.remote_update ~= nil
end

return LinkedSync
