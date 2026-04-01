#property strict
#include <Trade/Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh> 
CTrade trade;
CPositionInfo  m_position;
CSymbolInfo    m_symbol;

input double StartLot      = 0.01;  // Start Lot
input double Multiplier    = 1.5;   // Lot Multiplier
input int    DistancePips  = 1000;  // Distance
input double SL_points     = 6000;   // SL Level 1
input double TP_points     = 6000;  // TP Level 1
input double SL_points1    = 6000;  // SL Level 2
input double TP_points1    = 3000;  // TP Level 2
input double lot2          = 57;    // Lot Level 1
input double lot3          = 200;   // Lot Level 2 (split threshold)
input bool   close         = true;  // Close Order  
input bool   closeinmax    = false; // Close Pending Order in Lot Level 2 
input ulong  InpMagic      = 77777; // Magic Number

ulong  buyStops[];
ulong  sellStops[];

double buyPrice  = 0;
double sellPrice = 0;
double buySL;
double sellSL;
double buyTP;
double sellTP;

//-------------------------
// Panel Settings
//-------------------------
string FontName       = "Arial";
int    PANEL_PADDING  = 8;
int    HEADER_HEIGHT  = 20;
int    HeaderFontSize = 11;
bool   HeaderBold     = true;
color  TextColor      = clrWhite;

bool   ShowBackground        = false;
bool   ShowBorder            = true;
color  BackgroundColor       = clrBlack;
color  HeaderBackgroundColor = clrBlue;
color  BorderColor           = clrWhite;
int    BorderWidth           = 2;
color  separatorColor        = clrDarkGray;
string currencySymbol        = "$";

double   stopLevel;
double   stopLevel1;
double   takeLevel;
double   takeLevel1;
datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
int      lastBar;
double   currentLot;
bool     open           = false;
bool     tradingAllowed = true;
bool     waitForNewTick = false;
int      lastCloseTime  = 0;
int      currentTime    = 0;



//+------------------------------------------------------------------+
int OnInit()
{
    ArrayResize(buyStops,  0);
    ArrayResize(sellStops, 0);

    int x = 10, y = 10, width = 230, height = 180;

    CreatePanel("StatsPanel", x, y, width, height);
    CreateHeader("StatsPanel", "Siam Trading Hedge", x, y, width);

    int offsetY = y + HEADER_HEIGHT + 5;

    LabelCreate("lblTotalTrades", x + 10, offsetY + 20,  "", TextColor, 11);
    LabelCreate("lblBuyProfit",   x + 10, offsetY + 45,  "", TextColor, 11);
    LabelCreate("lblSellProfit",  x + 10, offsetY + 65,  "", TextColor, 11);
    LabelCreate("lblTotalProfit", x + 10, offsetY + 85,  "", TextColor, 11);
    LabelCreate("lblAverage",     x + 10, offsetY + 105, "", TextColor, 11);
    LabelCreate("lblBalance",     x + 10, offsetY + 125, "", TextColor, 11);
    LabelCreate("lblEquity",      x + 10, offsetY + 145, "", TextColor, 11);

    ObjectSetString(0, "lblTotalTrades", OBJPROP_TEXT, "Total Trades    " + IntegerToString(0));
    ObjectSetString(0, "lblBuyProfit",   OBJPROP_TEXT, "Buy Profit    "   + DoubleToString(0, 2));
    ObjectSetString(0, "lblSellProfit",  OBJPROP_TEXT, "Sell Profit  "    + DoubleToString(0, 2));
    ObjectSetString(0, "lblTotalProfit", OBJPROP_TEXT, "Total Profit  "   + DoubleToString(0, 2));
    ObjectSetString(0, "lblAverage",     OBJPROP_TEXT, "Average  "        + DoubleToString(0, 2));
    ObjectSetString(0, "lblBalance",     OBJPROP_TEXT, "Balance  "        + DoubleToString(0, 2));
    ObjectSetString(0, "lblEquity",      OBJPROP_TEXT, "Equity  "         + DoubleToString(0, 2));

    int buttonsY = y + height + 10;
    CreateButton("btn_close_all",   "Close All",       x + 130, buttonsY + 5,  clrRed,   clrWhite);
    CreateButton("btn_del_stops",   "Delete Stops",    x + 130, buttonsY + 35, clrGreen, clrWhite);
    CreateButton("btn_disable_trd", "Disable Trading", x + 130, buttonsY + 65, clrBlue,  clrWhite);

    RefreshStopLevels();

    int minStop = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    Print("📊 OnInit STOPS_LEVEL=", minStop,
          " | SL_points=", SL_points,
          " | TP_points=", TP_points,
          " | stopLevel=", stopLevel,
          " | takeLevel=", takeLevel);

    if(SL_points <= minStop || TP_points <= minStop)
        Alert("⚠️ SL/TP أصغر من الحد الأدنى للبروكر! STOPS_LEVEL=", minStop,
              " | يجب أن تكون SL_points و TP_points أكبر من ", minStop);

    trade.SetExpertMagicNumber(InpMagic);
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    currentLot = StartLot;

    RecoverStateOnRestart();

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void RefreshStopLevels()
{
    int minStop = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

    stopLevel  = SL_points  > minStop ? SL_points  : minStop + 1;
    stopLevel1 = SL_points1 > minStop ? SL_points1 : minStop + 1;
    takeLevel  = TP_points  > minStop ? TP_points  : minStop + 1;
    takeLevel1 = TP_points1 > minStop ? TP_points1 : minStop + 1;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    int total = ObjectsTotal(0);
    for(int i = total - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i);
        if(StringFind(name, "StatsPanel") == 0 || StringFind(name, "lbl") == 0)
            ObjectDelete(0, name);
    }
    ObjectDelete(0, "btn_close_all");
    ObjectDelete(0, "btn_del_stops");
    ObjectDelete(0, "btn_disable_trd");
}

//+------------------------------------------------------------------+
void OnTick()
{
    if(PositionsTotal() == 0 && OrdersTotal() == 1) DeleteAllPendingOrders();

    FastTradeLogic();

    if(IsNewBar()) UpdatePanel();
}

