extends CanvasLayer
## MINIJUEGO 1: TERMINAL DE CULTURA GENERAL
## Se construye por codigo. Lo abre campo_de_pruebas.gd al presionar E frente a
## $Colisiones/MinijuegoPreguntas.
##
## - Tres preguntas, una a la vez. Se responde escribiendo en un campo de texto (Enter o CONFIRMAR).
## - La respuesta se valida SIN importar mayusculas/minusculas, acentos ni espacios de mas.
## - Si es correcta entrega un numero de un solo digito; si no, se vuelve a intentar sin avanzar.
## - Al terminar las tres emite "completado" con los tres numeros, en orden.
## - Al cerrar el panel (ESC o CERRAR) el juego se reinicia desde la pregunta 1.
##
## PARA CAMBIAR PREGUNTAS/RESPUESTAS: edita PREGUNTAS (cada una puede tener varias respuestas validas).
## PARA CAMBIAR LOS NUMEROS: NO estan aqui; se configuran en el Inspector del nodo CampoDePruebas
## (grupo "Terminal de cultura general" > Digitos Terminal), asi son independientes de las respuestas.

signal completado(digitos: Array)
signal cerrado

const NOMBRE_TERMINAL: String = "TERMINAL ALFA-7"

const PREGUNTAS: Array = [
	{"texto": "¿Cuál es el planeta más grande del sistema solar?", "respuestas": ["Júpiter"]},
	{"texto": "¿Cuál es la capital de Francia?", "respuestas": ["París"]},
	{"texto": "¿Quién pintó la Mona Lisa?", "respuestas": ["Leonardo da Vinci", "Da Vinci", "Leonardo"]},
]
const COLOR_BORDE := Color(0, 0, 0, 1)
const COLOR_CIAN := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_OK := Color(0.3, 1.0, 0.5)
const COLOR_ERROR := Color(1.0, 0.3, 0.3)
const COLOR_TEXTO := Color(0.8, 0.95, 1.0)
const COLOR_FONDO := Color(0.02, 0.05, 0.1, 0.98)

## Los numeros que entrega cada pregunta (los pone campo_de_pruebas.gd)
var digitos: Array[int] = [7, 3, 9]

var abierto: bool = false

var _indice: int = 0
var _obtenidos: Array[int] = []
var _bloqueado: bool = false
var _gen: int = 0 # sirve para cancelar esperas pendientes al cerrar/reiniciar

var _fuente: SystemFont
var _estilo_panel: StyleBoxFlat
var _lbl_numero: Label
var _lbl_pregunta: Label
var _campo: LineEdit
var _btn_confirmar: Button
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
	_indice = 0
	_obtenidos.clear()
	_bloqueado = false
	_mostrar_pregunta()
	visible = true
	abierto = true
	_campo.grab_focus.call_deferred()


func cerrar() -> void:
	if not abierto:
		return
	_gen += 1 # cancela cualquier espera pendiente
	abierto = false
	visible = false
	_campo.release_focus()
	cerrado.emit()


# ---------------------------------------------------------------- logica

func _mostrar_pregunta() -> void:
	_bloqueado = false
	_lbl_numero.text = "PREGUNTA %d / %d" % [_indice + 1, PREGUNTAS.size()]
	_lbl_pregunta.text = str(PREGUNTAS[_indice]["texto"])
	_campo.text = ""
	_campo.editable = true
	_btn_confirmar.disabled = false
	_poner_mensaje("Esperando respuesta...", COLOR_CIAN)
	_actualizar_progreso()
	_campo.grab_focus.call_deferred()


func _actualizar_progreso() -> void:
	var total: int = PREGUNTAS.size()
	_barra.max_value = total
	_barra.value = _obtenidos.size()
	_lbl_progreso.text = "PROGRESO: %d / %d" % [_obtenidos.size(), total]
	var partes: PackedStringArray = []
	for i in total:
		partes.append(str(_obtenidos[i]) if i < _obtenidos.size() else "_")
	_lbl_digitos.text = "NÚMEROS:  " + "  ·  ".join(partes)


func _on_confirmar() -> void:
	if _bloqueado:
		return
	var respuesta: String = _normalizar(_campo.text)
	if respuesta.is_empty():
		_poner_mensaje("Escribe una respuesta antes de confirmar", Color(1.0, 0.85, 0.3))
		_campo.grab_focus()
		return
	if _es_correcta(respuesta):
		_acertar()
	else:
		_fallar()


