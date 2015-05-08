%% Feel free to use, reuse and abuse the code in this file.

%% @private
-module(websocket_app).
-behaviour(application).

%% API.
-export([start/0]).
-export([start/2]).
-export([stop/1]).

start() ->
	ok=application:start(crypto),
	ok=application:start(ranch),
	ok=application:start(cowlib),
	ok=application:start(cowboy),
	ok=application:start(websocket).

%% API.
start(_Type, _Args) ->
	Dispatch = cowboy_router:compile([
		{'_', [
			{"/static", cowboy_static, {priv_file, websocket, "index.html"}},
			{'_', ws_handler, []}
		]}
	]),
	{ok, _} = cowboy:start_http(http, 100, [{port, 8080}],
		[{env, [{dispatch, Dispatch}]}]),
	{ok, _} = mbutler:start_link(),
	websocket_sup:start_link().

stop(_State) ->
	ok.
