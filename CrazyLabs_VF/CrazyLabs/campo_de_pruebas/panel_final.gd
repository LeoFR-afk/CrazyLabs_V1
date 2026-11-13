extends CanvasLayer
## PANEL DE CONTRASEÑA FINAL
## Se construye por codigo. Lo abre campo_de_pruebas.gd al presionar E frente a
## $Colisiones/PanelFinal, y SOLO si ya se completaron la terminal y el minijuego de memoria.
##
## - Pantalla con 6 espacios para los digitos, teclado numerico 0-9, BORRAR y CONFIRMAR.
## - La contrasena es: 3 digitos de la terminal + 3 digitos de memoria (ej. 739482).
##   campo_de_pruebas.gd la arma y la guarda en "contrasena_correcta" antes de abrir.
## - Correcta -> "ACCESO CONCEDIDO" (emite acceso_concedido). Incorrecta -> "ACCESO DENEGADO".
## - Tambien se puede escribir con el teclado fisico: digitos, Backspace, Enter y ESC.
## - Al cerrar el panel (ESC o CERRAR) se reinicia.

signal acceso_concedido
signal cerrado

const LONGITUD: int = 6
const COLOR_BORDE := Color(0, 0, 0, 1)
const COLOR_CIAN := Color(0.25, 0.9, 1.0)
const COLOR_OK := Color(0.3, 1.0, 0.5)
const COLOR_ERROR := Color(1.0, 0.3, 0.3)

var contrasena_correcta: String = "739482"

var abierto: bool = false

var _ingresado: String = ""
var _bloqueado: bool = false
var _gen: int = 0 # sirve para cancelar esperas pendientes al cerrar
var _color_resultado: Color = Color(0, 0, 0, 0) # alfa 0 = sin resultado que mostrar

var _slots: Array[Label] = []
var _marcos: Array[PanelContainer] = []
var _estado: Label


func _ready() -> void:
	layer = 50
	visible = false
	_construir_ui()


func abrir() -> void:
	_gen += 1
	_ingresado = ""
	_bloqueado = false
	_color_resultado = Color(0, 0, 0, 0)
	_poner_estado("Introduce la contraseña de 6 dígitos", Color.WHITE)
	_actualizar_pantalla()
	visible = true
	abierto = true


func cerrar() -> void:
	if not abierto:
		return
	_gen += 1 # cancela esperas pendientes
	abierto = false
	visible = false
	cerrado.emit()


# ---------------------------------------------------------------- logica

func _agregar(digito: String) -> void:
	if _bloqueado or _ingresado.length() >= LONGITUD:
		return
	_ingresado += digito
	_actualizar_pantalla()


func _borrar() -> void:
	if _bloqueado or _ingresado.is_empty():
		return
	_ingresado = _ingresado.left(_ingresado.length() - 1)
	_actualizar_pantalla()


func _confirmar() -> void:
	if _bloqueado:
		return
	if _ingresado.length() < LONGITUD:
		_poner_estado("Faltan dígitos: ingresa los %d" % LONGITUD, Color(1.0, 0.85, 0.3))
		return

	_bloqueado = true
	var gen: int = _gen
	if _ingresado == contrasena_correcta:
		_color_resultado = COLOR_OK
		_poner_estado("ACCESO CONCEDIDO", COLOR_OK)
		_actualizar_pantalla()
		acceso_concedido.emit()
		await get_tree().create_timer(1.6).timeout
		if gen != _gen:
			return
		cerrar()
	else:
		_color_resultado = COLOR_ERROR
		_poner_estado("ACCESO DENEGADO", COLOR_ERROR)
		_actualizar_pantalla()
		await get_tree().create_timer(1.1).timeout
		if gen != _gen:
			return
		_ingresado = ""
		_bloqueado = false
		_color_resultado = Color(0, 0, 0, 0)
		_poner_estado("Introduce la contraseña de 6 dígitos", Color.WHITE)
		_actualizar_pantalla()


func _poner_estado(texto: String, color: Color) -> void:
	_estado.text = texto
	_estado.add_theme_color_override("font_color", color)


