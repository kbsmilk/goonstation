// balance defines
#define REBUILD_COST_OBJECT_METAL 0.9 // each of these measured in sheets.
#define REBUILD_COST_OBJECT_CRYSTAL 1.5
#define REBUILD_COST_TURF_METAL 1
#define REBUILD_COST_TURF_CRYSTAL 0.5
#define BAR_SHEET_VALUE 10
// code defines
#define SELECT_SKIP 0
#define SELECT_FIRST_CORNER 1
#define DESELECT_FIRST_CORNER 2
#define SELECT_SECOND_CORNER 3
#define DESELECT_SECOND_CORNER 4

/obj/abcuMarker
	desc = "Denotes a valid tile."
	icon = 'icons/obj/objects.dmi'
	name = "Building marker (valid)"
	icon_state = "bmarker"
	anchored = ANCHORED
	density = 0
	layer = TURF_LAYER

/obj/abcuMarker/red
	desc = "Denotes an invalid tile."
	icon = 'icons/obj/objects.dmi'
	name = "Building marker (invalid)"
	icon_state = "bmarkerred"
	anchored = ANCHORED
	density = 0
	layer = TURF_LAYER

/obj/machinery/abcu
	icon = 'icons/obj/objects.dmi'
	icon_state = "builder"
	name = "\improper ABC Unit"
	desc = "An Automated Blueprint Construction Unit. \
		This fine piece of machinery can construct entire rooms from blueprints."
	density = 1
	opacity = 0
	anchored = UNANCHORED
	processing_tier = PROCESSING_FULL

	var/invalid_count = 0
	var/building = FALSE
	var/build_index = 1
	var/build_end = 0
	var/list/markers = list()
	var/list/apc_list = list()
	var/metal_owed = 0
	var/crystal_owed = 0
	var/tile_cost_processed = FALSE

	var/datum/abcu_blueprint/current_bp = null
	var/locked = FALSE
	var/paused = FALSE
	var/off_x = 0
	var/off_y = 0

	New()
		..()
		UnsubscribeProcess()

	examine()
		. = ..()
		if (current_bp)
			. += "<br><span class='notice'>Someone has uploaded a blueprint named '[current_bp.room_name]'.</span>"

	attack_ai(mob/user)
		boutput(user, "<span class='alert'>This machine is not linked to your network.</span>")
		return

	attackby(obj/item/W, mob/user)
		if (istype(W, /obj/item/sheet) || istype(W, /obj/item/material_piece))
			boutput(user, "<span class='notice'>You insert the material into the machine.</span>")
			user.drop_item()
			W.set_loc(src)
			return
		. = ..()

	attack_hand(mob/user)
		if(src.building && !src.paused)
			if (tgui_alert(user, "Pause the construction?", "ABCU", list("Yes", "No")) == "Yes")
				src.pause_build()
			return

		var/list/option_list = list(
			"Check Materials",
			"Resume Construction",
			src.locked ? "Unlock" : "Lock",
			"Begin Building",
			"Dump Materials",
			"Select Blueprint",
			"Cancel Build",
		)
		var/input_list_desc = "Select an action."
		if (src.current_bp) input_list_desc += " Loaded blueprint: [src.current_bp.room_name]"
		var/user_input = tgui_input_list(user, src.building ? "The build job is currently paused. Choose:" : input_list_desc, "ABCU", option_list)
		if (!user_input) return

		switch(user_input)
			if("Unlock")
				if (src.building)
					boutput(user, "<span class='alert'>Lock status can't be changed with a build in progress.</span>")
					return
				if(!src.locked) return
				src.deactivate()

			if("Lock")
				if (src.building)
					boutput(user, "<span class='alert'>Lock status can't be changed with a build in progress.</span>")
					return
				if(src.locked) return
				if(!src.current_bp)
					boutput(user, "<span class='alert'>The machine requires a blueprint before it can be locked.</span>")
					return
				src.activate(user)

			if("Begin Building")
				if(src.building)
					boutput(user, "<span class='alert'>A build job is already in progress.</span>")
					return
				if(!src.locked)
					boutput(user, "<span class='alert'>The machine must be locked into place before activating it.</span>")
					return
				if(!src.current_bp)
					boutput(user, "<span class='alert'>The machine requires a blueprint before it can build anything.</span>")
					return
				src.prepare_build(user)

			if("Select Blueprint")
				src.get_blueprint(user)

			if("Dump Materials")
				for(var/obj/o in src)
					if(o == src.current_bp) continue
					o.set_loc(src.loc)

			if("Check Materials")
				src.audit_inventory(user)

			if ("Resume Construction")
				if (!src.building)
					boutput(user, "<span class='alert'>There's no build in progress.</span>")
					return
				if (!src.paused)
					boutput(user, "<span class='alert'>[src] is already unpaused.</span>")
					return
				src.unpause_build()

			if ("Cancel Build")
				if (!src.building)
					boutput(user, "<span class='alert'>There's no build in progress.</span>")
					return
				src.end_build()
		return

	process()
		..()
		if (!src.building) return
		if (src.build_index > src.build_end)
			src.end_build()
			return

		var/datum/tileinfo/tile = src.current_bp.roominfo[src.build_index]
		if (isnull(tile.tiletype))
			src.build_index++
			return

		// try to consume materials for this tile
		if (!src.tile_cost_processed)
			var/obj_count = length(tile.objects)
			src.metal_owed += REBUILD_COST_TURF_METAL + REBUILD_COST_OBJECT_METAL * obj_count
			src.crystal_owed += REBUILD_COST_TURF_CRYSTAL + REBUILD_COST_OBJECT_CRYSTAL * obj_count
			src.tile_cost_processed = TRUE
		for (var/obj/item in src)
			if (src.metal_owed <= 0 && src.crystal_owed <= 0) break
			if (item == src.current_bp) continue

			if (istype(item, /obj/item/sheet))
				var/obj/item/sheet/sheets = item
				if (!sheets.material) continue
				if (src.metal_owed && sheets.material.getMaterialFlags() & MATERIAL_METAL)
					var/sheets_consumed = ceil(min(sheets.amount, src.metal_owed))
					sheets.change_stack_amount(-sheets_consumed)
					src.metal_owed -= sheets_consumed
					continue
				if (src.crystal_owed && sheets.material.getMaterialFlags() & MATERIAL_CRYSTAL)
					var/sheets_consumed = ceil(min(sheets.amount, src.crystal_owed))
					sheets.change_stack_amount(-sheets_consumed)
					src.crystal_owed -= sheets_consumed
					continue

			else if (istype(item, /obj/item/material_piece))
				var/obj/item/material_piece/bars = item
				if (!bars.material) continue
				if (src.metal_owed && bars.material.getMaterialFlags() & MATERIAL_METAL)
					var/bars_consumed = ceil(min(bars.amount, src.metal_owed / BAR_SHEET_VALUE))
					bars.change_stack_amount(-bars_consumed)
					src.metal_owed -= bars_consumed * BAR_SHEET_VALUE
					continue
				if (src.crystal_owed && bars.material.getMaterialFlags() & MATERIAL_CRYSTAL)
					var/bars_consumed = ceil(min(bars.amount, src.crystal_owed / BAR_SHEET_VALUE))
					bars.change_stack_amount(-bars_consumed)
					src.crystal_owed -= bars_consumed * BAR_SHEET_VALUE
					continue

		if (src.metal_owed > 0 || src.crystal_owed > 0)
			src.pause_build()
			src.visible_message("<span class='alert'>[src] does not have enough materials to continue construction.</span>")
			playsound(src.loc, 'sound/machines/buzz-sigh.ogg', 20)
			return
		// now build the tile if we paid for it
		var/turf/pos = locate(text2num(tile.posx) + src.x,text2num(tile.posy) + src.y, src.z)
		for(var/obj/O in src.markers)
			if(O.loc == pos)
				qdel(O)
				break

		src.make_tile(tile, pos)
		src.tile_cost_processed = FALSE
		src.build_index++

	proc/make_tile(var/datum/tileinfo/tile, var/turf/pos)
		set waitfor = 0
		SPAWN(0)
			var/obj/overlay/V = new/obj/overlay(pos)
			V.icon = 'icons/obj/objects.dmi'
			V.icon_state = "buildeffect"
			V.name = "energy"
			V.anchored = ANCHORED
			V.set_density(0)
			V.layer = EFFECTS_LAYER_BASE

			sleep(1.5 SECONDS)

			qdel(V)

			if(tile.tiletype != null)
				var/turf/new_tile = pos
				new_tile.ReplaceWith(tile.tiletype)
				new_tile.icon_state = tile.state
				new_tile.set_dir(tile.direction)
				new_tile.inherit_area()

			for(var/datum/objectinfo/O in tile.objects)
				if (O.objecttype == null) continue
				if (ispath(O.objecttype, /obj/machinery/power/apc))
					src.apc_list[O] = pos
					continue
				var/list/properties = list(
					"layer" = O.layer,
					"pixel_x" = O.px,
					"pixel_y" = O.py,
					"dir" = O.direction)
				if (!isnull(O.icon_state)) properties["icon_state"] = O.icon_state // required for old blueprint support
				new/dmm_suite/preloader(pos, properties) // this doesn't spawn the objects, only presets their properties
				new O.objecttype(pos) // need this part to also spawn the objects

	proc/prepare_build(mob/user)
		if(src.invalid_count)
			boutput(usr, "<span class='alert'>The machine can not build on anything but empty space. Check for red markers.</span>")
			return

		src.build_end = length(src.current_bp.roominfo)
		if (src.build_end <= 0)
			return

		src.building = TRUE
		src.paused = FALSE
		src.build_index = 1
		src.icon_state = "builder1"
		SubscribeToProcess()
		src.visible_message("<span class='notice'>[src] starts to buzz and vibrate. The operation light blinks on.</span>")
		logTheThing(LOG_STATION, src, "[user] started ABCU build at [log_loc(src)], with blueprint [src.current_bp.room_name], authored by [src.current_bp.author]")

	proc/end_build()
		for (var/datum/objectinfo/N in src.apc_list)
			new N.objecttype(src.apc_list[N])
		src.apc_list = new/list

		src.building = FALSE
		UnsubscribeProcess()
		src.deactivate()

		src.icon_state = "builder"
		makepowernets()
		src.visible_message("<span class='notice'>[src] whirrs to a stop. The operation light flashes twice and turns off.</span>")

	proc/audit_inventory(mob/user)
		var/metal_count = 0
		var/crystal_count = 0
		for(var/obj/O in src)
			if(O == src.current_bp) continue
			if (istype(O, /obj/item/sheet))
				var/obj/item/sheet/sheets = O
				if (!sheets.material) continue
				if (sheets.material.getMaterialFlags() & MATERIAL_METAL)
					metal_count += sheets.amount
				if (sheets.material.getMaterialFlags() & MATERIAL_CRYSTAL)
					crystal_count += sheets.amount
			else if (istype(O, /obj/item/material_piece))
				var/obj/item/material_piece/bars = O
				if (!bars.material) continue
				if (bars.material.getMaterialFlags() & MATERIAL_METAL)
					metal_count += bars.amount * BAR_SHEET_VALUE
				if (bars.material.getMaterialFlags() & MATERIAL_CRYSTAL)
					crystal_count += bars.amount * BAR_SHEET_VALUE
		if (user)
			var/message = "<span class='notice'>The machine is holding [metal_count] metal, and [crystal_count] crystal, measured in sheets.</span>"
			if (src.current_bp)
				message += "<br><span class='notice'>Its current blueprint requires [src.current_bp.cost_metal] metal,"
				message += " and [src.current_bp.cost_crystal] crystal, measured in sheets.</span>"
			boutput(user, message)
		return list(metal_count, crystal_count)

	proc/unpause_build()
		src.paused = FALSE
		src.icon_state = "builder1"
		SubscribeToProcess()
		src.visible_message("<span class='notice'>[src] starts to buzz and vibrate.</span>")

	proc/pause_build()
		src.paused = TRUE
		src.icon_state = "builder"
		UnsubscribeProcess()
		src.visible_message("<span class='notice'>[src] releases a small puff of steam, then quiets down.</span>")

	proc/deactivate()
		for(var/obj/O in src.markers)
			qdel(O)
		src.locked = FALSE
		src.anchored = UNANCHORED
		src.visible_message("[src] disengages its anchors.")

	proc/activate(mob/user)
		src.locked = TRUE
		src.anchored = ANCHORED
		src.invalid_count = 0
		for(var/datum/tileinfo/T in src.current_bp.roominfo)
			var/turf/pos = locate(text2num(T.posx) + src.x,text2num(T.posy) + src.y, src.z)
			var/obj/abcuMarker/O = null

			if(istype(pos, /turf/space))
				O = new/obj/abcuMarker(pos)
			else
				O = new/obj/abcuMarker/red(pos)
				src.invalid_count++

			src.markers.Add(O)
		boutput(user, "<span class='notice'>Building this will require [src.current_bp.cost_metal] metal and [src.current_bp.cost_crystal] glass sheets.</span>")
		src.visible_message("[src] locks into place and begins humming softly.")

	proc/get_blueprint(mob/user, var/savepath = "")
		if(src.locked || src.building)
			boutput(user, "<span class='alert'>You can't load a different blueprint while the machine is locked or building.</span>")
			return
		var/datum/abcu_blueprint/load
		if (savepath)
			load = load_abcu_blueprint(user, savepath)
		else
			load = load_abcu_blueprint(user)
		if (load?.room_name)
			src.current_bp = load

