extends Node2D

@onready var jugador = $JugadorPrueba
@onready var camara = $JugadorPrueba/Camera2D
@onready var escenario_abajo = $Suelo/Escenario
@onready var escenario_arriba = $Suelo/Escenario2
@onready var punto_arriba = $PuntoArriba
@onready var punto_abajo = $PuntoAbajo
@onready var sprite = $JugadorPrueba/AnimatedSprite2D

## Distancia maxima a la que el jugador puede interactuar con una zona
@export var distancia_interaccion: float = 250.0

## Ruta de la escena a cargar al salir por la puerta. Al terminar el tutorial se pasa al campo de pruebas.
## Si se deja vacia, solo se muestra el mensaje de "escapaste".
@export_file("*.tscn") var escena_siguiente: String = "res://campo_de_pruebas/CampoDePruebas.tscn"
## Distancia maxima para usar la puerta (es mas grande que la de otras zonas)
@export var distancia_puerta: float = 320.0

const TEX_LUZ_APAGADA: Texture2D = preload("res://tutorial/Sprites/Escenarios/Escenario1_Finel.png")
const TEX_LUZ_ENCENDIDA: Texture2D = preload("res://tutorial/Sprites/Escenarios/Luz_Escendida.png")

## Cuantas veces parpadea la luz al reparar
@export var parpadeos: int = 8
## Brillo del fondo con la luz encendida (1.0 = normal, menor = mas oscuro)
@export_range(0.0, 1.0) var brillo_luz: float = 0.45
## Fuerza del temblor de camara (en pixeles) mientras parpadea la luz
@export var fuerza_temblor: float = 5.0
## Brillo del fondo en los instantes "apagados" del parpadeo (mas bajo = parpadeo mas marcado)
@export_range(0.0, 1.0) var brillo_apagado: float = 0.2
## Segundos que se queda "sin luz" antes de que parpadee la ventana
@export var pausa_apagon: float = 0.7
## Transicion de parpadeo al subir y bajar: segundos en cerrarse (ir a negro)
@export var parpadeo_cierre: float = 0.3
## Segundos que se queda TOTALMENTE negro antes de cambiar de escenario
@export var parpadeo_pausa_negro: float = 1
## Segundos en abrirse (volver a ver el nuevo escenario)
@export var parpadeo_apertura: float = 0.3

const PanelCodigoScript = preload("res://tutorial/panel_codigo.gd")
const MinijuegoScript = preload("res://tutorial/minijuego_tuberias.gd")

var reparando := false
var luz_encendida := false
var puerta_abierta := false
var saliendo := false

var panel_codigo: PanelCodigoScript
var minijuego: MinijuegoScript
var luz_puerta: Node2D
var halo_puerta: Node2D
var _bordes_ventila: Array = []
var _tiempo := 0.0
var _temblando := false
var _ventana_parpadeando := false
var _en_transicion := false
var _negro_parpadeo: ColorRect
var _capa_ventana: Sprite2D
var _ventana_pendiente := false # el parpadeo de la ventana espera a que el jugador baje

var _mensaje: Label
var _fundido: ColorRect
var _texto_final: Label
var _tween_mensaje: Tween

func _ready():
	$Suelo/Area2D.input_event.connect(_on_zona_subir_input)
	$Suelo/Area2D2.input_event.connect(_on_zona_bajar_input)
	$Suelo/Reparar.input_event.connect(_on_reparar_input)
	$Suelo/Codigo.input_event.connect(_on_codigo_input)
	$Suelo/Puerta.input_event.connect(_on_puerta_input)

	# Borde brillante de las zonas de ventilacion (se enciende al acercarse)
	_crear_borde_brillante($Suelo/Area2D/CollisionShape2D, escenario_abajo)
	_crear_borde_brillante($Suelo/Area2D2/CollisionShape2D, escenario_arriba)
	_crear_borde_brillante($Suelo/Reparar/ClickReparar, escenario_arriba)
	_crear_borde_brillante($Suelo/Codigo/ZonaCodigo, escenario_abajo)
	_crear_panel_codigo()
	_crear_minijuego()
	_crear_luz_puerta()
	_crear_interfaz()
	mostrar_abajo()

func esta_cerca(zona: Node2D, distancia: float = -1.0) -> bool:
	if distancia < 0.0:
		distancia = distancia_interaccion
	return jugador.global_position.distance_to(zona.global_position) <= distancia


## Clic izquierdo valido (y sin el panel de codigo abierto)
func _es_clic(event: InputEvent) -> bool:
	if _en_transicion:
		return false
	if panel_codigo != null and panel_codigo.abierto:
		return false
	if minijuego != null and minijuego.abierto:
		return false
	return event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT


