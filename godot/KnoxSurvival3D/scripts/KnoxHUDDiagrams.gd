extends Control
class_name KnoxHUDDiagrams

## Diagramas Vetoriais 1:1 do HUD Condado de Knox (Web -> Godot 4):
## - mode = "body": Silhueta Corporal colorida por integridade (Cabeca, Torso, Bracos, Pernas)
## - mode = "vehicle": Diagrama superior de Carro (4 rodas + vidros + farois + giroflex) ou Moto (2 rodas + guidao)

var mode: String = "body"
var hp_ratio: float = 1.0
var is_moto: bool = false
var is_police: bool = false
var lights_on: bool = false
var steer_val: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_body_state(ratio: float) -> void:
	var clamped: float = clampf(ratio, 0.0, 1.0)
	if absf(clamped - hp_ratio) > 0.01 or mode != "body":
		mode = "body"
		hp_ratio = clamped
		queue_redraw()


func set_vehicle_state(ratio: float, moto: bool, police: bool, lights: bool, steer: float = 0.0) -> void:
	mode = "vehicle"
	hp_ratio = clampf(ratio, 0.0, 1.0)
	is_moto = moto
	is_police = police
	lights_on = lights
	steer_val = steer
	queue_redraw()


func _health_color(r: float) -> Color:
	if r > 0.65:
		return Color.html("#4ade80").lerp(Color.html("#86efac"), clampf((r - 0.65) / 0.35, 0.0, 1.0))
	if r > 0.32:
		return Color.html("#eab308").lerp(Color.html("#4ade80"), clampf((r - 0.32) / 0.33, 0.0, 1.0))
	return Color.html("#ef4444").lerp(Color.html("#eab308"), clampf(r / 0.32, 0.0, 1.0))


func _draw() -> void:
	if mode == "body":
		_draw_body_silhouette()
	else:
		_draw_vehicle_diagram()


func _draw_body_silhouette() -> void:
	var w: float = size.x
	var h: float = size.y
	var cx: float = w * 0.5
	var col: Color = _health_color(hp_ratio)
	var border := Color(0.08, 0.12, 0.08, 0.95)
	var bg := Color(0.07, 0.10, 0.07, 0.65)
	draw_rect(Rect2(Vector2.ZERO, size), bg, true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.28, 0.38, 0.25, 0.65), false, 1.0)

	# Cabeca
	var head_c := Vector2(cx, h * 0.16)
	draw_circle(head_c, w * 0.135, col)
	draw_arc(head_c, w * 0.135, 0.0, TAU, 18, border, 1.2)

	# Torso
	var torso_r := Rect2(cx - w * 0.18, h * 0.29, w * 0.36, h * 0.30)
	draw_rect(torso_r, col, true)
	draw_rect(torso_r, border, false, 1.2)

	# Bracos esquerdo e direito
	var arm_l := Rect2(cx - w * 0.34, h * 0.30, w * 0.12, h * 0.29)
	var arm_r := Rect2(cx + w * 0.22, h * 0.30, w * 0.12, h * 0.29)
	draw_rect(arm_l, col, true)
	draw_rect(arm_l, border, false, 1.0)
	draw_rect(arm_r, col, true)
	draw_rect(arm_r, border, false, 1.0)

	# Pernas esquerda e direita
	var leg_l := Rect2(cx - w * 0.16, h * 0.62, w * 0.13, h * 0.32)
	var leg_r := Rect2(cx + w * 0.03, h * 0.62, w * 0.13, h * 0.32)
	draw_rect(leg_l, col, true)
	draw_rect(leg_l, border, false, 1.0)
	draw_rect(leg_r, col, true)
	draw_rect(leg_r, border, false, 1.0)