/datum/objectinfo
	var/objecttype = null
	var/direction = 0
	var/layer = 0
	var/px = 0
	var/py = 0
	var/icon_state = ""

/datum/tileinfo
	var/list/objects = new/list()
	var/state = ""
	var/direction = 0
	var/tiletype = null
	var/posx = 0
	var/posy = 0
	var/icon = ""

/verb/adminCreateBlueprint()
	set name = "Blueprint Create"
	set desc = "Allows creation of blueprints of any user."
	SET_ADMIN_CAT(ADMIN_CAT_FUN)

	var/picked = browse_abcu_blueprints(usr, "Admin Share Blueprint", "Choose a blueprint to print and share!", TRUE)
	if (!picked) return
	var/obj/printed = new /obj/item/abcu_blueprint_reference(usr, picked["path"])
	usr.put_in_hand_or_drop(printed)
	boutput(usr, "<span class='notice'>Spawned the blueprint '[picked["file"]]'.</span>")

/verb/adminDeleteBlueprint()
	set name = "Blueprint Delete"
	set desc = "Allows deletion of blueprints of any user."
	SET_ADMIN_CAT(ADMIN_CAT_FUN)

	delete_abcu_blueprint(usr, TRUE)

/verb/adminDumpBlueprint()
	set name = "Blueprint Dump"
	set desc = "Dumps readable HTML blueprint, of any user, to your client folder."
	SET_ADMIN_CAT(ADMIN_CAT_DEBUG)

	var/picked = browse_abcu_blueprints(usr, "Admin Dump Blueprint", "Choose a blueprint to export.", TRUE)
	if (!picked) return

	var/savefile/selectedbp = new/savefile(picked["path"])
	selectedbp.ExportText("/","data/blueprints/[picked["ckey"]]/[picked["file"]].txt")
	usr.client.Export("data/blueprints/[picked["ckey"]]/[picked["file"]].txt")
	fdel("data/blueprints/[picked["ckey"]]/[picked["file"]].txt")

	boutput(usr, "<span class='notice'>Dumped blueprint to BYOND user data folder.</span>")