func _process(delta: float) -> void:
	_tiempo += delta
	if _temblando:
		camara.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * fuerza_temblor
	var pulso := 0.65 + 0.35 * sin(_tiempo * 6.0)

	# Ventilas: el borde brilla solo si estas cerca y esa zona esta en pantalla
	for b in _bordes_ventila:
		var cerca: bool = b.escenario.visible and not saliendo and not panel_codigo.abierto and not minijuego.abierto and esta_cerca(b.zona)
		b.nodo.visible = cerca
		if cerca:
			b.nodo.modulate.a = pulso

	# Puerta desbloqueada: el halo respira suavemente
	if puerta_abierta and halo_puerta != null:
		halo_puerta.modulate.a = 0.55 + 0.45 * sin(_tiempo * 3.0)

func _on_zona_subir_input(_viewport, event, _shape_idx):
	if _es_clic(event):
		if esta_cerca($Suelo/Area2D/CollisionShape2D):
			ir_arriba()

func _on_zona_bajar_input(_viewport, event, _shape_idx):
	if _es_clic(event):
		if esta_cerca($Suelo/Area2D2/CollisionShape2D):
			ir_abajo()

func _on_reparar_input(_viewport, event, _shape_idx):
	if _es_clic(event) and not saliendo and not reparando and not jugador.reparando:
		if esta_cerca($Suelo/Reparar/ClickReparar):
			abrir_minijuego()
		else:
			_mostrar_mensaje("Acercate mas al panel electrico")

func ir_arriba():
	if _en_transicion or reparando:
		return
	await _transicion_parpadeo(func():
		jugador.global_position = punto_arriba.global_position
		jugador.velocity = Vector2.ZERO
		mostrar_arriba()
		camara.reset_smoothing())


## Transicion tipo parpadeo: la pantalla se va a negro, y SOLO cuando ya esta totalmente negra
## (y tras una pausa) se ejecuta el cambio de escenario; despues se abre de nuevo.
func _transicion_parpadeo(cambio: Callable) -> void:
	_en_transicion = true
	jugador.reparando = true # congela al jugador mientras dura el parpadeo

	# 1) Cerrar: a negro completo
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_property(_negro_parpadeo, "color:a", 1.0, parpadeo_cierre)
	await t.finished

	# 2) Ya es negro total: espera y recien ahi cambia de escenario
	await get_tree().create_timer(parpadeo_pausa_negro).timeout
	cambio.call()
	await get_tree().create_timer(0.05).timeout # deja que el nuevo escenario se dibuje

	# 3) Abrir: de negro al nuevo escenario
	t = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(_negro_parpadeo, "color:a", 0.0, parpadeo_apertura)
	await t.finished

	jugador.reparando = false
	_en_transicion = false

func ir_abajo():
	if _en_transicion or reparando:
		return
	await _transicion_parpadeo(func():
		jugador.global_position = punto_abajo.global_position
		jugador.velocity = Vector2.ZERO
		mostrar_abajo()
		camara.reset_smoothing())

func mostrar_arriba():
	escenario_arriba.visible = true
	escenario_abajo.visible = false
	if luz_puerta != null:
		luz_puerta.visible = false
	camara.limit_top = -1236
	camara.limit_bottom = -514

func mostrar_abajo():
	escenario_abajo.visible = true
	escenario_arriba.visible = false
	if luz_puerta != null:
		luz_puerta.visible = puerta_abierta
	camara.limit_top = -514
	camara.limit_bottom = 208
	if _ventana_pendiente:
		_ventana_pendiente = false
		_parpadeo_ventana()

## Pone la luz de los fondos: encendida/apagada + nivel de brillo (1.0 = normal)
func _poner_luz(encendida: bool, brillo: float) -> void:
	var color := Color(brillo, brillo, brillo, 1.0)
	escenario_abajo.texture = TEX_LUZ_ENCENDIDA if encendida else TEX_LUZ_APAGADA
	escenario_abajo.modulate = color
	escenario_arriba.modulate = color


