class_name LobbySeatCard
extends PanelContainer
## 房间固定席位卡：SEAT 01..04，占用/空席同一尺寸；空席虚线边框。

signal kick_requested(seat: int)

var seat := -1
var _empty := true
var _dashed: LobbyDashedBorder
var _name_label: Label
var _status_label: Label
var _has_host_badge := false
var _has_kick := false

func setup(p_seat: int, player: Dictionary, is_host: bool, is_me: bool, can_kick: bool) -> void:
	seat = p_seat
	_empty = player.is_empty()
	_has_host_badge = not _empty and is_host
	_has_kick = not _empty and can_kick
	custom_minimum_size = Vector2(0, 100)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(10)
	style.set_content_margin_all(7)
	style.bg_color = UITheme.color("bg_surface")
	if _empty:
		style.bg_color = UITheme.color("bg_table")
		style.bg_color.a = 0.55
		style.border_color = UITheme.color("border")
		style.border_color.a = 0.7
		style.set_border_width_all(1)
	elif is_host:
		style.bg_color = UITheme.color("bg_surface")
		style.border_color = UITheme.color("accent")
		style.set_border_width_all(2)
	else:
		style.border_color = UITheme.color("border")
		style.set_border_width_all(1)
	add_theme_stylebox_override("panel", style)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_dashed = null
	if _empty:
		_dashed = LobbyDashedBorder.new()
		_dashed.name = "DashedBorder"
		_dashed.color = UITheme.color("text_muted")
		_dashed.color.a = 0.45
		add_child(_dashed)

	var vb := VBoxContainer.new()
	vb.name = "VBox"
	vb.add_theme_constant_override("separation", 3)
	add_child(vb)
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 6)
	vb.add_child(header)
	var seat_lbl := Label.new()
	seat_lbl.text = "SEAT %02d" % (p_seat + 1)
	seat_lbl.add_theme_font_size_override("font_size", 10)
	seat_lbl.add_theme_color_override("font_color", UITheme.color("text_muted"))
	seat_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(seat_lbl)
	if not _empty and is_host:
		var badge := PanelContainer.new()
		badge.name = "HostBadge"
		var bs := StyleBoxFlat.new()
		bs.bg_color = UITheme.color("accent_soft")
		bs.set_corner_radius_all(6)
		bs.set_content_margin_all(3)
		badge.add_theme_stylebox_override("panel", bs)
		var bl := Label.new()
		bl.text = "房主"
		bl.add_theme_font_size_override("font_size", 10)
		bl.add_theme_color_override("font_color", UITheme.color("accent"))
		badge.add_child(bl)
		header.add_child(badge)
	if not _empty and can_kick:
		var kick := Button.new()
		kick.name = "Kick"
		kick.text = "踢出"
		kick.flat = true
		kick.add_theme_font_size_override("font_size", 10)
		kick.add_theme_color_override("font_color", UITheme.color("danger"))
		kick.pressed.connect(func(): kick_requested.emit(p_seat))
		header.add_child(kick)

	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(center)
	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(32, 32)
	avatar.size = Vector2(32, 32)
	var av := StyleBoxFlat.new()
	av.bg_color = UITheme.color("accent_soft") if not _empty else UITheme.color("bg_elevated")
	av.set_corner_radius_all(16)
	avatar.add_theme_stylebox_override("panel", av)
	center.add_child(avatar)
	var initial := Label.new()
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.add_theme_font_size_override("font_size", 15)
	if _empty:
		initial.text = "+"
		initial.add_theme_color_override("font_color", UITheme.color("text_muted"))
	else:
		var n := str(player.get("name", "玩家"))
		initial.text = n.left(1)
		initial.add_theme_color_override("font_color", UITheme.color("accent"))
	avatar.add_child(initial)

	var name_lbl := Label.new()
	name_lbl.name = "Name"
	_name_label = name_lbl
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.clip_text = true
	name_lbl.max_lines_visible = 1
	name_lbl.custom_minimum_size = Vector2(0, 20)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 14)
	if _empty:
		name_lbl.text = "等待加入"
		name_lbl.add_theme_color_override("font_color", UITheme.color("text_muted"))
	else:
		var nm := str(player.get("name", "玩家"))
		if is_me:
			nm += "（你）"
		name_lbl.text = nm
		name_lbl.add_theme_color_override("font_color", UITheme.color("text_primary"))
	vb.add_child(name_lbl)

	var status := Label.new()
	status.name = "Status"
	_status_label = status
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 10)
	if _empty:
		status.text = "等待加入"
		status.add_theme_color_override("font_color", UITheme.color("text_muted"))
	elif is_host:
		status.text = "● 已连接"
		status.add_theme_color_override("font_color", UITheme.color("success"))
	elif bool(player.get("ready", false)):
		status.text = "● 已准备"
		status.add_theme_color_override("font_color", UITheme.color("success"))
	else:
		status.text = "● 未准备"
		status.add_theme_color_override("font_color", UITheme.color("warning"))
	vb.add_child(status)

