class_name EngineAudio
extends AudioStreamPlayer3D
## Sonido de motor sintetizado en tiempo real (el juego no lleva archivos de audio): el tono sigue
## a las revoluciones, la aspereza a la carga (cuánto se pisa el acelerador) y, en marcha, se
## mezcla el rodar de los neumáticos y el derrape. Sirve para coches, motos, lanchas y naves
## (kind "car", "moto", "boat", "ship"). El vehículo solo tiene que poner rpm, load, skid y running.

const RATE := 22050.0

var kind := "car"
var rpm := 900.0        # revoluciones del motor
var load := 0.0         # 0..1 cuánto se acelera
var skid := 0.0         # 0..1 derrape de los neumáticos
var roll := 0.0         # 0..1 velocidad (ruido de rodadura / viento)
var running := false    # motor encendido

var _pb: AudioStreamGeneratorPlayback
var _phase := 0.0
var _phase2 := 0.0
var _lp := 0.0          # filtro del ruido
var _lp2 := 0.0
var _vol := 0.0
var _rpm_s := 900.0
var _load_s := 0.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.12
	stream = gen
	unit_size = 6.0 if kind != "ship" else 14.0
	max_distance = 70.0 if kind != "ship" else 160.0
	volume_db = -4.0
	attenuation_filter_cutoff_hz = 6000.0
	play()
	_pb = get_stream_playback() as AudioStreamGeneratorPlayback


func _process(_delta: float) -> void:
	if _pb == null:
		return
	var frames := _pb.get_frames_available()
	if frames <= 0:
		return
	var want_vol := (0.55 + 0.45 * load if running else 0.0) + (0.25 * roll if kind != "ship" else 0.0)
	if want_vol <= 0.0 and _vol < 0.001 and skid <= 0.05:
		_vol = 0.0
		return  # apagado y quieto: no gastar en generar silencio
	var cyl := 4.0 if kind == "car" else (2.0 if kind == "moto" else (6.0 if kind == "boat" else 1.0))
	for i in frames:
		# Suavizado por muestra: sin chasquidos al cambiar de marcha
		_rpm_s += (rpm - _rpm_s) * 0.0015
		_load_s += (load - _load_s) * 0.002
		_vol += (want_vol - _vol) * 0.0008
		var s := 0.0
		if kind == "ship":
			# Turbina: zumbido grave + silbido que sube con el empuje
			_phase = fmod(_phase + (38.0 + _load_s * 30.0) / RATE, 1.0)
			_phase2 = fmod(_phase2 + (420.0 + _rpm_s * 0.4) / RATE, 1.0)
			var n := randf() * 2.0 - 1.0
			_lp += (n - _lp) * (0.05 + _load_s * 0.25)
			s = sin(TAU * _phase) * 0.45 + sin(TAU * _phase2) * 0.06 * (0.3 + _load_s) + _lp * (0.35 + _load_s * 0.6)
		else:
			# Explosiones del motor: frecuencia de encendido = rpm/60 * cilindros/2
			var f := _rpm_s / 60.0 * cyl / 2.0
			_phase = fmod(_phase + f / RATE, 1.0)
			_phase2 = fmod(_phase2 + f * 0.5 / RATE, 1.0)
			var pulse := pow(1.0 - _phase, 6.0)        # golpe seco al principio de cada ciclo
			var body := sin(TAU * _phase) * 0.35 + sin(TAU * _phase2) * 0.25
			var n := randf() * 2.0 - 1.0
			_lp += (n - _lp) * 0.08
			s = (pulse * (0.5 + _load_s * 0.7) + body) * 0.55 + _lp * _load_s * 0.25
			if kind == "boat":
				s *= 0.8
		s *= _vol
		# Rodadura y viento (ruido grave) y derrape (ruido agudo con un tono que chirría)
		var n2 := randf() * 2.0 - 1.0
		_lp2 += (n2 - _lp2) * 0.03
		s += _lp2 * roll * 0.6
		if skid > 0.05:
			s += (sin(TAU * fmod(float(i) * 1150.0 / RATE, 1.0)) * 0.4 + n2 * 0.6) * skid * 0.35
		s = clampf(s, -1.0, 1.0)
		_pb.push_frame(Vector2(s, s))