func _draw_vehicle_diagram() -> void:
	var w: float = size.x
	var h: float = size.y
	var cx: float = w * 0.5
	var col: Color = _health_color(hp_ratio)
	var tire_col := Color(0.18, 0.22, 0.18, 0.95)
	var glass_col := Color(0.10, 0.16, 0.15, 0.92)
	var hl_col: Color = Color(1.0, 0.94, 0.55, 0.98) if lights_on else Color(0.45, 0.50, 0.44, 0.45)

	draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.09, 0.06, 0.72), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.30, 0.40, 0.26, 0.65), false, 1.0)

	if is_moto:
		# Feixe de farol da moto
		if lights_on:
			var beam := PackedVector2Array([
				Vector2(cx - 5.0, h * 0.16), Vector2(cx + 5.0, h * 0.16),
				Vector2(cx + 15.0, 2.0), Vector2(cx - 15.0, 2.0)
			])
			draw_colored_polygon(beam, Color(1.0, 0.95, 0.60, 0.24))
		# Roda dianteira + Roda traseira
		draw_rect(Rect2(cx - 4.0, h * 0.11, 8.0, h * 0.19), tire_col, true)
		draw_rect(Rect2(cx - 4.5, h * 0.71, 9.0, h * 0.20), tire_col, true)
		# Guidao
		draw_line(Vector2(cx - 16.0, h * 0.28 - steer_val * 3.0), Vector2(cx + 16.0, h * 0.28 + steer_val * 3.0), col, 3.0)
		# Tanque + Quadro + Banco duplo
		draw_rect(Rect2(cx - 8.0, h * 0.27, 16.0, h * 0.22), col, true)
		draw_rect(Rect2(cx - 6.0, h * 0.49, 12.0, h * 0.26), col.darkened(0.25), true)
		# Farol
		draw_circle(Vector2(cx, h * 0.17), 3.6, hl_col)
	else:
		# Feixes dos farois do carro
		if lights_on:
			for sx in [-1.0, 1.0]:
				var bx: float = cx + sx * (w * 0.22)
				var beam := PackedVector2Array([
					Vector2(bx - 4.0, h * 0.12), Vector2(bx + 4.0, h * 0.12),
					Vector2(bx + 10.0, 2.0), Vector2(bx - 10.0, 2.0)
				])
				draw_colored_polygon(beam, Color(1.0, 0.95, 0.60, 0.22))
		# 4 Rodas
		draw_rect(Rect2(cx - w * 0.38, h * 0.18, 6.0, 14.0), tire_col, true)
		draw_rect(Rect2(cx + w * 0.38 - 6.0, h * 0.18, 6.0, 14.0), tire_col, true)
		draw_rect(Rect2(cx - w * 0.38, h * 0.66, 6.0, 14.0), tire_col, true)
		draw_rect(Rect2(cx + w * 0.38 - 6.0, h * 0.66, 6.0, 14.0), tire_col, true)
		# Carroceria
		var body_r := Rect2(cx - w * 0.30, h * 0.12, w * 0.60, h * 0.76)
		draw_rect(body_r, col, true)
		draw_rect(body_r, Color(0.08, 0.12, 0.08), false, 1.3)
		# Para-brisa e vidro traseiro
		draw_rect(Rect2(cx - w * 0.23, h * 0.29, w * 0.46, h * 0.14), glass_col, true)
		draw_rect(Rect2(cx - w * 0.23, h * 0.62, w * 0.46, h * 0.11), glass_col, true)
		# Giroflex se for viatura policial
		if is_police:
			draw_rect(Rect2(cx - 10.0, h * 0.48, 10.0, 5.0), Color(0.95, 0.22, 0.20), true)
			draw_rect(Rect2(cx, h * 0.48, 10.0, 5.0), Color(0.24, 0.56, 1.0), true)
		# Farois dianteiros + Lanternas traseiras
		draw_rect(Rect2(cx - w * 0.25, h * 0.12, 8.0, 3.5), hl_col, true)
		draw_rect(Rect2(cx + w * 0.25 - 8.0, h * 0.12, 8.0, 3.5), hl_col, true)
		draw_rect(Rect2(cx - w * 0.25, h * 0.85, 8.0, 3.0), Color(0.88, 0.20, 0.18), true)
		draw_rect(Rect2(cx + w * 0.25 - 8.0, h * 0.85, 8.0, 3.0), Color(0.88, 0.20, 0.18), true)
