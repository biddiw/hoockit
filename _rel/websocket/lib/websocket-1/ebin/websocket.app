%% Feel free to use, reuse and abuse the code in this file.

{application, websocket, [
	{description, "Cowboy websocket example."},
	{vsn, "1"},
	{modules, ['websocket_app', 'websocket_sup', 'ws_handler']},
	{registered, [websocket_sup]},
	{applications, [
		kernel,
		stdlib,
		cowboy
	]},
	{mod, {websocket_app, []}},
	{env, []}
]}.
