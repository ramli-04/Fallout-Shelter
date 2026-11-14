extends Control
var values: Array = []
var title := "Synthetic IQ distribution"
func _ready() -> void: custom_minimum_size=Vector2(500,180)
func _draw() -> void:
	if values.is_empty(): return
	var peak: float = maxf(1,values.max())
	var width: float = size.x/values.size()
	for i in range(values.size()):
		var height: float = float(values[i])/peak*(size.y-50)
		draw_rect(Rect2(i*width+3,size.y-25-height,width-6,height),Color("508c7b"))
		draw_string(ThemeDB.fallback_font,Vector2(i*width+6,size.y-8),str(int(values[i])),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("33433b"))
	draw_string(ThemeDB.fallback_font,Vector2(4,18),title,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("33433b"))
