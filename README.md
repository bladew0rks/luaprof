# luaprof

luaprof [seconds] <function> [function ...]
luaprof_stop

use luaprof on client and luaprof_sv on server (superadmin only)
seconds defaults to 5
functions can be like hook.Run or Entity:GetPos

luaprof 10 hook.Run Entity:GetPos
