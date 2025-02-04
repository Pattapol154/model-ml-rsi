//+------------------------------------------------------------------+
//|                                               ONNX.rsi_model.mq5  |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2024, MetaQuotes Ltd."
#property link        "https://www.mql5.com"
#property version     "1.00"

#include <Trade\Trade.mqh>

// ตั้งค่าการเทรด
input double InpLots       = 1.0;    // จำนวน Lots
input bool   InpUseStops   = true;   // ใช้ Stop Loss
input int    InpTakeProfit = 500;    // ระดับ TakeProfit
input int    InpStopLoss   = 500;    // ระดับ StopLoss

// โหลดโมเดล ONNX ที่ใช้ RSI ในการทำนาย
#resource "\\Files\\model.xauusd.H1.rsi.onnx" as uchar ExtModel[]

long     ExtHandle=INVALID_HANDLE;
int      ExtPredictedClass=-1;
CTrade   ExtTrade;

// การทำนายผลลัพธ์จาก RSI
#define BUY_SIGNAL  0
#define SELL_SIGNAL 1

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(_Symbol!="XAUUSD" || _Period!=PERIOD_H1)
     {
      Print("Model must work with XAUUSD, H1 timeframe");
      return(INIT_FAILED);
     }

   // สร้างโมเดลจากไฟล์ ONNX
   ExtHandle=OnnxCreateFromBuffer(ExtModel,ONNX_DEFAULT);
   if(ExtHandle==INVALID_HANDLE)
     {
      Print("OnnxCreateFromBuffer error ",GetLastError());
      return(INIT_FAILED);
     }

   // กำหนดรูปร่างของ input tensor
   const long input_shape[] = {1,1}; // Batch size = 1, feature = 1 (RSI)
   if(!OnnxSetInputShape(ExtHandle,ONNX_DEFAULT,input_shape))
     {
      Print("OnnxSetInputShape error ",GetLastError());
      return(INIT_FAILED);
     }

   // กำหนดรูปร่างของ output tensor
   const long output_shape[] = {1,1};
   if(!OnnxSetOutputShape(ExtHandle,0,output_shape))
     {
      Print("OnnxSetOutputShape error ",GetLastError());
      return(INIT_FAILED);
     }
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(ExtHandle!=INVALID_HANDLE)
     {
      OnnxRelease(ExtHandle);
      ExtHandle=INVALID_HANDLE;
     }
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
    // สร้าง array สำหรับเก็บค่า RSI
   double RSIArray[];
   
   // สร้าง handle ของ RSI indicator
   int RSIDef = iRSI(_Symbol, _Period, 14, PRICE_CLOSE);

   // ตรวจสอบว่า handle ของ indicator ถูกสร้างขึ้นหรือไม่
   if (RSIDef == INVALID_HANDLE)
     {
      Print("Failed to create RSI indicator handle");
      return;
     }

   // กำหนดให้ array เป็นแบบ series (บาร์ล่าสุดอยู่ index 0)
   ArraySetAsSeries(RSIArray, true);
   
   // คัดลอกค่าของ RSI จาก indicator มาลงใน array
   // ต้องการคัดลอก 3 บาร์ล่าสุด
   if (CopyBuffer(RSIDef, 0, 0, 3, RSIArray) <= 0)
     {
      Print("Failed to copy RSI values");
      return;
     }

   // แสดงค่า RSI 3 บาร์ล่าสุด
   Print("RSI ล่าสุด: ", RSIArray[0]);
   Print("RSI ที่ผ่านมา 1 บาร์: ", RSIArray[1]);
   Print("RSI ที่ผ่านมา 2 บาร์: ", RSIArray[2]);

   // ตรวจสอบเงื่อนไขในการเปิดสถานะการซื้อขาย
   // ตัวอย่าง: หาก RSI ล่าสุดสูงกว่า 70 -> ขาย, หาก RSI ต่ำกว่า 30 -> ซื้อ
   if (RSIArray[0] > 70) // ขายเมื่อ RSI อยู่ในโซน Overbought
     {
      Print("RSI Overbought, พิจารณาขาย");
      // เรียกฟังก์ชันเพื่อเปิดสถานะขาย
      OpenSellPosition();  // เรียกใช้ฟังก์ชันเปิดสถานะขาย
     }
   else if (RSIArray[0] < 30) // ซื้อเมื่อ RSI อยู่ในโซน Oversold
     {
      Print("RSI Oversold, พิจารณาซื้อ");
      // เรียกฟังก์ชันเพื่อเปิดสถานะซื้อ
      OpenBuyPosition();  // เรียกใช้ฟังก์ชันเปิดสถานะซื้อ
     }
 // อัปเดตสถานะการเปิด/ปิดของคำสั่งซื้อขายตามกลยุทธ์เพิ่มเติม
   // อาจรวมถึงการตรวจสอบ trailing stop, stop loss, และ take profit
  }
