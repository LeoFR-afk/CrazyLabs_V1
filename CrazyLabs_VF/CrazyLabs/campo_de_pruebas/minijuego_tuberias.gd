extends CanvasLayer
## Minijuego de tuberias (panel de reparar). Se construye y se dibuja por codigo.
## COPIA del minijuego del tutorial, adaptada al campo de pruebas.
## Lo abre campo_de_pruebas.gd al presionar E frente a $Colisiones/MinijuegoTuberias.
##
## - Al cerrar el panel (ESC o CERRAR) el juego se reinicia: la proxima vez se vuelve a revolver.
##
## - Clic izquierdo sobre una pieza: gira 90 grados a la derecha. Clic derecho: a la izquierda.
## - Hay que conectar la bateria con el foco. Las tuberias conectadas a la bateria se ven verdes.
## - Al completarlo el foco se enciende y se REVELA EL CODIGO en la misma ventana.
## - Si ya lo resolviste, al volver a abrirlo se muestra resuelto con el codigo (para releerlo).
##
## Para cambiar el nivel solo edita RUTA (la lista de celdas, en orden, de la bateria al foco).

signal circuito_reparado
signal cerrado

## Codigo que se muestra al completar (el script principal lo iguala al del panel de la puerta)
@export var codigo_a_revelar: String = "1480AJ"

const COLUMNAS: int = 5
const FILAS: int = 5
const TAM: float = 72.0

# Direcciones: bit 0 = arriba, 1 = derecha, 2 = abajo, 3 = izquierda
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

## Camino correcto (columna, fila), de la bateria (primero) al foco (ultimo).
## Las celdas que no estan en la lista se dibujan como muros.
const RUTA: Array[Vector2i] = [
	Vector2i(1, 2), Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(3, 4),
	Vector2i(3, 3), Vector2i(4, 3), Vector2i(4, 2), Vector2i(3, 2), Vector2i(3, 1),
	Vector2i(2, 1), Vector2i(1, 1), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
]

const COLOR_BORDE := Color(0.0, 0.0, 0.0, 1.0)
const COLOR_OK := Color(0.3, 1.0, 0.5)

var abierto: bool = false
var resuelto: bool = false

var _solucion: Dictionary = {}   # Vector2i -> mascara correcta
var _mascara: Dictionary = {}    # Vector2i -> mascara actual (la que se ve)
var _energia: Dictionary = {}    # Vector2i -> true si le llega corriente
var _anim: Dictionary = {}       # Vector2i -> animacion de giro (1 -> 0)
var _bateria: Vector2i
var _foco: Vector2i
var _foco_encendido: bool = false
var _tiempo: float = 0.0

var _tablero: Tablero
var _estado: Label
var _codigo: Label


## Control donde se dibuja el tablero; reenvia dibujo y clics al script principal
class Tablero extends Control:
	var juego
	func _draw() -> void:
		juego._dibujar_tablero(self)
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				juego._clic_tablero(event.position, 1)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				juego._clic_tablero(event.position, -1)


func _ready() -> void:
	layer = 50
	visible = false
	_calcular_solucion()
	_construir_ui()


func _process(delta: float) -> void:
	if not abierto:
		return
	_tiempo += delta
	for c in _anim.keys():
		_anim[c] = move_toward(_anim[c], 0.0, delta * 8.0)
		if _anim[c] == 0.0:
			_anim.erase(c)
	_tablero.queue_redraw()


func abrir() -> void:
	if resuelto:
		_mascara = _solucion.duplicate()
		_foco_encendido = true
	else:
		_barajar()
		_foco_encendido = false
		_codigo.modulate.a = 0.0
		_codigo.text = ""
		_estado.text = "Conecta la bateria con el foco"
		_estado.modulate = Color.WHITE
	_anim.clear()
	_calcular_energia()
	visible = true
	abierto = true


func cerrar() -> void:
	if not abierto:
		return
	abierto = false
	visible = false
	resuelto = false # al salir del panel el juego se reinicia
	_foco_encendido = false
	cerrado.emit()


# ---------------------------------------------------------------- logica

## Deduce de RUTA la mascara de conexiones correcta de cada celda
func _calcular_solucion() -> void:
	_solucion.clear()
	for i in RUTA.size():
		var m: int = 0
		if i > 0:
			m |= _bit_hacia(RUTA[i], RUTA[i - 1])
		if i < RUTA.size() - 1:
			m |= _bit_hacia(RUTA[i], RUTA[i + 1])
		_solucion[RUTA[i]] = m
	_bateria = RUTA[0]
	_foco = RUTA[RUTA.size() - 1]


func _bit_hacia(desde: Vector2i, hasta: Vector2i) -> int:
	return 1 << DIRS.find(hasta - desde)


func _girar_mascara(m: int, sentido: int) -> int:
	if sentido > 0:
		return ((m << 1) | (m >> 3)) & 15
	return ((m >> 1) | (m << 3)) & 15


