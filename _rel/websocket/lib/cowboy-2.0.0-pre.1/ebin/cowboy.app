%% Copyright (c) 2011-2014, Loïc Hoguin <essen@ninenines.eu>
%%
%% Permission to use, copy, modify, and/or distribute this software for any
%% purpose with or without fee is hereby granted, provided that the above
%% copyright notice and this permission notice appear in all copies.
%%
%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
%% ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
%% OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

{application, cowboy, [
	{description, "Small, fast, modular HTTP server."},
	{vsn, "2.0.0-pre.1"},
	{id, ""},
	{modules, ['cowboy_router', 'cowboy', 'cowboy_bstr', 'cowboy_req', 'cowboy_app', 'cowboy_middleware', 'cowboy_spdy', 'cowboy_loop', 'cowboy_rest', 'cowboy_clock', 'cowboy_handler', 'cowboy_sub_protocol', 'cowboy_sup', 'cowboy_protocol', 'cowboy_static', 'cowboy_websocket', 'cowboy_constraints']},
	{registered, [cowboy_clock, cowboy_sup]},
	{applications, [
		kernel,
		stdlib,
		ranch,
		cowlib,
		crypto
	]},
	{mod, {cowboy_app, []}},
	{env, []}
]}.