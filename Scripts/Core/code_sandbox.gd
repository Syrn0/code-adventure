extends Node
## CodeSandbox - Safe execution of player-written GDScript
## Validates code against WizardAPI whitelist before execution
## Registered as autoload singleton (do NOT add class_name here)

signal execution_started
signal execution_completed(result: SandboxResult)
signal execution_error(error: String)

## Result of sandbox execution
class SandboxResult:
	var success: bool
	var return_value: Variant
	var error_message: String
	var execution_time_ms: int
	var print_output: Array

	func _init(p_success: bool, p_return_value: Variant = null, p_error: String = "", p_time: int = 0):
		success = p_success
		return_value = p_return_value
		error_message = p_error
		execution_time_ms = p_time
		print_output = []

## Blacklist: word-boundary patterns that must not appear in player code.
## Kept deliberately narrow so innocent substring matches (e.g. "before",
## "reward") do not trigger false positives.
const FORBIDDEN_PATTERNS := [
	"OS.", "FileAccess", "DirAccess", "ResourceLoader", "ResourceSaver",
	"Engine.", "ProjectSettings", "Input.", "DisplayServer",
	"load(", "preload(", "call(", "callv(", "call_deferred(",
	"set_script(", "instance_from_id(",
	"get_tree().quit", "get_tree().reload_current_scene",
	"yield", "signal ", "class_name",
]

## Language keywords that look like function calls but are not API calls
const BUILTIN_FUNCTIONS := [
	"if", "elif", "else", "for", "while", "return", "and", "or", "not",
	"print", "str", "int", "float", "bool", "len", "range",
	"abs", "min", "max", "clamp", "lerp", "randf", "randi",
	"push_error", "push_warning", "vec2",
	"Color", "Vector2", "Vector2i", "Rect2", "Array", "Dictionary",
	"sin", "cos", "tan", "sqrt", "pow", "floor", "ceil", "round",
	"floori", "ceili", "roundi", "sign", "snapped",
]

## Current API whitelist
var current_api: WizardAPI = null

## Set to true to dump the generated wrapper script to the console
const DEBUG_SHOW_WRAPPED: bool = false

## Reference to the game world (for API functions to interact with)
var world_context: Node = null

## Statistics
var _execution_count: int = 0
var _total_execution_time: int = 0


func _ready() -> void:
	# Try to load default Apprentice API
	if current_api == null and ResourceLoader.exists(WizardAPI.TIER_APPRENTICE):
		current_api = load(WizardAPI.TIER_APPRENTICE)


## Set the API whitelist for this sandbox
func set_api(api: WizardAPI) -> void:
	if api:
		var errors: Array[String] = api.validate()
		if errors.size() > 0:
			push_warning("WizardAPI has validation errors: " + ", ".join(errors))
	current_api = api


## Set the world context (for API functions to access game state)
func set_world_context(node: Node) -> void:
	world_context = node


