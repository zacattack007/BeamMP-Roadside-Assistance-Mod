import json
from pathlib import Path
from zipfile import ZipFile
from lupa.luajit21 import LuaRuntime
from lupa.luajit21 import lua_type
repo=Path(__file__).resolve().parents[1]
l=LuaRuntime(unpack_returned_tuples=True)
checks=0
def check(v,msg):
 global checks
 assert v,msg
 checks+=1
l.execute('''
handlers={}; notices={}; draws={}; entries={}; objects={}; registrations=0
local vector={}
vector.__index=vector
function vector.__add(a,b) return vec3(a.x+b.x,a.y+b.y,a.z+b.z) end
function vector.__sub(a,b) return vec3(a.x-b.x,a.y-b.y,a.z-b.z) end
function vector:length() return math.sqrt(self.x*self.x+self.y*self.y+self.z*self.z) end
function vec3(x,y,z) return setmetatable({x=x,y=y,z=z},vector) end
function ColorF(...) return {...} end
function ColorI(...) return {...} end
function String(s) return s end
function getCameraPosition() return vec3(0,0,0) end
function ui_message(s) table.insert(notices,s) end
function AddEventHandler(name,fn,source) handlers[name]=fn; registrations=registrations+1 end
function RemoveEventHandler(name,source) handlers[name]=nil end
be={getObjectByID=function(self,id) return objects[id] end}
extensions={MPVehicleGE={getVehicleByServerID=function(id) return entries[id] end}}
debugDrawer={
 drawCylinder=function(self,a,b,r,c) table.insert(draws,{'cylinder',a,b}) end,
 drawSphere=function(self,p,r,c) table.insert(draws,{'sphere',p}) end,
 drawTextAdvanced=function(self,p,text,fg,bg,other,color,shadow,useZ) table.insert(draws,{'text',p,text,useZ}) end
}
function spawn()
 entries['2-0']={gameVehicleID=10}
 objects[10]={position=vec3(10,0,0),getPosition=function(self) return self.position end}
end
''')

l.execute("""
serverEvents={}
function TriggerServerEvent(name,data) table.insert(serverEvents,{name,data}) end
function getPlayerVehicle() return objects[10] end
extensions.MPVehicleGE.getServerVehicleID=function(id) return id==10 and '2-0' or nil end
""")
def decode(raw):
 v=json.loads(raw)
 return l.table_from(v,recursive=True) if isinstance(v,(dict,list)) else v
def native(v):
 if lua_type(v)=='table': return {str(k):native(x) for k,x in v.items()}
 return v
l.globals().jsonDecode=decode
l.globals().jsonEncode=lambda v:json.dumps(native(v))
client=repo/'ClientSource/lua/ge/extensions/roadsideAssist.lua'
m=l.execute(client.read_text());m.onExtensionLoaded()
check(l.globals().registrations==5,'five named event handlers')
l.globals().spawn();l.execute('objects[10].getID=function() return 10 end')
l.globals().handlers.RoadsideAssistSelect('{"token":"12"}')
event=l.globals().serverEvents[1]
check(event[1]=='RoadsideAssistSelected' and json.loads(event[2])=={'token':'12','serverVehicleID':'2-0'},'current vehicle response')
l.execute('objects={}');l.globals().handlers.RoadsideAssistSelect('{"token":"13"}')
check(json.loads(l.globals().serverEvents[2][2])=={'token':'13'},'no vehicle response handled safely')
for raw in ['bad','{}','{"token":3}','{"token":"bad"}']:
 l.globals().handlers.RoadsideAssistSelect(raw)