func _es_correcta(respuesta_normalizada: String) -> bool:
	for valida in PREGUNTAS[_indice]["respuestas"]:
		if _normalizar(str(valida)) == respuesta_normalizada:
			return true
	return false


## Minusculas, sin acentos y sin espacios de mas (al inicio, al final o repetidos)
static func _normalizar(texto: String) -> String:
	var s: String = texto.strip_edges().to_lower()
	var con_acento: String = "áéíóúü"
	var sin_acento: String = "aeiouu"
	for i in con_acento.length():
		s = s.replace(con_acento[i], sin_acento[i])
	# Espacios de mas: tabulaciones a espacio, y se quitan los repetidos / de los extremos
	s = s.replace("\t", " ")
	return " ".join(s.split(" ", false))


func _acertar() -> void:
	_bloqueado = true
	var gen: int = _gen
	var numero: int = 0
	if _indice < digitos.size():
		numero = clampi(digitos[_indice], 0, 9)
	_obtenidos.append(numero)
	_campo.editable = false
	_btn_confirmar.disabled = true
	_poner_mensaje("RESPUESTA CORRECTA  -  NÚMERO OBTENIDO: %d" % numero, COLOR_OK)
	_actualizar_progreso()

	if _obtenidos.size() >= PREGUNTAS.size():
		_lbl_numero.text = "TERMINAL COMPLETADA"
		_lbl_pregunta.text = "Acceso parcial concedido. Memoriza los números obtenidos."
		completado.emit(_obtenidos.duplicate())
		return

	await get_tree().create_timer(1.4).timeout
	if gen != _gen:
		return
	_indice += 1
	_mostrar_pregunta()


func _fallar() -> void:
	_poner_mensaje("RESPUESTA INCORRECTA  -  INTÉNTALO DE NUEVO", COLOR_ERROR)
	_campo.text = ""
	_campo.grab_focus()
	create_tween().tween_property(_estilo_panel, "border_color", COLOR_BORDE, 0.6).from(COLOR_ERROR)


func _poner_mensaje(texto: String, color: Color) -> void:
	_lbl_mensaje.text = texto
	_lbl_mensaje.add_theme_color_override("font_color", color)


func _input(event: InputEvent) -> void:
	if not abierto:
		return
	# Solo se atrapa ESC: el resto de teclas debe llegar al campo de texto
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		cerrar()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- interfaz

