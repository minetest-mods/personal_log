local modname = minetest.get_current_modname()
local modpath = minetest.get_modpath(modname)
local ccompass_modpath = minetest.get_modpath("ccompass")
local default_modpath = minetest.get_modpath("default")
local modstore = minetest.get_mod_storage()

local ccompass_recalibration_allowed = minetest.settings:get_bool("ccompass_recalibrate", true)

local S = minetest.get_translator(modname)

local categories = {
	S("Location"),
	S("Event"),
	S("General"),
}

local LOCATION_CATEGORY = 1
local EVENT_CATEGORY = 2
local GENERAL_CATEGORY = 3

--------------------------------------------------------
-- Data store

local function get_state(player_name)
	local state = modstore:get(player_name .. "_state")
	if state then
		state = minetest.deserialize(state)
	end
	if not state then
		state = {category=LOCATION_CATEGORY, entry_selected={0,0,0}, entry_counts={0,0,0}}
	end
	return state
end

local function save_state(player_name, state)
	modstore:set_string(player_name .. "_state", minetest.serialize(state))
end

local function save_entry(player_name, category_index, entry_index, entry_text, topic_text)
	if topic_text then
		modstore:set_string(player_name .. "_category_" .. category_index .. "_entry_" .. entry_index .. "_topic",
			topic_text:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("\n", " "))
	end
	modstore:set_string(player_name .. "_category_" .. category_index .. "_entry_" .. entry_index .. "_content",
		entry_text:gsub("\r\n", "\n"):gsub("\r", "\n"))
end

local function swap(player_name, state, direction)
	local category_index = state.category
	local entry_index = state.entry_selected[category_index]
	local next_index = entry_index + direction
	if next_index < 1 or next_index > state.entry_counts[category_index] then
		return
	end
	
	local current_topic = modstore:get_string(player_name .. "_category_" .. category_index .. "_entry_" .. entry_index .. "_topic")
	local current_content = modstore:get_string(player_name .. "_category_" .. category_index .. "_entry_" .. entry_index .. "_content")
	local next_topic = modstore:get_string(player_name .. "_category_" .. category_index .. "_entry_" .. next_index .. "_topic")
	local next_content = modstore:get_string(player_name .. "_category_" .. category_index .. "_entry_" .. next_index .. "_content")

	save_entry(player_name, category_index, entry_index, next_content, next_topic)
	save_entry(player_name, category_index, next_index, current_content, current_topic)
	state.entry_selected[category_index] = next_index
	save_state(player_name, state)
end

local function delete(player_name, state)
	local category_index = state.category
	local entry_count = state.entry_counts[category_index]
	if entry_count == 0 then
		return
	end
	local entry_index = state.entry_selected[category_index]
	
	for i = entry_index + 1, entry_count do
		local topic = modstore:get_string(player_name .. "_category_" .. category_index .. "_entry_" .. i .. "_topic")
		local content = modstore:get_string(player_name .. "_category_" .. category_index .. "_entry_" .. i .. "_content")
		save_entry(player_name, category_index, i-1, content, topic)
	end
	
	modstore:set_string(player_name .. "_category_" .. category_index .. "_entry_" .. entry_count .. "_topic", "")
	modstore:set_string(player_name .. "_category_" .. category_index .. "_entry_" .. entry_count .. "_content", "")
	entry_count = entry_count - 1
	state.entry_counts[category_index] = entry_count
	if entry_index > entry_count then
		state.entry_selected[category_index] = entry_count
	end
	save_state(player_name, state)
end

----------------------------------------------------------------------------------------
-- String functions

local truncate_string = function(target, length)
	if target:len() > length then
		return target:sub(1,length-2).."..."
	end
	return target
end

local first_line = function(target)
	local first_return = target:find("\n")
	if not first_return then
		first_return = #target
	else
		first_return = first_return - 1 -- trim the hard return off
	end
	return target:sub(1, first_return)
end

---------------------------------------------------------------
-- Main formspec

