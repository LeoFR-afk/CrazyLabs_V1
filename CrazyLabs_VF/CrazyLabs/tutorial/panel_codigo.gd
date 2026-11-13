extends CanvasLayer
## Teclado del panel de codigo de la puerta.
## Se construye por codigo (no necesita nodos en la escena). Lo usa prueba_camara_emilio.gd.
##
## - Muestra 5 letras aleatorias + los digitos del 0 al 9.
## - Las letras que hacen falta para el codigo correcto SIEMPRE estan entre las 5
##   (si no, seria imposible ingresarlo); el resto se completa al azar.
## - Las letras cambian de lugar cada vez que se abre el panel.
## - Tambien se puede escribir con el teclado fisico. ESC o Backspace funcionan.

signal codigo_correcto
signal cerrado

const CODIGO_CORRECTO: String = "1480AJ"
const TOTAL_LETRAS: int = 5
const ABECEDARIO: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

const COLOR_BORDE := Color(0.0, 0.0, 0.0, 1.0)
const COLOR_OK := Color(0.3, 1.0, 0.5)
const COLOR_ERROR := Color(1.0, 0.3, 0.3)

var abierto: bool = false

var _ingresado: String = ""
var _letras: Array[String] = []
var _bloqueado: bool = false

var _raiz: Control
var _pantalla: Label
var _estado: Label
var _fila_letras: HBoxContainer


func _ready() -> void:
	layer = 50
	visible = false
	_construir_ui()


func abrir() -> void:
	_ingresado = ""
	_bloqueado = false
	_generar_letras()
	_rellenar_letras()
	_estado.text = "Ingresa el codigo de acceso"
	_estado.modulate = Color.WHITE
	_actualizar_pantalla()
	visible = true
	abierto = true


func cerrar() -> void:
	if not abierto:
		return
	abierto = false
	visible = false
	cerrado.emit()


# ---------------------------------------------------------------- logica

func _generar_letras() -> void:
	_letras.clear()
	# Primero las letras obligatorias del codigo
	for c in CODIGO_CORRECTO:
		if ABECEDARIO.contains(c) and not _letras.has(c):
			_letras.append(c)
	# El resto, al azar
	var otras: Array[String] = []
	for c in ABECEDARIO:
		if not _letras.has(c):
			otras.append(c)
	otras.shuffle()
	while _letras.size() < TOTAL_LETRAS and not otras.is_empty():
		_letras.append(otras.pop_back())
	_letras.shuffle()


func _agregar(caracter: String) -> void:
	if _bloqueado or _ingresado.length() >= CODIGO_CORRECTO.length():
		return
	_ingresado += caracter
	_actualizar_pantalla()
	if _ingresado.length() == CODIGO_CORRECTO.length():
		_verificar()


func _borrar() -> void:
	if _bloqueado or _ingresado.is_empty():
		return
	_ingresado = _ingresado.left(_ingresado.length() - 1)
	_actualizar_pantalla()


func _verificar() -> void:
	_bloqueado = true
	if _ingresado == CODIGO_CORRECTO:
		_estado.text = "ACCESO CONCEDIDO"
		_estado.modulate = COLOR_OK
		_pantalla.modulate = COLOR_OK
		await get_tree().create_timer(0.9).timeout
		_pantalla.modulate = Color.WHITE
		cerrar()
		codigo_correcto.emit()
	else:
		_estado.text = "CODIGO INCORRECTO"
		_estado.modulate = COLOR_ERROR
		_pantalla.modulate = COLOR_ERROR
		await get_tree().create_timer(0.8).timeout
		_pantalla.modulate = Color.WHITE
		_estado.text = "Ingresa el codigo de acceso"
		_estado.modulate = Color.WHITE
		_ingresado = ""
		_actualizar_pantalla()
		_bloqueado = false


func _actualizar_pantalla() -> void:
	var partes: PackedStringArray = []
	for i in CODIGO_CORRECTO.length():
		partes.append(_ingresado[i] if i < _ingresado.length() else "_")
	_pantalla.text = "  ".join(partes)


func _input(event: InputEvent) -> void:
	if not abierto:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if not _bloqueado:
				cerrar()
		elif event.keycode == KEY_BACKSPACE:
			_borrar()
		elif event.unicode > 0:
			var c: String = char(event.unicode).to_upper()
			# Solo digitos, o letras que existan en el teclado actual
			if c.is_valid_int() or _letras.has(c):
				_agregar(c)
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- interfaz

