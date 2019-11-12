from flask import Flask, jsonify, request, abort
from datetime import datetime
from pytz import timezone
from datetime import date, datetime
import time 
import fnmatch
import json
import os

# try loading MetaTrader5 module
import imp
try:
    imp.find_module('MetaTrader5')
    from MetaTrader5 import *

    # connect to MetaTrader 5
    MT5Initialize()

    # wait till MetaTrader 5 establishes connection to the trade server and synchronizes the environment
    MT5WaitForTerminal()

    hasMT5 = True
except ImportError:
    hasMT5 = False
 
# ----------------------------------------------------------------  

print("Starting up") 
timezone('UTC') 
app = Flask(__name__)

# https://github.com/khramkov/MQL5-JSON-API/blob/master/Experts/JsonAPI.mq5

symbols = [ "EURUSD", "GBPUSD", "USDCHF", "USDJPY", "USDCAD", "AUDUSD", "EURCHF", "EURJPY", "EURGBP", "EURCAD", "GBPCHF", "GBPJPY", "AUDJPY" ]
lastmeta = {}

# ----------------------------------------------------------------  
# helpers

# serialize object to return json response
def json_serial(obj):
  """JSON serializer for objects not serializable by default json code"""

  if isinstance(obj, (datetime, date)):
    return obj.isoformat()
  raise TypeError ("Type %s not serializable" % type(obj))

# check if connecting IP is authorized or not
authorized_ips = os.environ.get('AUTH_IP')
if authorized_ips != None:
  authorized_ips = authorized_ips.split(",")

def authorized():
  if authorized_ips == None:
    return
  for ip in authorized_ips:
    if fnmatch.fnmatch(request.remote_addr, ip):
      return

  print("Unauthorized ip " + request.remote_addr)
  abort(403)

# transform interval to MT5 resolution
def resolution(time):
	if time == 60:
		return MT5_TIMEFRAME_H1
	if time == 120:
		return MT5_TIMEFRAME_H2
	if time == 180:
		return MT5_TIMEFRAME_H3
	if time == 240:
		return MT5_TIMEFRAME_H4
	if time == 360:
		return MT5_TIMEFRAME_H6
	if time == 480:
		return MT5_TIMEFRAME_H8
	if time == 12 * 60:
		return MT5_TIMEFRAME_H12
	if time == 1440:
		return MT5_TIMEFRAME_D1
	return time

def pipeCommandRequest(type):
  authorized()
  data = json.loads(request.get_data())
  res = pipe.send(type, data)
  return jsonify(res)

# ----------------------------------------------------------------

@app.route('/')
def index():
  authorized()
  info = MT5TerminalInfo()
  return jsonify({
  	"status": info[0],
  	"server": info[1],
  	"login":  info[2]
  })

@app.route('/version')
def get_version():
  authorized()
  version = MT5Version()
  return jsonify({
  	"terminal_version": version[0],
  	"build": version[1],
  	"release_date": version[2]
  })

@app.route('/demo')
def get_demo():
  authorized()
  info = MT5TerminalInfo()
  return jsonify( "demo" in info[1].lower() )

@app.route('/ticks/<string:symbol>/<int:interval>/<int:start>/<int:end>')
def get_ticks_range(symbol, interval, start, end):
  authorized()
  return jsonify( MT5CopyRatesRange(symbol, resolution(interval), datetime.fromtimestamp(start), datetime.fromtimestamp(end)) )

@app.route('/ticks/<string:symbol>/<int:interval>')
def get_ticks(symbol, interval):
  authorized()
  return jsonify( MT5CopyRatesRange(symbol, resolution(interval), datetime(2015,1,1,0), 1000) )

@app.route('/symbols')
def get_symbols():
  authorized()
  global symbols
  return jsonify(symbols)

@app.route('/positions')
def get_positions():
  authorized()
  global lastmeta
  return jsonify(lastmeta["pos"])

@app.route('/history/<int:start>')
def get_history(start):
  authorized()
  res = pipe.send("history", { "from": start })
  return jsonify(res)

@app.route('/balance')
def get_balance():
  authorized()
  global lastmeta
  return {
  	"enabled": lastmeta["enabled"],
  	"balance": lastmeta["balance"],
  	"equity": lastmeta["equity"],
  	"margin": lastmeta["margin"],
  	"margin_free": lastmeta["margin_free"],
  }