func _construir_ui() -> void:
	_fuente = SystemFont.new()
	_fuente.font_names = PackedStringArray(["Consolas", "Courier New", "DejaVu Sans Mono", "monospace"])

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
	_estilo_panel = _estilo(COLOR_FONDO, COLOR_BORDE, 2, 6)
	panel.add_theme_stylebox_override("panel", _estilo_panel)
	centro.add_child(panel)

	var margen := MarginContainer.new()
	for lado in ["left", "right", "top", "bottom"]:
		margen.add_theme_constant_override("margin_" + lado, 26)
	panel.add_child(margen)

	var caja := VBoxContainer.new()
	caja.custom_minimum_size = Vector2(640, 0)
	caja.add_theme_constant_override("separation", 12)
	margen.add_child(caja)

	# --- Cabecera: nombre de la terminal + estado
	var cabecera := HBoxContainer.new()
	caja.add_child(cabecera)
	var nombre := _label(NOMBRE_TERMINAL, 26, COLOR_CIAN)
	nombre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cabecera.add_child(nombre)
	caja.add_child(_linea())

	# --- Numero de pregunta y pregunta
	_lbl_numero = _label("", 18, Color(1.0, 1.0, 1.0, 1.0))
	caja.add_child(_lbl_numero)

	var marco_pregunta := PanelContainer.new()
	marco_pregunta.add_theme_stylebox_override("panel", _estilo(Color(0.0, 0.1, 0.15), COLOR_BORDE, 1, 3))
	caja.add_child(marco_pregunta)
	var margen_pregunta := MarginContainer.new()
	for lado in ["left", "right", "top", "bottom"]:
		margen_pregunta.add_theme_constant_override("margin_" + lado, 14)
	marco_pregunta.add_child(margen_pregunta)
	_lbl_pregunta = _label("", 24, COLOR_TEXTO)
	_lbl_pregunta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_pregunta.custom_minimum_size = Vector2(0, 72)
	_lbl_pregunta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	margen_pregunta.add_child(_lbl_pregunta)

	# --- Campo de respuesta + boton confirmar
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 10)
	caja.add_child(fila)
	fila.add_child(_label(">", 28, COLOR_CIAN))

	_campo = LineEdit.new()
	_campo.placeholder_text = "escribe tu respuesta..."
	_campo.custom_minimum_size = Vector2(0, 46)
	_campo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_campo.add_theme_font_override("font", _fuente)
	_campo.add_theme_font_size_override("font_size", 22)
	_campo.add_theme_color_override("font_color", COLOR_TEXTO)
	_campo.add_theme_color_override("caret_color", COLOR_CIAN)
	_campo.add_theme_color_override("font_placeholder_color", Color(0.4, 0.55, 0.6))
	_campo.add_theme_stylebox_override("normal", _estilo(Color(0.0, 0.07, 0.1), COLOR_BORDE, 2, 3))
	_campo.add_theme_stylebox_override("focus", _estilo(Color(0.0, 0.09, 0.13), COLOR_BORDE, 2, 3))
	_campo.add_theme_stylebox_override("read_only", _estilo(Color(0.0, 0.05, 0.07), COLOR_BORDE, 2, 3))
	_campo.text_submitted.connect(func(_texto: String) -> void: _on_confirmar())
	fila.add_child(_campo)

	_btn_confirmar = _boton("CONFIRMAR", COLOR_OK.darkened(0.55), COLOR_OK, _on_confirmar, Vector2(160, 46))
	fila.add_child(_btn_confirmar)

	# --- Mensaje de correcto / incorrecto
	_lbl_mensaje = _label("", 20, COLOR_CIAN)
	_lbl_mensaje.custom_minimum_size = Vector2(0, 30)
	caja.add_child(_lbl_mensaje)

	caja.add_child(_linea())

	# --- Indicador de progreso
	_lbl_progreso = _label("", 16, Color(0.55, 0.8, 0.9))
	caja.add_child(_lbl_progreso)
	_barra = ProgressBar.new()
	_barra.show_percentage = false
	_barra.custom_minimum_size = Vector2(0, 14)
	_barra.add_theme_stylebox_override("background", _estilo(Color(0.0, 0.07, 0.1), COLOR_BORDE, 1, 2))
	_barra.add_theme_stylebox_override("fill", _estilo(COLOR_CIAN, COLOR_CIAN, 0, 2))
	caja.add_child(_barra)
	_lbl_digitos = _label("", 22, COLOR_OK)
	caja.add_child(_lbl_digitos)

	var cerrar_btn := _boton("CERRAR", Color(0.12, 0.12, 0.2), Color(0.6, 0.6, 0.8), cerrar, Vector2(150, 44))
	cerrar_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	caja.add_child(cerrar_btn)


func _label(texto: String, tam: int, color: Color) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_override("font", _fuente)
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	return l


func _linea() -> ColorRect:
	var r := ColorRect.new()
	r.color = COLOR_BORDE
	r.custom_minimum_size = Vector2(0, 2)
	return r


func _boton(texto: String, fondo: Color, borde: Color, accion: Callable, tam: Vector2) -> Button:
	var b := Button.new()
	b.text = texto
	b.custom_minimum_size = tam
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _fuente)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_stylebox_override("normal", _estilo(fondo, COLOR_BORDE, 2, 4))
	b.add_theme_stylebox_override("hover", _estilo(fondo.lightened(0.2), COLOR_BORDE, 3, 4))
	b.add_theme_stylebox_override("pressed", _estilo(fondo.lightened(0.4), COLOR_BORDE, 3, 4))
	b.add_theme_stylebox_override("disabled", _estilo(fondo.darkened(0.4), COLOR_BORDE, 2, 4))
	b.pressed.connect(accion)
	return b


func _estilo(fondo: Color, borde: Color, grosor: int, radio: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fondo
	s.border_color = borde
	s.set_border_width_all(grosor)
	s.set_corner_radius_all(radio)
	return s