//+------------------------------------------------------------------+
// ✅ دالة مساعدة: جمع لوتات آخر دورة من التاريخ (نفس اتجاه آخر صفقة مغلقة)
double GetTotalLotFromLastCycle()
{
    if(!HistorySelect(0, TimeCurrent())) return StartLot;
    int total = HistoryDealsTotal();
    if(total == 0) return StartLot;

    // ── خطوة 1: حدد وقت إغلاق آخر صفقة ────────────────────────────
    datetime lastCloseTime = 0;
    for(int i = total - 1; i >= 0; i--)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(HistoryDealGetString(ticket,  DEAL_SYMBOL) != _Symbol)        continue;
        if(HistoryDealGetInteger(ticket, DEAL_MAGIC)  != InpMagic)       continue;
        if(HistoryDealGetInteger(ticket, DEAL_ENTRY)  != DEAL_ENTRY_OUT) continue;

        lastCloseTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
        break;
    }
    if(lastCloseTime == 0) return StartLot;

    // ── خطوة 2: جمع BUY و SELL بشكل منفصل لكل الصفقات في نفس الـ "جلسة"
    // نعتبر الدورة الواحدة: كل الصفقات المغلقة بين بداية الدورة وآخر إغلاق
    // نجمع الكل ونرجع الأكبر بين BUY total و SELL total
    double buyTotal  = 0;
    double sellTotal = 0;

    // نمشي للخلف ونجمع كل صفقات نفس الـ magic حتى نجد فجوة زمنية كبيرة
    // أو حتى نجد صفقة TP (بداية دورة سابقة)
    datetime prevTime   = lastCloseTime;
    bool     firstDeal  = true;

    for(int i = total - 1; i >= 0; i--)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(HistoryDealGetString(ticket,  DEAL_SYMBOL) != _Symbol)        continue;
        if(HistoryDealGetInteger(ticket, DEAL_MAGIC)  != InpMagic)       continue;
        if(HistoryDealGetInteger(ticket, DEAL_ENTRY)  != DEAL_ENTRY_OUT) continue;

        datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
        long     dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);
        double   dealLot  = HistoryDealGetDouble(ticket, DEAL_VOLUME);

        // إذا وجدنا صفقة أُغلقت بـ TP قبل الدورة الحالية → توقف
        // (الصفقة الأولى التي نجدها بـ TP تعني بداية دورة سابقة)
        if(!firstDeal)
        {
            ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(ticket, DEAL_REASON);
            if(reason == DEAL_REASON_TP) break;
        }
        firstDeal = false;

        if(dealType == DEAL_TYPE_BUY)  buyTotal  += dealLot;
        if(dealType == DEAL_TYPE_SELL) sellTotal += dealLot;
    }

    double step     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double maxTotal = MathMax(buyTotal, sellTotal);
    maxTotal        = MathFloor(maxTotal / step) * step;

    Print("📊 GetTotalLotFromLastCycle: buyTotal=", buyTotal,
          " sellTotal=", sellTotal,
          " → maxTotal=", maxTotal);

    return maxTotal > 0 ? maxTotal : StartLot;
}

//+------------------------------------------------------------------+
void RecoverStateOnRestart()
{
    ArrayResize(buyStops,  0);
    ArrayResize(sellStops, 0);

    // ✅ حالة 1: لا صفقات ولا أوردرات
    if(PositionsTotal() == 0 && OrdersTotal() == 0)
    {
        // آخر صفقة أُغلقت بـ TP → دورة جديدة طبيعية
        if(LastTradeClosedByTP())
        {
            currentLot = StartLot;
            lastBar    = 0;
            buyPrice   = 0;
            sellPrice  = 0;
            Print("♻️ Recover: آخر صفقة TP → دورة جديدة بـ StartLot=", StartLot);
        }
        // آخر صفقة أُغلقت بـ SL → FastTradeLogic سيتكفل بفتح الدورة التالية باللوت المضاعف
        else if(LastTradeClosedBySL())
        {
            currentLot = StartLot; // مؤقت، سيُحسب في FastTradeLogic
            lastBar    = 0;
            buyPrice   = 0;
            sellPrice  = 0;
            Print("⚠️ Recover: آخر صفقة SL → FastTradeLogic سيفتح الدورة التالية");
        }
        else
        {
            // لا تاريخ أصلاً → دورة جديدة
            currentLot = StartLot;
            lastBar    = 0;
            buyPrice   = 0;
            sellPrice  = 0;
            Print("♻️ Recover: لا تاريخ → دورة جديدة");
        }
        return;
    }

    // ✅ حالة 2: توجد صفقات مفتوحة أو أوردرات → استرجاع الحالة كما كانت

    // استرجاع الأوردرات المعلقة
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(!OrderSelect(ticket)) continue;
        if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if(OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;

        ENUM_ORDER_TYPE otype = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
        if(otype == ORDER_TYPE_BUY_STOP)
        {
            buyPrice = OrderGetDouble(ORDER_PRICE_OPEN);
            buySL    = OrderGetDouble(ORDER_SL);
            buyTP    = OrderGetDouble(ORDER_TP);
            int sz = ArraySize(buyStops);
            ArrayResize(buyStops, sz + 1);
            buyStops[sz] = ticket;
        }
        else if(otype == ORDER_TYPE_SELL_STOP)
        {
            sellPrice = OrderGetDouble(ORDER_PRICE_OPEN);
            sellSL    = OrderGetDouble(ORDER_SL);
            sellTP    = OrderGetDouble(ORDER_TP);
            int sz = ArraySize(sellStops);
            ArrayResize(sellStops, sz + 1);
            sellStops[sz] = ticket;
        }
    }

    // استرجاع الصفقات المفتوحة
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

        double posPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        if(buyPrice  == 0) buyPrice  = posPrice;
        if(sellPrice == 0) sellPrice = posPrice;

        buySL  = PositionGetDouble(POSITION_SL);
        sellSL = PositionGetDouble(POSITION_SL);
        buyTP  = PositionGetDouble(POSITION_TP);
        sellTP = PositionGetDouble(POSITION_TP);
    }

    // استرجاع currentLot
    double totalBuyLot  = GetTotalLotByType(POSITION_TYPE_BUY);
    double totalSellLot = GetTotalLotByType(POSITION_TYPE_SELL);
    double maxOpenLot   = MathMax(totalBuyLot, totalSellLot);

    if(maxOpenLot > 0)
        currentLot = NormalizeDouble(maxOpenLot * Multiplier, 2);
    else
        currentLot = StartLot;

    // استرجاع lastBar
    int posType = GetLastOpenTypeBySymbol();
    if(posType == POSITION_TYPE_BUY)  lastBar = 1;
    if(posType == POSITION_TYPE_SELL) lastBar = 2;

    Print("✅ RecoverStateOnRestart:",
          " buyPrice=",   buyPrice,
          " sellPrice=",  sellPrice,
          " currentLot=", currentLot,
          " lastBar=",    lastBar,
          " buyStops=",   ArraySize(buyStops),
          " sellStops=",  ArraySize(sellStops));
}