/obj/item/abcu_blueprint_reference
	name = "structure blueprint"
	desc = "An ABCU blueprint. You can use this to learn it, or tap it on an ABCU to upload the referenced blueprint."
	icon = 'icons/obj/writing.dmi'
	icon_state = "interdictor_blueprint" // yoinking this unused icon
	item_state = "sheet"
	// jank alert: this item lets filenames and saved roomname data be different. but who cares?

	var/author = ""
	var/room_name = ""
	var/blueprint_path = ""

	New(turf/new_loc, var/savepath = "")
		. = ..(new_loc)
		if (!savepath || !fexists(savepath)) return
		src.blueprint_path = savepath
		var/savefile/save = new/savefile(savepath)
		save.cd = "/"
		src.author = save["author"]
		src.room_name = save["roomname"]
		src.name += ": [src.room_name]"

	attack_self(mob/user)
		if (!user?.client?.ckey)
			. = ..()
			return
		if (!src.blueprint_path || !fexists(src.blueprint_path))
			boutput(user, "<span class='alert'>This item is broken, please tell a coder if it keeps breaking!</span>")
			return
		// ckeyEx to sanitize filename: no spaces/special chars, only '_', '-', and '@' allowed. 54 char limit in tgui_input
		var/input = ckeyEx(tgui_input_text(user, "You are copying '[src.room_name]' to your own collection. \
			Choose a file name for it. Use only alphanumeric characters, and - and _.", "Copy Homework", null, 54))
		var/timeout = 0
		while (input && fexists("data/blueprints/[user.client.ckey]/[input].dat"))
			if (!user?.client?.ckey || timeout > 5)
				boutput(user, "<span class='alert'>Copy operation timed out. Please try again.</span>")
				return
			input = ckeyEx(tgui_input_text(user, "A blueprint named '[input]' already exists. Please input another, or cancel.",
				"Copy Homework", input, 54)) // handy dandy prompt autofilled with the last used input
			timeout++
		if (!input) return
		fcopy(src.blueprint_path, "data/blueprints/[user.client.ckey]/[input].dat")
		boutput(user, "<span class='notice'>Copied this blueprint! Its filename is: '[input]'.</span>")

	afterattack(atom/target, mob/user)
		if (!istype(target, /obj/machinery/abcu))
			. = ..()
			return
		if (!src.blueprint_path || !fexists(src.blueprint_path))
			boutput(user, "<span class='alert'>This item is broken, please tell a coder if it keeps breaking!</span>")
			return
		var/obj/machinery/abcu/abcu = target
		abcu.get_blueprint(user, src.blueprint_path)

