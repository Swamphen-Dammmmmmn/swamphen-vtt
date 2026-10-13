extends RefCounted

var source := ""
var cursor := 0
var failure := ""
var depth := 0

func evaluate(expression: String) -> Dictionary:
	source = expression.strip_edges().replace("×", "*").replace("÷", "/").replace("−", "-")
	cursor = 0
	failure = ""
	depth = 0
	if source.is_empty():
		return {"ok": false, "error": "请输入表达式。"}
	if source.length() > 256:
		return {"ok": false, "error": "表达式最多 256 个字符。"}
	var value := _expression()
	_skip_spaces()
	if failure.is_empty() and cursor < source.length():
		failure = "第 %d 个字符无法识别；仅支持数字、四则运算和括号。" % (cursor + 1)
	if failure.is_empty() and not is_finite(value):
		failure = "结果超出可计算范围。"
	if not failure.is_empty():
		return {"ok": false, "error": failure}
	return {"ok": true, "value": value, "display": _display(value)}

func _expression() -> float:
	var value := _term()
	while failure.is_empty():
		_skip_spaces()
		var operation := _peek()
		if operation not in ["+", "-"]:
			break
		cursor += 1
		var right := _term()
		value = value + right if operation == "+" else value - right
	return value

func _term() -> float:
	var value := _operand()
	while failure.is_empty():
		_skip_spaces()
		var operation := _peek()
		if operation not in ["*", "/"]:
			break
		cursor += 1
		var right := _operand()
		if not failure.is_empty():
			return 0.0
		if operation == "/" and right == 0.0:
			failure = "不能除以零。"
			return 0.0
		value = value * right if operation == "*" else value / right
	return value

func _operand() -> float:
	_skip_spaces()
	var sign := 1.0
	while _peek() in ["+", "-"]:
		if _peek() == "-":
			sign = -sign
		cursor += 1
		_skip_spaces()
	if _peek() == "(":
		cursor += 1
		depth += 1
		if depth > 32:
			failure = "括号嵌套最多 32 层。"
			return 0.0
		var value := _expression()
		_skip_spaces()
		if _peek() != ")" and failure.is_empty():
			failure = "括号不匹配，缺少右括号。"
		if _peek() == ")":
			cursor += 1
		depth -= 1
		return sign * value
	var start := cursor
	while cursor < source.length() and source[cursor] in "0123456789.":
		cursor += 1
	var number := source.substr(start, cursor - start)
	if number.is_empty() or not number.is_valid_float():
		failure = "第 %d 个字符处需要有效数字或括号。" % (start + 1)
		return 0.0
	return sign * number.to_float()

func _skip_spaces() -> void:
	while cursor < source.length() and source[cursor] in " \t\n\r":
		cursor += 1

func _peek() -> String:
	return source[cursor] if cursor < source.length() else ""

func _display(value: float) -> String:
	if value == 0.0:
		return "0"
	if absf(value) > 1.0e12 or absf(value) < 1.0e-8:
		return str(value)
	return String.num(value, 10)
