"""Genera data/catalog.json: el índice de modelos 3D que la IA del juego puede usar para crear cosas
(herramienta search_catalog del agente). Cada modelo lleva nombre en español, etiquetas y una
altura real por defecto en metros (los GLB vienen a escalas distintas; AssetLibrary.place escala
a esa altura).

    python tools/make_catalog.py
"""
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(ROOT, "assets", "models")
OUT = os.path.join(ROOT, "data", "catalog.json")
SKIP_PACKS = {"modular_men", "modular_women"}  # personas: se crean con spawn_npc

# token del nombre -> [nombre en español, etiquetas, altura en m]
WORDS = {
    "Bathtub": ["bañera", "baño", 0.6], "Mirror1": ["espejo", "baño", 0.8], "Mirror2": ["espejo", "baño", 0.8],
    "Shower1": ["regadera", "baño ducha", 2.1], "Sink": ["lavabo", "baño cocina", 0.9], "Toilet": ["excusado", "baño wc", 0.8],
    "Toilet2": ["excusado", "baño wc", 0.8], "ToiletPaper": ["papel de baño", "baño", 0.12], "ToiletPaperPile": ["pila de papel de baño", "baño", 0.3],
    "Towel": ["toalla", "baño", 0.6], "WashingMachine": ["lavadora", "baño electrodoméstico", 0.9],
    "Bunk": ["litera", "cama dormir", 1.7], "King": ["cama matrimonial", "cama dormir", 0.6], "Single": ["cama individual", "cama dormir", 0.6],
    "Bookshelf": ["librero", "libros estante mueble", 2.0], "Carpet": ["alfombra", "tapete suelo", 0.02], "Round": ["redondo", "", 0],
    "Chair": ["silla", "asiento sentarse mueble", 0.9], "Column": ["columna", "pilar estructura", 3.0],
    "Couch": ["sofá", "sillón asiento sentarse mueble", 0.85], "Curtains": ["cortinas", "ventana tela", 2.2],
    "Door": ["puerta", "entrada", 2.1], "Drawer": ["cómoda", "cajones mueble guardar", 1.0], "Fireplace": ["chimenea", "fuego calor", 1.3],
    "Fork": ["tenedor", "cubiertos cocina", 0.2], "Houseplant": ["planta de interior", "maceta planta", 0.8],
    "Kitchen": ["mueble de cocina", "cocina", 0.9], "Cabinet1": ["alacena", "cocina guardar", 0.9], "Cabinet2": ["alacena", "cocina guardar", 0.9],
    "CabinetSmall": ["alacena pequeña", "cocina", 0.6], "Fridge": ["refrigerador", "cocina frío electrodoméstico", 1.9],
    "Oven": ["estufa", "cocina horno cocinar", 0.9], "Knife": ["cuchillo", "cocina herramienta arma", 0.25],
    "Light": ["lámpara", "luz iluminación", 0.5], "Ceiling1": ["de techo", "", 0], "Chandelier": ["candelabro", "luz lujo", 0.9],
    "Desk": ["de escritorio", "", 0], "Floor1": ["de pie", "", 1.7], "NightStand": ["buró", "mesita noche mueble", 0.6],
    "Plate": ["plato", "cocina comida", 0.04], "Shelf": ["repisa", "estante guardar", 1.0], "Spoon": ["cuchara", "cubiertos", 0.18],
    "Stool": ["banco", "taburete asiento sentarse", 0.7], "Table": ["mesa", "mueble comer", 0.75], "Trashcan": ["bote de basura", "basura", 0.9],
    "Window": ["ventana", "vidrio", 1.2], "Large": ["grande", "", 0], "Small": ["pequeño", "", 0],
    "Details": ["", "", 0], "Pipes": ["tuberías", "tubo metal industrial", 0.5], "Vent": ["rejilla de ventilación", "ventilación metal", 0.5],
    "Props": ["", "", 0], "Base": ["base metálica", "plataforma sci-fi", 0.3], "Capsule": ["cápsula", "sci-fi criogenia", 2.0],
    "Chest": ["cofre", "baúl guardar", 0.7], "Computer": ["computadora", "ordenador terminal sci-fi", 1.5], "ComputerSmall": ["computadora pequeña", "terminal", 0.8],
    "ContainerFull": ["contenedor", "carga caja", 1.2], "Crate": ["caja", "carga cajón madera", 0.8], "CrateLong": ["caja larga", "carga cajón", 0.8],
    "Laser": ["cañón láser", "arma sci-fi", 1.2], "Pod": ["cápsula de escape", "nave sci-fi", 2.2], "Statue": ["estatua", "adorno", 2.0],
    "Teleporter": ["teletransportador", "sci-fi portal", 0.6], "Vessel": ["depósito", "tanque contenedor sci-fi", 1.4], "Tall": ["alto", "", 0],
    "Short": ["bajo", "", 0], "BirchTree": ["abedul", "árbol naturaleza", 7.0], "BushBerries": ["arbusto con bayas", "planta fruta", 1.0],
    "Bush": ["arbusto", "planta", 1.0], "Cactus": ["cactus", "planta desierto", 2.0], "CommonTree": ["árbol", "naturaleza", 6.5],
    "Autumn": ["de otoño", "", 0], "Dead": ["seco", "", 0], "Snow": ["nevado", "nieve", 0], "Flowers": ["flores", "planta jardín", 0.4],
    "Grass": ["hierba", "pasto", 0.4], "PalmTree": ["palmera", "árbol playa", 7.0], "PineTree": ["pino", "árbol bosque", 8.0],
    "Plant": ["planta", "naturaleza", 0.8], "Rock": ["roca", "piedra", 1.0], "Moss": ["con musgo", "", 0], "TreeStump": ["tocón", "tronco", 0.5],
    "Willow": ["sauce", "árbol", 6.0], "WoodLog": ["tronco", "madera leña", 0.4], "Boat": ["barca", "bote barco agua vehículo", 1.2],
    "BoatWSail": ["velero", "barco vela agua vehículo", 5.0], "CruiseShip": ["crucero", "barco grande vehículo", 25.0],
    "Lifeboat": ["bote salvavidas", "barco agua vehículo", 1.4], "Sail": ["velero grande", "barco vela vehículo", 12.0],
    "Viking": ["barco vikingo", "barco antiguo vehículo", 6.0], "Sign": ["señal", "letrero tráfico calle", 2.2], "NoParking": ["de no estacionarse", "", 0],
    "Stop": ["de alto", "", 0], "Triangle": ["triangular", "", 0], "Streetlight": ["farola", "luz calle poste", 4.4],
    "Double": ["doble", "", 0], "Triple": ["triple", "", 0], "Axe": ["hacha", "herramienta talar", 0.75], "Backpack": ["mochila", "bolsa guardar", 0.6],
    "Bandages": ["vendas", "medicina curar", 0.1], "Battery": ["batería", "pila energía", 0.3], "Big": ["grande", "", 0],
    "BearTrap": ["trampa para osos", "trampa", 0.15], "Closed": ["cerrado", "", 0], "Open": ["abierto", "", 0],
    "Bonfire": ["fogata", "fuego leña calor", 0.6], "Fire": ["encendida", "fuego", 0], "Can": ["lata", "comida", 0.15], "Broken": ["rota", "", 0],
    "Red": ["roja", "", 0], "Compass": ["brújula", "orientación", 0.08], "FirstAidKit": ["botiquín", "medicina curar", 0.3],
    "Hard": ["rígido", "", 0], "FlareGun": ["pistola de bengalas", "señal emergencia", 0.25], "GasCan": ["bidón de gasolina", "combustible", 0.45],
    "Match": ["cerillo", "fuego", 0.06], "Burnt": ["quemado", "", 0], "Matchbox": ["caja de cerillos", "fuego", 0.06], "Pan": ["sartén", "cocina", 0.1],
    "Phone": ["celular", "teléfono", 0.15], "Pistol": ["pistola", "arma", 0.2], "Pot": ["olla", "cocina", 0.25],
    "PropaneTank": ["tanque de gas", "combustible", 0.6], "Radio": ["radio", "señal comunicación", 0.3], "Raft": ["balsa", "agua vehículo madera", 0.5],
    "Paddle": ["remo", "agua", 1.4], "Revolver": ["revólver", "arma", 0.2], "Shotgun": ["escopeta", "arma", 0.3], "SawedOff": ["recortada", "", 0],
    "ShortStock": ["de culata corta", "", 0], "Shovel": ["pala", "herramienta cavar", 1.1], "Tent": ["tienda de campaña", "refugio dormir", 2.0],
    "Torch": ["linterna", "luz", 0.3], "WaterBottle": ["botella de agua", "beber", 0.25], "WoodenTorch": ["antorcha", "fuego luz", 1.0],
}
FEMININE = {"silla", "mesa", "cama", "lámpara", "repisa", "caja", "roca", "planta", "palmera", "barca", "balsa", "señal",
            "farola", "lata", "olla", "pala", "mochila", "brújula", "pistola", "escopeta", "antorcha", "bañera", "regadera",
            "toalla", "lavadora", "litera", "alfombra", "columna", "puerta", "cómoda", "chimenea", "estufa", "alacena",
            "computadora", "cápsula", "estatua", "hierba", "linterna", "trampa", "batería", "botella", "tienda", "ventana"}