// whitelists/blacklists applied during both saving and loading, so it's functionally retroactive
#define WHITELIST_OBJECTS list( \
	/obj/stool, \
	/obj/grille, \
	/obj/window, \
	/obj/machinery/door, \
	/obj/cable, \
	/obj/table, \
	/obj/rack, \
	/obj/structure, \
	/obj/disposalpipe, \
	/obj/machinery/light, \
	/obj/machinery/door_control, \
	/obj/machinery/light_switch, \
	/obj/machinery/camera, \
	/obj/item/device/radio/intercom, \
	/obj/machinery/firealarm, \
	/obj/machinery/power/apc, \
	/obj/machinery/alarm, \
	/obj/machinery/disposal, \
	/obj/machinery/gibber, \
	/obj/machinery/floorflusher, \
	/obj/machinery/activation_button/driver_button, \
	/obj/machinery/door_control, \
	/obj/machinery/disposal, \
	/obj/submachine/chef_oven, \
	/obj/submachine/chef_sink, \
	/obj/machinery/launcher_loader, \
	/obj/machinery/optable, \
	/obj/machinery/mass_driver, \
	/obj/machinery/sleeper, \
	/obj/machinery/sleep_console, \
	/obj/submachine/slot_machine, \
	/obj/machinery/deep_fryer, \
	/obj/submachine/ATM, \
	/obj/submachine/ice_cream_dispenser, \
	/obj/machinery/portable_atmospherics, \
	/obj/machinery/ai_status_display, \
	/obj/securearea, \
	/obj/submachine/mixer, \
	/obj/submachine/foodprocessor, \
)
// blacklist overrules whitelist
#define BLACKLIST_OBJECTS list( \
	/obj/disposalpipe/loafer, \
	/obj/submachine/slot_machine/item, \
	/obj/machinery/portable_atmospherics/canister, \
)

