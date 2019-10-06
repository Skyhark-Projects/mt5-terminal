from flask import Flask, jsonify, request, abort
from datetime import datetime
from pytz import timezone
from datetime import date, datetime 
import fnmatch
import json
import os

# try loading MetaTrader5 module
import imp
try:
    imp.find_module('MetaTrader5')

    # connect to MetaTrader 5
    MT5Initialize()

    # wait till MetaTrader 5 establishes connection to the trade server and synchronizes the environment
    MT5WaitForTerminal()

    hasMT5 = True
except ImportError:
    hasMT5 = False
 
# ----------------------------------------------------------------  

print("Starting up") 
utc_tz = timezone('UTC') 
app = Flask(__name__)

# https://github.com/khramkov/MQL5-JSON-API/blob/master/Experts/JsonAPI.mq5

symbols = [ "EURUSD", "GBPUSD", "USDCHF", "USDJPY", "USDCAD", "AUDUSD", "EURCHF", "EURJPY", "EURGBP", "EURCAD", "GBPCHF", "GBPJPY", "AUDJPY" ]
lastmeta = {}
requestedOrders = {}

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

def addOrderRequest(type):
  authorized()
  data = json.loads(request.get_data())

  global requestedOrders
  if type in requestedOrders:
  	requestedOrders[type].append(data)
  else:
  	requestedOrders[type] = [ data ]

  return jsonify(data)

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

@app.route('/history')
def get_history():
  authorized()
  return 'Get closed positions history'

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

@app.route('/create/long', methods = ['POST'])
def create_long():
  return addOrderRequest("buy")

@app.route('/create/short', methods = ['POST'])
def create_short():
  return addOrderRequest("short")

@app.route('/close', methods = ['POST'])
def close_position():
  return addOrderRequest("close")

@app.route('/meta-update', methods = ['POST'])
def update_meta():
  if request.remote_addr != "127.0.0.1":
  	print ("Unauthorized meta update from " + request.remote_addr)
  	abort(403)

  data = request.get_data()
  global lastmeta

  lastmeta = json.loads(data[:len(data)-1])
  if "sym" in lastmeta:
    global symbols
    symbols = lastmeta["sym"]

  global requestedOrders
  res = jsonify(requestedOrders)
  requestedOrders = {}
  return res

if __name__ == "__main__":
  app.run(host='0.0.0.0')