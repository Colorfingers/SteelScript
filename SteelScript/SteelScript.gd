extends Node

const InvalidNames = ['true', 'false']

var API = null

func eval_str(input):
	var script = GDScript.new()
	script.set_source_code('func eval():\n\treturn ' + input)
	script.reload()

	var obj = Reference.new()
	obj.set_script(script)

	return obj.eval()

func check_float(infloat):
	if infloat == int(infloat):
		infloat = int(infloat)
	return infloat

func call_api(call, args):
	#print(call, args)
	call = funcref(self.API, call).call_func(args)

func load_node(node):
	node = load(self.get_script().get_path().get_base_dir()+"/Nodes/Scenes/"+node+".tscn").instance()
	node.sroot = self.sroot
	node.line_number = current_line
	return node



func ParseError(message):
	print('ParseError: ' + message + ' @ line ' + str(self.current_line+1))
	self.successful_parse = false


func strip_white(script):
	var out = ''
	var in_string = false
	for index in len(script):
		if script[index] == "'":
			in_string = !in_string
			out += script[index]
			continue
		if in_string or script[index] != ' ' and script[index] != '	' :
			out += script[index]
	return out

func remove_open_curly(string):
	var out = ''
	for car in string:
		if car == '{':
			continue
		out += car
	return out

func prepare_paren_str(string):
	var out = ''
	var in_string = false
	for car in string:
		if car == "'":
			in_string = !in_string

		if car == '#' and not in_string:
			break
		out += car
	return out

func list_to_end(string, start):
	var out = []
	for cindex in len(string):
		if cindex >= start:
			out.append(cindex)
	return out

func paren_parser(parent, string, index=0):
	string = prepare_paren_str(string)

	var opencount = 0
	var carlist = []
	var childlist = []

	var endex = 0
	var in_string = false
	for cindex in list_to_end(string, index):
		var car = string[cindex]

		if car == "'":
			in_string = !in_string

		elif car == '(' and not in_string:
			opencount += 1
			if opencount > 1:
				childlist.append(paren_parser(parent, string, cindex))
			continue

		elif car == ')' and not in_string:
			opencount -= 1
			if opencount <= 0:
				endex = cindex
				break
			continue

		if opencount <= 1:
			carlist.append([car, opencount])

	if in_string:
		ParseError('Expected string end before line end')
		return null

	if opencount > 0:
		ParseError('Unclosed parentheses')
		return null

	if len(list_to_end(string, index))-endex > 1 and index == 0:
		ParseError('Invalid characters following parentheses')
		return null

	var fullstr = ''
	for car in carlist:
		fullstr += car[0]

	if fullstr == '':
		ParseError('Empty parentheses pair')
		return null

	# Begin parsing!
	var node = null
	if fullstr.is_valid_float():  # It is a number
		node = load_node('Number')
		node.Number = check_float(float(fullstr))

	elif fullstr in ['+', '-', '*', '/']:  # Math node
		node = load_node('Math')
		node.Operation = fullstr

	elif fullstr[0] in ['=', '>', '<', "!"] and fullstr[1] in ['=', '>', '<', "!"]:
		node = load_node('Comparison')
		node.Expression = fullstr

	elif fullstr[0]  == "'":  # String
		if fullstr[len(fullstr)-1] == "'":
			node = load_node('String')
			node.Contents = fullstr
		else:
			ParseError('Expected end of string')
			return null

	elif fullstr in ['true', 'false']:  # Boolean
		node = load_node('Bool')
		node.Boolean = fullstr == 'true'

	else:  # Must be a getvar
		node = load_node('GetVar')
		node.Variable = fullstr

	for child in childlist:
		node.add_child(child)
	return node


var sroot = null
var current_line = 0
var successful_parse = true

func exec_script(script):
	self.sroot = load(self.get_script().get_path().get_base_dir()+"/ScriptRoot.tscn").instance()
	var parent = self.sroot
	add_child(self.sroot)

	self.current_line = 0
	self.successful_parse = true

	var split = strip_white(script).split('\n')

	for lindex in len(split):
		var line = split[lindex]
		self.current_line = lindex

		if line == '\n':
			continue

		elif line.substr(0,3) == 'var':
			var SetVar = load_node('SetVar')

			var equaldex = null
			for cindex in len(line)-3:
				if line.substr(3,len(line)-3)[cindex] == '=':
					equaldex = cindex+3
					break
				SetVar.Variable += line.substr(3,len(line)-3)[cindex]

			if SetVar.Variable == '':
				ParseError('Variable name required in variable declaration')
				break

			if SetVar.Variable in InvalidNames:
				ParseError('Invalid variable name "' + SetVar.Variable + '" in variable declaration')
				break

			if equaldex == null:
				ParseError('Missing equal sign in variable declaration')
				break

			parent.add_child(SetVar)
			var paren = paren_parser(SetVar, line.substr(equaldex+1,len(line)-equaldex+1))
			if paren != null:
				SetVar.add_child(paren)
			else:
				break


		elif line.substr(0,3) == 'if(':
			var If = load_node('If')
			parent.add_child(If)

			var paren = paren_parser(If, remove_open_curly(line.substr(2, len(line)-2)))
			if paren != null:
				If.add_child(paren)
			else:
				break
			parent = If


		elif line.substr(0,1) == '}':
			parent = parent.get_parent()
			if len(line) > 1:
				if line.substr(1,1) != '#':
					ParseError('Invalid characters following }')


		elif line.substr(0,4) == 'api.':
			var APICall = load_node('APICall')

			var parendex = null
			for cindex in len(line)-4:
				var car = line[cindex+4]

				if car == '(':
					parendex = cindex+3
					break
				else:
					APICall.Call += car

			if APICall.Call == '':
				ParseError('Missing call name in API call')

			parent.add_child(APICall)

			var paren = paren_parser(APICall, line.substr(parendex+1,len(line)-parendex+1))
			if paren != null:
				APICall.add_child(paren)
			else:
				break

		else:
			if line.substr(0,1) != '#' and line != '':
				ParseError('Invalid line')

	if parent != sroot:
		ParseError('Block left unclosed from line ' + str(parent.line_number+1))

	if self.successful_parse:
		self.sroot.start()
	else:
		self.sroot.queue_free()


var script = """
var str_var = ('Why hello there good sir! I did not see you there!')
var test_var = (42)
var test_var = ((test_var)-(2)) #dsfsdfsf

if ((test_var)==(40)){ # test
	api.print(str_var)
} # Dis is a comment

if (true){
	api.print('Booleans are live! #Progress!')
}

api.print(0) # ha ha ha
#test
"""

func _ready():
	self.API = load(self.get_script().get_path().get_base_dir()+"/API.gd").new()
	exec_script(script)