#define WHITELIST_TURFS list(/turf/simulated)

/datum/abcu_blueprint
	var/cost_metal = 0
	var/cost_crystal = 0
	var/size_x = 0
	var/size_y = 0
	var/author = ""
	var/room_name = ""
	var/list/roominfo = list()

proc/save_abcu_blueprint(mob/user, list/turf_list, var/use_whitelist = TRUE)
	if (!user.client.ckey) return
	if (!length(turf_list))
		boutput(user, "<span class='alert'>There are no selected tiles to save.</span>")
		return

	// ckeyEx to sanitize filename: no spaces/special chars, only '_', '-', and '@' allowed. 54 char limit in tgui_input
	var/input = strip_html(tgui_input_text(user, "Set a name for your new blueprint. \
		Filename conversion preserves only alphanumeric characters, and - and _.",
		"Blueprint Name", null, 54))
	if (!input) return
	// raw input goes into savefile's roomname, sanitized goes into filename
	var/input_sanitized = ckeyEx(input)
	var/savepath = "data/blueprints/[user.client.ckey]/[input_sanitized].dat"

	var/savefile/save = new/savefile("[savepath]") // creates a save, or loads an existing one
	save.cd = "/"
	if (save["sizex"] || save["sizey"]) // if it exists, and has data in it, ALERT!
		if (tgui_alert(user, "A blueprint file named [input_sanitized] already exists. Really overwrite?",
			"Overwrite Blueprint", list("Yes", "No")) == "No")
			return
		fdel("[savepath]")
		save = new/savefile("[savepath]")

	var/minx = 100000000
	var/miny = 100000000
	var/maxx = 0
	var/maxy = 0

	for(var/turf/t as anything in turf_list)
		if(t.x < minx) minx = t.x
		if(t.y < miny) miny = t.y

		if(t.x > maxx) maxx = t.x
		if(t.y > maxy) maxy = t.y

	var/sizex = (maxx - minx) + 1
	var/sizey = (maxy - miny) + 1
	var/turf_count
	var/obj_count

	save.cd = "/"
	save["sizex"] << sizex
	save["sizey"] << sizey
	save["roomname"] << input
	save["author"] << user.client.ckey
	save.dir.Add("tiles")

	for(var/atom/curr in turf_list)
		if (!istypes(curr, WHITELIST_TURFS))
			continue

		var/posx = (curr.x - minx)
		var/posy = (curr.y - miny)

		save.cd = "/tiles/[posx],[posy]"
		save["type"] << curr.type
		save["dir"] << curr.dir
		save["state"] << curr.icon_state
		if (curr.icon != initial(curr.icon))
			save["icon"] << "[curr.icon]" // string this or it saves the entire .dmi file
		turf_count++

		for(var/obj/o in curr)
			if (use_whitelist && (!istypes(o, WHITELIST_OBJECTS) || istypes(o, BLACKLIST_OBJECTS)))
				continue

			var/id = "\ref[o]"
			save.cd = "/tiles/[posx],[posy]/objects"
			while(save.dir.Find(id))
				id = id + "I"
			save.cd = "[id]"
			save["dir"] << o.dir
			save["type"] << o.type
			save["layer"] << o.layer
			save["pixelx"] << o.pixel_x
			save["pixely"] << o.pixel_y
			save["icon_state"] << o.icon_state
			obj_count++

	boutput(user, "<span class='notice'>Saved blueprint '[input]' with filename '[input_sanitized]'. \
		Saved [turf_count] tile\s, [obj_count] object\s.</span>")

