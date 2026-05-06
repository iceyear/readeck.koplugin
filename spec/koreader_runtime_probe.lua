local plugin_dir = os.getenv("READECK_PLUGIN_DIR") or arg[1]
assert(plugin_dir and plugin_dir ~= "", "READECK_PLUGIN_DIR is required")

package.path = "./?.lua;./?/init.lua;" .. plugin_dir .. "/?.lua;" .. package.path

dofile("setupkoenv.lua")
dofile("spec/front/unit/commonrequire.lua")

local Readeck = dofile(plugin_dir .. "/main.lua")

local menu_items = {}
Readeck.addToMainMenu({
    directory = "/tmp/readeck",
    filter_tag = "",
    sort_param = "-created",
    sort_options = {
        { "-created", "Added, most recent first" },
    },
    ignore_tags = "",
    auto_tags = "",
    completion_action_finished_enabled = true,
    completion_action_read_enabled = false,
    archive_instead_of_delete = true,
    process_completion_on_sync = false,
    remove_local_missing_remote = false,
    export_highlights_before_sync = true,
    auto_export_highlights = true,
    periodic_sync_enabled = false,
    periodic_sync_interval_minutes = 60,
    remote_star_threshold = 0,
    sync_star_rating_as_label = false,
    send_review_as_tags = false,
    remove_finished_from_history = false,
    remove_read_from_history = false,
    sync_star_status = false,
    auth_token = "",
    access_token = "",
    oauth_refresh_token = "",
    isempty = function(_, value)
        return value == nil or value == ""
    end,
    getArticleID = function()
        return nil
    end,
}, menu_items)

assert(menu_items.readeck, "Readeck menu item was not registered")
assert(menu_items.readeck.text == "Readeck", "unexpected Readeck menu title")
assert(type(menu_items.readeck.sub_item_table) == "table", "Readeck submenu is missing")

local function contains_menu_text(items, expected)
    for _, item in ipairs(items or {}) do
        local text = item.text
        if not text and item.text_func then
            text = item.text_func()
        end
        if text == expected then
            return true
        end
        if contains_menu_text(item.sub_item_table, expected) then
            return true
        end
    end
    return false
end

assert(contains_menu_text(menu_items.readeck.sub_item_table, "Highlights"), "Highlights submenu is missing")
assert(contains_menu_text(menu_items.readeck.sub_item_table, "Periodic sync"), "Periodic sync submenu is missing")
assert(contains_menu_text(menu_items.readeck.sub_item_table, "Configure Readeck client"), "client settings are missing")

print("KOReader runtime smoke passed")