func _construir_ui() -> void:
	_raiz = Control.new()
	_raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_raiz.mouse_filter = Control.MOUSE_FILTER_STOP # los clics no pasan al juego
	add_child(_raiz)

	var oscuro := ColorRect.new()
	oscuro.color = Color(0, 0, 0, 0.65)
	oscuro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	oscuro.mouse_filter = Control.MOUSE_FILTER_STOP
	_raiz.add_child(oscuro)

	var centro := CenterContainer.new()
	centro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(centro)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _estilo(Color(0.04, 0.07, 0.16, 0.97), COLOR_BORDE, 3, 8))
	centro.add_child(panel)

	var margen := MarginContainer.new()
	for lado in ["left", "right", "top", "bottom"]:
		margen.add_theme_constant_override("margin_" + lado, 24)
	panel.add_child(margen)

	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 14)
	margen.add_child(caja)

	var titulo := Label.new()
	titulo.text = "PANEL DE ACCESO"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 28)
	titulo.add_theme_color_override("font_color", Color.WHITE)
	caja.add_child(titulo)

	# Pantallita con el codigo que se va escribiendo
	var marco_pantalla := PanelContainer.new()
	marco_pantalla.add_theme_stylebox_override("panel", _estilo(Color(0.02, 0.03, 0.08), Color(0.0, 0.0, 0.0, 1.0), 2, 4))
	caja.add_child(marco_pantalla)
	_pantalla = Label.new()
	_pantalla.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pantalla.custom_minimum_size = Vector2(0, 64)
	_pantalla.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pantalla.add_theme_font_size_override("font_size", 40)
	marco_pantalla.add_child(_pantalla)

	_estado = Label.new()
	_estado.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_estado.add_theme_font_size_override("font_size", 18)
	caja.add_child(_estado)

	# Fila de letras (se rellena en abrir())
	_fila_letras = HBoxContainer.new()
	_fila_letras.alignment = BoxContainer.ALIGNMENT_CENTER
	_fila_letras.add_theme_constant_override("separation", 8)
	caja.add_child(_fila_letras)

	# Digitos 1-9 y 0 en dos filas de 5
	var digitos := GridContainer.new()
	digitos.columns = 5
	digitos.add_theme_constant_override("h_separation", 8)
	digitos.add_theme_constant_override("v_separation", 8)
	caja.add_child(digitos)
	for d in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]:
		digitos.add_child(_crear_boton(d, Color(0.349, 0.0, 0.031, 1.0), COLOR_BORDE, _agregar.bind(d)))

	var acciones := HBoxContainer.new()
	acciones.alignment = BoxContainer.ALIGNMENT_CENTER
	acciones.add_theme_constant_override("separation", 8)
	caja.add_child(acciones)
	var b_borrar := _crear_boton("BORRAR", Color(0.3, 0.12, 0.12), COLOR_ERROR, _borrar, Vector2(140, 48))
	var b_cerrar := _crear_boton("CERRAR", Color(0.12, 0.12, 0.2), Color(0.6, 0.6, 0.8), _on_cerrar_pulsado, Vector2(140, 48))
	acciones.add_child(b_borrar)
	acciones.add_child(b_cerrar)


func _rellenar_letras() -> void:
	for hijo in _fila_letras.get_children():
		hijo.queue_free()
	for l in _letras:
		_fila_letras.add_child(_crear_boton(l, Color(0.449, 0.0, 0.117, 1.0), Color(0.0, 0.0, 0.0, 1.0), _agregar.bind(l)))


func _on_cerrar_pulsado() -> void:
	if not _bloqueado:
		cerrar()


func _crear_boton(texto: String, fondo: Color, borde: Color, accion: Callable, tam: Vector2 = Vector2(64, 64)) -> Button:
	var b := Button.new()
	b.text = texto
	b.custom_minimum_size = tam
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_stylebox_override("normal", _estilo(fondo, borde, 2, 4))
	b.add_theme_stylebox_override("hover", _estilo(fondo.lightened(0.2), borde.lightened(0.3), 3, 4))
	b.add_theme_stylebox_override("pressed", _estilo(fondo.lightened(0.4), Color.WHITE, 3, 4))
	b.pressed.connect(accion)
	return b


func _estilo(fondo: Color, borde: Color, grosor: int, radio: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fondo
	s.border_color = borde
	s.set_border_width_all(grosor)
	s.set_corner_radius_all(radio)
	return s
