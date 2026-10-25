import json, sys
from pathlib import Path
from lupa.lua53 import LuaRuntime, lua_type
repo=Path(__file__).resolve().parents[1]
checks=0

def check(v,msg):
 global checks
 assert v,msg
 checks+=1

class Server:
 def __init__(self):
  self.l=LuaRuntime(unpack_returned_tuples=True)
  l=self.l
  self.time=1000
  self.players={0:'Alice',1:'TowDriver',2:'SecondDriver',3:'Bob'}
  self.vehicles={0:{0:'car',7:'truck'},1:{0:'tow'},2:{0:'tow'},3:{0:'car'}}
  self.messages=[]; self.events=[]
  def convert(v):
   if lua_type(v)=='table': return {str(k):convert(x) for k,x in v.items()}
   return v
  def decode(s):
   v=json.loads(s)
   return l.table_from(v,recursive=True) if isinstance(v,(dict,list)) else v
  def send(pid,event,data): self.events.append((pid,event,data)); return True
  l.globals().MP=l.table_from({
   'RegisterEvent':lambda *a:None,'CreateEventTimer':lambda *a:None,
   'SendChatMessage':lambda pid,msg:self.messages.append((pid,msg)),
   'GetPlayerName':lambda pid:self.players.get(pid),
   'GetPlayers':lambda:l.table_from(self.players),
   'GetPlayerVehicles':lambda pid:l.table_from(self.vehicles.get(pid,{})),
   'TriggerClientEvent':send,
  })
  l.globals().Util=l.table_from({'JsonDecode':decode,'JsonEncode':lambda v:json.dumps(convert(v))})
  l.globals().os.time=lambda:self.time
  l.globals().print=lambda *a:None
  l.execute((repo/'BeamMP-Roadside-Assistance-Mod/Server/Roadside Assistance/Main.lua').read_text())
 def chat(self,pid,msg):
  self.messages=[];self.events=[]
  return self.l.globals().RoadsideAssistChat(pid,'UntrustedName',msg)
 def text(self):return '\n'.join(m for _,m in self.messages)
 def selected(self,pid,token,svid):self.l.globals().RoadsideAssistSelected(pid,json.dumps({'token':token,'serverVehicleID':svid}))

s=Server()
check(s.chat(0,'/help')==0,'do not intercept other help')
s.chat(0,'/assist'); token=json.loads(s.events[0][2])['token']
check(s.events[0][0]==0 and s.events[0][1]=='RoadsideAssistSelect','current vehicle selection private')
s.selected(1,token,'0-0'); s.chat(1,'/assist list'); check('No open' in s.text(),'other sender cannot forge request')
s.selected(0,token,'1-0'); check('own vehicle' in s.text(),'cannot request another players vehicle')
s.chat(0,'/assist'); token=json.loads(s.events[0][2])['token'];s.selected(0,token,'0-0')
check('Request #1 created' in s.text(),'current vehicle request created')
s.selected(0,token,'0-7'); s.chat(1,'/assist list'); check(s.text().count('Job #')==1,'selection replay does not duplicate')
s.chat(0,'/assist 7');check('already have' in s.text(),'one request per player')
s.chat(0,'/assist accept 1');check(not s.events,'self accept blocked')
s.chat(1,'/assist accept 1');check(any(e[0]==1 and e[1]=='RoadsideAssistLocate' and json.loads(e[2])['serverVehicleID']=='0-0' for e in s.events),'helper exact target marker')
check(any(pid==0 and 'TowDriver accepted' in msg for pid,msg in s.messages),'requester notified')
s.chat(2,'/assist accept 1');check('already accepted' in s.text() and not s.events,'second helper cannot steal')
s.chat(1,'/assist 0');check('Complete or release' in s.text(),'helper cannot also request')
s.chat(2,'/assist complete');check('no accepted' in s.text(),'outsider cannot complete')
s.chat(0,'/assist status');check('TowDriver' in s.text(),'requester sees assigned helper')
s.chat(1,'/assist release');check(any(e[1]=='RoadsideAssistClear' for e in s.events),'release clears locator')
s.chat(2,'/assist accept 1');check('Accepted' in s.text(),'released job claimable')
s.chat(2,'/assist complete');check(any(pid==0 and 'completed' in m for pid,m in s.messages),'completion notifies requester')
s.chat(0,'/assist 0');check('wait' in s.text(),'request cooldown')
s.time+=31;s.chat(0,'/assist 7');check('Request #2' in s.text(),'request after cooldown')
s.chat(1,'/assist accept 2');s.chat(0,'/assist cancel');check(any(e[0]==1 and e[1]=='RoadsideAssistClear' for e in s.events),'owner cancellation clears helper')
s.chat(1,'/assist complete');check('no accepted' in s.text(),'cancel frees helper')
# Disconnect and ID reuse cleanup.
s.time+=31;s.chat(0,'/assist 0');s.chat(1,'/assist accept 3')
s.l.globals().RoadsideAssistDisconnect(1);s.players.pop(1)
s.chat(2,'/assist accept 3');check('Accepted' in s.text(),'helper disconnect reopens')
s.l.globals().RoadsideAssistDisconnect(0);s.players.pop(0);s.vehicles.pop(0)
s.chat(2,'/assist status');check('no active' in s.text(),'requester disconnect ends job')
s.players[0]='NewPlayer';s.vehicles[0]={0:'car'}
s.chat(0,'/assist status');check('no active' in s.text(),'reused player ID has no old request')
s.chat(0,'/assist 0');s.l.globals().RoadsideAssistVehicleDeleted(0,7)
s.chat(2,'/assist list');check('Job #4' in s.text(),'unrelated vehicle deletion does not cancel')
s.l.globals().RoadsideAssistVehicleDeleted(0,0);s.chat(2,'/assist list');check('No open' in s.text(),'target deletion cancels')
# Timer catches external deletions and pending timeouts.
s.time+=31;s.chat(0,'/assist 0');s.vehicles[0]={};s.l.globals().RoadsideAssistMaintenance()
s.chat(2,'/assist list');check('No open' in s.text(),'external removal swept')
s.chat(3,'/assist');token=json.loads(s.events[0][2])['token'];s.time+=16;s.selected(3,token,'3-0')
s.chat(2,'/assist list');check('No open' in s.text(),'expired token rejected')
s.chat(3,'/assist');token=json.loads(s.events[0][2])['token'];s.chat(3,'/assist cancel');s.selected(3,token,'3-0')
s.chat(2,'/assist list');check('No open' in s.text(),'cancel invalidates pending token')
for cmd in ['/assist -1','/assist 0 extra','/assist accept 1 extra','/assist complete extra','/assist reset','/assist 999999999999999999999']:
 s.chat(3,cmd);check('Unknown command' in s.text(),'strict args '+cmd)