## Gira al azar las piezas (la bateria y el foco no se mueven)
func _barajar() -> void:
	var intentos: int = 0
	while true:
		_mascara = _solucion.duplicate()
		var distintas: int = 0
		for c in _solucion.keys():
			if c == _bateria or c == _foco:
				continue
			for k in randi() % 4:
				_mascara[c] = _girar_mascara(_mascara[c], 1)
			if _mascara[c] != _solucion[c]:
				distintas += 1
		_calcular_energia()
		intentos += 1
		# Que quede bien revuelto y que no venga ya resuelto
		if (distintas >= 6 and not _energia.has(_foco)) or intentos > 50:
			break


## Rellena _energia con las celdas conectadas a la bateria. Devuelve true si llega al foco.
func _calcular_energia() -> bool:
	_energia.clear()
	_energia[_bateria] = true
	var pendientes: Array[Vector2i] = [_bateria]
	while not pendientes.is_empty():
		var c: Vector2i = pendientes.pop_back()
		for i in 4:
			if (_mascara[c] & (1 << i)) == 0:
				continue
			var v: Vector2i = c + DIRS[i]
			if not _mascara.has(v) or _energia.has(v):
				continue
			if (_mascara[v] & (1 << ((i + 2) % 4))) != 0:
				_energia[v] = true
				pendientes.append(v)
	return _energia.has(_foco)


func _clic_tablero(pos: Vector2, sentido: int) -> void:
	if resuelto:
		return
	var c := Vector2i(int(pos.x / TAM), int(pos.y / TAM))
	if not _mascara.has(c) or c == _bateria or c == _foco:
		return
	_mascara[c] = _girar_mascara(_mascara[c], sentido)
	_anim[c] = float(sentido)
	if _calcular_energia():
		_completar()


func _completar() -> void:
	resuelto = true
	_foco_encendido = true
	_estado.text = "CIRCUITO REPARADO"
	_estado.modulate = COLOR_OK
	circuito_reparado.emit()
	await get_tree().create_timer(0.7).timeout # deja ver el foco encendido

func _input(event: InputEvent) -> void:
	if not abierto:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			cerrar()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- dibujo

func _dibujar_tablero(ci: Control) -> void:
	for y in FILAS:
		for x in COLUMNAS:
			var origen := Vector2(x, y) * TAM
			if _mascara.has(Vector2i(x, y)):
				_dibujar_baldosa(ci, origen)
			else:
				_dibujar_muro(ci, origen)
	for c in _mascara.keys():
		_dibujar_pieza(ci, c)


func _dibujar_muro(ci: Control, o: Vector2) -> void:
	ci.draw_rect(Rect2(o, Vector2(TAM, TAM)), Color(0.05, 0.05, 0.07))
	var r := Rect2(o + Vector2(2, 2), Vector2(TAM - 4, TAM - 4))
	ci.draw_rect(r, Color(0.6, 0.5, 0.42))
	# triangulo oscuro (el efecto diagonal del arte original)
	ci.draw_colored_polygon(PackedVector2Array([
		r.position + Vector2(r.size.x, 0), r.position + r.size, r.position + Vector2(0, r.size.y)]),
		Color(0.5, 0.41, 0.35))
	_remaches(ci, r, Color(0.2, 0.15, 0.12))


func _dibujar_baldosa(ci: Control, o: Vector2) -> void:
	ci.draw_rect(Rect2(o, Vector2(TAM, TAM)), Color(0.05, 0.05, 0.07))
	var r := Rect2(o + Vector2(2, 2), Vector2(TAM - 4, TAM - 4))
	ci.draw_rect(r, Color(0.82, 0.83, 0.85))
	_remaches(ci, r, Color(0.15, 0.15, 0.18))


func _remaches(ci: Control, r: Rect2, color: Color) -> void:
	for dx in [6.0, r.size.x - 6.0]:
		for dy in [6.0, r.size.y - 6.0]:
			ci.draw_circle(r.position + Vector2(dx, dy), 1.8, color)


func _dibujar_pieza(ci: Control, c: Vector2i) -> void:
	var centro := (Vector2(c) + Vector2(0.5, 0.5)) * TAM
	var giro: float = _anim.get(c, 0.0)
	ci.draw_set_transform(centro, -giro * PI * 0.5, Vector2.ONE)

	var ancho: float = TAM * 0.2
	var puntos := _trazo(_mascara[c])
	var energizada: bool = _energia.has(c)
	ci.draw_polyline(puntos, Color(0.45, 0.08, 0.08), ancho + 6.0)
	ci.draw_polyline(puntos, Color(0.92, 0.27, 0.27), ancho)
	if energizada:
		ci.draw_polyline(puntos, Color(0.25, 0.85, 0.4), ancho * 0.55)
	else:
		ci.draw_polyline(puntos, Color(1.0, 0.65, 0.65), ancho * 0.3)

	if c == _bateria:
		_dibujar_bateria(ci)
	elif c == _foco:
		_dibujar_foco(ci)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Linea de la tuberia (relativa al centro de la celda) segun sus conexiones