check(len(l.globals().serverEvents)==2,'bad selection payloads ignored')
payload=json.dumps({'serverVehicleID':'2-0','label':'Job #1 - Alice (Player 2, vehicle 0)'})
def show():l.globals().handlers.RoadsideAssistLocate(payload)
def reset():l.execute('draws={}')
l.globals().spawn();show();m.onUpdate(.1)
check(len(l.globals().draws)==3,'marker drawn')
check('10 m from camera' in l.globals().draws[3][3],'distance shown')
l.execute('objects[10].position=vec3(30,0,0)');reset();m.onUpdate(.1)
check(l.globals().draws[1][2].x==30,'marker follows vehicle')
l.globals().handlers.RoadsideAssistClear('');reset();m.onUpdate(.1)
check(len(l.globals().draws)==0,'job closure clears marker')
show();reset();m.onUpdate(600)
check(len(l.globals().draws)==0 and '/assist locate' in l.globals().notices[len(l.globals().notices)],'expiry offers refresh')
show();m.onUpdate(.1);l.execute("entries['2-0']=nil");reset();m.onUpdate(.1)
check(len(l.globals().draws)==0,'removed vehicle clears')
l.globals().spawn();show();m.onUpdate(.1);l.globals().spawn();reset();m.onUpdate(.1)
check(len(l.globals().draws)==0,'ID reuse does not retarget')
l.execute('objects={};entries={}');show();m.onUpdate(5)
check('not spawned' in l.globals().notices[len(l.globals().notices)],'unspawned vehicle feedback')
l.globals().spawn();show();m.onClientEndMission();reset();m.onUpdate(.1)
check(len(l.globals().draws)==0,'map exit clears')
m.onExtensionUnloaded();check(l.globals().handlers.RoadsideAssistSelect is None,'unregister on unload')
l.execute('savedAdd=AddEventHandler;AddEventHandler=nil');m.onExtensionLoaded()
l.execute('AddEventHandler=savedAdd');m.onUpdate(.1)
check(l.globals().handlers.RoadsideAssistSelect is not None,'delayed BeamMP loading supported')
with ZipFile(repo/'BeamMP-Roadside-Assistance-Mod/Client/BeamMP-Roadside-Assistance.zip') as z:
 check({'lua/ge/extensions/roadsideAssist.lua','scripts/roadsideAssist/modScript.lua','ui/modules/apps/RoadsideAssistance/app.json','ui/modules/apps/RoadsideAssistance/app.js','ui/modules/apps/RoadsideAssistance/app.html','ui/modules/apps/RoadsideAssistance/app.css','ui/modules/apps/RoadsideAssistance/app.png'} <= set(z.namelist()),'ZIP mount paths')
 check(z.read('lua/ge/extensions/roadsideAssist.lua')==client.read_bytes(),'ZIP matches source')
print(f'Passed {checks} roadside client and packaging checks in LuaJIT.')

# The game-side GUI bridge sends only whitelisted actions and clears on unload.
l.execute('''
hooks={}
guihooks={trigger=function(event,data) table.insert(hooks,{event,data}) end}
MPCoreNetwork={isMPSession=function() return false end}
''')
count=len(l.globals().serverEvents)
m.uiAction('request')
check(len(l.globals().serverEvents)==count and l.globals().hooks[1][2].connected==False,'offline app does not send server requests')
l.execute('MPCoreNetwork.isMPSession=function() return true end')
m.uiAction('accept',4)
event=l.globals().serverEvents[len(l.globals().serverEvents)]
check(event[1]=='RoadsideAssistUI' and json.loads(event[2])=={'action':'accept','jobId':4},'GUI command serialized')
count=len(l.globals().serverEvents)
m.uiAction('reset');m.uiAction('accept','4');m.uiAction('accept',-1)
check(len(l.globals().serverEvents)==count,'invalid local UI actions ignored')
l.globals().handlers.RoadsideAssistState('{"connected":true,"playerId":0}')
check(l.globals().hooks[len(l.globals().hooks)][1]=='RoadsideAssistAppState','server state forwarded to UI')
l.globals().handlers.RoadsideAssistNotice('{"text":"Job accepted"}')
check(l.globals().hooks[len(l.globals().hooks)][2].text=='Job accepted','server feedback forwarded to UI')
m.onExtensionUnloaded()
check(l.globals().handlers.RoadsideAssistState is None and l.globals().handlers.RoadsideAssistSelect is None,'UI unload does not re-register handlers')
event=l.globals().serverEvents[len(l.globals().serverEvents)]
check(json.loads(event[2])['action']=='unsubscribe','UI subscription ends on unload')
print('GUI client checks passed; total client assertions:',checks)