@app.route('/attach/trailing_tp', methods = ['POST'])
def attach_trailing_tp():
  return pipeCommandRequest("trailing_tp")

@app.route('/attach/tp_sl', methods = ['POST'])
def attach_tp_sl():
  return pipeCommandRequest("tp_sl")

@app.route('/create/long', methods = ['POST'])
def create_long():
  return pipeCommandRequest("buy")

@app.route('/create/short', methods = ['POST'])
def create_short():
  return pipeCommandRequest("short")

@app.route('/close', methods = ['POST'])
def close_position():
  return pipeCommandRequest("close")

# ----------------------------------------------------------------

#@app.route('/backtest/sl_tp/<string:symbol>', methods = ['POST'])
#def backtest_sl_tp(symbol):
#   authorized()
#   data = json.loads(request.get_data())
#   
#   if "unix" not in data or "long" not in data or "tp" not in data or "sl" not in data or "trail" not in data or "trail_offset" not in data:
#   	return jsonify({ "error": "Please provide all required variables: unix, long, tp, sl, trail, trail_offset" })
# 
#   return jsonify({
#   	"test": data
#   })

@app.route('/ticks/history/<string:symbol>/<int:from_unix>/<int:to_unix>')
def ticks_history(symbol, from_unix, to_unix):
  authorized()
  res = MT5CopyTicksRange(symbol, datetime.fromtimestamp(from_unix), datetime.fromtimestamp(to_unix), MT5_COPY_TICKS_INFO)
  if len(res) > 100000:
  	res = res[:100000]

  return jsonify(res)

# ----------------------------------------------------------------

# Create pipe stream that allows commands to be send throught http requests
# When the MT5 terminals makes an http request to our server, the answer will not be send until the next http request is received or until we wants to send a command to MT5
class Pipe:
  commands = []
  id = 0
  notifyId = 0
  _onAction = {}
  _idRes = {}

  def send(self, action, data):
    # Create id for command
    if self.id > 10000:
      self.id = 1
    else:
      self.id = self.id + 1

    reqId = self.id

    # Append command
    self.commands.append({ "action": action, "data": data, "id": reqId })

    # Wait for command answer
    while reqId not in self._idRes:
      time.sleep(0.01)

    # Remove result from buffer and return result
    res = self._idRes[reqId]
    del self._idRes[reqId]
    return res

  # Bind callback to generic action
  def onCommand(self, action, cb):
    if action not in self._onAction:
      self._onAction[action] = [ cb ]
    else:
      self._onAction[action].append(cb)

  def _handleCommandAnswer(self, data):
    # Handle action callbacks
    if "action" in data and data["action"] in self._onAction:
      cbs = self._onAction[data["action"]]
      for cb in cbs:
        cb(data["data"])

    # Handle command result by id
    if "id" in data:
      if "data" in data:
        self._idRes[data["id"]] = data["data"]
      else:
        self._idRes[data["id"]] = {}

  # Handle http request received from MT5 terminal
  def onNotify(self, data):

    # Assign id to request
    if self.notifyId > 10000:
      self.notifyId = 1
    else:
      self.notifyId = self.notifyId + 1

    myId = self.notifyId

    # Handle received data (commands anwers)
    if isinstance(data, list):
      for key in data:
        self._handleCommandAnswer(key)

    # Wait till new request has been received or new command is queud
    count = 0
    while self.notifyId == myId and len(self.commands) == 0 and count < 70:
      count = count + 1
      time.sleep(0.015)    

    # Send commands back to terminal
    res = jsonify(self.commands)
    self.commands = []

    return res

pipe = Pipe()

# Handle symbols
def onMeta(res):
  global symbols
  global lastmeta

  lastmeta = res
  if "sym" in res:
    symbols = res["sym"]

# Handle history notifications from MT5
def onHistoryNotification(res):
  print("received history")
  print(res)

pipe.onCommand("meta", onMeta)
pipe.onCommand("history", onHistoryNotification)

#-----

# Handle MT5 http endpoint to receive requests and creates a communication channel between python and MT5
@app.route('/meta-update', methods = ['POST'])
def update_meta():
  if request.remote_addr != "127.0.0.1":
  	print ("Unauthorized meta update from " + request.remote_addr)
  	abort(403)

  data = request.get_data()
  data = json.loads(data[:len(data)-1])
  return pipe.onNotify(data)

if __name__ == "__main__":
  app.run(host='0.0.0.0')