//+------------------------------------------------------------------+
double ValidateAndFixSL(ENUM_POSITION_TYPE posType, double sl, double bPrice, double sPrice)
{
    double fixedSL = sl;

    if(posType == POSITION_TYPE_BUY)
    {
        if(sPrice > 0 && sl >= sPrice)
        {
            fixedSL = NormalizeDouble(sPrice - stopLevel * _Point, _Digits);
            Print("⚠️ ValidateAndFixSL BUY: SL=", sl, " >= sellPrice=", sPrice,
                  " → Fixed SL=", fixedSL);
        }
    }
    else if(posType == POSITION_TYPE_SELL)
    {
        if(bPrice > 0 && sl <= bPrice)
        {
            fixedSL = NormalizeDouble(bPrice + stopLevel * _Point, _Digits);
            Print("⚠️ ValidateAndFixSL SELL: SL=", sl, " <= buyPrice=", bPrice,
                  " → Fixed SL=", fixedSL);
        }
    }

    return fixedSL;
}

//+------------------------------------------------------------------+
void PlaceFirstOrders()
{
    MqlTick tick;
    if(!SymbolInfoTick(_Symbol, tick)) return;

    RefreshStopLevels();

    buyPrice  = NormalizeDouble(tick.ask + DistancePips * _Point, _Digits);
    sellPrice = NormalizeDouble(tick.bid - DistancePips * _Point, _Digits);

    buySL  = NormalizeDouble(sellPrice - stopLevel * _Point, _Digits);
    sellSL = NormalizeDouble(buyPrice  + stopLevel * _Point, _Digits);
    buyTP  = NormalizeDouble(buyPrice  + takeLevel * _Point, _Digits);
    sellTP = NormalizeDouble(sellPrice - takeLevel * _Point, _Digits);

    buySL  = ValidateAndFixSL(POSITION_TYPE_BUY,  buySL,  buyPrice, sellPrice);
    sellSL = ValidateAndFixSL(POSITION_TYPE_SELL, sellSL, buyPrice, sellPrice);

    int minStop = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

    if(MathAbs(buyPrice - buySL)   / _Point < minStop)
        buySL  = NormalizeDouble(buyPrice  - (minStop + 10) * _Point, _Digits);
    if(MathAbs(buyTP    - buyPrice) / _Point < minStop)
        buyTP  = NormalizeDouble(buyPrice  + (minStop + 10) * _Point, _Digits);
    if(MathAbs(sellPrice - sellSL)  / _Point < minStop)
        sellSL = NormalizeDouble(sellPrice + (minStop + 10) * _Point, _Digits);
    if(MathAbs(sellTP - sellPrice)  / _Point < minStop)
        sellTP = NormalizeDouble(sellPrice - (minStop + 10) * _Point, _Digits);

    Print("📌 PlaceFirstOrders: buyPrice=", buyPrice, " buySL=", buySL, " buyTP=", buyTP,
          " | sellPrice=", sellPrice, " sellSL=", sellSL, " sellTP=", sellTP,
          " | minStop=", minStop, " stopLevel=", stopLevel);

    datetime Expiration = TimeCurrent() + 600000;

    bool placeBuy  = (LastTradeClosedByTPWithMaxLot() && GetLastOpenTypeBySymbol() == POSITION_TYPE_SELL) || (lastBar == 0);
    bool placeSell = (LastTradeClosedByTPWithMaxLot() && GetLastOpenTypeBySymbol() == POSITION_TYPE_BUY)  || (lastBar == 0);

    if(placeBuy)
    {
        if(trade.BuyStop(currentLot, buyPrice, _Symbol, buySL, buyTP, ORDER_TIME_DAY, Expiration))
        {
            int sz = ArraySize(buyStops);
            ArrayResize(buyStops, sz + 1);
            buyStops[sz] = trade.ResultOrder();
            Print("✅ PlaceFirstOrders: BuyStop placed ticket=", buyStops[sz]);
        }
        else
            Print("❌ PlaceFirstOrders: BuyStop FAILED error=", GetLastError(),
                  " buyPrice=", buyPrice, " buySL=", buySL, " buyTP=", buyTP);
    }

    if(placeSell)
    {
        if(trade.SellStop(currentLot, sellPrice, _Symbol, sellSL, sellTP, ORDER_TIME_DAY, Expiration))
        {
            int sz = ArraySize(sellStops);
            ArrayResize(sellStops, sz + 1);
            sellStops[sz] = trade.ResultOrder();
            Print("✅ PlaceFirstOrders: SellStop placed ticket=", sellStops[sz]);
        }
        else
            Print("❌ PlaceFirstOrders: SellStop FAILED error=", GetLastError(),
                  " sellPrice=", sellPrice, " sellSL=", sellSL, " sellTP=", sellTP);
    }
}

//+------------------------------------------------------------------+
void DeleteStopsByArray(ulong &tickets[])
{
    for(int i = ArraySize(tickets) - 1; i >= 0; i--)
    {
        if(tickets[i] != 0 && OrderExists(tickets[i]))
        {
            trade.OrderDelete(tickets[i]);
            Print("🗑️ Deleted order ticket=", tickets[i]);
        }
    }
    ArrayResize(tickets, 0);
}