func _trazo(m: int) -> PackedVector2Array:
	var dirs: Array[Vector2] = []
	for i in 4:
		if (m & (1 << i)) != 0:
			dirs.append(Vector2(DIRS[i]))
	var h: float = TAM * 0.5
	if dirs.size() == 1:
		return PackedVector2Array([Vector2.ZERO, dirs[0] * h])
	if dirs[0] == -dirs[1]:
		return PackedVector2Array([dirs[0] * h, dirs[1] * h])
	# Curva: cuarto de circulo alrededor de la esquina compartida
	var esquina: Vector2 = (dirs[0] + dirs[1]) * h
	var a0: float = (-dirs[1]).angle()
	var delta: float = angle_difference(a0, (-dirs[0]).angle())
	var pts := PackedVector2Array()
	for k in 13:
		pts.append(esquina + Vector2.from_angle(a0 + delta * k / 12.0) * h)
	return pts


func _dibujar_bateria(ci: Control) -> void:
	ci.draw_rect(Rect2(-15, -27, 30, 54), Color(0.05, 0.05, 0.05))
	ci.draw_rect(Rect2(-15, -27, 30, 20), Color(1.0, 0.75, 0.1))
	ci.draw_rect(Rect2(-6, -33, 12, 6), Color(0.7, 0.7, 0.7))
	ci.draw_polyline(PackedVector2Array([
		Vector2(3, -2), Vector2(-4, 8), Vector2(2, 8), Vector2(-3, 20)]), Color(0.95, 0.2, 0.2), 3.0)


func _dibujar_foco(ci: Control) -> void:
	var pos := Vector2(6, 0)
	ci.draw_rect(Rect2(-14, -7, 14, 14), Color(0.2, 0.2, 0.22)) # casquillo
	if _foco_encendido:
		var pulso: float = 0.8 + 0.2 * sin(_tiempo * 5.0)
		ci.draw_circle(pos, 46.0 * pulso, Color(1.0, 0.95, 0.5, 0.12))
		ci.draw_circle(pos, 34.0 * pulso, Color(1.0, 0.95, 0.5, 0.22))
		ci.draw_circle(pos, 22.0, Color(1.0, 0.97, 0.6))
	else:
		ci.draw_circle(pos, 22.0, Color(0.75, 0.9, 0.95, 0.85))
		ci.draw_arc(pos, 22.0, 0.0, TAU, 24, Color(0.4, 0.55, 0.6), 2.0)


# ---------------------------------------------------------------- interfaz

func _construir_ui() -> void:
	var raiz := Control.new()
	raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	raiz.mouse_filter = Control.MOUSE_FILTER_STOP # los clics no pasan al juego
	add_child(raiz)

	var oscuro := ColorRect.new()
	oscuro.color = Color(0, 0, 0, 0.7)
	oscuro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	oscuro.mouse_filter = Control.MOUSE_FILTER_STOP
	raiz.add_child(oscuro)

	var centro := CenterContainer.new()
	centro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz.add_child(centro)

	var panel := PanelContainer.new()
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.04, 0.07, 0.16, 0.98)
	estilo.border_color = COLOR_BORDE
	estilo.set_border_width_all(3)
	estilo.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", estilo)
	centro.add_child(panel)

	var margen := MarginContainer.new()
	for lado in ["left", "right", "top", "bottom"]:
		margen.add_theme_constant_override("margin_" + lado, 20)
	panel.add_child(margen)

	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 10)
	margen.add_child(caja)

	var titulo := Label.new()
	titulo.text = "REPARAR CIRCUITO"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 26)
	titulo.add_theme_color_override("font_color", Color.WHITE)
	caja.add_child(titulo)

	var ayuda := Label.new()
	ayuda.text = "Clic izquierdo: girar a la derecha  |  Clic derecho: girar a la izquierda"
	ayuda.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ayuda.add_theme_font_size_override("font_size", 17)
	ayuda.modulate = Color(0.75, 0.8, 0.9)
	caja.add_child(ayuda)

	_tablero = Tablero.new()
	_tablero.juego = self
	_tablero.custom_minimum_size = Vector2(COLUMNAS, FILAS) * TAM
	_tablero.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_tablero.mouse_filter = Control.MOUSE_FILTER_STOP
	caja.add_child(_tablero)

	_estado = Label.new()
	_estado.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_estado.add_theme_font_size_override("font_size", 18)
	caja.add_child(_estado)

	_codigo = Label.new()
	_codigo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_codigo.custom_minimum_size = Vector2(0, 44)
	_codigo.add_theme_font_size_override("font_size", 34)
	_codigo.add_theme_color_override("font_color", COLOR_OK)
	_codigo.modulate.a = 0.0
	caja.add_child(_codigo)

	var cerrar_btn := Button.new()
	cerrar_btn.text = "CERRAR"
	cerrar_btn.custom_minimum_size = Vector2(160, 44)
	cerrar_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cerrar_btn.focus_mode = Control.FOCUS_NONE
	cerrar_btn.add_theme_font_size_override("font_size", 20)
	cerrar_btn.pressed.connect(cerrar)
	caja.add_child(cerrar_btn)
