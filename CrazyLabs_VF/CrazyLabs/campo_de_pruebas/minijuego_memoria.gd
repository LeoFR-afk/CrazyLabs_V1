extends CanvasLayer
## MINIJUEGO 2: MEMORIA DE COLORES
## Se construye por codigo. Lo abre campo_de_pruebas.gd al presionar E frente a
## $Colisiones/MinijuegoMemoria.
##
## - Cuatro botones de colores: rojo, azul, verde y amarillo.
## - Se ilumina una secuencia aleatoria, uno por uno; luego el jugador la repite con clics.
## - Tres rondas con secuencias cada vez mas largas (3, 4 y 5 colores).
## - Cada ronda superada entrega un digito. Si se equivoca, repite la ronda actual.
## - Al terminar emite "completado" con los tres digitos, en orden.
## - Al cerrar el panel (ESC o CERRAR) el juego se reinicia desde la ronda 1.
##
## PARA CAMBIAR LOS DIGITOS Y LA LONGITUD DE CADA RONDA: Inspector del nodo CampoDePruebas
## (grupo "Memoria de colores"). Aqui solo estan los tiempos y la opcion de abajo.

signal completado(digitos: Array)
signal cerrado

## Segundos que se queda encendido cada color durante la secuencia
const TIEMPO_ENCENDIDO: float = 0.55
## Segundos de pausa (apagado) entre un color y el siguiente
const TIEMPO_PAUSA: float = 0.25
## Si es true, al equivocarse la ronda se repite con una secuencia NUEVA; si es false, con la misma
const REGENERAR_AL_FALLAR: bool = false


const COLORES: Array = [
	Color(0.9, 0.12, 0.12),
	Color(0.15, 0.4, 1.0),
	Color(0.15, 0.8, 0.25),
	Color(1.0, 0.85, 0.1),
]

const COLOR_CIAN := Color(0.0, 0.0, 0.0, 1.0)
const COLOR_OK := Color(0.302, 1.0, 0.502, 0.671)
const COLOR_ERROR := Color(1.0, 0.302, 0.302, 0.686)
const COLOR_AVISO := Color(1.0, 1.0, 1.0, 1.0)

enum Fase { BLOQUEADO, MOSTRANDO, ENTRADA }

## Digito que entrega cada ronda y largo de cada secuencia (los pone campo_de_pruebas.gd)
var digitos: Array[int] = [4, 8, 2]
var longitudes: Array[int] = [3, 4, 5]

var abierto: bool = false

var _fase: Fase = Fase.BLOQUEADO
var _ronda: int = 0
var _secuencia: Array[int] = []
var _paso: int = 0 # cuantos colores lleva acertados el jugador en esta ronda
var _obtenidos: Array[int] = []
var _gen: int = 0 # sirve para cancelar esperas pendientes al cerrar/reiniciar

var _estilo_panel: StyleBoxFlat
var _botones: Array[Button] = []
var _lbl_ronda: Label
var _lbl_mensaje: Label
var _barra: ProgressBar
var _lbl_progreso: Label
var _lbl_digitos: Label


func _ready() -> void:
	layer = 50
	visible = false
	_construir_ui()


func abrir() -> void:
	_gen += 1
	_ronda = 0
	_obtenidos.clear()
	_secuencia.clear()
	_apagar_todos()
	visible = true
	abierto = true
	_iniciar_ronda(true)


func cerrar() -> void:
	if not abierto:
		return
	_gen += 1 # cancela la secuencia / esperas pendientes
	abierto = false
	visible = false
	_fase = Fase.BLOQUEADO
	_apagar_todos()
	cerrado.emit()


# ---------------------------------------------------------------- logica

func _total_rondas() -> int:
	return longitudes.size()