//+------------------------------------------------------------------+
double GetTotalLotByType(ENUM_POSITION_TYPE posType)
{
    struct PosInfo 
    { 
        datetime time; 
        double   lot; 
        ENUM_POSITION_TYPE type; 
    };
    
    PosInfo arr[];
    int count = 0;

    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

        ArrayResize(arr, count + 1);
        arr[count].time = (datetime)PositionGetInteger(POSITION_TIME);
        arr[count].lot  = PositionGetDouble(POSITION_VOLUME);
        arr[count].type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        count++;
    }

    if(count == 0) return 0;

    for(int i = 0; i < count - 1; i++)
    {
        int maxIdx = i;
        for(int j = i + 1; j < count; j++)
            if(arr[j].time > arr[maxIdx].time) maxIdx = j;
        if(maxIdx != i)
        {
            PosInfo tmp  = arr[i];
            arr[i]       = arr[maxIdx];
            arr[maxIdx]  = tmp;
        }
    }

    double totalLot = 0;
    for(int i = 0; i < count; i++)
    {
        if(arr[i].type != posType) break;
        totalLot += arr[i].lot;
    }

    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    totalLot = MathFloor(totalLot / step) * step;

    return totalLot;
}

//+------------------------------------------------------------------+
bool CreateNextOrder(bool createBuy)
{
    RefreshStopLevels();

    ENUM_POSITION_TYPE targetType = createBuy ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
    double totalLot = GetTotalLotByType(targetType);
    //Comment(totalLot);
    if(totalLot <= 0) totalLot = GetLastOpenLotBySymbol();
    double lotb    = GetMaxLot(_Symbol, ORDER_TYPE_BUY);
    double lots    = GetMaxLot(_Symbol, ORDER_TYPE_SELL);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

    currentLot =    NormalizeDouble(totalLot * Multiplier, _Digits);
    currentLot = currentLot < 0.02
                ? MathCeil(currentLot / lotStep)  * lotStep
                : MathRound(currentLot / lotStep) * lotStep;
    Print("📊 CreateNextOrder: totalLot=", totalLot,
          " Multiplier=", Multiplier,
          " currentLot=", currentLot,
          " createBuy=", createBuy);



    if(createBuy && lotb <= 0)
    {
        Print("❌ CreateNextOrder(Buy): Not enough margin! lotb=", lotb);
        return false;
    }
    if(!createBuy && lots <= 0)
    {
        Print("❌ CreateNextOrder(Sell): Not enough margin! lots=", lots);
        return false;
    }

    if(buyPrice == 0 || sellPrice == 0)
    {
        Print("❌ CreateNextOrder: buyPrice=", buyPrice, " sellPrice=", sellPrice, " → RecoverStateOnRestart()");
        RecoverStateOnRestart();
        if(buyPrice == 0 || sellPrice == 0)
        {
            Print("❌ CreateNextOrder: Prices still invalid after recovery, aborting.");
            return false;
        }
    }

    int minStop = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

    if(createBuy)
    {
        if(MathAbs(buyPrice - buySL) / _Point < minStop)
            buySL = NormalizeDouble(buyPrice - (minStop + 10) * _Point, _Digits);
        if(MathAbs(buyTP - buyPrice) / _Point < minStop)
            buyTP = NormalizeDouble(buyPrice + (minStop + 10) * _Point, _Digits);
    }
    else
    {
        if(MathAbs(sellSL - sellPrice) / _Point < minStop)
            sellSL = NormalizeDouble(sellPrice + (minStop + 10) * _Point, _Digits);
        if(MathAbs(sellPrice - sellTP) / _Point < minStop)
            sellTP = NormalizeDouble(sellPrice - (minStop + 10) * _Point, _Digits);
    }

    double splitMax  = maxLot;
    double brokerMax = createBuy ? lotb : lots;
    double chunkMax  ;

    double remaining = currentLot;
    int    partCount = 0;
    double parts[];

if(currentLot <= maxLot)
{
    // لوت واحد مباشرة، بدون تقسيم
    ArrayResize(parts, 1);
    parts[0] = NormalizeDouble(MathFloor(currentLot / lotStep) * lotStep, 2);
    if(parts[0] < minLot) parts[0] = minLot;
    
    partCount = 1;
    remaining = 0;
}
else
{
     chunkMax = MathMin(maxLot, brokerMax);
    while(remaining >= minLot)
    {
        double chunk = MathMin(remaining, chunkMax);
        chunk = MathFloor(chunk / lotStep) * lotStep;
        chunk = NormalizeDouble(chunk, 2);
        if(chunk < minLot) break;

        ArrayResize(parts, partCount + 1);
        parts[partCount] = chunk;
        partCount++;
        remaining = NormalizeDouble(remaining - chunk, 2);

        if(partCount >= 50) break;
    }
}

    Print("📌 CreateNextOrder: createBuy=", createBuy,
          " targetLot=", currentLot,
          " chunkMax=", chunkMax,
          " parts=", partCount);

    datetime Expiration = TimeCurrent() + 600000;

    if(createBuy)
    {
        ArrayResize(buyStops, 0);
        for(int p = 0; p < partCount; p++)
        {
            bool ok = trade.BuyStop(parts[p], buyPrice, _Symbol, buySL, buyTP,
                                    ORDER_TIME_DAY, Expiration);
            if(ok)
            {
                int sz = ArraySize(buyStops);
                ArrayResize(buyStops, sz + 1);
                buyStops[sz] = trade.ResultOrder();
                Print("✅ BuyStop#", p + 1, " lot=", parts[p], " ticket=", buyStops[sz]);
            }
            else
            {
                Print("❌ BuyStop#", p + 1, " FAILED lot=", parts[p], " error=", GetLastError());
                if(p == 0) return false;
            }
        }
        return true;
    }
    else
    {
        ArrayResize(sellStops, 0);
        for(int p = 0; p < partCount; p++)
        {
            bool ok = trade.SellStop(parts[p], sellPrice, _Symbol, sellSL, sellTP,
                                     ORDER_TIME_DAY, Expiration);
            if(ok)
            {
                int sz = ArraySize(sellStops);
                ArrayResize(sellStops, sz + 1);
                sellStops[sz] = trade.ResultOrder();
                Print("✅ SellStop#", p + 1, " lot=", parts[p], " ticket=", sellStops[sz]);
            }
            else
            {
                Print("❌ SellStop#", p + 1, " FAILED lot=", parts[p], " error=", GetLastError());
                if(p == 0) return false;
            }
        }
        return true;
    }
}