proc/load_abcu_blueprint(mob/user, var/savepath = "", var/use_whitelist = TRUE)
	if (!savepath) // make this proc usable with or without a user and menu
		var/picked = browse_abcu_blueprints(user, "Load Blueprint", "Pick a blueprint to load.")
		if (!picked) return
		savepath = picked["path"]
	if (!fexists(savepath)) return
	var/savefile/save = new/savefile("[savepath]")

	var/datum/abcu_blueprint/bp = new/datum/abcu_blueprint
	var/turf_count
	var/obj_count
	save.cd = "/"
	bp.room_name = save["roomname"]
	bp.size_x = save["sizex"]
	bp.size_y = save["sizey"]
	bp.author = save["author"]

	save.cd = "/tiles" // cd to tiles
	for (var/A in save.dir) // and now loop on every listing in tiles
		save.cd = "/tiles/[A]"
		var/list/coords = splittext(A, ",")
		var/datum/tileinfo/tf = new/datum/tileinfo()
		tf.posx = coords[1]
		tf.posy = coords[2]
		tf.tiletype = save["type"]
		tf.state = save["state"]
		tf.direction = save["dir"]
		tf.icon = save["icon"]
		bp.cost_metal += REBUILD_COST_TURF_METAL
		bp.cost_crystal += REBUILD_COST_TURF_CRYSTAL
		save.cd = "/tiles/[A]/objects"
		turf_count++

		for (var/B in save.dir)
			save.cd = "/tiles/[A]/objects/[B]"
			var/object_type = save["type"]
			var/permitted = FALSE
			if (use_whitelist)
				for (var/whitelisted in WHITELIST_OBJECTS)
					if (ispath(object_type, whitelisted))
						permitted = TRUE
						break
				for (var/blacklisted in BLACKLIST_OBJECTS)
					if (ispath(object_type, blacklisted))
						permitted = FALSE
						break
				if (!permitted)
					continue // skip this obj. do not pass go

			var/datum/objectinfo/O = new/datum/objectinfo()
			O.objecttype = object_type
			O.direction = save["dir"]
			O.layer = save["layer"]
			O.px = save["pixelx"]
			O.py = save["pixely"]
			O.icon_state = save["icon_state"]
			bp.cost_metal += REBUILD_COST_OBJECT_METAL
			bp.cost_crystal += REBUILD_COST_OBJECT_CRYSTAL
			tf.objects.Add(O)
			obj_count++

		bp.roominfo.Add(tf)

	bp.cost_metal = round(bp.cost_metal)
	bp.cost_crystal = round(bp.cost_crystal)

	boutput(user, "<span class='notice'>Loaded blueprint [bp.room_name], with [turf_count] tile\s, and [obj_count] object\s.</span>")
	return bp

#undef WHITELIST_OBJECTS
#undef BLACKLIST_OBJECTS

proc/browse_abcu_blueprints(mob/user, var/window_title = "Blueprints", var/description = "Pick a blueprint.", var/browse_all_users = FALSE)
	if (!user.client) return
	var/picked_ckey
	if (browse_all_users) // for the admin procs
		var/inputuser = tgui_input_list(user, "Select a user's blueprint folder, by ckey.", "Users", flist("data/blueprints/"))
		if(!inputuser) return
		picked_ckey = splittext(inputuser, "/")[1]
	else
		picked_ckey = user.client.ckey
	if (!picked_ckey) return

	var/list/bplist = flist("data/blueprints/[picked_ckey]/")
	if (!length(bplist))
		boutput(user, "<span class='alert'>No blueprints found.</span>")
		return
	var/inputbp = tgui_input_list(user, description, window_title, bplist)
	if (!inputbp) return
	return list("path" = "data/blueprints/[picked_ckey]/[inputbp]", "ckey" = picked_ckey, "file" = inputbp)

proc/delete_abcu_blueprint(mob/user, var/browse_all_users = FALSE)
	var/picked = browse_abcu_blueprints(user, "Delete Blueprint", "Delete one of these blueprints?", browse_all_users)
	if (!picked) return
	if (fexists(picked["path"]))
		if (tgui_alert(user, "Really delete [picked["file"]]?", "Blueprint Deletion", list("Yes", "No")) == "No")
			return
		fdel(picked["path"])
		boutput(user, "<span class='alert'>Blueprint [picked["file"]] deleted.</span>")
	else
		boutput(user, "<span class='alert'>Blueprint [picked["file"]] not found.</span>")

