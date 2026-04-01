# Siam-trading-hedge
Siam Trading Hedge is a hedging tool. On startup it places a BuyStop above the current price and a SellStop below it. Whichever side the market triggers first becomes the live position, and the EA immediately places a new pending order in the opposite direction at a multiplied lot size. The goal is for the winning side to close at TP,
<img width="1599" height="765" alt="Capture" src="https://github.com/user-attachments/assets/2e8b702b-cd6b-436c-9acf-006e379f1b4c" />




StartLot   	Lot size at the start of each fresh cycle
Multiplier	   Factor applied to the previous cycle's lot after an SL hit
DistancePips	   Points away from current price to place the initial stops
SL_points / TP_points	Stop-loss and take-profit for level 1 (normal cycle)
SL_points1 / TP_points1	SL/TP for level 2, activated when lot reaches lot2
lot2	Lot threshold that triggers a switch to level-2 SL/TP
lot3	Lot threshold that triggers the breakeven-style modification
close	If true, automatically closes the smaller-lot side when both directions are open
closeinmax	If true, deletes pending orders when lot3 is reached
InpMagic	Magic number to distinguish this EA's orders from others
  





OnInit() runs once at startup. It resets the order ticket arrays, draws the on-chart panel, calls RefreshStopLevels() to clamp SL/TP values to the broker's minimum, then calls RecoverStateOnRestart() .

RecoverStateOnRestart() is the safety net for restarts. It scans existing pending orders and open positions to rebuild buyPrice , sellPrice , buySL , sellSL , buyTP , sellTP , currentLot , and lastBar . If nothing is open and the last closed deal was a TP, it resets to StartLot . If the last deal was an SL, it leaves the lot calculation to FastTradeLogic .

OnTick() fires on every price tick. It calls FastTradeLogic() and refreshes the on-chart panel once per bar.

FastTradeLogic() is the core brain. Every tick it runs these steps in order:

CheckOrphanPositionsAfterTP() — if there are no open positions but orphaned pending orders from one direction only, deletes them and resets.
ModifyAllOrders() — if the current open lot equals lot2 , switches all positions and pending orders to level-2 SL/TP.
ModifyAllOrders2(lastBar) — if lot equals lot3 , applies a breakeven-style modification depending on which direction is winning.
CheckAndFixOpenPositionsSL() — validates that no position's SL has drifted into an invalid zone relative to the opposite price level.
EnsureOppositeOrderExists() — if a position is open but its opposing pending order is missing, recreates it immediately.
No trades and no orders — waits one tick then opens a fresh cycle. If the last close was an SL, multiplies the lot; otherwise resets to StartLot .
BUY was triggered — deletes old sell-stop array, calls CreateNextOrder(false) to place a new SellStop at totalSellLot × Multiplier , sets lastBar = 1 .
SELL was triggered — deletes old buy-stop array, calls CreateNextOrder(true) to place a new BuyStop, sets lastBar = 2 .
TP hit detected — resets everything ( currentLot = StartLot , lastBar = 0 , buyPrice = 0 , etc.) and sets waitForNewTick = true .
Key helper functions
PlaceFirstOrders() — computes the initial BuyStop and SellStop prices from the current bid/ask plus DistancePips , calculates SL and TP for each, validates them against the broker's minimum stop level, and places both orders with a daily expiry.

CreateNextOrder() — after one side triggers, this function computes totalLot × Multiplier for the opposite direction. If the result exceeds the broker's maxLot , it splits the order into multiple smaller parts (up to 50 chunks) and places them all, storing every ticket in the array.

ModifyAllOrders() — replaces SL and TP on all open positions and pending orders with the level-2 values ( SL_points1 / TP_points1 ) when lot reaches lot2 .

ModifyAllOrders2(lastBar) — when lot reaches lot3 , adjusts positions toward breakeven. If lastBar = 1 (BUY is the big position), the BUY SL is moved to sellPrice and the SELL TP is set to sellPrice . If lastBar = 2 , the mirror logic applies.

ValidateAndFixSL() — prevents a BUY position's SL from being placed above sellPrice , or a SELL's SL from being below buyPrice .

CloseSmallerLots() — when both a BUY and a SELL are simultaneously open, finds the one with the smaller lot and closes it.

GetTotalLotFromLastCycle() — walks backward through the deal history to sum up all closed lots in the last cycle, used to compute the correct starting lot after an SL loss.

LastTradeClosedByTP() / LastTradeClosedBySL() — inspect the deal history to determine how the most recent trade was closed, driving the reset-or-multiply decision.