local function make_personal_log_formspec(player)
	local player_name = player:get_player_name()

	local state = get_state(player_name)
	local category_index = state.category
	
	local formspec = {
		"formspec_version[2]"
		.."size[10,10]"
		.."dropdown[1.5,0.25;2,0.5;category_select;"
		.. table.concat(categories, ",") .. ";"..category_index.."]"
		.. "label[0.5,0.5;"..S("Category:").."]"
		.. "label[4.5,0.5;"..S("Personal Log Entries").."]"
	}
	
	local entries = {}
	for i = 1, state.entry_counts[category_index] do
		table.insert(entries, modstore:get_string(player_name .. "_category_" .. category_index .. "_entry_" .. i .. "_content"))
	end
	local entry = ""
	local entry_selected = state.entry_selected[category_index]
	if entry_selected > 0 then
		entry = entries[entry_selected]
	end

	local topics = {}
	for i = 1, state.entry_counts[category_index] do
		table.insert(topics, modstore:get_string(player_name .. "_category_" .. category_index .. "_entry_" .. i .. "_topic"))
	end
	local topic = ""
	if entry_selected > 0 then
		topic = topics[entry_selected]
	end
	
	formspec[#formspec+1] = "tablecolumns[text;text]table[0.5,1.0;9,4.75;log_table;"
	for i, entry in ipairs(entries) do
		formspec[#formspec+1] = minetest.formspec_escape(truncate_string(topics[i], 30)) .. ","
		formspec[#formspec+1] = minetest.formspec_escape(truncate_string(first_line(entry), 30))
		formspec[#formspec+1] = ","
	end
	formspec[#formspec] = ";"..entry_selected.."]" -- don't use +1, this overwrites the last ","
	
	if category_index == GENERAL_CATEGORY then
		formspec[#formspec+1] = "textarea[0.5,6.0;9,0.5;topic_data;;" .. minetest.formspec_escape(topic) .. "]"
		formspec[#formspec+1] = "textarea[0.5,6.5;9,1.75;entry_data;;".. minetest.formspec_escape(entry) .."]"
	else
		formspec[#formspec+1] = "textarea[0.5,6.0;9,2.25;entry_data;;".. minetest.formspec_escape(entry) .."]"
	end

	formspec[#formspec+1] = "container[0.5,8.5]"
		.."button[0,0;2,0.5;save;"..S("Save").."]"
		.."button[2,0;2,0.5;create;"..S("New").."]"
		.."button[4.5,0;2,0.5;move_up;"..S("Move Up").."]"
		.."button[4.5,0.5;2,0.5;move_down;"..S("Move Down").."]"
		.."button[7,0;2,0.5;delete;"..S("Delete") .."]"

	if default_modpath then
		formspec[#formspec+1] = "button[0,0.75;1.25,0.5;copy_to;"..S("To Book").."]"
			.."button[1.375,0.75;1.25,0.5;copy_from;"..S("From Book").."]"
	end
		
	if ccompass_modpath and category_index == LOCATION_CATEGORY then
		formspec[#formspec+1] = "button[2.75,0.75;1.25,0.5;set_ccompass;"..S("To Compass").."]"
	end

	formspec[#formspec+1] = "container_end[]"

	return table.concat(formspec)
end

---------------------------------------
-- Reading and writing stuff to items

-- Book parameters
local lpp = 14
local max_text_size = 10000
local max_title_size = 80
local short_title_size = 35
local function write_book(player_name)
	local state = get_state(player_name)
	local category = state.category
	local entry_selected = state.entry_selected[category]
	local content = modstore:get(player_name .. "_category_" .. category .. "_entry_" .. entry_selected .. "_content") or ""
	local topic = modstore:get(player_name .. "_category_" .. category .. "_entry_" .. entry_selected .. "_topic") or ""
	if state.category ~= 3 then
		-- If it's a location or an event, add a little context to the title
		topic = topic .. ": " .. first_line(content)
	end
	
	local new_book = ItemStack("default:book_written")
	local meta = new_book:get_meta()
	
	meta:set_string("owner", player_name)
	meta:set_string("title", topic:sub(1, max_title_size))
	meta:set_string("description", S("\"@1\" by @2", truncate_string(topic, short_title_size), player_name))
	meta:set_string("text", content:sub(1, max_text_size))
	meta:set_int("page", 1)
	meta:set_int("page_max", math.ceil((#content:gsub("[^\n]", "") + 1) / lpp))
	return new_book
end

local function read_book(itemstack, player_name)
	local meta = itemstack:get_meta()
	local topic = meta:get_string("title")
	local content = meta:get_string("text")

	local date_string = topic:match("^%d%d%d%d%-%d%d%-%d%d")
	local pos_string = topic:match("^%(%-?[0-9]+,%-?[0-9]+,%-?[0-9]+%)")
	
	local category = GENERAL_CATEGORY
	if date_string then
		topic = date_string
		category = EVENT_CATEGORY
	elseif pos_string then
		topic = pos_string
		category = LOCATION_CATEGORY
	end
	
	local state = get_state(player_name)
	local entry_index = state.entry_counts[category] + 1
	state.entry_counts[category] = entry_index
	save_entry(player_name, category, entry_index, content, topic)
	save_state(player_name, state)
end

local function set_ccompass(player_name, old_compass)
	local old_pos = old_compass:get_meta():get_string("target_pos")
	if not ccompass_recalibration_allowed and old_pos ~= "" then
		minetest.chat_send_player(player_name, S("Compass is already calibrated."))
		return
	end

	local state = get_state(player_name)
	local category = state.category
	if category ~= LOCATION_CATEGORY then
		return
	end
	local entry_selected = state.entry_selected[category]
	local topic = modstore:get(player_name .. "_category_" .. category .. "_entry_" .. entry_selected .. "_topic") or ""
	local pos = minetest.string_to_pos(topic)
	if not pos then
		return
	end
	
	local content = modstore:get(player_name .. "_category_" .. category .. "_entry_" .. entry_selected .. "_content") or ""
	content = truncate_string(first_line(content), max_title_size)
	local new_ccompass = ItemStack("ccompass:0")
	local param = {
		target_pos_string = topic,
		target_name = content,
		playername = player_name
	}
	ccompass.set_target(new_ccompass, param)
	return new_ccompass
end

local ccompass_prefix = "ccompass:"
local ccompass_prefix_length = #ccompass_prefix
local detached_callbacks = {
	allow_put = function(inv, listname, index, stack, player)
		if listname == "write_book" then
			if stack:get_name() == "default:book" then
				return 1
			end
			return 0
		elseif listname == "read_book" then
			if stack:get_name() == "default:book_written" then
				return 1
			end
			return 0
		elseif listname == "set_ccompass" then
			if stack:get_name():sub(1,ccompass_prefix_length) == ccompass_prefix then
				return 1
			end
			return 0
		end
	end,
    on_put = function(inv, listname, index, stack, player)
		local player_name = player:get_player_name()
		if listname == "write_book" then
			inv:remove_item(listname, stack)		
			inv:add_item(listname, write_book(player_name))
		elseif listname == "read_book" then
			read_book(stack, player_name)
		elseif listname == "set_ccompass" then
			local new_ccompass = set_ccompass(player_name, stack)
			if new_ccompass then
				inv:remove_item(listname, stack)
				inv:add_item(listname, new_ccompass)
			end
		end
	end,
}

local item_invs = {}
local function item_formspec(player_name, label, listname)
	if not item_invs[player_name] then
		local inv = minetest.create_detached_inventory("personal_log_"..player_name, detached_callbacks)
		if default_modpath then
			inv:set_size("write_book", 1)
			inv:set_size("read_book", 1)
		end
		if ccompass_modpath then
			inv:set_size("set_ccompass", 1)
		end
		item_invs[player_name] = true
	end

	local formspec = "size[8,6]"
		.. "label[1,0.25;" .. label .. "]"
		.. "list[detached:personal_log_"..player_name..";"..listname..";3.5,0;1,1;]"
		.. "list[current_player;main;0,1.5;8,4;]"
		.. "listring[]"
		.. "button[3.5,5.5;1,1;back;"..S("Back").."]"
		
	return formspec
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "personal_log:item" then
		return
	end
	if fields.back then
		minetest.show_formspec(player:get_player_name(),"personal_log:root", make_personal_log_formspec(player))
	end
end)

-------------------------------------------

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "personal_log:root" then
		return
	end
	local player_name = player:get_player_name()
	local player_pos = player:get_pos()
	local state = get_state(player_name)
	local category = state.category
	local entry_selected = state.entry_selected[category]

	if fields.log_table then
		local table_event = minetest.explode_table_event(fields.log_table)
		if table_event.type == "CHG" then
			state.entry_selected[category] = table_event.row
			save_state(player_name, state)
			minetest.show_formspec(player_name,"personal_log:root", make_personal_log_formspec(player))
			return
		end
	end
	
	if fields.save then
		if category == GENERAL_CATEGORY then
			save_entry(player_name, category, entry_selected, fields.entry_data, fields.topic_data)
		else
			save_entry(player_name, category, entry_selected, fields.entry_data)
		end
		minetest.show_formspec(player_name,"personal_log:root", make_personal_log_formspec(player))
		return
	end
	
	if fields.create then
		local content = ""
		local general_topic = ""
		if entry_selected == 0 then
			content = fields.entry_data
			general_topic = fields.topic_data
		end
		
		local entry_index = state.entry_counts[category] + 1
		state.entry_counts[category] = entry_index
		state.entry_selected[category] = entry_index
		if category == LOCATION_CATEGORY then
			local pos = vector.round(player:get_pos())
			save_entry(player_name, category, entry_index, content, minetest.pos_to_string(pos))
		elseif category == EVENT_CATEGORY then
			local current_date = os.date("%Y-%m-%d")
			save_entry(player_name, category, entry_index, content, current_date)
		else
			save_entry(player_name, category, entry_index, content, general_topic)
		end
		save_state(player_name, state)
		minetest.show_formspec(player_name,"personal_log:root", make_personal_log_formspec(player))
		return
	end
	
	if fields.move_up then
		swap(player_name, state, -1)
		minetest.show_formspec(player_name,"personal_log:root", make_personal_log_formspec(player))
		return
	end
	if fields.move_down then
		swap(player_name, state, 1)
		minetest.show_formspec(player_name,"personal_log:root", make_personal_log_formspec(player))
		return
	end
	if fields.delete then
		delete(player_name, state)
		minetest.show_formspec(player_name,"personal_log:root", make_personal_log_formspec(player))
		return
	end

	if fields.copy_to then
		minetest.show_formspec(player_name, "personal_log:item",
			item_formspec(player_name, S("Copy log to blank book:"), "write_book"))
		return
	end
	if fields.copy_from then
		minetest.show_formspec(player_name, "personal_log:item",
			item_formspec(player_name, S("Copy log from written book:"), "read_book"))
		return
	end
	if fields.set_ccompass then
		minetest.show_formspec(player_name, "personal_log:item",
			item_formspec(player_name, S("Set a compass to this location:"), "set_ccompass"))
		return
	end
	
	-- Do this one last, since it should always be true and we don't want to do it if we don't have to
	if fields.category_select then
		for i, category in ipairs(categories) do
			if category == fields.category_select then
				if state.category ~= i then
					state.category = i
					save_state(player_name, state)
					minetest.show_formspec(player_name,"personal_log:root", make_personal_log_formspec(player))
					return
				else
					break
				end
			end
		end
	end
end)


-------------------------------------------------------------------------------------------------------


-- Unified Inventory
if minetest.get_modpath("unified_inventory") then
	unified_inventory.register_button("personal_log", {
		type = "image",
		image = "personal_log_open_book.png",
		tooltip = S("Your personal log for keeping track of what happens where"),
		action = function(player)
			local name = player:get_player_name()
			minetest.show_formspec(name,"personal_log:root", make_personal_log_formspec(player))
		end,
	})
end

-- sfinv_buttons
if minetest.get_modpath("sfinv_buttons") then
	sfinv_buttons.register_button("personal_log", {
		image = "personal_log_open_book.png",
		tooltip = S("Your personal log for keeping track of what happens where"),
		title = S("Log"),
		action = function(player)
			local name = player:get_player_name()
			minetest.show_formspec(name,"personal_log:root", make_personal_log_formspec(player))
		end,
	})
elseif minetest.get_modpath("sfinv") then
	sfinv.register_page("personal_log:personal_log", {
		title = S("Log"),
		get = function(_, player, context)
			local name = player:get_player_name()
			minetest.show_formspec(name,"personal_log:root", make_personal_log_formspec(player))
			return sfinv.make_formspec(player, context, "button[2.5,3;3,1;open_personal_log;"..S("Open personal log").."]", false)
		end,
		on_player_receive_fields = function(_, player, _, fields)
			local name = player:get_player_name()
			if fields.open_personal_log then
				minetest.show_formspec(name,"personal_log:root", make_personal_log_formspec(player))
				return true
			end
		end
	})
end