## Main execution entry point
func execute(code: String, context: Dictionary = {}) -> SandboxResult:
	if current_api == null:
		return SandboxResult.new(false, null, "No API whitelist configured", 0)

	# Validate the world/context BEFORE compiling so the API implementation
	# never receives a freed instance (freed-but-not-null would pass a plain
	# `!= null` check and crash the engine mid-spell).
	if not is_instance_valid(world_context):
		var world_error := "The game world is not available - spells cannot run right now."
		execution_error.emit(world_error)
		return SandboxResult.new(false, null, world_error, 0)

	for key in ["level", "player", "goal"]:
		# NOTE: a freed object stored in a Variant reads as == null in Godot 4,
		# but still hard-errors when passed to a typed parameter. Distinguish a
		# legitimately-null entry (e.g. a level without a goal, typeof == NIL)
		# from a freed one (typeof stays TYPE_OBJECT but is no longer valid).
		if context.has(key) and typeof(context[key]) == TYPE_OBJECT and not is_instance_valid(context[key]):
			var ctx_error := "The game object '%s' no longer exists - spells cannot run right now." % key
			execution_error.emit(ctx_error)
			return SandboxResult.new(false, null, ctx_error, 0)

	# Start timing
	var start_time := Time.get_ticks_msec()
	execution_started.emit()

	# Step 1: Static validation
	var validation_error := _validate_code(code)
	if validation_error != "":
		execution_error.emit(validation_error)
		return SandboxResult.new(false, null, validation_error, 0)

	# Step 2: Build the wrapped script
	var wrapped_code := _build_wrapped_script(code)
	if DEBUG_SHOW_WRAPPED:
		print("=== SANDBOX SCRIPT ===\n" + wrapped_code + "\n======================")

	# Step 3: Compile
	var script := GDScript.new()
	script.source_code = wrapped_code

	var compile_start := Time.get_ticks_msec()
	var compile_result := script.reload()
	var compile_time := Time.get_ticks_msec() - compile_start

	if compile_result != OK:
		var compile_error := _describe_compile_error(compile_result)
		execution_error.emit(compile_error)
		return SandboxResult.new(false, null, compile_error, compile_time)

	# Step 4: Instantiate
	var instance = script.new()
	if instance == null:
		var inst_error := "Failed to create script instance"
		execution_error.emit(inst_error)
		return SandboxResult.new(false, null, inst_error, compile_time)

	# Set up API implementation
	if current_api.api_implementation_path != "":
		var api_impl_script: Script = load(current_api.api_implementation_path)
		if api_impl_script:
			var api_impl = api_impl_script.new()
			if api_impl.has_method("setup"):
				api_impl.setup(world_context, context.get("player", null))
			if instance.has_method("set_api"):
				instance.set_api(api_impl)

	# Set up context
	if instance.has_method("set_context"):
		instance.set_context(context)
	if instance.has_method("set_world") and world_context:
		instance.set_world(world_context)
	if instance.has_method("set_player") and context.has("player"):
		instance.set_player(context["player"])

	# Step 5: Execute
	var result: Variant = null
	var error_msg := ""

	if instance.has_method("_execute"):
		result = instance._execute()
		if instance.has_method("get_error"):
			error_msg = instance.get_error()
	else:
		error_msg = "Script has no _execute() method"

	var total_time := Time.get_ticks_msec() - start_time

	# Check execution time
	if total_time > current_api.max_execution_time_ms:
		error_msg = "Execution timeout (%dms > %dms limit)" % [total_time, current_api.max_execution_time_ms]
		execution_error.emit(error_msg)
		return SandboxResult.new(false, null, error_msg, total_time)

	# Update stats
	_execution_count += 1
	_total_execution_time += total_time

	var sandbox_result: SandboxResult
	if error_msg != "":
		sandbox_result = SandboxResult.new(false, null, error_msg, total_time)
		execution_error.emit(error_msg)
	else:
		sandbox_result = SandboxResult.new(true, result, "", total_time)
		# Copy print output if available
		if instance.has_method("get_print_output"):
			sandbox_result.print_output = instance.get_print_output()

	execution_completed.emit(sandbox_result)
	return sandbox_result


## Turn a GDScript compile error code into a friendlier message.
## (Godot only surfaces the detailed parse message on stderr, so we give the
## player guidance instead of a raw error code.)
func _describe_compile_error(code: int) -> String:
	if code == ERR_PARSE_ERROR:
		return "Syntax error - check for a missing colon, an unmatched bracket, or a misspelled spell name."
	return "Your spell could not be cast (error %d)." % code