func reparar():
	if reparando or luz_encendida:
		return
	reparando = true
	jugador.reparando = true
	sprite.play("fix")
	await sprite.animation_finished

	# 1) La luz del cuarto parpadea (solo brillo, el fondo sigue siendo el ORIGINAL).
	_temblando = true # la camara tiembla mientras dura el parpadeo
	var i := 0
	while i < parpadeos:
		_poner_luz(false, 1.0)
		await get_tree().create_timer(randf_range(0.08, 0.25)).timeout
		_poner_luz(false, brillo_apagado)
		await get_tree().create_timer(randf_range(0.08, 0.3)).timeout
		i += 1

	_temblando = false
	camara.offset = Vector2.ZERO

	# 2) Se va la luz: el cuarto se queda oscuro, todavia con el fondo original
	_poner_luz(false, brillo_luz)
	luz_encendida = true
	await get_tree().create_timer(pausa_apagon).timeout

	jugador.reparando = false
	reparando = false

	# 3) Parpadeo de la ventana: se intercambia el fondo original <-> el de la revelacion.
	# La ventana esta en el cuarto de ABAJO: si el jugador esta arriba, espera a que baje.
	if escenario_abajo.visible:
		_parpadeo_ventana()
	else:
		_ventana_pendiente = true


## Parpadeo SIN FIN y fluido de la ventana: sobre el fondo original se pone una capa con el fondo
## de la revelacion del codigo y su opacidad sube y baja suavemente (crossfade).
func _parpadeo_ventana() -> void:
	if _ventana_parpadeando:
		return
	_ventana_parpadeando = true

	# Capa encima del fondo (misma posicion y tamano); hereda el brillo del fondo
	_capa_ventana = Sprite2D.new()
	_capa_ventana.texture = TEX_LUZ_ENCENDIDA
	_capa_ventana.modulate.a = 0.0
	escenario_abajo.add_child(_capa_ventana)

	while is_inside_tree():
		var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(_capa_ventana, "modulate:a", 1.0, randf_range(0.35, 0.7))
		await t.finished
		t = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(_capa_ventana, "modulate:a", 0.0, randf_range(0.45, 0.9))
		await t.finished


# =============================================================================
#  BORDE BRILLANTE DE VENTILAS
# =============================================================================

func _crear_borde_brillante(forma: CollisionShape2D, escenario: Node2D) -> void:
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

	_bordes_ventila.append({"zona": forma, "nodo": nodo, "escenario": escenario})


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
#  PANEL DE CODIGO
# =============================================================================

func _crear_panel_codigo() -> void:
	panel_codigo = PanelCodigoScript.new()
	add_child(panel_codigo)
	panel_codigo.codigo_correcto.connect(_on_codigo_correcto)
	panel_codigo.cerrado.connect(_on_panel_cerrado)


func _on_codigo_input(_viewport, event, _shape_idx):
	if not _es_clic(event) or saliendo:
		return
	if puerta_abierta:
		_mostrar_mensaje("El panel ya esta desbloqueado")
	elif reparando or jugador.reparando:
		return
	elif esta_cerca($Suelo/Codigo/ZonaCodigo):
		abrir_panel()
	else:
		_mostrar_mensaje("Acercate mas al panel")


func abrir_panel() -> void:
	jugador.reparando = true # congela al jugador mientras escribe
	jugador.velocity = Vector2.ZERO
	if sprite.sprite_frames.has_animation("idle"):
		sprite.play("idle")
	panel_codigo.abrir()


func _on_panel_cerrado() -> void:
	if not saliendo:
		jugador.reparando = false


func _on_codigo_correcto() -> void:
	abrir_puerta()


# =============================================================================
#  PUERTA
# =============================================================================

## Dibuja (oculta) la iluminacion de la puerta como hijos de su zona de colision,
## asi se acomoda sola si mueves/redimensionas $Suelo/Puerta/ZonaPuerta en el editor.
func _crear_luz_puerta() -> void:
	var forma: CollisionShape2D = $Suelo/Puerta/ZonaPuerta
	var m := (forma.shape as RectangleShape2D).size / 2.0
	var verde := Color(0.25, 1.0, 0.5)
	
	luz_puerta = Node2D.new()
	luz_puerta.visible = false
	luz_puerta.z_index = 20
	forma.add_child(luz_puerta)

	var marco := PackedVector2Array([
		Vector2(-m.x, -m.y), Vector2(m.x, -m.y), Vector2(m.x, m.y), Vector2(-m.x, m.y)])

	# Relleno suave de luz sobre la puerta
	var relleno := Polygon2D.new()
	relleno.polygon = marco
	relleno.color = Color(verde.r, verde.g, verde.b, 0.12)
	relleno.material = _material_aditivo()
	luz_puerta.add_child(relleno)

	# Halo + borde (el halo es lo que "respira" en _process)
	halo_puerta = Node2D.new()
	luz_puerta.add_child(halo_puerta)
	halo_puerta.add_child(_crear_linea(marco, 22.0, Color(verde.r, verde.g, verde.b, 0.22)))
	halo_puerta.add_child(_crear_linea(marco, 12.0, Color(verde.r, verde.g, verde.b, 0.30)))
	luz_puerta.add_child(_crear_linea(marco, 4.0, Color(0.8, 1.0, 0.85, 1.0)))

	# La lampara roja de arriba pasa a verde (posicion relativa al centro de la puerta)
	var lampara := Polygon2D.new()
	lampara.polygon = _rect_poligono(Vector2(-6.5, -206.5), Vector2(72, 30))
	lampara.color = Color(0.3, 1.0, 0.5, 0.95)
	luz_puerta.add_child(lampara)
	var brillo_lampara := Polygon2D.new()
	brillo_lampara.polygon = _rect_poligono(Vector2(-6.5, -206.5), Vector2(110, 60))
	brillo_lampara.color = Color(verde.r, verde.g, verde.b, 0.25)
	brillo_lampara.material = _material_aditivo()
	luz_puerta.add_child(brillo_lampara)


