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

int OnInit()
  {
   EventSetTimer(1);
   notifyData();
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Deinitialization function of the expert                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
  }
//+------------------------------------------------------------------+
//| "Tick" event handler function                                    |
//+------------------------------------------------------------------+
void OnTick()
  {

  }
//+------------------------------------------------------------------+
//| "Trade" event handler function                                   |
//+------------------------------------------------------------------+
void OnTrade()
  {
   notifyData();
  }
//+------------------------------------------------------------------+
//| "Timer" event handler function                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   notifyData();
  }
//+------------------------------------------------------------------+

int i = 0;
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
     position["id"]=PositionGetInteger(POSITION_IDENTIFIER);
     position["magic"]=PositionGetInteger(POSITION_MAGIC);
     position["symbol"]=PositionGetString(POSITION_SYMBOL);
     position["type"]=EnumToString(ENUM_POSITION_TYPE(PositionGetInteger(POSITION_TYPE)));
     position["time_setup"]=PositionGetInteger(POSITION_TIME);
     position["open"]=PositionGetDouble(POSITION_PRICE_OPEN);
     position["stoploss"]=PositionGetDouble(POSITION_SL);
     position["takeprofit"]=PositionGetDouble(POSITION_TP);
     position["volume"]=PositionGetDouble(POSITION_VOLUME);

     data["pos"].Add(position);
   }
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

string NotifyJSONData() {
   i++;
 
   CJAVal info;
   info["enabled"] = MQLInfoInteger(MQL_TRADE_ALLOWED) && TerminalInfoInteger(TERMINAL_TRADE_ALLOWED);
   //info["pos"] = PositionsJSON();
   PositionsJSON(info);
   BalancesJSON(info);
   // OrdersJSON(info);
   
   if(i > 10 || i == 1) {
     SymbolsJSON(info);
     i = 1;
   }
  
   return info.Serialize();
}

void Buy(CJAVal &pos) {
   //--- declare and initialize the trade request and result of trade request
   MqlTradeRequest request={0};
   MqlTradeResult  result={0};
   //--- parameters of request
   request.action   = TRADE_ACTION_DEAL;                     // type of trade operation
   request.symbol   = pos["symbol"].ToStr();                 // symbol
   request.volume   = pos["volume"].ToDbl();                 // volume
   request.type     = ORDER_TYPE_BUY;                        // order type
   request.price    = SymbolInfoDouble(request.symbol,SYMBOL_ASK); // price for opening
   request.deviation= 5;                                     // allowed deviation from the price
   request.magic    = EXPERT_MAGIC;                          // MagicNumber of the order

   if(pos.HasKey("comment"))
      request.comment = pos["comment"].ToStr();
   if(pos.HasKey("magic"))
      request.magic = pos["magic"].ToInt();
   
   //--- send the request
   if(!OrderSend(request,result))
      PrintFormat("OrderSend error %d",GetLastError());     // if unable to send the request, output the error code
   //--- information about the operation
   PrintFormat("retcode=%u  deal=%I64u  order=%I64u",result.retcode,result.deal,result.order);
}

void Short(CJAVal &pos) {
   //--- declare and initialize the trade request and result of trade request
   MqlTradeRequest request={0};
   MqlTradeResult  result={0};
   //--- parameters of request
   request.action   = TRADE_ACTION_DEAL;                     // type of trade operation
   request.symbol   = pos["symbol"].ToStr();                 // symbol
   request.volume   = pos["volume"].ToDbl();                 // volume
   request.type     = ORDER_TYPE_SELL;                       // order type
   request.price    = SymbolInfoDouble(request.symbol,SYMBOL_BID); // price for opening
   request.deviation= 5;                                     // allowed deviation from the price
   request.magic    = EXPERT_MAGIC;                          // MagicNumber of the order
   
   if(pos.HasKey("comment"))
      request.comment = pos["comment"].ToStr();
   if(pos.HasKey("magic"))
      request.magic = pos["magic"].ToInt();
   
   //--- send the request
   if(!OrderSend(request,result))
      PrintFormat("OrderSend error %d",GetLastError());     // if unable to send the request, output the error code
   //--- information about the operation
   PrintFormat("retcode=%u  deal=%I64u  order=%I64u",result.retcode,result.deal,result.order);
}

void Close(CJAVal &pos) {
   CTrade trade;
   trade.PositionClose(pos["id"].ToInt());
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
 
   // Execute buy orders from request response
   if(jv.HasKey("buy")) {
      CJAVal pos = jv["buy"];
      for(int x = 0; x < pos.Size(); x++) {
         Buy(pos[x]);
      }
   }

   // Execute short orders from request response
   if(jv.HasKey("short")) {
      CJAVal pos = jv["short"];
      for(int x = 0; x < pos.Size(); x++) {
         Short(pos[x]);
      }
   }

   // Execute positions closing from request response
   if(jv.HasKey("close")) {
      CJAVal pos = jv["close"];
      for(int x = 0; x < pos.Size(); x++) {
         Close(pos[x]);
      }
   }
}