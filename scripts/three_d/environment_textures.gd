extends RefCounted
## Tiny generated tile shared by every facade; image and mip chain are built once per process.
static var _stone_texture: Texture2D
static var _facade_materials: Dictionary = {}

static func stone_texture() -> Texture2D:
	if _stone_texture != null: return _stone_texture
	const SIZE := 128
	var image:=Image.create(SIZE,SIZE,false,Image.FORMAT_RGBA8)
	for y in range(SIZE):
		for x in range(SIZE):
			var row:=y%32
			var column: int=(x+(16 if int(y/32)%2==1 else 0))%32
			var mortar: bool=row<2 or column<2
			var grain:=.91+sin(float(x)*PI*.5)*cos(float(y)*PI*.5)*.025+sin(float(x+y)*PI*.25)*.02
			var value:=.58 if mortar else grain
			image.set_pixel(x,y,Color(.94*value,.90*value,.82*value,1))
	image.generate_mipmaps()
	_stone_texture=ImageTexture.create_from_image(image)
	return _stone_texture

static func facade_material(tint: Color) -> StandardMaterial3D:
	var key:=tint.to_html(true)
	if _facade_materials.has(key): return _facade_materials[key]
	var material:=StandardMaterial3D.new()
	material.albedo_color=tint
	material.albedo_texture=stone_texture()
	material.roughness=.96
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.uv1_scale=Vector3(4,4,4)
	_facade_materials[key]=material
	return material