SPECIAL = {"Raft_Paddle": ["remo", "agua remar", 1.4], "Light_Desk": ["lámpara de escritorio", "luz", 0.5],
           "Kitchen_Fridge": ["refrigerador", "cocina frío electrodoméstico", 1.9], "Kitchen_Oven": ["estufa", "cocina cocinar", 0.9],
           "Kitchen_Oven_Large": ["estufa grande", "cocina cocinar", 0.9], "Kitchen_Sink": ["fregadero", "cocina lavar", 0.9],
           "Kitchen_Cabinet1": ["alacena", "cocina guardar", 0.9], "Kitchen_Cabinet2": ["alacena", "cocina guardar", 0.9],
           "Kitchen_CabinetSmall": ["alacena pequeña", "cocina guardar", 0.6]}


def describe(pack, name):
    if name in SPECIAL:
        es, tg, h = SPECIAL[name]
        return {"model": "%s/%s" % (pack, name), "name": es, "tags": sorted(tg.split()), "height": h, "pack": pack}
    tokens = [t for t in re.split(r"_", name) if t and not t.isdigit()]
    words, tags, height = [], set(), 0.0
    for i, t in enumerate(tokens):
        base = re.sub(r"\d+$", "", t)
        info = WORDS.get(t) or WORDS.get(base)
        if not info:
            continue
        es, tg, h = info
        if es:
            words.append(es)
        tags.update(tg.split())
        if h and (height == 0.0 or i == 0):
            height = h
    if pack == "buildings_pack_3":
        stories = int(name[0]) if name[0].isdigit() else 2
        words = ["edificio de %d piso%s" % (stories, "s" if stories > 1 else "")]
        tags.update(["casa", "edificio", "construcción"])
        if "Sign" in name:
            tags.add("negocio")
        height = 3.2 * stories + 1.5
    if not words:
        words = [name.replace("_", " ").lower()]
    label = words[0]
    if len(words) > 1:
        rest = " ".join(words[1:])
        if label.split(" ")[0] in FEMININE:
            ws = rest.split(" ")
            rest = " ".join(w[:-1] + "a" if w.endswith("o") and len(w) > 3 and (i == 0 or ws[i - 1] != "de") else w
                            for i, w in enumerate(ws))
        label = label + " " + rest
    return {"model": "%s/%s" % (pack, name), "name": label.strip(), "tags": sorted(t for t in tags if t),
            "height": round(height or 1.0, 2), "pack": pack}


def main():
    out = []
    for pack in sorted(os.listdir(MODELS)):
        folder = os.path.join(MODELS, pack)
        if pack in SKIP_PACKS or not os.path.isdir(folder):
            continue
        for f in sorted(os.listdir(folder)):
            if f.endswith(".glb"):
                out.append(describe(pack, f[:-4]))
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump({"_comment": "Generado por tools/make_catalog.py. Modelos que la IA puede usar al crear cosas.",
                   "models": out}, fh, ensure_ascii=False, indent="\t")
        fh.write("\n")
    print("%d modelos en %s" % (len(out), OUT))


if __name__ == "__main__":
    main()
