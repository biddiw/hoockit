%% Feel free to use, reuse and abuse the code in this file.

{application, mqtt, [
	{description, "TCP MQTT Broker"},
	{vsn, "1"},
	{modules, ['mqtt_app', 'mqtt_sup', 'tcp_handler', 'mbutler', 'mqtt_session', 'transport_tcp', 'websocket_app', 'napdu', 'websocket_sup', 'ws_handler', 'hck_lib']},
	{registered, [mqtt_sup]},
	{applications, [
		kernel,
		stdlib,
		ranch
	]},
	{mod, {mqtt_app, []}},
	{env, []}
]}.