//+------------------------------------------------------------------+
void CheckAndFixOpenPositionsSL()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket))                 continue;
        if(PositionGetString(POSITION_SYMBOL)  != _Symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC)  != InpMagic)continue;

        double currentSL  = PositionGetDouble(POSITION_SL);
        double currentTP  = PositionGetDouble(POSITION_TP);
        double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double newSL      = currentSL;
        bool   needFix    = false;

        if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
            if(sellPrice > 0 && currentSL >= sellPrice)
            {
                newSL   = NormalizeDouble(entryPrice - stopLevel * _Point, _Digits);
                if(newSL >= sellPrice)
                    newSL = NormalizeDouble(sellPrice - stopLevel * _Point, _Digits);
                needFix = true;
                Print("⚠️ CheckSL BUY ticket=", ticket,
                      " entryPrice=", entryPrice,
                      " SL=", currentSL, " >= sellPrice=", sellPrice,
                      " → newSL=", newSL);
            }
        }
        else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
        {
            if(buyPrice > 0 && currentSL <= buyPrice)
            {
                newSL   = NormalizeDouble(entryPrice + stopLevel * _Point, _Digits);
                if(newSL <= buyPrice)
                    newSL = NormalizeDouble(buyPrice + stopLevel * _Point, _Digits);
                needFix = true;
                Print("⚠️ CheckSL SELL ticket=", ticket,
                      " entryPrice=", entryPrice,
                      " SL=", currentSL, " <= buyPrice=", buyPrice,
                      " → newSL=", newSL);
            }
        }

        if(needFix && newSL > 0)
        {
            if(trade.PositionModify(ticket, newSL, currentTP))
                Print("✅ CheckSL Fixed ticket=", ticket, " newSL=", newSL);
            else
                Print("❌ CheckSL Failed ticket=", ticket, " error=", GetLastError());
        }
    }
}

//+------------------------------------------------------------------+
void EnsureOppositeOrderExists()
{
    int posType = GetLastOpenTypeBySymbol();
    if(posType == -1) return;

    if(buyPrice == 0 || sellPrice == 0)
    {
        RecoverStateOnRestart();
        if(buyPrice == 0 || sellPrice == 0) return;
    }

    bool buyStopExists  = (ArraySize(buyStops)  > 0);
    bool sellStopExists = (ArraySize(sellStops) > 0);

    if(buyStopExists)
    {
        buyStopExists = false;
        for(int k = 0; k < ArraySize(buyStops); k++)
            if(OrderExists(buyStops[k])) { buyStopExists = true; break; }
    }
    if(sellStopExists)
    {
        sellStopExists = false;
        for(int k = 0; k < ArraySize(sellStops); k++)
            if(OrderExists(sellStops[k])) { sellStopExists = true; break; }
    }

    if(posType == POSITION_TYPE_BUY && !sellStopExists)
    {
        Print("⚠️ EnsureOpposite: BUY open but no SellStop found → creating...");
        if(CreateNextOrder(false))
        {
            lastBar = 1;
            Print("✅ EnsureOpposite: SellStop created");
        }
        else
            Print("❌ EnsureOpposite: SellStop creation FAILED");
    }

    if(posType == POSITION_TYPE_SELL && !buyStopExists)
    {
        Print("⚠️ EnsureOpposite: SELL open but no BuyStop found → creating...");
        if(CreateNextOrder(true))
        {
            lastBar = 2;
            Print("✅ EnsureOpposite: BuyStop created");
        }
        else
            Print("❌ EnsureOpposite: BuyStop creation FAILED");
    }
}

//+------------------------------------------------------------------+
void CloseAllByType(ENUM_POSITION_TYPE typeToClose, ENUM_ORDER_TYPE typeToClose1)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
        if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == typeToClose)
        {
            trade.PositionClose(ticket);
            Print("🔴 CloseAllByType: closed ", (typeToClose == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                  " ticket=", ticket);
        }
    }
    
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket1 = OrderGetTicket(i);
        if(!OrderSelect(ticket1)) continue;
        if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if(OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
        if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) == typeToClose1)
        {
            trade.OrderDelete(ticket1);
            Print("🔴 CloseAllByType: deleted order ticket=", ticket1);
        }
    }
}

//+------------------------------------------------------------------+
bool LastTradeClosedByTP()
{
    if(!HistorySelect(0, TimeCurrent())) return false;
    int total = HistoryDealsTotal();
    for(int i = total - 1; i >= 0; i--)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(HistoryDealGetString(ticket,  DEAL_SYMBOL) != _Symbol)        continue;
        if(HistoryDealGetInteger(ticket, DEAL_MAGIC)  != InpMagic)       continue;
        if(HistoryDealGetInteger(ticket, DEAL_ENTRY)  != DEAL_ENTRY_OUT) continue;

        ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(ticket, DEAL_REASON);
        return (reason == DEAL_REASON_TP);
    }
    return false;
}

//+------------------------------------------------------------------+
void CheckOrphanPositionsAfterTP()
{
    if(PositionsTotal() != 0) return;

    int buyStopCount  = 0;
    int sellStopCount = 0;

    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(!OrderSelect(ticket)) continue;
        if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
        if(OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;

        ENUM_ORDER_TYPE otype = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
        if(otype == ORDER_TYPE_BUY_STOP)  buyStopCount++;
        if(otype == ORDER_TYPE_SELL_STOP) sellStopCount++;
    }

    bool orphanBuy  = (buyStopCount  > 1 && sellStopCount == 0);
    bool orphanSell = (sellStopCount > 1 && buyStopCount  == 0);

    if(!orphanBuy && !orphanSell) return;

    string side = orphanBuy ? "BUY" : "SELL";
    Print("🔁 CheckOrphanPositions: أوردرات يتيمة (", side, ") عدد=",
          orphanBuy ? buyStopCount : sellStopCount, " → حذف وبدء دورة جديدة");

    DeleteAllPendingOrders();

    buySL      = 0; sellSL     = 0;
    buyTP      = 0; sellTP     = 0;
    lastBar    = 0;
    currentLot = StartLot;
    waitForNewTick = false;

    Print("✅ CheckOrphanPositions: تم الحذف، دورة جديدة في التيك القادم");
}