func _actualizar_pantalla() -> void:
	for i in LONGITUD:
		var lleno: bool = i < _ingresado.length()
		_slots[i].text = _ingresado[i] if lleno else "_"
		var borde: Color = COLOR_BORDE
		var texto: Color = Color.WHITE if lleno else Color(1, 1, 1, 0.35)
		if _color_resultado.a > 0.0:
			texto = _color_resultado
			borde = _color_resultado
		_slots[i].add_theme_color_override("font_color", texto)
		_marcos[i].add_theme_stylebox_override("panel", _estilo(Color(0.02, 0.03, 0.08), borde, 2, 4))


func _input(event: InputEvent) -> void:
	if not abierto:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			cerrar()
		elif event.keycode == KEY_BACKSPACE:
			_borrar()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_confirmar()
		elif event.unicode > 0:
			var c: String = char(event.unicode)
			if c.length() == 1 and c >= "0" and c <= "9":
				_agregar(c)
		get_viewport().set_input_as_handled()


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
	panel.add_theme_stylebox_override("panel", _estilo(Color(0.04, 0.07, 0.16, 0.98), COLOR_BORDE, 2, 8))
	centro.add_child(panel)

	var margen := MarginContainer.new()
	for lado in ["left", "right", "top", "bottom"]:
		margen.add_theme_constant_override("margin_" + lado, 24)
	panel.add_child(margen)

	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 14)
	margen.add_child(caja)

	var titulo := Label.new()
	titulo.text = "PANEL DE SEGURIDAD"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 28)
	caja.add_child(titulo)

	# --- Pantalla con los 6 espacios
	var fila_slots := HBoxContainer.new()
	fila_slots.alignment = BoxContainer.ALIGNMENT_CENTER
	fila_slots.add_theme_constant_override("separation", 8)
	caja.add_child(fila_slots)
	for i in LONGITUD:
		var marco := PanelContainer.new()
		marco.custom_minimum_size = Vector2(56, 76)
		fila_slots.add_child(marco)
		var l := Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 44)
		marco.add_child(l)
		_marcos.append(marco)
		_slots.append(l)

	_estado = Label.new()
	_estado.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_estado.custom_minimum_size = Vector2(0, 30)
	_estado.add_theme_font_size_override("font_size", 20)
	caja.add_child(_estado)

	# --- Teclado numerico: 1-9, y abajo BORRAR 0 CONFIRMAR
	var teclado := GridContainer.new()
	teclado.columns = 3
	teclado.add_theme_constant_override("h_separation", 8)
	teclado.add_theme_constant_override("v_separation", 8)
	teclado.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	caja.add_child(teclado)
	for d in ["1", "2", "3", "4", "5", "6", "7", "8", "9"]:
		teclado.add_child(_crear_boton(d, Color(0.12, 0.2, 0.34), COLOR_CIAN.darkened(0.3), _agregar.bind(d)))
	teclado.add_child(_crear_boton("BORRAR", Color(0.34, 0.12, 0.12), COLOR_ERROR, _borrar, 20))
	teclado.add_child(_crear_boton("0", Color(0.12, 0.2, 0.34), COLOR_CIAN.darkened(0.3), _agregar.bind("0")))
	teclado.add_child(_crear_boton("CONFIRMAR", Color(0.1, 0.34, 0.18), COLOR_OK, _confirmar, 18))

	var cerrar_btn := _crear_boton("CERRAR", Color(0.12, 0.12, 0.2), Color(0.6, 0.6, 0.8), cerrar, 20)
	cerrar_btn.custom_minimum_size = Vector2(150, 44)
	cerrar_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	caja.add_child(cerrar_btn)


func _crear_boton(texto: String, fondo: Color, borde: Color, accion: Callable, tam_fuente: int = 28) -> Button:
	var b := Button.new()
	b.text = texto
	b.custom_minimum_size = Vector2(120, 62)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", tam_fuente)
	b.add_theme_stylebox_override("normal", _estilo(fondo, COLOR_BORDE, 2, 4))
	b.add_theme_stylebox_override("hover", _estilo(fondo.lightened(0.2), COLOR_BORDE, 3, 4))
	b.add_theme_stylebox_override("pressed", _estilo(fondo.lightened(0.4), COLOR_BORDE, 3, 4))
	b.pressed.connect(accion)
	return b


func _estilo(fondo: Color, borde: Color, grosor: int, radio: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fondo
	s.border_color = borde
	s.set_border_width_all(grosor)
	s.set_corner_radius_all(radio)
	return s
