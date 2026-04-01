# Siam-trading-hedge
Siam Trading Hedge is a hedging tool. On startup it places a BuyStop above the current price and a SellStop below it. Whichever side the market triggers first becomes the live position, and the EA immediately places a new pending order in the opposite direction at a multiplied lot size. The goal is for the winning side to close at TP,