## Static validation of code (before compilation)
func _validate_code(code: String) -> String:
	# Check for forbidden patterns
	for pattern in FORBIDDEN_PATTERNS:
		if pattern in code:
			return "Forbidden statement: '%s'" % pattern

	# Check statement count (rough estimate: non-empty, non-comment lines)
	var lines := code.split("\n")
	var statement_count := 0
	for line in lines:
		var stripped := line.strip_edges()
		if stripped != "" and not stripped.begins_with("#"):
			statement_count += 1

	if statement_count > current_api.max_statements:
		return "Too many statements (%d > %d limit)" % [statement_count, current_api.max_statements]

	# Validate allowed functions
	var error := _validate_function_calls(code)
	if error != "":
		return error

	# Catch parameter names used as if they were variables (e.g. `color`)
	error = _validate_identifiers(code)
	if error != "":
		return error

	# Validate language features
	if not current_api.allow_loops:
		if _contains_keyword(code, "for") or _contains_keyword(code, "while"):
			return "Loops are not allowed in this level"

	if not current_api.allow_functions:
		if _contains_keyword(code, "func"):
			return "Function definitions are not allowed in this level"

	if not current_api.allow_match:
		if _contains_keyword(code, "match"):
			return "Match statements are not allowed in this level"

	return ""


## Check for a whole-word keyword outside of string literals (rough)
func _contains_keyword(code: String, keyword: String) -> bool:
	var regex := RegEx.new()
	regex.compile("\\b" + keyword + "\\b")
	return regex.search(code) != null


## Validate all function calls in the code
func _validate_function_calls(code: String) -> String:
	# Strip comments before checking
	var clean_code := _strip_comments(code)

	var regex := RegEx.new()
	regex.compile("([a-zA-Z_][a-zA-Z0-9_]*)\\s*\\(")

	var matches := regex.search_all(clean_code)
	for match in matches:
		var func_name := match.get_string(1)

		# Skip built-in functions and keywords
		if func_name in BUILTIN_FUNCTIONS:
			continue

		# Skip if it's a method call (preceded by .)
		var prefix_start := match.get_start() - 1
		if prefix_start >= 0 and clean_code[prefix_start] == ".":
			continue

		# Check if function is allowed
		if not current_api.is_function_allowed(func_name):
			return "Function '%s' is not allowed in this level" % func_name

		# Check the argument count for API functions
		var arity_error := _validate_arg_count(func_name, clean_code, match.get_end() - 1)
		if arity_error != "":
			return arity_error

	return ""


## Validate that an API call passes the right number of arguments.
## `open_paren_index` is the index of the call's opening parenthesis.
func _validate_arg_count(func_name: String, code: String, open_paren_index: int) -> String:
	var signature := current_api.get_function_signature(func_name)
	var total: int = signature.get("args", []).size()

	# Highest index that is not optional (+1) = number of required args
	var required := 0
	for i in range(total):
		if current_api.get_arg_default(signature, i) == null:
			required = i + 1

	var given := _count_call_args(code, open_paren_index)

	if given < required:
		return "%s() needs at least %d argument%s but got %d." % [
			func_name, required, "" if required == 1 else "s", given
		]
	if given > total:
		return "%s() takes at most %d argument%s but got %d." % [
			func_name, total, "" if total == 1 else "s", given
		]
	return ""


## Count the top-level arguments of a call, starting at its opening parenthesis.
## Correctly skips nested brackets and string literals.
func _count_call_args(code: String, open_paren_index: int) -> int:
	var depth := 0
	var commas := 0
	var has_content := false
	var in_string := false
	var string_delim := ""
	var i := open_paren_index

	while i < code.length():
		var ch := code[i]

		if in_string:
			if ch == "\\":
				i += 2
				continue
			if ch == string_delim:
				in_string = false
		elif ch == "\"" or ch == "'":
			in_string = true
			string_delim = ch
			has_content = true
		elif ch == "(" or ch == "[" or ch == "{":
			depth += 1
			if depth > 1:
				has_content = true
		elif ch == ")" or ch == "]" or ch == "}":
			depth -= 1
			if depth == 0:
				break
		elif ch == "," and depth == 1:
			commas += 1
			has_content = true
		elif ch != " " and ch != "\t" and ch != "\n":
			has_content = true

		i += 1

	return 0 if not has_content else commas + 1


