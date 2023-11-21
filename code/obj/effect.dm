/obj/effect
	name = "" // for some reason mouse_opacity itself doesn't work for hiding this from rightclick, empty name works though
	mouse_opacity = 0
	event_handler_flags = IMMUNE_MANTA_PUSH | IMMUNE_TRENCH_WARP

/obj/effect/distort
	icon = 'icons/effects/distort.dmi'
	appearance_flags = PIXEL_SCALE | RESET_COLOR | RESET_TRANSFORM | RESET_ALPHA | NO_CLIENT_COLOR
	vis_flags = VIS_INHERIT_DIR

	New()
		..()
		src.render_target = "*\ref[src]"

/obj/effect/rt
	vis_flags = VIS_INHERIT_DIR

	New()
		..()
		src.render_target = "*\ref[src]"

/obj/effect/artifact_glowie
	appearance_flags = PIXEL_SCALE | RESET_COLOR | KEEP_TOGETHER
