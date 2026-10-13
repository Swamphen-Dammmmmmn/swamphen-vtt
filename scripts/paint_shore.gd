extends RefCounted
## Worker-safe approximate signed shoreline distance, measured in feet.
static func build(image: Image, extent_feet: Vector2) -> Image:
	var w := image.get_width()
	var h := image.get_height()
	var step := extent_feet/Vector2(w,h)
	var distances := PackedFloat32Array()
	var inside := PackedByteArray()
	distances.resize(w*h)
	inside.resize(w*h)
	for y in range(h):
		for x in range(w): inside[y*w+x] = 1 if image.get_pixel(x,y).a>=0.5 else 0
	for y in range(h):
		for x in range(w):
			var i := y*w+x
			var boundary := inside[i]==1 and (x==0 or y==0 or x==w-1 or y==h-1)
			for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var at: Vector2i = Vector2i(x,y)+offset
				if at.x>=0 and at.y>=0 and at.x<w and at.y<h:
					boundary = boundary or inside[i]!=inside[at.y*w+at.x]
			distances[i] = 0.0 if boundary else 10000.0
	for pass_index in range(2):
		var ys = range(h) if pass_index==0 else range(h-1,-1,-1)
		var xs = range(w) if pass_index==0 else range(w-1,-1,-1)
		var direction := -1 if pass_index==0 else 1
		for y in ys:
			for x in xs:
				var i: int = y*w+x
				for offset in [Vector2i(direction,0),Vector2i(0,direction),Vector2i(direction,direction),Vector2i(-direction,direction)]:
					var at: Vector2i = Vector2i(x,y)+offset
					if at.x>=0 and at.y>=0 and at.x<w and at.y<h:
						var cost := (Vector2(offset)*step).length()
						distances[i] = minf(distances[i],distances[at.y*w+at.x]+cost)
	var result := Image.create(w,h,false,Image.FORMAT_RF)
	for y in range(h):
		for x in range(w):
			var i := y*w+x
			var feet := minf(80.0,distances[i])*(1.0 if inside[i]==1 else -1.0)
			result.set_pixel(x,y,Color(feet,0,0))
	return result