//+------------------------------------------------------------------+
void FastTradeLogic()
{
    int    count_buy  = 0;
    int    count_sell = 0;
    double maxLot     = 0.0;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(!m_position.SelectByIndex(i)) continue;
        if(m_position.Symbol() == _Symbol && m_position.Magic() == InpMagic)
        {
            if(m_position.PositionType() == POSITION_TYPE_BUY)  count_buy++;
            else                                                 count_sell++;

            double lot = m_position.Volume();
            if(lot > maxLot) maxLot = lot;
        }
    }
    CheckOrphanPositionsAfterTP();
    if(GetLastOpenLotBySymbol() == lot2) ModifyAllOrders();
    if(GetLastOpenLotBySymbol() == lot3) ModifyAllOrders2(lastBar);

    if(PositionsTotal() > 0) CheckAndFixOpenPositionsSL();
    if(PositionsTotal() > 0) EnsureOppositeOrderExists();

    // لا صفقات ولا أوردرات: ابدأ من جديد
    if(PositionsTotal() == 0 && OrdersTotal() == 0)
    {
        currentTime = currentTime + 1;
        if(!waitForNewTick)
        {
            waitForNewTick = true;
            lastCloseTime  = currentTime;
            Print("⏳ Waiting for new tick before opening new cycle...");
            return;
        }

        if(currentTime == lastCloseTime)
            return;

        waitForNewTick = false;

        // ✅ إذا آخر صفقة SL → افتح باللوت التالي (مضاعف)
        if(LastTradeClosedBySL())
        {
            double lastLot = GetTotalLotFromLastCycle();
            currentLot     = NormalizeDouble(lastLot * Multiplier, 2);
            Print("⚠️ Last SL → opening next cycle with lot=", currentLot);
        }
        else
        {
            currentLot = StartLot;
        }

        open    = true;
        PlaceFirstOrders();
        lastBar = 0;
        return;
    }
    else
    {
        waitForNewTick = false;
    }

    // BUY تفعّلت
    if(PositionsTotal() > 0 &&
       GetLastOpenTypeBySymbol() == POSITION_TYPE_BUY &&
       (lastBar != 1 || OrdersTotal() == 0))
    {
        DeleteStopsByArray(sellStops);
        if(CreateNextOrder(false))
        {
            lastBar = 1;
            Print("✅ FastTradeLogic: lastBar=1 | SellStop created after BUY activated");
        }
        else
            Print("❌ FastTradeLogic: SellStop creation FAILED after BUY activated, will retry next tick");
    }

    // SELL تفعّلت
    if(PositionsTotal() > 0 &&
       GetLastOpenTypeBySymbol() == POSITION_TYPE_SELL &&
       (lastBar != 2 || OrdersTotal() == 0))
    {
        DeleteStopsByArray(buyStops);
        if(CreateNextOrder(true))
        {
            lastBar = 2;
            Print("✅ FastTradeLogic: lastBar=2 | BuyStop created after SELL activated");
        }
        else
            Print("❌ FastTradeLogic: BuyStop creation FAILED after SELL activated, will retry next tick");
    }

    // TP hit → أغلق كل شيء وابدأ دورة جديدة
    if(LastTradeClosedByTP() && PositionsTotal() == 0 && OrdersTotal() == 0)
    {
        Print("🎯 TP hit detected → Reset and start new cycle");
        currentLot = StartLot;
        lastBar    = 0;
        buyPrice   = 0;
        sellPrice  = 0;
        ArrayResize(buyStops,  0);
        ArrayResize(sellStops, 0);
        waitForNewTick = true;
        lastCloseTime  = currentTime;
        return;
    }

    if(PositionsTotal() > 0 || (PositionsTotal() == 0 && OrdersTotal() == 1 && LastTradeClosedBySL()))
    {
        if(maxLot > 0 && close) CloseSmallerLots(maxLot);
    }
}

//+------------------------------------------------------------------+
int CountPendings()
{
    int pending = 0;
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if(!OrderSelect(i)) continue;
        if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
           OrderGetInteger(ORDER_MAGIC) == InpMagic)
            pending++;
    }
    return pending;
}

//+------------------------------------------------------------------+
bool OrderExists(ulong ticket)
{
    if(ticket == 0) return false;
    return OrderSelect(ticket);
}

bool IsPositionExists(ulong i)
{
    return PositionSelectByTicket(i);
}

//+------------------------------------------------------------------+
void DeleteAllPendingOrders()
{
    for(int b = OrdersTotal() - 1; b >= 0; b--)
    {
        ulong ticket = OrderGetTicket(b);
        if(!OrderSelect(ticket)) continue;
        if(OrderGetString(ORDER_SYMBOL) == Symbol() &&
           OrderGetInteger(ORDER_MAGIC) == InpMagic)
            trade.OrderDelete(ticket);
    }
    ArrayResize(buyStops,  0);
    ArrayResize(sellStops, 0);
}

//+------------------------------------------------------------------+
void ModifyAllOrders()
{
    int total = PositionsTotal();
    int pend  = OrdersTotal();

    RefreshStopLevels();

    buySL  = NormalizeDouble(sellPrice - stopLevel1 * _Point, _Digits);
    sellSL = NormalizeDouble(buyPrice  + stopLevel1 * _Point, _Digits);
    buyTP  = NormalizeDouble(buyPrice  + takeLevel1 * _Point, _Digits);
    sellTP = NormalizeDouble(sellPrice - takeLevel1 * _Point, _Digits);

    for(int i = 0; i < total; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;

        double oldtp = PositionGetDouble(POSITION_TP);

        if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY &&
           oldtp != buyTP &&
           PositionGetInteger(POSITION_MAGIC) == InpMagic)
            trade.PositionModify(ticket, buySL, buyTP);

        else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL &&
                oldtp != sellTP &&
                PositionGetInteger(POSITION_MAGIC) == InpMagic)
            trade.PositionModify(ticket, sellSL, sellTP);
    }

    for(int i = 0; i < pend; i++)
    {
        ulong ticket = OrderGetTicket(i);
        if(!OrderSelect(ticket)) continue;
        double price  = OrderGetDouble(ORDER_PRICE_OPEN);
        double oldtp1 = OrderGetDouble(ORDER_TP);

        if(OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP &&
           oldtp1 != buyTP &&
           OrderGetInteger(ORDER_MAGIC) == InpMagic)
            trade.OrderModify(ticket, price, buyTP, buySL, ORDER_TIME_GTC, 0);

        if(OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP &&
           oldtp1 != sellTP &&
           OrderGetInteger(ORDER_MAGIC) == InpMagic)
            trade.OrderModify(ticket, price, sellTP, sellSL, ORDER_TIME_GTC, 0);
    }
}

