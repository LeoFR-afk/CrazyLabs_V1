extends Node2D
## Campo de pruebas: escenario con SOLO colisiones, el personaje y los minijuegos del laboratorio.
## Se carga cuando termina el tutorial (ver escena_siguiente en tutorial/prueba_camara_emilio.gd).
##
## Para agregar mas colisiones: dentro del nodo "Colisiones" agrega un CollisionShape2D con una
## forma RectangleShape2D; este script le pone un relleno visible automaticamente.
##
## MINIJUEGOS (se interactua con la tecla E estando junto al dispositivo; el borde brilla al acercarse):
##   - Colisiones/MinijuegoTuberias  -> tuberias (copia del tutorial)
##   - Colisiones/MinijuegoPreguntas -> terminal de cultura general (da 3 numeros)
##   - Colisiones/MinijuegoMemoria   -> memoria de colores (da 3 digitos)
##   - Colisiones/PanelFinal         -> panel de contrasena (solo se abre con terminal + memoria completas)
## Contrasena final = numeros de la terminal + digitos de memoria (por defecto 739482).
## Al cerrar cualquier panel, ese minijuego se reinicia (los numeros ya ganados se conservan).

## Color del relleno que hace visibles las colisiones
@export var color_colision: Color = Color(0.35, 0.8, 1.0, 0.35)
## Segundos que tarda en aclararse la pantalla al entrar (viene del fundido a negro del tutorial)
@export var duracion_entrada: float = 0.8

@export_group("Terminal de cultura general")
## Los 3 numeros (0-9) que entrega la terminal, uno por pregunta. Son independientes de las respuestas.
@export var digitos_terminal: Array[int] = [7, 3, 9]

@export_group("Memoria de colores")
## Los 3 digitos (0-9) que entrega el minijuego, uno por ronda.
@export var digitos_memoria: Array[int] = [4, 8, 2]
## Cuantos colores tiene la secuencia de cada ronda (el numero de rondas = el largo de esta lista)
@export var longitudes_secuencia: Array[int] = [3, 4, 5]

@export_group("Interaccion")
## Pixeles extra alrededor de cada zona en los que todavia se puede interactuar con E
@export var margen_interaccion: float = 40.0

const TuberiasScript = preload("res://campo_de_pruebas/minijuego_tuberias.gd")
const PreguntasScript = preload("res://campo_de_pruebas/minijuego_preguntas.gd")
const MemoriaScript = preload("res://campo_de_pruebas/minijuego_memoria.gd")
const PanelFinalScript = preload("res://campo_de_pruebas/panel_final.gd")

@onready var jugador = $JugadorPrueba
@onready var sprite: AnimatedSprite2D = $JugadorPrueba/AnimatedSprite2D

var _tuberias: TuberiasScript
var _preguntas: PreguntasScript
var _memoria: MemoriaScript
var _final: PanelFinalScript

var _terminal_completa: bool = false
var _memoria_completa: bool = false
var _acceso_concedido: bool = false
var _digitos_terminal: Array[int] = []
var _digitos_memoria: Array[int] = []

var _zonas: Array = []          # {id, area, forma, aviso, borde}
var _zona_actual: Dictionary = {}
var _tiempo: float = 0.0
var _led_final: Polygon2D

var _aviso: Label
var _mensaje: Label
var _tween_mensaje: Tween


func _ready() -> void:
	_mostrar_colisiones()

	_crear_minijuegos()
	_crear_interfaz()
	_registrar_zonas()
	_fundido_de_entrada()


func _process(delta: float) -> void:
	_tiempo += delta
	var pulso: float = 0.65 + 0.35 * sin(_tiempo * 6.0)
	var libre: bool = not _panel_abierto()

	# El borde de cada dispositivo brilla solo si estas cerca (y no hay un panel abierto)
	var mejor: Dictionary = {}
	var mejor_d: float = INF
	for z: Dictionary in _zonas:
		var cerca: bool = libre and _esta_cerca(z)
		var borde: Node2D = z["borde"]
		borde.visible = cerca
		if cerca:
			borde.modulate.a = pulso
			var d: float = absf(jugador.global_position.x - (z["forma"] as Node2D).global_position.x)
			if d < mejor_d:
				mejor_d = d
				mejor = z
	_zona_actual = mejor

	_aviso.visible = not mejor.is_empty()
	if not mejor.is_empty():
		_aviso.text = "[E]  " + str(mejor["aviso"])


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode != KEY_E:
		return
	if _panel_abierto() or _zona_actual.is_empty():
		return
	get_viewport().set_input_as_handled() # que la "e" no se escriba en el campo de la terminal
	_abrir_zona(_zona_actual["id"])