func _iniciar_ronda(nueva_secuencia: bool) -> void:
	var gen: int = _gen
	_fase = Fase.BLOQUEADO
	_paso = 0
	if nueva_secuencia:
		_secuencia = _generar_secuencia(longitudes[_ronda])
	_actualizar_indicadores()
	_poner_mensaje("Observa la secuencia...", COLOR_AVISO)

	await get_tree().create_timer(0.9).timeout
	if gen != _gen:
		return

	_fase = Fase.MOSTRANDO
	for color in _secuencia:
		_encender(color, true)
		await get_tree().create_timer(TIEMPO_ENCENDIDO).timeout
		if gen != _gen:
			return
		_encender(color, false)
		await get_tree().create_timer(TIEMPO_PAUSA).timeout
		if gen != _gen:
			return

	_fase = Fase.ENTRADA
	_poner_mensaje("Tu turno: repite la secuencia", Color.BLACK)


func _generar_secuencia(largo: int) -> Array[int]:
	var seq: Array[int] = []
	for i in largo:
		seq.append(randi() % 4)
	return seq


func _pulsar(color: int) -> void:
	if _fase != Fase.ENTRADA:
		return
	_destello(color)
	if color == _secuencia[_paso]:
		_paso += 1
		_actualizar_indicadores()
		if _paso >= _secuencia.size():
			_acertar_ronda()
	else:
		_fallar_ronda()


func _acertar_ronda() -> void:
	_fase = Fase.BLOQUEADO
	var gen: int = _gen
	var digito: int = 0
	if _ronda < digitos.size():
		digito = clampi(digitos[_ronda], 0, 9)
	_obtenidos.append(digito)
	_actualizar_indicadores()

	if _obtenidos.size() >= _total_rondas():
		_poner_mensaje("¡CORRECTO! Dígito obtenido: %d  -  ¡MEMORIA COMPLETADA!" % digito, COLOR_OK)
		completado.emit(_obtenidos.duplicate())
		return

	_poner_mensaje("¡CORRECTO! Dígito obtenido: %d" % digito, COLOR_OK)
	await get_tree().create_timer(1.6).timeout
	if gen != _gen:
		return
	_ronda += 1
	_iniciar_ronda(true)


func _fallar_ronda() -> void:
	_fase = Fase.BLOQUEADO
	var gen: int = _gen
	_poner_mensaje("¡ERROR! Debes repetir la ronda", COLOR_ERROR)
	create_tween().tween_property(_estilo_panel, "border_color", Color.BLACK, 0.7).from(COLOR_ERROR)
	await get_tree().create_timer(1.4).timeout
	if gen != _gen:
		return
	_iniciar_ronda(REGENERAR_AL_FALLAR)


func _actualizar_indicadores() -> void:
	var total: int = _total_rondas()
	_lbl_ronda.text = "RONDA %d / %d   (%d colores)" % [mini(_ronda + 1, total), total, _secuencia.size()]
	_barra.max_value = total
	_barra.value = _obtenidos.size()
	_lbl_progreso.text = "PROGRESO: %d / %d rondas   |   Pasos: %d / %d" % [_obtenidos.size(), total, _paso, _secuencia.size()]
	var partes: PackedStringArray = []
	for i in total:
		partes.append(str(_obtenidos[i]) if i < _obtenidos.size() else "_")
	_lbl_digitos.text = "DÍGITOS:  " + "  ·  ".join(partes)


func _poner_mensaje(texto: String, color: Color) -> void:
	_lbl_mensaje.text = texto
	_lbl_mensaje.add_theme_color_override("font_color", color)


func _input(event: InputEvent) -> void:
	if not abierto:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			cerrar()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- iluminacion

func _encender(color: int, encendido: bool) -> void:
	var estilo: StyleBoxFlat = _estilo_boton(color, encendido)
	var b: Button = _botones[color]
	for estado in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(estado, estilo)


func _apagar_todos() -> void:
	for i in _botones.size():
		_encender(i, false)


## Destello corto al hacer clic en un boton
func _destello(color: int) -> void:
	var gen: int = _gen
	_encender(color, true)
	await get_tree().create_timer(0.2).timeout
	if gen != _gen:
		return
	_encender(color, false)


func _estilo_boton(color: int, encendido: bool) -> StyleBoxFlat:
	var base: Color = COLORES[color]
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(14)
	s.set_border_width_all(4)
	if encendido:
		s.bg_color = base.lightened(0.3)
		s.border_color = Color.WHITE
		s.shadow_color = Color(base, 0.85)
		s.shadow_size = 30
	else:
		s.bg_color = base.darkened(0.6)
		s.border_color = base.darkened(0.75)
	return s