## Catch the common beginner mistake of using an API parameter NAME as if it
## were a variable, e.g. `color_platform(1, 2, color)` — `color` only exists in
## the spell's signature, not in the player's scope. Catching this before
## compilation also avoids a raw engine parser error in the console.
func _validate_identifiers(code: String) -> String:
	if current_api == null:
		return ""

	var clean_code := _mask_strings(_strip_comments(code))

	# Names the player declared themselves are always fine.
	var declared := _collect_declared_identifiers(clean_code)

	# Every API parameter name is "suspect": it looks like a value but isn't.
	var param_owners := {}
	for func_name in current_api.allowed_functions.keys():
		var signature: Dictionary = current_api.allowed_functions[func_name]
		for param_name in signature.get("param_names", []):
			var key := str(param_name)
			if not param_owners.has(key):
				param_owners[key] = []
			param_owners[key].append(func_name)
	if param_owners.is_empty():
		return ""

	var regex := RegEx.new()
	regex.compile("[a-zA-Z_][a-zA-Z0-9_]*")

	for match in regex.search_all(clean_code):
		var token := match.get_string()
		if not param_owners.has(token):
			continue
		if declared.has(token):
			continue
		if token in BUILTIN_FUNCTIONS:
			continue

		# A member access (e.g. `thing.color`) is a property, not a variable.
		var p := match.get_start() - 1
		while p >= 0 and (clean_code[p] == " " or clean_code[p] == "\t"):
			p -= 1
		if p >= 0 and clean_code[p] == ".":
			continue

		# Prefer the spell whose call actually encloses this token.
		var owners: Array = param_owners[token]
		var owner := _enclosing_call_name(clean_code.substr(0, match.get_start()))
		if owner != "" and owners.has(owner):
			return "'%s' is not a variable here - it is the name of a parameter of %s(). Pass your own value instead." % [token, owner]
		return "'%s' is not a variable here. Did you mean to declare it with `var %s = ...`?" % [token, token]

	return ""


## Find the name of the call that encloses the end of `prefix`
## (e.g. "foo(1, " -> "foo").
func _enclosing_call_name(prefix: String) -> String:
	var regex := RegEx.new()
	regex.compile("([a-zA-Z_][a-zA-Z0-9_]*)\\s*\\([^()]*$")
	var m := regex.search(prefix)
	if m:
		return m.get_string(1)
	return ""


## Collect identifiers the player declares via var/const/for/func so we don't
## mistake their own variables for the parameter-name mistake above.
func _collect_declared_identifiers(code: String) -> Dictionary:
	var declared := {}

	var var_regex := RegEx.new()
	var_regex.compile("\\b(?:var|const)\\s+([a-zA-Z_][a-zA-Z0-9_]*)")
	for m in var_regex.search_all(code):
		declared[m.get_string(1)] = true

	var for_regex := RegEx.new()
	for_regex.compile("\\bfor\\s+([a-zA-Z_][a-zA-Z0-9_]*)\\s+in\\b")
	for m in for_regex.search_all(code):
		declared[m.get_string(1)] = true

	var func_regex := RegEx.new()
	func_regex.compile("\\bfunc\\s+([a-zA-Z_][a-zA-Z0-9_]*)\\s*\\(([^)]*)\\)")
	for m in func_regex.search_all(code):
		declared[m.get_string(1)] = true
		for param in m.get_string(2).split(","):
			var pname := param.strip_edges()
			var colon := pname.find(":")
			if colon >= 0:
				pname = pname.substr(0, colon)
			var equals := pname.find("=")
			if equals >= 0:
				pname = pname.substr(0, equals)
			pname = pname.strip_edges()
			if pname != "":
				declared[pname] = true

	return declared


## Blank out the contents of string literals (keeping their quotes) so an
## identifier scan never picks up words that are just text. Length is preserved.
func _mask_strings(code: String) -> String:
	var out := ""
	var i := 0
	var n := code.length()
	while i < n:
		var ch := code[i]
		if ch == "\"" or ch == "'":
			var delim := ch
			out += ch
			i += 1
			while i < n:
				var c := code[i]
				if c == "\\":
					out += "  "
					i += 2
					continue
				if c == delim:
					out += c
					i += 1
					break
				out += " "
				i += 1
			continue
		out += ch
		i += 1
	return out