# =============================================================================
#  ZONAS DE INTERACCION
# =============================================================================

func _registrar_zonas() -> void:
	_registrar_zona(&"tuberias", $Colisiones/MinijuegoTuberias, $Colisiones/MinijuegoTuberias/JugarTuberias, "Reparar circuito")
	_registrar_zona(&"preguntas", $Colisiones/MinijuegoPreguntas, $Colisiones/MinijuegoPreguntas/JugarPreguntas, "Usar terminal")
	_registrar_zona(&"memoria", $Colisiones/MinijuegoMemoria, $Colisiones/MinijuegoMemoria/JugarMemoria, "Usar dispositivo de memoria")
	_registrar_zona(&"final", $Colisiones/PanelFinal, $Colisiones/PanelFinal/JugarPanelFinal, "Usar panel de seguridad")


func _registrar_zona(id: StringName, area: Area2D, forma: CollisionShape2D, aviso: String) -> void:
	_zonas.append({"id": id, "area": area, "forma": forma, "aviso": aviso, "borde": _crear_borde_brillante(forma)})


func _esta_cerca(z: Dictionary) -> bool:
	var area: Area2D = z["area"]
	if area.overlaps_body(jugador):
		return true
	# Respaldo: el jugador esta junto a la zona (a su altura) aunque no la toque exactamente
	var forma: CollisionShape2D = z["forma"]
	var tam: Vector2 = (forma.shape as RectangleShape2D).size * forma.global_scale.abs()
	var dist: Vector2 = (jugador.global_position - forma.global_position).abs()
	return dist.x <= tam.x / 2.0 + margen_interaccion and dist.y <= 160.0


func _panel_abierto() -> bool:
	return _tuberias.abierto or _preguntas.abierto or _memoria.abierto or _final.abierto


func _abrir_zona(id: StringName) -> void:
	match id:
		&"tuberias":
			_congelar_jugador()
			_tuberias.abrir()
		&"preguntas":
			_congelar_jugador()
			_preguntas.abrir()
		&"memoria":
			_congelar_jugador()
			_memoria.abrir()
		&"final":
			if not (_terminal_completa and _memoria_completa):
				var faltan: PackedStringArray = []
				if not _terminal_completa:
					faltan.append("la terminal de preguntas")
				if not _memoria_completa:
					faltan.append("la memoria de colores")
				_mostrar_mensaje("Panel bloqueado. Falta completar: " + " y ".join(faltan), 3.0)
				return
			_congelar_jugador()
			_final.contrasena_correcta = _contrasena()
			_final.abrir()


## Congela al jugador mientras hay un panel abierto
func _congelar_jugador() -> void:
	jugador.reparando = true
	jugador.velocity = Vector2.ZERO
	if sprite.sprite_frames.has_animation("idle"):
		sprite.play("idle")


func _on_panel_cerrado() -> void:
	jugador.reparando = false


# =============================================================================
#  MINIJUEGOS
# =============================================================================

func _crear_minijuegos() -> void:
	_tuberias = TuberiasScript.new()
	add_child(_tuberias)
	_tuberias.cerrado.connect(_on_panel_cerrado)

	_preguntas = PreguntasScript.new()
	_preguntas.digitos = digitos_terminal
	add_child(_preguntas)
	_preguntas.cerrado.connect(_on_panel_cerrado)
	_preguntas.completado.connect(_on_terminal_completada)

	_memoria = MemoriaScript.new()
	_memoria.digitos = digitos_memoria
	_memoria.longitudes = longitudes_secuencia
	add_child(_memoria)
	_memoria.cerrado.connect(_on_panel_cerrado)
	_memoria.completado.connect(_on_memoria_completada)

	_final = PanelFinalScript.new()
	add_child(_final)
	_final.cerrado.connect(_on_panel_cerrado)
	_final.acceso_concedido.connect(_on_acceso_concedido)


func _on_terminal_completada(digitos: Array) -> void:
	_digitos_terminal.assign(digitos)
	_terminal_completa = true



func _on_memoria_completada(digitos: Array) -> void:
	_digitos_memoria.assign(digitos)
	_memoria_completa = true



