# TEST PROCEDURE

1. account 3 saves for 15 minutes for 3 FTM
   Bonus: Account 2 saves 1 FTM for fun for 30mins
2. account 1 saves 1 AVAX for 1 hr
3. account 1 breaks his save early
4. account 2 breaks his save
5. Account 5 saves 2 FTM for 10min
<!-- NOTE ACCOUNTS 3 BALANCE BEFORE WITHDRAING INTEREST -->
6. account 3 completes his save and withdraws his interest

# THINGS TO LOOK OUT FOR WHILE TESTING

FUND CONTRACTS WITH ENOUGH GAS

1. check for increase in total savers, total time saved, the user savings details for account 3

Bonus: Check for the same thing as step 1 but for account 2

2. Check for the same processes in step 1

3. Now you should check that the total default balance of avax should increase by 0.5 avax and total savers should be 2

4. Now you should check that the total default balance of ftm should increase by 0.5 FTM and total savers should be 1

5. Total savers should be 2 and account 5 saving details should have updated

6. Account 3 would be sharing a possible interest with account 5. Then take account 3 saving time which is 15mins and divide it by the total saving time which should be 25 mins multiplied by total price of the default balance in usd then convert that to ftm.

7. Check if your interest matches the balance
