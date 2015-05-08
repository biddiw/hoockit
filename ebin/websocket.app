%% Feel free to use, reuse and abuse the code in this file.

{application, websocket, [
	{description, "Cowboy websocket example."},
	{vsn, "1"},
	{modules, ['tcp_handler', 'mbutler', 'mqtt_session', 'transport_tcp', 'websocket_app', 'napdu', 'websocket_sup', 'ws_handler', 'hck_lib']},
	{registered, [websocket_sup]},
	{applications, [
		kernel,
		stdlib,
		cowboy
	]},
	{mod, {websocket_app, []}},
	{env, []}
]}.
