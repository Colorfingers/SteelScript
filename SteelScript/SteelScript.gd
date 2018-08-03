extends Node

const DebugMessages = false

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
	return node


func Message(message):
	if DebugMessages:
		print(message)

func ParseError(message):
	print('Error: '+message+' @ line ' + str(self.current_line+1))
	self.successful_parse = false


func strip_white(script):
	var out = ''
	for index in len(script):
		if script[index] != ' ' and script[index] != '	':
			out += script[index]
	return out


func list_to_end(string, start):
	var out = []
	for cindex in len(string):
		if cindex >= start:
			out.append(cindex)
	return out

func paren_parser(parent, string, index=0):
	#print(string[index], string[index+1])
	var opencount = 0
	var carlist = []
	var childlist = []

	var endex = 0
	for cindex in list_to_end(string, index):
		var car = string[cindex]

		if car == '(':
			opencount += 1
			if opencount > 1:
				childlist.append(paren_parser(parent, string, cindex))
			continue

		if car == ')':
			opencount -= 1
			if opencount <= 0:
				endex = cindex
				break
			continue

		if opencount <= 1:
			carlist.append([car, opencount])

	if opencount > 0:
		ParseError('Unclosed parentheses')
		return null

	if len(list_to_end(string, index))-endex > 1 and index == 0:
		ParseError('Parentheses terminated early')
		return null

	var fullstr = ''
	for car in carlist:
		fullstr += car[0]

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

			if equaldex == null:
				ParseError('Missing equal sign in variable declaration')
				break


			parent.add_child(SetVar)
			var paren = paren_parser(SetVar, line.substr(equaldex+1,len(line)-equaldex+1))
			if paren != null:
				SetVar.add_child(paren)
			else:
				break


		elif line.substr(0,2) == 'if':
			var paren_str = line.substr(2, len(line)-2)
			if paren_str[len(paren_str)-1] == '{':
				paren_str = paren_str.substr(0,len(line)-3)

			var If = load_node('If')
			parent.add_child(If)

			var paren = paren_parser(If, paren_str)
			if paren != null:
				If.add_child(paren)
			else:
				break
			parent = If


		elif line == '}':
			parent = parent.get_parent()


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

			parent.add_child(APICall)

			var paren = paren_parser(APICall, line.substr(parendex+1,len(line)-parendex+1))
			if paren != null:
				APICall.add_child(paren)
			else:
				break


	if self.successful_parse:
		self.sroot.start()
	else:
		self.sroot.queue_free()


var script = """
var test_var = (42)
var test_var = ((test_var)-(2))
if ((test_var)==(40)){
	api.print(test_var)
}
api.print(0)
"""

func _ready():
	self.API = load(self.get_script().get_path().get_base_dir()+"/API.gd").new()
	exec_script(script)