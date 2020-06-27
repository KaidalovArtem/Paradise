/obj/machinery/atmospherics/binary/passive_gate
	//Tries to achieve target pressure at output (like a normal pump) except
	//	Uses no power but can not transfer gases from a low pressure area to a high pressure area
	icon = 'icons/atmos/passive_gate.dmi'
	icon_state = "map"

	name = "passive gate"
	desc = "A one-way air valve that does not require power"

	can_unwrench = 1

	var/on = 0
	var/target_pressure = ONE_ATMOSPHERE

	var/frequency = 0
	var/id = null
	var/datum/radio_frequency/radio_connection

/obj/machinery/atmospherics/binary/passive_gate/atmos_init()
	..()
	if(frequency)
		set_frequency(frequency)

/obj/machinery/atmospherics/binary/passive_gate/Destroy()
	if(SSradio)
		SSradio.remove_object(src, frequency)
	radio_connection = null
	return ..()

/obj/machinery/atmospherics/binary/passive_gate/update_icon()
	..()
	icon_state = "[on ? "on" : "off"]"

/obj/machinery/atmospherics/binary/passive_gate/update_underlays()
	if(..())
		underlays.Cut()
		var/turf/T = get_turf(src)
		if(!istype(T))
			return
		add_underlay(T, node1, turn(dir, 180))
		add_underlay(T, node2, dir)

/obj/machinery/atmospherics/binary/passive_gate/process_atmos()
	..()
	if(!on)
		return 0

	var/output_starting_pressure = air2.return_pressure()
	var/input_starting_pressure = air1.return_pressure()

	if(output_starting_pressure >= min(target_pressure,input_starting_pressure-10))
		//No need to pump gas if target is already reached or input pressure is too low
		//Need at least 10 KPa difference to overcome friction in the mechanism
		return 1

	//Calculate necessary moles to transfer using PV = nRT
	if((air1.total_moles() > 0) && (air1.temperature>0))
		var/pressure_delta = min(target_pressure - output_starting_pressure, (input_starting_pressure - output_starting_pressure)/2)
		//Can not have a pressure delta that would cause output_pressure > input_pressure

		var/transfer_moles = pressure_delta*air2.volume/(air1.temperature * R_IDEAL_GAS_EQUATION)

		//Actually transfer the gas
		var/datum/gas_mixture/removed = air1.remove(transfer_moles)
		air2.merge(removed)

		parent1.update = 1

		parent2.update = 1
	return 1

//Radio remote control
/obj/machinery/atmospherics/binary/passive_gate/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	if(frequency)
		radio_connection = SSradio.add_object(src, frequency, filter = RADIO_ATMOSIA)

/obj/machinery/atmospherics/binary/passive_gate/proc/broadcast_status()
	if(!radio_connection)
		return 0

	var/datum/signal/signal = new
	signal.transmission_method = 1 //radio signal
	signal.source = src

	signal.data = list(
		"tag" = id,
		"device" = "AGP",
		"power" = on,
		"target_output" = target_pressure,
		"sigtype" = "status"
	)

	radio_connection.post_signal(src, signal, filter = RADIO_ATMOSIA)

	return 1

/obj/machinery/atmospherics/binary/passive_gate/receive_signal(datum/signal/signal)
	if(!signal.data["tag"] || (signal.data["tag"] != id) || (signal.data["sigtype"]!="command"))
		return 0

	var/old_on = on //for logging

	if("power" in signal.data)
		on = text2num(signal.data["power"])

	if("power_toggle" in signal.data)
		on = !on

	if("set_output_pressure" in signal.data)
		target_pressure = between(
			0,
			text2num(signal.data["set_output_pressure"]),
			ONE_ATMOSPHERE*50
		)

	if(on != old_on)
		investigate_log("was turned [on ? "on" : "off"] by a remote signal", "atmos")

	if("status" in signal.data)
		spawn(2)
			broadcast_status()
		return //do not update_icon

	spawn(2)
		broadcast_status()
	update_icon()
	return

/obj/machinery/atmospherics/binary/passive_gate/attack_hand(mob/user)
	if(..())
		return

	if(!allowed(user))
		to_chat(user, "<span class='alert'>Доступ запрещен.</span>")
		return

	add_fingerprint(user)
	ui_interact(user)

/obj/machinery/atmospherics/binary/passive_gate/attack_ghost(mob/user)
	ui_interact(user)

/obj/machinery/atmospherics/binary/passive_gate/ui_interact(mob/user, ui_key = "main", datum/nanoui/ui = null, force_open = 1, var/master_ui = null, var/datum/topic_state/state = GLOB.default_state)
	user.set_machine(src)
	ui = SSnanoui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "atmos_pump.tmpl", name, 385, 115, state = state)
		ui.open()

/obj/machinery/atmospherics/binary/passive_gate/ui_data(mob/user)
	var/list/data = list()
	data["on"] = on
	data["pressure"] = round(target_pressure)
	data["max_pressure"] = round(MAX_OUTPUT_PRESSURE)
	return data

/obj/machinery/atmospherics/binary/passive_gate/Topic(href,href_list)
	if(..())
		return 1

	if(href_list["power"])
		on = !on
		investigate_log("was turned [on ? "on" : "off"] by [key_name(usr)]", "atmos")
		. = TRUE
	if(href_list["pressure"])
		var/pressure = href_list["pressure"]
		if(pressure == "max")
			pressure = MAX_OUTPUT_PRESSURE
			. = TRUE
		else if(pressure == "input")
			pressure = input("New output pressure (0-[MAX_OUTPUT_PRESSURE] kPa):", name, target_pressure) as num|null
			if(!isnull(pressure))
				. = TRUE
		else if(text2num(pressure) != null)
			pressure = text2num(pressure)
			. = TRUE
		if(.)
			target_pressure = Clamp(pressure, 0, MAX_OUTPUT_PRESSURE)
			investigate_log("was set to [target_pressure] kPa by [key_name(usr)]", "atmos")

	update_icon()
	SSnanoui.update_uis(src)

/obj/machinery/atmospherics/binary/passive_gate/attackby(obj/item/W, mob/user, params)
	if(!istype(W, /obj/item/wrench))
		return ..()
	if(on)
		to_chat(user, "<span class='alert'>You cannot unwrench this [src], turn it off first.</span>")
		return 1
	return ..()
