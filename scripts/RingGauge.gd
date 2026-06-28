extends Control
# ============================================================================
# RingGauge.gd — gauge cincin ringan untuk kolom info (DRIVE/THERMAL/POWER).
# Cincin track + arc nilai (mulai atas, searah jarum jam) + teks tengah.
# ============================================================================

var value: float = 0.0                                  # 0..1
var arc_color: Color = Color(0.435, 0.482, 0.941)       # indigo
var track_color: Color = Color(0.945, 0.957, 0.976)     # abu sangat muda
var center_text: String = ""
var _font: Font

func _ready() -> void:
	custom_minimum_size = Vector2(64, 64)
	_font = ThemeDB.fallback_font

func set_gauge(v: float, text: String, col: Color) -> void:
	value = clampf(v, 0.0, 1.0)
	center_text = text
	arc_color = col
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.42
	var w := 6.5
	draw_arc(c, r, 0.0, TAU, 48, track_color, w, true)
	var start := -PI * 0.5
	if value > 0.0:
		draw_arc(c, r, start, start + TAU * value, 48, arc_color, w, true)
	if center_text != "" and _font != null:
		var fs := 14
		var ts := _font.get_string_size(center_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var pos := c + Vector2(-ts.x * 0.5, ts.y * 0.30)
		draw_string(_font, pos, center_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(0.165, 0.184, 0.235))
