extends EditorInspectorPlugin


func can_handle(object):
	print('can handle?', object)
	return true


func parse_property(object, type, path, hint, hint_text, usage):
	print('parse_property', object, type, path, hint, hint_text, usage)
	return false