func _on_acceso_concedido() -> void:
	_acceso_concedido = true

	_mostrar_mensaje("ACCESO CONCEDIDO", 4.0)


## Contrasena final: primero los digitos de la terminal y despues los de memoria (ej. 739482)
func _contrasena() -> String:
	var s: String = ""
	for d in _digitos_terminal:
		s += str(d)
	for d in _digitos_memoria:
		s += str(d)
	return s


# =============================================================================
#  BORDE BRILLANTE (mismo metodo del tutorial)
# =============================================================================

func _crear_borde_brillante(forma: CollisionShape2D) -> Node2D:
	var rect := forma.shape as RectangleShape2D
	var m := rect.size / 2.0
	var puntos := PackedVector2Array([
		Vector2(-m.x, -m.y), Vector2(m.x, -m.y), Vector2(m.x, m.y), Vector2(-m.x, m.y)])

	var nodo := Node2D.new()
	nodo.visible = false
	nodo.z_index = 20
	forma.add_child(nodo)
	nodo.add_child(_crear_linea(puntos, 14.0, Color(0.2, 0.9, 1.0, 0.25))) # resplandor
	nodo.add_child(_crear_linea(puntos, 3.0, Color(0.7, 1.0, 1.0, 1.0)))   # borde
	return nodo


func _crear_linea(puntos: PackedVector2Array, ancho: float, color: Color) -> Line2D:
	var l := Line2D.new()
	l.points = puntos
	l.closed = true
	l.width = ancho
	l.default_color = color
	l.joint_mode = Line2D.LINE_JOINT_ROUND
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD # suma luz, se ve "neon"
	l.material = mat
	return l


# =============================================================================
#  INTERFAZ (aviso "[E]" y mensajes)
# =============================================================================

func _crear_interfaz() -> void:
	var capa := CanvasLayer.new()
	capa.layer = 40
	add_child(capa)

	_aviso = Label.new()
	_aviso.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_aviso.offset_top = -90
	_aviso.offset_bottom = -45
	_aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aviso.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aviso.add_theme_font_size_override("font_size", 24)
	_aviso.add_theme_constant_override("outline_size", 8)
	_aviso.add_theme_color_override("font_outline_color", Color.BLACK)
	_aviso.add_theme_color_override("font_color", Color(0.7, 1.0, 1.0))
	_aviso.visible = false
	capa.add_child(_aviso)

	_mensaje = Label.new()
	_mensaje.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_mensaje.offset_top = 40
	_mensaje.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mensaje.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mensaje.add_theme_font_size_override("font_size", 26)
	_mensaje.add_theme_constant_override("outline_size", 8)
	_mensaje.add_theme_color_override("font_outline_color", Color.BLACK)
	_mensaje.modulate.a = 0.0
	capa.add_child(_mensaje)


func _mostrar_mensaje(texto: String, duracion: float = 1.8) -> void:
	_mensaje.text = texto
	if _tween_mensaje != null:
		_tween_mensaje.kill()
	_mensaje.modulate.a = 1.0
	_tween_mensaje = create_tween()
	_tween_mensaje.tween_interval(duracion)
	_tween_mensaje.tween_property(_mensaje, "modulate:a", 0.0, 0.5)


# =============================================================================
#  ESCENARIO
# =============================================================================

## Dibuja un rectangulo sobre cada colision para poder verlas sin activar "Visible Collision Shapes"
func _mostrar_colisiones() -> void:
	for nodo in $Colisiones.get_children():
		if nodo is CollisionShape2D and nodo.shape is RectangleShape2D:
			var m: Vector2 = (nodo.shape as RectangleShape2D).size / 2.0
			var relleno := Polygon2D.new()
			relleno.color = color_colision
			relleno.polygon = PackedVector2Array([
				Vector2(-m.x, -m.y), Vector2(m.x, -m.y), Vector2(m.x, m.y), Vector2(-m.x, m.y)])
			nodo.add_child(relleno)


func _fundido_de_entrada() -> void:
	var capa := CanvasLayer.new()
	capa.layer = 100
	add_child(capa)
	var negro := ColorRect.new()
	negro.color = Color(0, 0, 0, 1)
	negro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	negro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capa.add_child(negro)
	var t := create_tween()
	t.tween_property(negro, "color:a", 0.0, duracion_entrada)
	await t.finished
	capa.queue_free()