## Strip # comments from code (naive, does not handle strings)
func _strip_comments(code: String) -> String:
	var result := ""
	for line in code.split("\n"):
		var comment_pos := line.find("#")
		if comment_pos >= 0:
			result += line.substr(0, comment_pos) + "\n"
		else:
			result += line + "\n"
	return result


## Build the wrapped script with injected API
func _build_wrapped_script(player_code: String) -> String:
	var wrapped := "extends RefCounted\n\n"

	# Boilerplate: API handle, context, print capture
	wrapped += """var api_impl = null
var _context = {}
var _world = null
var _print_output = []
var _error = ""

func set_api(api) -> void:
	api_impl = api

func set_context(ctx) -> void:
	_context = ctx

func set_world(world) -> void:
	_world = world
	if api_impl and api_impl.has_method("set_world"):
		api_impl.set_world(world)

func set_player(player) -> void:
	if api_impl and api_impl.has_method("set_player"):
		api_impl.set_player(player)

func get_error() -> String:
	return _error

func get_print_output() -> Array:
	return _print_output

func _log(msg) -> void:
	_print_output.append(str(msg))

"""

	# Generate a wrapper for each whitelisted API function
	if current_api:
		for func_name in current_api.allowed_functions.keys():
			var signature: Dictionary = current_api.allowed_functions[func_name]
			var returns: String = signature.get("returns", "void")

			var arg_decls: Array = current_api.build_arg_declarations(func_name)
			var arg_names: Array[String] = []
			for i in range(arg_decls.size()):
				arg_names.append("arg%d" % i)

			var arg_decl := ", ".join(arg_decls)
			var call_args := ", ".join(arg_names)

			var ret_decl := "" if returns == "void" else (" -> %s" % returns)

			wrapped += "func %s(%s)%s:\n" % [func_name, arg_decl, ret_decl]
			wrapped += "	if api_impl and api_impl.has_method(\"%s\"):\n" % func_name

			if returns == "void":
				wrapped += "		api_impl.%s(%s)\n" % [func_name, call_args]
			else:
				wrapped += "		return api_impl.%s(%s)\n" % [func_name, call_args]
			wrapped += "	_log(\"API %s is not available\")\n" % func_name

			if returns != "void":
				wrapped += "	return %s\n" % current_api.get_default_return(returns)
			wrapped += "\n"

	# Player entry point
	wrapped += "func _execute() -> void:\n"

	var player_lines := player_code.split("\n")
	var has_code := false
	for line in player_lines:
		var stripped := line.strip_edges()
		if stripped != "" and not stripped.begins_with("#"):
			# Indent one level into _execute. The player's own indentation is
			# converted to tabs first - beginners (and pasted hints) often
			# indent with spaces, and GDScript rejects tab/space mixtures
			# within a block.
			wrapped += "	" + "\t".repeat(_indent_levels(line)) + stripped + "\n"
			has_code = true

	if not has_code:
		wrapped += "	pass\n"

	return wrapped


## Convert a line's leading whitespace into indentation levels
## (4 spaces or 1 tab = one level; any partial level counts as one).
func _indent_levels(line: String) -> int:
	var columns := 0
	for i in range(line.length()):
		var ch := line[i]
		if ch == "\t":
			columns += 4
		elif ch == " ":
			columns += 1
		else:
			break
	var levels := columns / 4
	if columns % 4 != 0:
		levels += 1
	return levels


## Get execution statistics
func get_stats() -> Dictionary:
	return {
		"execution_count": _execution_count,
		"total_time_ms": _total_execution_time,
		"avg_time_ms": _total_execution_time / max(_execution_count, 1),
	}


## Reset statistics
func reset_stats() -> void:
	_execution_count = 0
	_total_execution_time = 0