//+------------------------------------------------------------------+
//| ทำนายสัญญาณซื้อขายจาก RSI ด้วยโมเดล ONNX                         |
//+------------------------------------------------------------------+
void PredictTradeSignal(float rsi)
  {
   static vectorf output_data(1); // vector สำหรับเก็บผลลัพธ์
   static vectorf input_data(1);  // vector สำหรับ input RSI

   input_data[0] = rsi;

   // รันโมเดล ONNX
   if(!OnnxRun(ExtHandle,ONNX_NO_CONVERSION, input_data, output_data))
     {
      Print("OnnxRun failed");
      ExtPredictedClass=-1;
      return;
     }

   // รับผลลัพธ์ (0 = buy, 1 = sell)
   ExtPredictedClass = (int)output_data[0];
  }
//+------------------------------------------------------------------+
//| ตรวจสอบการเปิดสถานะ                                              |
//+------------------------------------------------------------------+
void CheckForOpen(void)
  {
   ENUM_ORDER_TYPE signal = WRONG_VALUE;

   // เช็คผลลัพธ์จากโมเดล
   if(ExtPredictedClass == SELL_SIGNAL)
      signal = ORDER_TYPE_SELL;
   else if(ExtPredictedClass == BUY_SIGNAL)
      signal = ORDER_TYPE_BUY;

   // เปิดสถานะหากมีสัญญาณ
   if(signal != WRONG_VALUE && TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      double price, sl=0, tp=0;
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      
      if(signal == ORDER_TYPE_SELL)
        {
         price = bid;
         if(InpUseStops)
           {
            sl = NormalizeDouble(bid + InpStopLoss*_Point, _Digits);
            tp = NormalizeDouble(bid - InpTakeProfit*_Point, _Digits);
           }
        }
      else if(signal == ORDER_TYPE_BUY)
        {
         price = ask;
         if(InpUseStops)
           {
            sl = NormalizeDouble(ask - InpStopLoss*_Point, _Digits);
            tp = NormalizeDouble(ask + InpTakeProfit*_Point, _Digits);
           }
        }
      ExtTrade.PositionOpen(_Symbol, signal, InpLots, price, sl, tp);
     }
  }
//+------------------------------------------------------------------+
//| ตรวจสอบการปิดสถานะ                                              |
//+------------------------------------------------------------------+
void CheckForClose(void)
  {
   bool closeSignal = false;
   long type = PositionGetInteger(POSITION_TYPE);

   // ปิดสถานะหากมีสัญญาณตรงกันข้าม
   if(type == POSITION_TYPE_BUY && ExtPredictedClass == SELL_SIGNAL)
      closeSignal = true;
   if(type == POSITION_TYPE_SELL && ExtPredictedClass == BUY_SIGNAL)
      closeSignal = true;

   if(closeSignal && TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      ExtTrade.PositionClose(_Symbol);
     }
  }
 
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| ฟังก์ชันเปิดสถานะการซื้อ                                         |
//+------------------------------------------------------------------+
void OpenBuyPosition()
  {
   // ตรวจสอบว่าอนุญาตให้ทำการซื้อขายได้หรือไม่
   if (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      Print("การซื้อขายไม่อนุญาตในขณะนี้");
      return;
     }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = NormalizeDouble(ask - 50 * _Point, _Digits); // Stop Loss 50 pips ต่ำกว่าราคา
   double tp = NormalizeDouble(ask + 100 * _Point, _Digits); // Take Profit 100 pips สูงกว่าราคา

   // ส่งคำสั่งซื้อ (Buy)
   CTrade trade;
   trade.Buy(0.1, _Symbol, ask, sl, tp);  // Buy 0.1 Lots
  }
//+------------------------------------------------------------------+
//| ฟังก์ชันเปิดสถานะการขาย                                          |
//+------------------------------------------------------------------+
void OpenSellPosition()
  {
   // ตรวจสอบว่าอนุญาตให้ทำการซื้อขายได้หรือไม่
   if (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      Print("การซื้อขายไม่อนุญาตในขณะนี้");
      return;
     }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = NormalizeDouble(bid + 50 * _Point, _Digits); // Stop Loss 50 pips สูงกว่าราคา
   double tp = NormalizeDouble(bid - 100 * _Point, _Digits); // Take Profit 100 pips ต่ำกว่าราคา

   // ส่งคำสั่งขาย (Sell)
   CTrade trade;
   trade.Sell(0.1, _Symbol, bid, sl, tp);  // Sell 0.1 Lots
  }
//+------------------------------------------------------------------+