/obj/item/blueprint_marker
	name = "blueprint marker"
	desc = "A tool used to map rooms for the creation of blueprints. \
		Blueprints can be used in an ABC Unit to reconstruct a saved room."
	icon = 'icons/obj/items/device.dmi'

	icon_state = "blueprintmarker"
	item_state = "gun"

	flags = FPRINT | EXTRADELAY | TABLEPASS | CONDUCT
	w_class = W_CLASS_SMALL

	var/prints_left = 5

	var/mob/using = null
	var/selecting = 0
	var/turf/selectcorner1
	var/image/corner1img

	var/roomname = "NewRoom"
	var/list/turf/roomList = new/list()

	var/list/permittedTileTypes = list("/turf/simulated")


	pixelaction(atom/target, params, mob/user)
		if(GET_DIST(src,target) > 10) return

		if(!isturf(target)) target = get_turf(target)

		var/minx = 100000000
		var/miny = 100000000

		var/maxx = 0
		var/maxy = 0

		var/maxSize = 20

		var/permitted = 0
		for(var/p in permittedTileTypes)
			var/type = text2path(p)
			if(istype(target, type))
				permitted = 1
				break

		if(!permitted)
			boutput(user, "<span class='alert'>Unsupported Tile type detected.</span>")
			return

		for(var/turf/t as anything in roomList) // is this better than storing min/max permanently?
			if(t.x < minx) minx = t.x
			if(t.y < miny) miny = t.y

			if(t.x > maxx) maxx = t.x
			if(t.y > maxy) maxy = t.y

		//Do stuff

		if(target.x < minx) minx = target.x
		if(target.y < miny) miny = target.y

		if(target.x > maxx) maxx = target.x
		if(target.y > maxy) maxy = target.y

		if(abs(minx - maxx) >= maxSize || abs(miny - maxy) >= maxSize)
			boutput(user, "<span class='alert'>Tile exceeds maximum size of blueprint.</span>")
			playsound(src.loc, 'sound/machines/button.ogg', 25)
			return

		switch (selecting)
			if (SELECT_SKIP)

			if (SELECT_FIRST_CORNER, DESELECT_FIRST_CORNER) // set to 1 or 2 by use-in-hand option list
				qdel(corner1img)
				selectcorner1 = target
				selecting += 2 // if 3 then select second corner, if 4 then deselect second corner
				corner1img = image('icons/misc/old_or_unused.dmi', selectcorner1, "marker", layer = HUD_LAYER)
				user << corner1img
				playsound(src.loc, 'sound/machines/tone_beep.ogg', 15)
				return

			if (SELECT_SECOND_CORNER, DESELECT_SECOND_CORNER)
				var/diffx = abs(target.x - selectcorner1.x)
				var/diffy = abs(target.y - selectcorner1.y)
				if(diffx >= maxSize || diffy >= maxSize)
					boutput(user, "<span class='alert'>Tile exceeds maximum size of blueprint.</span>")
					playsound(src.loc, 'sound/machines/button.ogg', 25)
					return

				var/selectedz = selectcorner1.z
				var/currx = min(target.x, selectcorner1.x)
				var/curry = min(target.y, selectcorner1.y)
				var/startx = currx
				var/endx = currx + diffx

				var/ix
				for (ix=0, ix < (diffx + 1) * (diffy + 1), ix++) // add 1 to diffs or a whole row/column of tiles are left out by math
					var/turf/t = locate(currx, curry, selectedz)

					currx++
					if (currx > endx)
						currx = startx
						curry++

					var/perm = 0
					for(var/p in permittedTileTypes)
						var/ttype = text2path(p)
						if(istype(t, ttype))
							perm = 1
							break
					if(!perm) continue

					if (selecting == SELECT_SECOND_CORNER)
						if (!roomList.Find(t))
							roomList.Add(t)
							roomList[t] = image('icons/misc/old_or_unused.dmi', t, "tiletag", layer = HUD_LAYER)
					else
						if (using?.client)
							using.client.images -= roomList[t]
						roomList.Remove(t)


				selecting = SELECT_SKIP
				qdel(corner1img)
				playsound(src.loc, 'sound/machines/tone_beep.ogg', 15)
				updateOverlays()
				return

			else selecting = SELECT_SKIP

		if(roomList.Find(target))
			if (using?.client)
				using.client.images -= roomList[target]
			roomList.Remove(target)
			playsound(src.loc, 'sound/machines/button.ogg', 25, 0.1)
		else
			roomList.Add(target)
			roomList[target] = image('icons/misc/old_or_unused.dmi',target,"tiletag", layer = HUD_LAYER)
			updateOverlays()
			playsound(src.loc, 'sound/machines/tone_beep.ogg', 15, 0.1)

		return

	New()
		..()

	proc/removeOverlays()
		if (using?.client)
			for(var/a in roomList)
				var/image/i = roomList[a]
				using.client.images -= i
		return

	proc/updateOverlays()
		if (using?.client)
			removeOverlays()
			for(var/a in roomList)
				var/image/i = roomList[a]
				using.client.images += i
		return

	attack_self(mob/user as mob)
		if(!user.client)
			return

		if (selecting)
			selecting = SELECT_SKIP
			qdel(corner1img)
			boutput(user, "<span class='notice'>Cancelled rectangle select.</span>")
			playsound(src.loc, 'sound/machines/button.ogg', 25)
			return

		var/list/options = list("Select Rectangle", "Deselect Rectangle", "Reset",
			"Save Blueprint", "Delete Blueprint", "Share A Blueprint", "Information",)
		//var/input = input(user,"Select option:","Option") in options
		var/input = tgui_input_list(user, "Choose an action.", "Blueprint Marker", options)

		switch(input)
			if("Select Rectangle")
				selecting = SELECT_FIRST_CORNER

			if("Deselect Rectangle")
				selecting = DESELECT_FIRST_CORNER

			if("Reset")
				boutput(user, "<span class='notice'>Resetting ...</span>")
				removeOverlays()
				roomList.Cut()

			if("Share A Blueprint")
				if(prints_left <= 0)
					boutput(user, "<span class='alert'>Out of energy.</span>")
					return
				var/picked = browse_abcu_blueprints(user, "Share Blueprint", "Choose a blueprint to print and share!")
				if (!picked) return
				var/obj/printed = new /obj/item/abcu_blueprint_reference(src, picked["path"])
				user.put_in_hand_or_drop(printed)
				src.prints_left--
				boutput(user, "<span class='notice'>Printed the blueprint '[picked["file"]]'. Prints remaining: [src.prints_left].</span>")
				return

			if("Save Blueprint")
				save_abcu_blueprint(user, roomList)
				return

			if("Delete Blueprint")
				delete_abcu_blueprint(user)
				return

			if("Information")
				var/message = "<span class='notice'>This tool is used for making, saving and loading room blueprints on the server.</span><br>"
				message += "<span class='notice'>Saved blueprints persist between rounds, but are limited to a size of 20 tiles on each axis, making 20x20 the largest blueprint.</span><br><br>"
				message += "<span class='notice'>(De)Select Rectangle: Mass-selects or deselects tiles in a filled rectangle shape, defined by 2 corners.</span><br>"
				message += "<span class='notice'>Reset: Resets the tools and clears all marked areas.</span><br>"
				message += "<span class='notice'>Save Blueprint: Saves a blueprint of the marked area to the server. Most structures will be saved, but it can not save all types of objects.</span><br>"
				message += "<span class='notice'>Delete Blueprint: Permanently deletes a chosen blueprint from the server.</span><br>"
				message += "<span class='notice'>Share Blueprint: Prints a chosen blueprint. The printout can be used on an ABCU, or memorized by other players.</span><br>"
				message += "<span class='notice'>Outdated blueprints can be migrated using the 'Migrate blueprint' local verb.</span><br>"
				boutput(user, message)
				return

		return

	dropped(mob/user as mob)
		removeOverlays()
		selecting = 0
		qdel(corner1img)
		using = null
		return

	pickup(mob/user)
		using = user
		updateOverlays()
		return

	equipped(var/mob/user, var/slot)
		..()
		using = user
		updateOverlays()
		return

