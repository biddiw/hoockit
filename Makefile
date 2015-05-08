PROJECT = mqtt
DEPS = cowboy erlzmq hashids
dep_cowboy = git "git://github.com/ninenines/cowboy" 1.0.x
dep_erlzmq = git "git://github.com/zeromq/erlzmq2"
dep_hashids = git "git://github.com/snaiper80/hashids-erlang.git"
include erlang.mk