//+------------------------------------------------------------------+
void ModifyAllOrders2(int id)
{
    int total = PositionsTotal();

    for(int i = 0; i < total; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;

        double oldtp = PositionGetDouble(POSITION_TP);
        double oldsl = PositionGetDouble(POSITION_SL);

        if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY &&
           id == 1 && oldsl != sellPrice &&
           PositionGetInteger(POSITION_MAGIC) == InpMagic)
            trade.PositionModify(ticket, sellPrice, buyTP);

        else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL &&
                id == 1 && oldtp != sellPrice &&
                PositionGetInteger(POSITION_MAGIC) == InpMagic)
            trade.PositionModify(ticket, sellSL, sellPrice);

        if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY &&
           id == 2 && oldtp != buyPrice &&
           PositionGetInteger(POSITION_MAGIC) == InpMagic)
            trade.PositionModify(ticket, buySL, buyPrice);

        else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL &&
                id == 2 && oldsl != buyPrice &&
                PositionGetInteger(POSITION_MAGIC) == InpMagic)
            trade.PositionModify(ticket, buyPrice, sellTP);

        if(closeinmax) DeleteAllPendingOrders();
    }
}

//+------------------------------------------------------------------+
double GetLastOpenLotBySymbol()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)) &&
           PositionGetInteger(POSITION_MAGIC) == InpMagic)
        {
            if(PositionGetString(POSITION_SYMBOL) == Symbol())
                return PositionGetDouble(POSITION_VOLUME);
        }
    }
    return 0;
}

//+------------------------------------------------------------------+
int GetLastOpenTypeBySymbol()
{
    datetime last_time = 0;
    int      last_type = -1;

    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) == InpMagic &&
               PositionGetString(POSITION_SYMBOL) == Symbol())
            {
                datetime pos_time = (datetime)PositionGetInteger(POSITION_TIME);
                if(pos_time > last_time)
                {
                    last_time = pos_time;
                    last_type = (int)PositionGetInteger(POSITION_TYPE);
                }
            }
        }
    }
    return last_type;
}

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(id == CHARTEVENT_OBJECT_CLICK)
    {
        if(sparam == "btn_close_all")
            CloseAllTrades();
        else if(sparam == "btn_del_stops")
            DeleteAllPendingOrders();
        else if(sparam == "btn_disable_trd")
        {
            tradingAllowed = !tradingAllowed;
            ObjectSetString(0, "btn_disable_trd", OBJPROP_TEXT,
                            tradingAllowed ? "Disable Trading" : "Trading OFF");
        }
    }
}

bool CanTrade() { return tradingAllowed; }

//+------------------------------------------------------------------+
void CloseAllTrades()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagic)
            trade.PositionClose(ticket);
    }
    ArrayResize(buyStops,  0);
    ArrayResize(sellStops, 0);
}

//+------------------------------------------------------------------+
void CreateButton(string name, string text, int x, int y, color clr, color clr1)
{
    if(ObjectFind(0, name) == -1)
    {
        ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
        ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
        ObjectSetInteger(0, name, OBJPROP_XSIZE,     120);
        ObjectSetInteger(0, name, OBJPROP_YSIZE,     22);
        ObjectSetInteger(0, name, OBJPROP_COLOR,     clr1);
        ObjectSetInteger(0, name, OBJPROP_BGCOLOR,   clr);
        ObjectSetString (0, name, OBJPROP_TEXT,      text);
        ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
    }
}

//+------------------------------------------------------------------+
void RectLabelCreate(string name, int x, int y, color clr, int width, int height, bool selection)
{
    ObjectDelete(0, name);
    if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) return;
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
    ObjectSetInteger(0, name, OBJPROP_XSIZE,      width);
    ObjectSetInteger(0, name, OBJPROP_YSIZE,      height);
    ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE,BORDER_FLAT);
    ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_RIGHT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, selection);
    ObjectSetInteger(0, name, OBJPROP_BACK,       false);
    ObjectSetInteger(0, name, OBJPROP_ZORDER,     0);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN,     false);
}

//+------------------------------------------------------------------+
void LabelCreate(string name, int x, int y, string text, color clr, int font_size, bool isBold = false)
{
    ObjectDelete(0, name);
    if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) return;
    ObjectSetString (0, name, OBJPROP_TEXT,      text);
    ObjectSetString (0, name, OBJPROP_FONT,      isBold ? "Arial Bold" : FontName);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  font_size);
    ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
    ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_ANCHOR,    ANCHOR_RIGHT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
    ObjectSetInteger(0, name, OBJPROP_BACK,      false);
    ObjectSetInteger(0, name, OBJPROP_ZORDER,    2);
    ObjectSetInteger(0, name, OBJPROP_HIDDEN,    false);
}

//+------------------------------------------------------------------+
void CreatePanel(string name, int x, int y, int width, int height)
{
    if(!ShowBackground) return;
    if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
    RectLabelCreate(name + "Back", x, y, BackgroundColor,
                    width + (BorderWidth * 2), height + (BorderWidth * 2), false);
    ObjectSetInteger(0, name + "Back", OBJPROP_ZORDER, 1);
}

//+------------------------------------------------------------------+
void CreateHeader(string name, string text, int x, int y, int width)
{
    LabelCreate(name + "Header", x + PANEL_PADDING, y + (HEADER_HEIGHT / 2),
                text, TextColor, HeaderFontSize, HeaderBold);
}

//+------------------------------------------------------------------+
void CalculateHistoryStats(ulong magic, int &totalTrades,
                           double &buyProfit, double &sellProfit, double &totalProfit)
{
    totalTrades = 0; buyProfit = 0; sellProfit = 0; totalProfit = 0;
    HistorySelect(0, TimeCurrent());
    int deals = HistoryDealsTotal();

    for(int i = 0; i < deals; i++)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != magic) continue;

        double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
        long   type   = HistoryDealGetInteger(ticket, DEAL_TYPE);

        if(type == DEAL_TYPE_BUY)  buyProfit  += profit;
        if(type == DEAL_TYPE_SELL) sellProfit += profit;
        totalProfit += profit;
        totalTrades++;
    }
}

//+------------------------------------------------------------------+
bool IsNewBar()
{
    static datetime lastBarTime = 0;
    datetime current = iTime(_Symbol, PERIOD_M1, 0);
    if(current != lastBarTime) { lastBarTime = current; return true; }
    return false;
}

