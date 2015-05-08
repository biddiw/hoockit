%% Feel free to use, reuse and abuse the code in this file.

%% @private
-module(mqtt_app).
-behaviour(application).

%% API.
-export([start/2, start/0]).
-export([stop/1]).

%% API.

start() ->
	ok=application:start(crypto),
	ok=application:start(ranch),
	ok=application:start(mqtt).

start(_Type, _Args) ->
	{ok, _} = start_tcp(mqtt, 10, [{port, 8080}, {max_connections, 100}], [{handler, tcp_handler}, {handler_opts, []}]),
	mqtt_sup:start_link().

stop(_State) ->
	
	stop_listener(mqtt),
	ok.
	
-spec start_tcp(ranch:ref(), non_neg_integer(), ranch_tcp:opts(),
	cowboy_protocol:opts()) -> {ok, pid()} | {error, any()}.

start_tcp(Ref, NbAcceptors, TransOpts, ProtoOpts)
		when is_integer(NbAcceptors), NbAcceptors > 0 ->
	ranch:start_listener(Ref, NbAcceptors,
		ranch_tcp, TransOpts, transport_tcp, ProtoOpts).
		
-spec stop_listener(ranch:ref()) -> ok | {error, not_found}.

stop_listener(Ref) ->
	ranch:stop_listener(Ref).