# ---------------------------------------------------------------- interfaz

func _construir_ui() -> void:
	var raiz := Control.new()
	raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	raiz.mouse_filter = Control.MOUSE_FILTER_STOP # los clics no pasan al juego
	add_child(raiz)

	var oscuro := ColorRect.new()
	oscuro.color = Color(0, 0, 0, 0.72)
	oscuro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	oscuro.mouse_filter = Control.MOUSE_FILTER_STOP
	raiz.add_child(oscuro)

	var centro := CenterContainer.new()
	centro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz.add_child(centro)

	var panel := PanelContainer.new()
	_estilo_panel = StyleBoxFlat.new()
	_estilo_panel.bg_color = Color(0.04, 0.05, 0.12, 0.98)
	_estilo_panel.border_color = Color.BLACK
	_estilo_panel.set_border_width_all(2)
	_estilo_panel.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", _estilo_panel)
	centro.add_child(panel)

	var margen := MarginContainer.new()
	for lado in ["left", "right", "top", "bottom"]:
		margen.add_theme_constant_override("margin_" + lado, 24)
	panel.add_child(margen)

	var caja := VBoxContainer.new()
	caja.custom_minimum_size = Vector2(500, 0)
	caja.add_theme_constant_override("separation", 10)
	margen.add_child(caja)

	var titulo := _label("MEMORIA DE COLORES", 28, Color.WHITE)
	caja.add_child(titulo)

	_lbl_ronda = _label("", 20, Color.WHITE)
	caja.add_child(_lbl_ronda)

	# --- Los cuatro botones de colores (2 x 2)
	var rejilla := GridContainer.new()
	rejilla.columns = 2
	rejilla.add_theme_constant_override("h_separation", 14)
	rejilla.add_theme_constant_override("v_separation", 14)
	rejilla.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	caja.add_child(rejilla)
	for i in 4:
		var b := Button.new()

		b.custom_minimum_size = Vector2(200, 110)
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_font_size_override("font_size", 22)
		b.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
		b.add_theme_color_override("font_hover_color", Color(1, 1, 1, 0.75))
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.button_down.connect(_pulsar.bind(i))
		rejilla.add_child(b)
		_botones.append(b)
	_apagar_todos()

	# --- Mensajes de acierto / error
	_lbl_mensaje = _label("", 20, COLOR_CIAN)
	_lbl_mensaje.custom_minimum_size = Vector2(0, 30)
	_lbl_mensaje.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caja.add_child(_lbl_mensaje)

	# --- Indicador de progreso
	_lbl_progreso = _label("", 16, Color(0.7, 0.8, 0.95))
	_lbl_progreso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caja.add_child(_lbl_progreso)
	_barra = ProgressBar.new()
	_barra.show_percentage = false
	_barra.custom_minimum_size = Vector2(0, 14)
	_barra.add_theme_stylebox_override("background", _estilo(Color(0.02, 0.04, 0.1), COLOR_CIAN.darkened(0.5), 1, 2))
	_barra.add_theme_stylebox_override("fill", _estilo(COLOR_CIAN, COLOR_CIAN, 0, 2))
	caja.add_child(_barra)
	_lbl_digitos = _label("", 22, COLOR_OK)
	_lbl_digitos.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caja.add_child(_lbl_digitos)

	var cerrar_btn := Button.new()
	cerrar_btn.text = "CERRAR"
	cerrar_btn.custom_minimum_size = Vector2(150, 44)
	cerrar_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cerrar_btn.focus_mode = Control.FOCUS_NONE
	cerrar_btn.add_theme_font_size_override("font_size", 20)
	cerrar_btn.pressed.connect(cerrar)
	caja.add_child(cerrar_btn)


func _label(texto: String, tam: int, color: Color) -> Label:
	var l := Label.new()
	l.text = texto
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	return l


func _estilo(fondo: Color, borde: Color, grosor: int, radio: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fondo
	s.border_color = borde
	s.set_border_width_all(grosor)
	s.set_corner_radius_all(radio)
	return s