func is_empty_seat() -> bool:
	return _empty

## 宽屏房间左侧：横向紧凑席位行。
func setup_row(p_seat: int, player: Dictionary, is_host: bool, is_me: bool, can_kick: bool) -> void:
	seat = p_seat
	_empty = player.is_empty()
	_has_host_badge = not _empty and is_host
	_has_kick = not _empty and can_kick
	custom_minimum_size = Vector2(0, 64)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	style.bg_color = UITheme.color("bg_surface")
	if _empty:
		style.bg_color = UITheme.color("bg_table")
		style.bg_color.a = 0.55
		style.border_color = UITheme.color("border")
		style.border_color.a = 0.7
		style.set_border_width_all(1)
	elif is_host:
		style.border_color = UITheme.color("accent")
		style.set_border_width_all(2)
	else:
		style.border_color = UITheme.color("border")
		style.set_border_width_all(1)
	add_theme_stylebox_override("panel", style)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if _empty:
		var dashed := LobbyDashedBorder.new()
		dashed.color = UITheme.color("text_muted")
		dashed.color.a = 0.45
		add_child(dashed)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var num := Label.new()
	num.text = "%02d" % (p_seat + 1)
	num.custom_minimum_size = Vector2(24, 0)
	num.add_theme_font_size_override("font_size", 11)
	num.add_theme_color_override("font_color", UITheme.color("text_muted"))
	row.add_child(num)
	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(30, 30)
	avatar.size = Vector2(30, 30)
	var av := StyleBoxFlat.new()
	av.bg_color = UITheme.color("accent_soft") if not _empty else UITheme.color("bg_elevated")
	av.set_corner_radius_all(15)
	avatar.add_theme_stylebox_override("panel", av)
	row.add_child(avatar)
	var initial := Label.new()
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.add_theme_font_size_override("font_size", 13)
	if _empty:
		initial.text = "+"
		initial.add_theme_color_override("font_color", UITheme.color("text_muted"))
	else:
		var n := str(player.get("name", "玩家"))
		initial.text = n.left(1)
		initial.add_theme_color_override("font_color", UITheme.color("accent"))
	avatar.add_child(initial)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	row.add_child(info)
	_name_label = Label.new()
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.clip_text = true
	_name_label.max_lines_visible = 1
	_name_label.add_theme_font_size_override("font_size", 14)
	if _empty:
		_name_label.text = "等待加入"
		_name_label.add_theme_color_override("font_color", UITheme.color("text_muted"))
	else:
		var nm := str(player.get("name", "玩家"))
		_name_label.text = nm + ("（你）" if is_me else "")
		_name_label.add_theme_color_override("font_color", UITheme.color("text_primary"))
	info.add_child(_name_label)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 10)
	if _empty:
		_status_label.text = "等待加入"
		_status_label.add_theme_color_override("font_color", UITheme.color("text_muted"))
	elif is_host:
		_status_label.text = "房主 · 已连接"
		_status_label.add_theme_color_override("font_color", UITheme.color("accent"))
	elif bool(player.get("ready", false)):
		_status_label.text = "● 已准备"
		_status_label.add_theme_color_override("font_color", UITheme.color("success"))
	else:
		_status_label.text = "● 未准备"
		_status_label.add_theme_color_override("font_color", UITheme.color("warning"))
	info.add_child(_status_label)
	if not _empty and is_host:
		var badge := Label.new()
		badge.text = "房主"
		badge.add_theme_font_size_override("font_size", 10)
		badge.add_theme_color_override("font_color", UITheme.color("accent"))
		row.add_child(badge)
	if not _empty and can_kick:
		var kick := Button.new()
		kick.text = "踢出"
		kick.flat = true
		kick.add_theme_font_size_override("font_size", 10)
		kick.add_theme_color_override("font_color", UITheme.color("danger"))
		kick.pressed.connect(func(): kick_requested.emit(p_seat))
		row.add_child(kick)

func seat_number() -> int:
	return seat + 1

func name_text() -> String:
	return _name_label.text if _name_label != null else ""

func status_text() -> String:
	return _status_label.text if _status_label != null else ""

func has_host_badge() -> bool:
	return _has_host_badge

func has_kick_button() -> bool:
	return _has_kick