func _rect_poligono(centro: Vector2, tam: Vector2) -> PackedVector2Array:
	var h := tam / 2.0
	return PackedVector2Array([
		centro + Vector2(-h.x, -h.y), centro + Vector2(h.x, -h.y),
		centro + Vector2(h.x, h.y), centro + Vector2(-h.x, h.y)])


func _material_aditivo() -> CanvasItemMaterial:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return mat


func abrir_puerta() -> void:
	puerta_abierta = true
	luz_puerta.visible = escenario_abajo.visible
	luz_puerta.modulate.a = 0.0
	create_tween().tween_property(luz_puerta, "modulate:a", 1.0, 0.8)
	_mostrar_mensaje("PUERTA DESBLOQUEADA - haz clic en la puerta para salir", 3.0)


func _on_puerta_input(_viewport, event, _shape_idx):
	if not _es_clic(event) or saliendo:
		return
	if not puerta_abierta:
		_mostrar_mensaje("La puerta esta bloqueada. Necesitas el codigo del panel")
	elif not esta_cerca($Suelo/Puerta/ZonaPuerta, distancia_puerta):
		_mostrar_mensaje("Acercate mas a la puerta")
	else:
		salir()


func salir() -> void:
	saliendo = true
	jugador.reparando = true
	jugador.velocity = Vector2.ZERO
	var t := create_tween()
	t.tween_property(_fundido, "color:a", 1.0, 1.0)
	await t.finished
	if escena_siguiente != "" and ResourceLoader.exists(escena_siguiente):
		get_tree().change_scene_to_file(escena_siguiente)
	else:
		_texto_final.visible = true # no hay siguiente nivel todavia


# =============================================================================
#  INTERFAZ (mensajes, fundido a negro, texto final)
# =============================================================================

func _crear_interfaz() -> void:
	var capa := CanvasLayer.new()
	capa.layer = 40
	add_child(capa)

	_fundido = ColorRect.new()
	_fundido.color = Color(0, 0, 0, 0)
	_fundido.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fundido.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capa.add_child(_fundido)

	_negro_parpadeo = ColorRect.new()
	_negro_parpadeo.color = Color(0, 0, 0, 0)
	_negro_parpadeo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_negro_parpadeo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capa.add_child(_negro_parpadeo)

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

	_texto_final = Label.new()
	_texto_final.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_texto_final.text = "¡ESCAPASTE DEL LABORATORIO!"
	_texto_final.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_texto_final.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_texto_final.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texto_final.add_theme_font_size_override("font_size", 48)
	_texto_final.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	_texto_final.visible = false
	capa.add_child(_texto_final)


func _mostrar_mensaje(texto: String, duracion: float = 1.8) -> void:
	_mensaje.text = texto
	if _tween_mensaje != null:
		_tween_mensaje.kill()
	_mensaje.modulate.a = 1.0
	_tween_mensaje = create_tween()
	_tween_mensaje.tween_interval(duracion)
	_tween_mensaje.tween_property(_mensaje, "modulate:a", 0.0, 0.5)


# =============================================================================
#  MINIJUEGO DE REPARAR (tuberias)
# =============================================================================

func _crear_minijuego() -> void:
	minijuego = MinijuegoScript.new()
	minijuego.codigo_a_revelar = PanelCodigoScript.CODIGO_CORRECTO # un solo codigo para todo
	add_child(minijuego)
	minijuego.cerrado.connect(_on_minijuego_cerrado)


func abrir_minijuego() -> void:
	jugador.reparando = true # congela al jugador mientras juega
	jugador.velocity = Vector2.ZERO
	if sprite.sprite_frames.has_animation("idle"):
		sprite.play("idle")
	minijuego.abrir()


func _on_minijuego_cerrado() -> void:
	if minijuego.resuelto and not luz_encendida and not reparando:
		reparar() # animacion de arreglar + se enciende la luz del cuarto
	else:
		jugador.reparando = false
