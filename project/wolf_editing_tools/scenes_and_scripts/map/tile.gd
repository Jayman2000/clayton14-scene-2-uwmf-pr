tool
extends MeshInstance


const FALLBACK_EAST_TEXTURE_PATH := "res://wolf_editing_tools/art/e.webp"
const FALLBACK_NORTH_TEXTURE_PATH := "res://wolf_editing_tools/art/n.webp"
const FALLBACK_SOUTH_TEXTURE_PATH := "res://wolf_editing_tools/art/s.webp"
const FALLBACK_WEST_TEXTURE_PATH := "res://wolf_editing_tools/art/w.webp"
const FALLBACK_FACE_TEXTURE_PATHS := [
	FALLBACK_SOUTH_TEXTURE_PATH,
	FALLBACK_EAST_TEXTURE_PATH,
	FALLBACK_NORTH_TEXTURE_PATH,
	FALLBACK_WEST_TEXTURE_PATH,
	FALLBACK_EAST_TEXTURE_PATH,
	FALLBACK_EAST_TEXTURE_PATH
]
const BLACK_SQUARE_FALLBACK_ERROR := "Failed to load fallback texture. Using a completely black square as a fallback…"
const IMAGE_FORMAT := Image.FORMAT_RGB8
const OUTPUT_DIR := "res://wolf_editing_tools/generated/art/walls/cache/"

export var texture_east : Texture = preload(FALLBACK_EAST_TEXTURE_PATH) setget set_texture_east
export var texture_north : Texture = preload(FALLBACK_NORTH_TEXTURE_PATH) setget set_texture_north
export var texture_south : Texture = preload(FALLBACK_SOUTH_TEXTURE_PATH) setget set_texture_south
export var texture_west : Texture = preload(FALLBACK_WEST_TEXTURE_PATH) setget set_texture_west


func _init() -> void:
	# This will prevent errors when running Util.texture_path().
	Util.make_dir_recursive_or_error(OUTPUT_DIR)


static func _backing_texture_id(face_texture_paths : Array) -> String:
	var face_texture_hashes := []
	face_texture_hashes.resize(len(face_texture_paths))
	
	var file := File.new()
	for face_number in len(face_texture_paths):
		var sha256 := file.get_sha256(face_texture_paths[face_number])
		if sha256.empty():
			push_warning(
					"Failed to get sha256 of the contents of “%s”. Hashing its path instead…"
					% [face_texture_paths[face_number]]
			)
			face_texture_hashes[face_number] = hash(face_texture_paths[face_number])
		else:
			face_texture_hashes[face_number] = sha256
	return "%x" % [hash(face_texture_hashes)]


static func generate_surface_material(face_texture_paths : Array) -> Material:
	var backing_texture_id = _backing_texture_id(face_texture_paths)
	var backing_texture_path := Util.texture_path(OUTPUT_DIR, backing_texture_id)
	var new_backing_texture : Texture
	if ResourceLoader.exists(backing_texture_path):
		new_backing_texture = load(backing_texture_path)
	else:
		var albedo_image := Image.new()
		# TODO: What are mipmaps? Should use_mipmaps be true?
		albedo_image.create(VSwap.WALL_LENGTH * 3, VSwap.WALL_LENGTH * 2, false, IMAGE_FORMAT)
		for face_number in 6:
			var texture_to_add = load(face_texture_paths[face_number])
			var image_to_add : Image
			if texture_to_add == null:
				var fallback_texture_path : String
				fallback_texture_path = FALLBACK_FACE_TEXTURE_PATHS[face_number]
				push_error(
						"Failed to load “%s”. Using “%s” as a fallback…"
						% [face_texture_paths[face_number], fallback_texture_path]
				)
				texture_to_add = load(fallback_texture_path)
				if texture_to_add == null:
					push_error(BLACK_SQUARE_FALLBACK_ERROR)
					image_to_add = Image.new()
					image_to_add.create(
							VSwap.WALL_LENGTH,
							VSwap.WALL_LENGTH,
							false,
							Image.FORMAT_L8
					)
					image_to_add.fill(Color.black)
			if image_to_add == null:
				image_to_add = texture_to_add.get_data()
			
			var row : int = face_number % 3
			var column : int = 0 if face_number < 3 else 1
			image_to_add.resize(
					VSwap.WALL_LENGTH,
					VSwap.WALL_LENGTH,
					Image.INTERPOLATE_NEAREST
			)
			if face_number == 4:
				# Without this, the top texture would appear upside down.
				image_to_add.unlock()
				image_to_add.flip_x()
				image_to_add.flip_y()
				image_to_add.lock()
			albedo_image.blit_rect(
					image_to_add,
					Rect2(0, 0, VSwap.WALL_LENGTH, VSwap.WALL_LENGTH),
					Vector2(row * VSwap.WALL_LENGTH, column * VSwap.WALL_LENGTH)
			)
		new_backing_texture = ImageTexture.new()
		new_backing_texture.create_from_image(
				albedo_image,
				Texture.FLAGS_DEFAULT & ~Texture.FLAG_FILTER
		)
		backing_texture_path = Util.save_texture(
				new_backing_texture,
				OUTPUT_DIR,
				backing_texture_id
		)
		new_backing_texture.take_over_path(backing_texture_path)
	
	var return_value := SpatialMaterial.new()
	return_value.flags_unshaded = true
	return_value.albedo_texture = new_backing_texture
	
	return return_value


func effective_automap_texture_path() -> String:
	return texture_east.resource_path


func _update_material() -> void:
	set_surface_material(
		0,
		generate_surface_material([
			texture_south.resource_path,
			texture_east.resource_path,
			texture_north.resource_path,
			texture_west.resource_path,
			effective_automap_texture_path(),
			effective_automap_texture_path()
		])
	)


# This ensures that _update_material() gets run at most once per physics tic.
# Without something like this, the following code would unnecessarily run
# _update_material() multiple times:
#     set_texture_east(missing_texture)
#     set_texture_north(missing_texture)
#     set_texture_south(missing_texture)
#     set_texture_west(missing_texture)
func _physics_process(_delta) -> void:
	_update_material()
	set_physics_process(false)


func queue_update_material() -> void:
	set_physics_process(true)


func set_texture_east(new_texture_east : Texture) -> void:
	texture_east = new_texture_east
	queue_update_material()


func set_texture_north(new_texture_north : Texture) -> void:
	texture_north = new_texture_north
	queue_update_material()


func set_texture_south(new_texture_south : Texture) -> void:
	texture_south = new_texture_south
	queue_update_material()


func set_texture_west(new_texture_west : Texture) -> void:
	texture_west = new_texture_west
	queue_update_material()


# This prevents the material from being saved into the scene file. Here’s why
# I’m doing that:
#     1. The Material’s albedo_texture can be generated by looking at
#        texture_east, texture_north, texture_south and texture_west. Including
#        it in a saved scene would be redundant.
#     2. We don’t want users inadvertently distributing copyrighted content
#        that they don’t own or have a license for (example: walls from
#        VSWAP.WL6).
func _get(property):
	for i in get_surface_material_count():
		if property == "material/%s" % [i]:
			return SpatialMaterial.new()