//+------------------------------------------------------------------+
void UpdatePanel()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

    int    totalTrades;
    double buyProfit, sellProfit, totalProfit;
    CalculateHistoryStats(InpMagic, totalTrades, buyProfit, sellProfit, totalProfit);

    double average = totalTrades > 0 ? totalProfit / totalTrades : 0.0;

    ObjectSetString(0, "lblTotalTrades", OBJPROP_TEXT, "Total Trades    " + IntegerToString(totalTrades));
    ObjectSetString(0, "lblBuyProfit",   OBJPROP_TEXT, "Buy Profit    "   + DoubleToString(buyProfit,   2));
    ObjectSetString(0, "lblSellProfit",  OBJPROP_TEXT, "Sell Profit  "    + DoubleToString(sellProfit,  2));
    ObjectSetString(0, "lblTotalProfit", OBJPROP_TEXT, "Total Profit  "   + DoubleToString(totalProfit, 2));
    ObjectSetString(0, "lblAverage",     OBJPROP_TEXT, "Average  "        + DoubleToString(average,     2));
    ObjectSetString(0, "lblBalance",     OBJPROP_TEXT, "Balance  "        + DoubleToString(balance,     2));
    ObjectSetString(0, "lblEquity",      OBJPROP_TEXT, "Equity  "         + DoubleToString(equity,      2));
}

//+------------------------------------------------------------------+
bool LastTradeClosedByTPWithMaxLot()
{
    if(!HistorySelect(0, TimeCurrent())) return false;
    int total = HistoryDealsTotal();
    if(total == 0) return false;

    ulong             lastTicket = 0;
    double            lastLot    = 0;
    ENUM_DEAL_REASON  lastReason;
    bool              foundLast  = false;

    for(int i = total - 1; i >= 0; i--)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(HistoryDealGetString(ticket,  DEAL_SYMBOL) != _Symbol)        continue;
        if(HistoryDealGetInteger(ticket, DEAL_MAGIC)  != InpMagic)       continue;
        if(HistoryDealGetInteger(ticket, DEAL_ENTRY)  != DEAL_ENTRY_OUT) continue;

        lastTicket = ticket;
        lastLot    = HistoryDealGetDouble(ticket, DEAL_VOLUME);
        lastReason = (ENUM_DEAL_REASON)HistoryDealGetInteger(ticket, DEAL_REASON);
        foundLast  = true;
        break;
    }

    if(!foundLast)                   return false;
    if(lastReason != DEAL_REASON_TP) return false;

    double maxLot = 0;
    for(int i = total - 1; i >= 0; i--)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(HistoryDealGetString(ticket,  DEAL_SYMBOL) != _Symbol)        continue;
        if(HistoryDealGetInteger(ticket, DEAL_MAGIC)  != InpMagic)       continue;
        if(HistoryDealGetInteger(ticket, DEAL_ENTRY)  != DEAL_ENTRY_OUT) continue;

        ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(ticket, DEAL_REASON);
        if(ticket != lastTicket && reason == DEAL_REASON_TP) break;

        double lot = HistoryDealGetDouble(ticket, DEAL_VOLUME);
        if(lot > maxLot) maxLot = lot;
    }

    return (lastLot >= maxLot);
}

//+------------------------------------------------------------------+
bool LastTradeClosedBySL()
{
    if(!HistorySelect(0, TimeCurrent())) return false;
    int total = HistoryDealsTotal();
    if(total == 0) return false;

    for(int i = total - 1; i >= 0; i--)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(HistoryDealGetString(ticket,  DEAL_SYMBOL) != _Symbol)        continue;
        if(HistoryDealGetInteger(ticket, DEAL_MAGIC)  != InpMagic)       continue;
        if(HistoryDealGetInteger(ticket, DEAL_ENTRY)  != DEAL_ENTRY_OUT) continue;

        ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(ticket, DEAL_REASON);
        return (reason == DEAL_REASON_SL);
    }
    return false;
}

//+------------------------------------------------------------------+
void CloseSmallerLots(double currentMaxLot)
{
    ENUM_POSITION_TYPE maxLotType = -1;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

        if(PositionGetDouble(POSITION_VOLUME) == currentMaxLot)
        {
            maxLotType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            break;
        }
    }

    if(maxLotType == -1) return;

    ENUM_POSITION_TYPE oppositeType = (maxLotType == POSITION_TYPE_BUY)
                                      ? POSITION_TYPE_SELL
                                      : POSITION_TYPE_BUY;

    bool hasOpposite = false;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
        if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == oppositeType)
        {
            hasOpposite = true;
            break;
        }
    }

    if(!hasOpposite) return;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
        if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

        if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == oppositeType)
        {
            trade.PositionClose(ticket);
            Print("🔴 CloseSmallerLots: closed OPPOSITE ",
                  (oppositeType == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                  " ticket=", ticket,
                  " lot=", PositionGetDouble(POSITION_VOLUME));
        }
    }
}

//+------------------------------------------------------------------+
bool CanOpenLot(double lot, ENUM_ORDER_TYPE type)
{
    double price = (type == ORDER_TYPE_BUY_STOP)
                   ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                   : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double margin;
    if(!OrderCalcMargin(type, _Symbol, lot, price, margin)) return false;
    return AccountInfoDouble(ACCOUNT_FREEMARGIN) > margin;
}

//+------------------------------------------------------------------+
double GetMaxLot(string symbol, ENUM_ORDER_TYPE type)
{
    double freeMargin = AccountInfoDouble(ACCOUNT_FREEMARGIN);
    double lotStep    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    double minLot     = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot     = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

    double price = (type == ORDER_TYPE_BUY)
                   ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                   : SymbolInfoDouble(symbol, SYMBOL_BID);

    double marginForOneLot = 0.0;
    if(!OrderCalcMargin(type, symbol, 1.0, price, marginForOneLot)) return 0.0;
    if(marginForOneLot <= 0.0) return 0.0;

    double maxPossibleLot = MathFloor((freeMargin / marginForOneLot) / lotStep) * lotStep;

    if(maxPossibleLot < minLot) return 0.0;
    if(maxPossibleLot > maxLot) maxPossibleLot = maxLot;

    return NormalizeDouble(maxPossibleLot, 2);
}