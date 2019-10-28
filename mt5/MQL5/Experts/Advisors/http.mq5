//+------------------------------------------------------------------+
//|                                                         Http.mq5 |
//|                        Copyright 2019, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2019, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#define EXPERT_MAGIC 123456
#include <Json.mqh>
#include <Trade\Trade.mqh>

int historyCount = 0;

int OnInit() {
   HistorySelect(0, TimeCurrent());
   historyCount = HistoryDealsTotal();

   EventSetTimer(1);
   notifyData();
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Deinitialization function of the expert                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   EventKillTimer();
}
//+------------------------------------------------------------------+
//| "Tick" event handler function                                    |
//+------------------------------------------------------------------+
CJAVal trailing_tps;
void OnTick() {
   // Handle trailing tp's
   for(int x=0; x<trailing_tps.Size(); x++) {
      CJAVal tp = trailing_tps[x];
      double trigger = tp["trigger"].ToDbl();
      if(trigger == 0)
         continue;

      if(tp["is_long"].ToBool()) {
         // Long
         double current_price = SymbolInfoDouble(tp["symbol"].ToStr(), SYMBOL_BID);
         double triggeredRate = -1;

         if(current_price >= trigger) {
            tp["trigger"]   = current_price;
            tp["triggered"] = true;
            triggeredRate   = current_price;
         } else if(tp.HasKey("triggered") && tp["triggered"].ToBool()) {
            triggeredRate = trigger;
         }

         if(triggeredRate != -1 && current_price <= triggeredRate-tp["offset"].ToDbl()) {
            Print("Long Trailing TP triggered " + tp["id"].ToStr());
            Close(tp);
         }
      } else {
         // Short
         double current_price = SymbolInfoDouble(tp["symbol"].ToStr(), SYMBOL_ASK);
         double triggeredRate = -1;

         if(current_price <= trigger) {
            tp["trigger"]   = current_price;
            tp["triggered"] = true;
            triggeredRate   = current_price;
         } else if(tp.HasKey("triggered") && tp["triggered"].ToBool()) {
            triggeredRate = trigger;
         }

         if(triggeredRate != -1 && current_price >= triggeredRate+tp["offset"].ToDbl()) {
            Print("Short Trailing TP triggered " + tp["id"].ToStr());
            Close(tp);
         }
      }
   }
}
//+------------------------------------------------------------------+
//| "Trade" event handler function                                   |
//+------------------------------------------------------------------+
void OnTrade() {
   // Remove closed trailing tp's
   CJAVal n;
   for(int x=0; x<trailing_tps.Size(); x++) {
      int id = int(trailing_tps[x]["id"].ToInt());
      if(PositionSelectByTicket(id)) {
         n.Add(trailing_tps[x]);
      }
   }

   trailing_tps.Set(n);

   // Add new history orders to notifications
   HistorySelect(0, TimeCurrent());
   int count = HistoryDealsTotal();
   if(historyCount < count) {
      for(;historyCount<count; historyCount++) {
         int ticket = int(HistoryDealGetTicket(historyCount));
         if (HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
            continue;

         // Add notification command
         CJAVal metaCommand;
         metaCommand["action"] = "history";
         metaCommand["data"].Set( HistoryItem(ticket) );

         commands.Add(metaCommand);
      }
   }

   // Notify new data to python
   notifyData();
}
//+------------------------------------------------------------------+
//| "Timer" event handler function                                   |
//+------------------------------------------------------------------+
void OnTimer() {
   notifyData();
}

//+------------------------------------------------------------------+

int isymbol = 0;
bool req_history = false;
void SymbolsJSON(CJAVal &data) {
   int length = SymbolsTotal(false);
   for(int i=0; i<length; i++) {
      data["sym"].Add(SymbolName(i, false));
   }
}

void BalancesJSON(CJAVal &data) {
   data["balance"] = AccountInfoDouble(ACCOUNT_BALANCE);
   data["equity"] = AccountInfoDouble(ACCOUNT_EQUITY);
   data["margin"] = AccountInfoDouble(ACCOUNT_MARGIN);
   data["margin_free"] = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
}

void PositionsJSON(CJAVal &data) {
   CJAVal position;

   // Get positions  
   int positionsTotal=PositionsTotal();
   // Create empty array if no positions
   if(!positionsTotal) data["pos"].Add(position);
   // Go through positions in a loop
   for(int i=0;i<positionsTotal;i++){
     ResetLastError();
     PositionGetSymbol(i);
     position["id"]           = PositionGetInteger(POSITION_IDENTIFIER);
     position["magic"]        = PositionGetInteger(POSITION_MAGIC);
     position["symbol"]       = PositionGetString(POSITION_SYMBOL);
     position["type"]         = EnumToString(ENUM_POSITION_TYPE(PositionGetInteger(POSITION_TYPE)));
     position["time_setup"]   = PositionGetInteger(POSITION_TIME);
     position["open"]         = PositionGetDouble(POSITION_PRICE_OPEN);
     position["stoploss"]     = PositionGetDouble(POSITION_SL);
     position["takeprofit"]   = PositionGetDouble(POSITION_TP);
     position["volume"]       = PositionGetDouble(POSITION_VOLUME);

     for(int x=0; x<trailing_tps.Size(); x++) {
      if(trailing_tps[x]["id"].ToInt() == position["id"].ToInt()) {
         position["trailing_tp"].Set(trailing_tps[x]);
         break;
      }
     }

     data["pos"].Add(position);
   }
}

CJAVal HistoryItem(int ticket) {
   CJAVal position;
   position["id"]           = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
   position["ticket"]       = ticket;
   position["magic"]        = HistoryDealGetInteger(ticket, DEAL_MAGIC);
   position["symbol"]       = HistoryDealGetString(ticket, DEAL_SYMBOL);
   position["type"]         = EnumToString(ENUM_POSITION_TYPE(HistoryDealGetInteger(ticket, DEAL_TYPE)));
   position["time_setup"]   = HistoryDealGetInteger(ticket, DEAL_TIME);
   position["open"]         = HistoryDealGetDouble(ticket, DEAL_PRICE);
   position["fee"]          = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   position["profit"]       = HistoryDealGetDouble(ticket, DEAL_PROFIT);
   position["volume"]       = HistoryDealGetDouble(ticket, DEAL_VOLUME);
   position["comment"]      = HistoryDealGetString(ticket, DEAL_COMMENT);
   return position;
}

CJAVal History(CJAVal &data, int limit) {
   CJAVal info;

   HistorySelect(0, TimeCurrent());

   // Get positions  
   int positionsTotal = HistoryDealsTotal();
   int start          = data["from"].ToInt();
   int count          = 0;

   // Go through history in a loop
   for(int i=0;i<positionsTotal;i++){
     ResetLastError();
     int ticket = int(HistoryDealGetTicket(i));
     info.Add( HistoryItem(ticket) );

     count++;
     if(count >= limit)
       break;
   }

   return info;
}

/*CJAVal OrdersJSON(){
   ResetLastError();
   CJAVal order, data;
   
   // Get orders
   if (HistorySelect(0,TimeCurrent())){    
      int ordersTotal = OrdersTotal();
      // Create empty array if no orders
      if(!ordersTotal) { data.Add(order); }
      
      for(int i=0;i<ordersTotal;i++){

         OrderGetTicket(i);
            //order["id"]=(string) myorder.Ticket();
            order["magic"]=OrderGetInteger(ORDER_MAGIC); 
            order["symbol"]=OrderGetString(ORDER_SYMBOL);
            order["type"]=EnumToString(ENUM_ORDER_TYPE(OrderGetInteger(ORDER_TYPE)));
            order["time_setup"]=OrderGetInteger(ORDER_TIME_SETUP);
            order["open"]=OrderGetDouble(ORDER_PRICE_OPEN);
            order["stoploss"]=OrderGetDouble(ORDER_SL);
            order["takeprofit"]=OrderGetDouble(ORDER_TP);
            order["volume"]=OrderGetDouble(ORDER_VOLUME_INITIAL);
            
            //data["error"]=(bool) false;
            //data["orders"].Add(order);
            data.Add(order);
      }
   }
      
   return data;
}*/

double transformVolume(CJAVal &pos) {
   double lot_step = SymbolInfoDouble(pos["symbol"].ToStr(), SYMBOL_VOLUME_STEP);
   return MathRound(pos["volume"].ToDbl() / lot_step) * lot_step;
}

CJAVal result_to_json(MqlTradeResult &result) {
   CJAVal info;
   info["id"] = int(result.order);
   info["code"] = int(result.retcode);
   info["deal"] = int(result.deal);
   info["volume"] = result.volume;
   info["price"] = result.price;
   info["comment"] = result.comment;
   return info;
}

CJAVal Buy(CJAVal &pos) {
   //--- declare and initialize the trade request and result of trade request
   MqlTradeRequest request={0};
   MqlTradeResult  result={0};
   //--- parameters of request
   request.action   = TRADE_ACTION_DEAL;                     // type of trade operation

   request.symbol   = pos["symbol"].ToStr();                 // symbol
   request.volume   = transformVolume(pos);                  // volume
   request.type     = ORDER_TYPE_BUY;                        // order type
   request.price    = SymbolInfoDouble(request.symbol, SYMBOL_ASK); // price for opening
   request.deviation= 5;                                     // allowed deviation from the price
   request.magic    = EXPERT_MAGIC;                          // MagicNumber of the order
   request.type_filling = ORDER_FILLING_IOC;
   request.type_time = ORDER_TIME_DAY;

   if(pos.HasKey("comment"))
      request.comment = pos["comment"].ToStr();
   if(pos.HasKey("magic"))
      request.magic = pos["magic"].ToInt();
   if(pos.HasKey("sl"))
      request.sl = pos["sl"].ToDbl();
   if(pos.HasKey("tp"))
      request.tp = pos["tp"].ToDbl();

   //--- send the request
   if(!OrderSend(request,result))
      PrintFormat("OrderSend error %d",GetLastError());     // if unable to send the request, output the error code
   //--- information about the operation
   PrintFormat("retcode=%u  deal=%I64u  order=%I64u",result.retcode,result.deal,result.order);

   CJAVal resInfo = result_to_json(result);
   if(pos.HasKey("trailing_tp")) {
      CJAVal tp = pos["trailing_tp"];
      tp["id"] = int(result.order);
      resInfo["trailing_tp"].Set(TrailingTp(tp));
   }

   return resInfo;
}

CJAVal Short(CJAVal &pos) {
   //--- declare and initialize the trade request and result of trade request
   MqlTradeRequest request={0};
   MqlTradeResult  result={0};
   //--- parameters of request
   request.action   = TRADE_ACTION_DEAL;                     // type of trade operation
   request.symbol   = pos["symbol"].ToStr();                 // symbol
   request.volume   = transformVolume(pos);                  // volume
   request.type     = ORDER_TYPE_SELL;                       // order type
   request.price    = SymbolInfoDouble(request.symbol,SYMBOL_BID); // price for opening
   request.deviation= 5;                                     // allowed deviation from the price
   request.magic    = EXPERT_MAGIC;                          // MagicNumber of the order
   request.type_filling = ORDER_FILLING_IOC;
   request.type_time = ORDER_TIME_DAY;

   if(pos.HasKey("comment"))
      request.comment = pos["comment"].ToStr();
   if(pos.HasKey("magic"))
      request.magic = pos["magic"].ToInt();
   if(pos.HasKey("sl"))
      request.sl = pos["sl"].ToDbl();
   if(pos.HasKey("tp"))
      request.tp = pos["tp"].ToDbl();

   //--- send the request
   if(!OrderSend(request, result))
      PrintFormat("OrderSend error %d",GetLastError());     // if unable to send the request, output the error code
   //--- information about the operation
   PrintFormat("retcode=%u  deal=%I64u  order=%I64u",result.retcode,result.deal,result.order);

   CJAVal resInfo = result_to_json(result);
   if(pos.HasKey("trailing_tp")) {
      CJAVal tp = pos["trailing_tp"];
      tp["id"] = int(result.order);
      resInfo["trailing_tp"].Set(TrailingTp(tp));
   }

   return resInfo;
}

CJAVal Close(CJAVal &pos) {
   int timeBeforeExec = TimeCurrent();
   CTrade trade;
   int id = int(pos["id"].ToInt());
   if(!trade.PositionClose(id)) {
      CJAVal info;
      info["success"] = false;
      return info;
   }

   HistorySelect(timeBeforeExec, TimeCurrent());
   return HistoryItem(int(trade.ResultDeal()));
}

// Create trailing tp
CJAVal TrailingTp(CJAVal &data) {
   CJAVal info;

   // Validate input data
   // ToDo add ability to exprime offset in percent
   if(!data.HasKey("id") || !data["id"].IsNumeric()) {
      info["error"] = "No valid id provided";
      return info;
   } else if (!data.HasKey("trigger") || !data["trigger"].IsNumeric()) {
      info["error"] = "No valid trigger provided";
      return info;
   } else if (!data.HasKey("offset") || !data["offset"].IsNumeric()) {
      info["error"] = "No valid offset provided";
      return info;
   } else if(data.HasKey("sl") && !data["sl"].IsNumeric()) {
      info["error"] = "Wrong stop loss provided";
      return info;
   } else if(data.HasKey("tp") && !data["tp"].IsNumeric()) {
      info["error"] = "Wrong take profit provided";
      return info;
   }

   // Select position id and verify if position exists
   int id = int(data["id"].ToInt());
   if(!PositionSelectByTicket(id)) {
      info["error"] = "Position not found";
      return info;
   }

   // Attach simple tp / sl
   if(data.HasKey("sl") || data.HasKey("tp")) {
      CTrade trade;
      if(!trade.PositionModify(id, data["sl"].ToDbl(), data["tp"].ToDbl())) {
         Print("Coud not attach sl/tp to position", id);
      }
   }

   // Setup trailing tp
   string symbol   = PositionGetString(POSITION_SYMBOL);
   bool is_long    = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
   data["is_long"] = is_long;
   data["symbol"]  = symbol;

   // Handle initial trigger value
   // If we don't require to trigger from current timestamp, check if tp already reached in past data
   if((!data.HasKey("from_current_timestamp") || !data["from_current_timestamp"].ToBool()) && data["trigger"].ToDbl() != 0) {
      int ellapsed_time = int((TimeCurrent() - PositionGetInteger(POSITION_TIME)) / 60);

      if(is_long) {
         int highIndex  = iHighest(symbol, PERIOD_M1, MODE_HIGH, ellapsed_time, 0);
         double highest = iHigh(symbol, PERIOD_M1, highIndex);

         if(highest >= data["trigger"].ToDbl()) {
            data["trigger"] = highest;
            data["triggered"] = true;
         }
      } else {
         int lowIndex  = iLowest(symbol, PERIOD_M1, MODE_LOW, ellapsed_time, 0);
         double lowest = iLow(symbol, PERIOD_M1, lowIndex);

         if(lowest <= data["trigger"].ToDbl()) {
            data["trigger"] = lowest;
            data["triggered"] = true;
         }
      }
   }

   // Replace tp in list if already exists
   for(int x=0; x<trailing_tps.Size(); x++) {
      if(trailing_tps[x]["id"].ToInt() == id) {
         data["action"] = "replaced";
         trailing_tps[x].Set(data);
         info.Set(trailing_tps[x]);
         return info;
      }
   }

   // Add tp to list if not present yet
   data["action"] = "created";
   trailing_tps.Add(data);
   info.Set(data);
   return info;
}

//----------------------------------------------
// Communication protocol

CJAVal OnCommand(string action, CJAVal &data) {

   if(action == "buy") {
      return Buy(data);
   } else if(action == "short") {
      return Short(data);
   } else if(action == "close") {
      return Close(data);
   } else if(action == "history") {
      return History(data, 250);
   } else if(action == "tp_sl") {
      return TrailingTp(data);
   }

   CJAVal err;
   err["error"] = "Unknown action " + action + " received";
   return err;
}

//---------------------------

CJAVal commands;

string NotifyJSONData() {
   isymbol++;
 
   //Prepare meta data
   CJAVal meta;
 
   meta["enabled"] = MQLInfoInteger(MQL_TRADE_ALLOWED) && TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   PositionsJSON(meta);
   BalancesJSON(meta);
 
   if(isymbol > 10 || isymbol == 1) {
     SymbolsJSON(meta);
     isymbol = 1;
   }

   // Add meta command
   CJAVal metaCommand;
   metaCommand["action"] = "meta";
   metaCommand["data"].Set(meta);

   commands.Add(metaCommand);

   // Serialize commands data
   string data = commands.Serialize();
   commands.Clear();
   return data;
}

void notifyData() {

   // Serialize positions, balances and symbols
   string strPost = NotifyJSONData();
 
   // Send data with an http request to our python server
   char result[];
   char post[];
   string headers;
   StringToCharArray(strPost, post);
   int res = WebRequest("POST", "http://127.0.0.1:5000/meta-update", "", NULL, 30, post, StringLen(strPost), result,headers);
   if(res==-1) { 
      Print("Error in WebRequest. Error code =",GetLastError());
      return;
   } 

   // Parse response
   CJAVal jv;
   jv.Deserialize(result);

   for(int x = 0; x < jv.Size(); x++) {
      CJAVal cmd = jv[x];
      CJAVal r = OnCommand(cmd["action"].ToStr(), cmd["data"]);

      CJAVal cmdRes;
      cmdRes["id"] = cmd["id"];
      cmdRes["data"].Set(r);
      commands.Add(cmdRes);
   }

   if(commands.Size() > 0) {
      notifyData();
   }
}