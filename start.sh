#!/bin/sh
cd `dirname $0`
exec erl -mnesia dir \"priv/mnesia\" -pa ebin -pa deps/*/ebin -name hck-ng-dev"@"127.0.0.1
# exec erl -mnesia dir \"priv/mnesia\" -pa ebin -pa deps/*/ebin -name hck-ng-dev"@"127.0.0.1 -s websocket_app