#undef WHITELIST_TURFS

/obj/item/blueprint_marker/verb/migrate_bigfile_blueprint()
	// this is a tucked-away verb because it's niche and for old stuff, don't want it on the tool's main menu
	set name = "Migrate blueprint"
	set desc = "Attempt to convert an older blueprint to the latest save system."
	set category = "Local"
	set src in usr
	var/mob/user = usr
	if (!user.client) return
	boutput(user, "<span class='notice'>Looking for older blueprints to convert. If this process doesn't work, sorry, I tried my best.</span>")

	var/savefile/save = new/savefile("data/blueprints.dat")
	save.cd = "/"
	if (!save.dir.Find("[user.client.ckey]"))
		boutput(user, "<span class='alert'>Your user wasn't found in the blueprints file. Stopping.</span>")
		return
	save.cd = "/[user.client.ckey]"
	var/list/bplist = save.dir

	if (!length(bplist))
		boutput(user, "<span class='alert'>No blueprints found. Stopping.</span>")
		return
	var/input = tgui_input_list(user, "Select a blueprint to migrate.", "Blueprints", bplist)
	if (!input) return
	var/old_save_path = "/[user.client.ckey]/[input]"
	save.cd = old_save_path
	var/new_save_name = strip_html(tgui_input_text(user, "Input the name for the new, migrated blueprint. \
		Old name was: [input]", "New Blueprint Name"))
	if (!new_save_name) return

	var/savefile/new_save = new/savefile("data/blueprints/[user.client.ckey]/[new_save_name].dat")
	new_save.cd = "/"
	new_save["sizex"] << save["sizex"]
	new_save["sizey"] << save["sizey"]
	new_save["roomname"] << new_save_name
	new_save["author"] << user.client.ckey
	var/turf_count = 0
	var/obj_count = 0

	for (var/A in save.dir)
		if(A == "sizex" || A == "sizey" || A == "roomname") continue
		save.cd = "[old_save_path]/[A]"
		new_save.cd = "/tiles/[A]"

		new_save["type"] << save["type"]
		new_save["dir"] << save["dir"]
		new_save["state"] << save["state"]
		turf_count++
		for (var/B in save.dir)
			if(B == "type" || B == "state" || B == "dir") continue
			save.cd = "[old_save_path]/[A]/[B]"
			new_save.cd = "/tiles/[A]/objects/[B]"

			new_save["dir"] << save["dir"]
			new_save["type"] << save["type"]
			new_save["layer"] << save["layer"]
			new_save["pixelx"] << save["pixelx"]
			new_save["pixely"] << save["pixely"]
			obj_count++
	boutput(user, "<span class='notice'>Created blueprint file [new_save_name]. Copied [turf_count] tiles and [obj_count] objects.</span>")

#undef REBUILD_COST_OBJECT_METAL
#undef REBUILD_COST_OBJECT_CRYSTAL
#undef REBUILD_COST_TURF_METAL
#undef REBUILD_COST_TURF_CRYSTAL
#undef BAR_SHEET_VALUE
#undef SELECT_SKIP
#undef SELECT_FIRST_CORNER
#undef DESELECT_FIRST_CORNER
#undef SELECT_SECOND_CORNER
#undef DESELECT_SECOND_CORNER
