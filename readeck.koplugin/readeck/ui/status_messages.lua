local Status = require("readeck.sync.status")

local StatusMessages = {}

function StatusMessages.install(Readeck, deps)
    local L = deps.L
    local T = deps.T

    function Readeck:formatLocalProcessingMessage(counts)
        counts = counts or Status.new_counts()
        local parts = { L("Articles processed.") }
        if (counts.remote_archived or 0) > 0 then
            table.insert(parts, T(L("Archived in Readeck: %1"), counts.remote_archived))
        end
        if (counts.remote_deleted or 0) > 0 then
            table.insert(parts, T(L("Deleted from Readeck: %1"), counts.remote_deleted))
        end
        if (counts.local_removed or 0) > 0 then
            table.insert(parts, T(L("Removed from KOReader: %1"), counts.local_removed))
        end
        if (counts.failed or 0) > 0 then
            table.insert(parts, T(L("Failed: %1"), counts.failed))
        end
        if #parts == 1 then
            table.insert(parts, L("No local articles needed processing."))
        end
        return table.concat(parts, "\n")
    end

    function Readeck:appendCompletionResultParts(parts, counts)
        if (counts.remote_archived or 0) > 0 then
            table.insert(parts, T(L("Archived in Readeck: %1"), counts.remote_archived))
        end
        if (counts.remote_deleted or 0) > 0 then
            table.insert(parts, T(L("Deleted from Readeck: %1"), counts.remote_deleted))
        end
        if (counts.remote_progress_updated or 0) > 0 then
            table.insert(parts, T(L("Reading progress synced: %1"), counts.remote_progress_updated))
        end
        if (counts.local_progress_updated or 0) > 0 then
            table.insert(parts, T(L("KOReader progress updated: %1"), counts.local_progress_updated))
        end
        if (counts.highlights_imported or 0) > 0 then
            table.insert(parts, T(L("Highlights imported: %1"), counts.highlights_imported))
        end
        if (counts.highlights_exported or 0) > 0 then
            table.insert(parts, T(L("Highlights exported: %1"), counts.highlights_exported))
        end
        if (counts.highlights_local_only or 0) > 0 then
            table.insert(parts, T(L("Highlights kept local only: %1"), counts.highlights_local_only))
        end
        if (counts.highlights_skipped or 0) > 0 then
            table.insert(parts, T(L("Highlights skipped: %1"), counts.highlights_skipped))
        end
        if (counts.highlights_failed or 0) > 0 then
            table.insert(parts, T(L("Highlight sync failed: %1"), counts.highlights_failed))
        end
        if (counts.local_removed or 0) > 0 then
            table.insert(parts, T(L("Removed from KOReader: %1"), counts.local_removed))
        end
        if (counts.completion_actions_disabled or 0) > 0 then
            table.insert(parts, L("Completion actions skipped during sync."))
        end
    end

    function Readeck:formatSyncMessage(downloaded_count, skipped_count, failed_count, counts)
        counts = counts or Status.new_counts()
        local parts = { L("Processing finished.") }
        table.insert(parts, T(L("Downloaded: %1"), downloaded_count or 0))
        table.insert(parts, T(L("Skipped: %1"), skipped_count or 0))
        if (failed_count or 0) > 0 then
            table.insert(parts, T(L("Failed: %1"), failed_count))
        end
        self:appendCompletionResultParts(parts, counts)
        if (counts.failed or 0) > 0 then
            table.insert(parts, T(L("Completion action failed: %1"), counts.failed))
        end
        return table.concat(parts, "\n")
    end

    function Readeck:formatDownloadProgressMessage(counts, total, action_counts)
        counts = counts or {}
        action_counts = action_counts or {}
        local parts = {
            T(L("Syncing articles… %1/%2 checked"), counts.completed or 0, total or 0),
            table.concat({
                T(L("Downloaded: %1"), counts.downloaded or 0),
                T(L("Skipped: %1"), counts.skipped or 0),
                T(L("Failed: %1"), counts.failed or 0),
            }, "  "),
        }
        self:appendCompletionResultParts(parts, action_counts)
        return table.concat(parts, "\n")
    end

    function Readeck:formatCompletionPlanMessage(plan)
        plan = plan or {}
        local parts = { L("Processing local completion actions…") }
        if (plan.remote_archive_candidates or 0) > 0 then
            table.insert(parts, T(L("Will archive in Readeck: %1"), plan.remote_archive_candidates))
        end
        if (plan.remote_delete_candidates or 0) > 0 then
            table.insert(parts, T(L("Will delete from Readeck: %1"), plan.remote_delete_candidates))
        end
        if (plan.local_remove_candidates or 0) > 0 then
            table.insert(parts, T(L("Will remove from KOReader: %1"), plan.local_remove_candidates))
        end
        if (plan.remote_progress_candidates or 0) > 0 then
            table.insert(parts, T(L("Will sync reading progress: %1"), plan.remote_progress_candidates))
        end
        if #parts == 1 then
            table.insert(parts, L("No local articles needed processing."))
        end
        return table.concat(parts, "\n")
    end
end

return StatusMessages