s.chat(3,'/assist 999');check('does not belong' in s.text(),'vehicle ownership validation')
s.chat(3,'/assist 0');check('created' in s.text(),'manual vehicle selection works')
s.chat(2,'/assist list');check('Bob' in s.text(),'board displays requester')
s.chat(3,'/assist help');check('/assist release' in s.text(),'help covers release')
s.chat(2,'/assist vehicles');check('/assist 0' in s.text(),'own vehicle listing')
# No callback can create a request without a pending server selection.
s=Server();s.l.globals().RoadsideAssistSelected(0,'{bad');s.selected(0,'1','0-0')
s.chat(1,'/assist list');check('No open' in s.text(),'unsolicited callback rejected')
print(f'Passed {checks} roadside server behavior checks in Lua 5.3.')

# GUI actions reuse the same server-owned state machine.
s=Server()
def ui(pid,action,**fields):
 s.messages=[];s.events=[]
 s.l.globals().RoadsideAssistUI(pid,json.dumps(dict(action=action,**fields)))
def view(pid):
 states=[json.loads(raw) for recipient,event,raw in s.events if recipient==pid and event=='RoadsideAssistState']
 return states[-1] if states else None
ui(0,'refresh');check(view(0)['playerId']==0 and view(0)['connected'],'UI state uses authenticated sender')
ui(0,'request',playerId=3)
selection=[e for e in s.events if e[1]=='RoadsideAssistSelect'][0]
check(selection[0]==0,'UI cannot spoof requester')
check(view(0)['selecting'],'GUI shows pending selection')
s.selected(0,json.loads(selection[2])['token'],'0-0')
check(view(0)['request']['owner']==0 and view(0)['cooldown']==30,'GUI receives request and cooldown')
ui(1,'accept',jobId=1,playerId=2)
check(view(1)['assignment']['helper']==1,'UI accept binds actual helper')
check(view(0)['request']['helperName']=='TowDriver','requester receives live assigned status')
ui(2,'complete');check(view(2).get('assignment') is None,'outsider GUI cannot complete')
s.time+=1
ui(1,'complete');check(view(0).get('request') is None and view(1).get('assignment') is None,'GUI completion clears both views')
ui(1,'unsubscribe');s.events=[];s.chat(0,'/assist status')
check(not any(pid==1 and event=='RoadsideAssistState' for pid,event,_ in s.events),'closed UI unsubscribes')
for action,extra in [('reset',{}),('accept',{'jobId':'1'}),('accept',{'jobId':-1}),('accept',{'jobId':1.5}),('accept',{'jobId':2147483648}),('accept 1',{})]:
 s.time+=1;ui(2,action,**extra)
 check(not any(event=='RoadsideAssistLocate' for _,event,_ in s.events),'invalid GUI command rejected')
s.time+=1;s.events=[]
for i in range(20):s.l.globals().RoadsideAssistUI(3,'{"action":"refresh"}')
check(sum(event=='RoadsideAssistState' for _,event,_ in s.events)==8,'GUI events rate limited')
s.time+=1;ui(99,'refresh');check(not s.events,'disconnected sender ignored')
print('GUI server checks passed; total server assertions:',checks)
