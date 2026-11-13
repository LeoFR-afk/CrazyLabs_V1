extends CharacterBody2D
## PERSONAJE PROVISIONAL - Escena de pruebas CrazyLabs (carpeta tutorial).
## Este script es temporal y sera sustituido por el personaje definitivo del compañero.
##
## Controles: A / D = mover, W o Espacio = saltar, S = agacharse.
## Los nombres de animacion se configuran en el grupo "Animaciones" del Inspector.
## Si alguna no existe en el AnimatedSprite2D, simplemente se ignora.

@export_group("Movimiento")
@export var velocidad_mover: float = 280.0
@export var velocidad_salto: float = -500.0
## Salto cuando el personaje esta agachado (mas negativo = mas alto)
@export var velocidad_salto_agachado: float = -580.0

@export_group("Pared")
## Velocidad maxima de caida mientras esta pegado a la pared
@export var velocidad_caida_pared: float = 60.0
## Impulso horizontal (hacia afuera de la pared) del salto de pared
@export var salto_pared_x: float = 260.0
## Impulso vertical del salto de pared
@export var salto_pared_y: float = -480.0
## Segundos en que se ignora el input horizontal tras el salto de pared
@export var tiempo_bloqueo_salto_pared: float = 0.18

@export_group("Animaciones")
@export var anim_idle: StringName = &"idle"
@export var anim_correr: StringName = &"RUN"
@export var anim_salto: StringName = &"JUMP"
## Al caer se usa la misma de salto (se queda en su ultimo frame)
@export var anim_caida: StringName = &"JUMP"
@export var anim_pared: StringName = &"WALLCLIMB"
## No hay animacion de agacharse todavia: usa la de idle
@export var anim_agachado: StringName = &"idle"

const velocidad_gravedad: float = 980.0

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")

var agachado: bool = false
var en_pared: bool = false
var bloqueo_control: float = 0.0
## Lo activa el script de la escena mientras se reproduce la animacion de reparar
var reparando: bool = false


func _ready() -> void:
	_registrar_controles()
	if sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation(anim_idle):
		sprite.play(anim_idle)


## Crea las acciones WASD por codigo (teclas fisicas, funcionan en cualquier distribucion de teclado)
func _registrar_controles() -> void:
	_agregar_accion(&"izquierda", [KEY_A])
	_agregar_accion(&"derecha", [KEY_D])
	_agregar_accion(&"agachar", [KEY_S])
	_agregar_accion(&"saltar", [KEY_W, KEY_SPACE])


func _agregar_accion(nombre: StringName, teclas: Array) -> void:
	if not InputMap.has_action(nombre):
		InputMap.add_action(nombre)
	for tecla in teclas:
		var evento := InputEventKey.new()
		evento.physical_keycode = tecla
		InputMap.action_add_event(nombre, evento)


func _physics_process(delta: float) -> void:
	# Mientras repara no se mueve ni cambia de animacion (solo le afecta la gravedad)
	if reparando:
		velocity.x = 0.0
		velocity.y += velocidad_gravedad * delta
		move_and_slide()
		return

	var direccion: float = Input.get_axis("izquierda", "derecha")
	agachado = Input.is_action_pressed("agachar") and is_on_floor()
	bloqueo_control = max(bloqueo_control - delta, 0.0)

	# --- Movimiento horizontal ---
	if bloqueo_control > 0.0:
		pass # justo despues de un salto de pared: se conserva el impulso
	elif agachado:
		velocity.x = 0.0
	else:
		velocity.x = direccion * velocidad_mover

	# --- Gravedad ---
	velocity.y += velocidad_gravedad * delta

	# --- Pegado a la pared (hay que mantener la direccion hacia la pared) ---
	en_pared = false
	if is_on_wall_only() and direccion != 0.0 and velocity.y > 0.0:
		if sign(direccion) == -sign(get_wall_normal().x):
			en_pared = true
			velocity.y = min(velocity.y, velocidad_caida_pared)

	# --- Salto ---
	if Input.is_action_just_pressed("saltar"):
		if is_on_floor():
			velocity.y = velocidad_salto_agachado if agachado else velocidad_salto
		elif en_pared:
			velocity.y = salto_pared_y
			velocity.x = get_wall_normal().x * salto_pared_x
			bloqueo_control = tiempo_bloqueo_salto_pared
			en_pared = false

	move_and_slide()
	_actualizar_animacion(direccion)


func _actualizar_animacion(direccion: float) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return

	# Voltear el sprite segun hacia donde mira (el arte original debe mirar a la derecha)
	if bloqueo_control > 0.0:
		if velocity.x != 0.0:
			sprite.flip_h = velocity.x < 0.0
	elif direccion != 0.0:
		sprite.flip_h = direccion < 0.0

	var anim: StringName = anim_idle

	if en_pared:
		anim = anim_pared
	elif not is_on_floor():
		anim = anim_salto if velocity.y < 0.0 else anim_caida
	elif agachado:
		anim = anim_agachado
	elif abs(velocity.x) > 1.0:
		anim = anim_correr

	# Solo se cambia cuando es otra animacion (si no, las que no tienen loop se reiniciarian cada frame)
	if sprite.sprite_frames.has_animation(anim) and sprite.animation != anim:
		sprite.play(anim)
