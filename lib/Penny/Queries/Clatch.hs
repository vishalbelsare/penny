{-# LANGUAGE TypeFamilies #-}
-- | Queries on 'Penny.Clatch.Clatch'.

module Penny.Queries.Clatch where

import Control.Monad
import Data.Sums
import Penny.Amount
import Penny.Balance
import Penny.Clatch
import Penny.Commodity
import Penny.Ledger
import Penny.Representation
import Penny.Qty
import Penny.SeqUtil
import Penny.Serial
import Penny.Trio

-- | Gets the 'PostingL' from the 'Clatch'.
postingL :: Clatch m -> PostingL m
postingL
  (Filtered (Sersetted _ (RunningBalance _ (Sorted (Sersetted _
    (Filtered (Sersetted _ (_, vw)))))))) = pstg
  where
    Converted _ pstg = onView vw

-- | Gets the 'Amount' after conversion, if any conversion took place.
convertedAmount
  :: Clatch l
  -> Maybe Amount
convertedAmount
  (Filtered (Sersetted _ (RunningBalance _ (Sorted (Sersetted _
    (Filtered (Sersetted _ (_, vw)))))))) = mayAmt
  where
    Converted mayAmt _ = onView vw

-- | Gets the 'TransactionL' from a 'Clatch'.
transactionL
  :: Clatch l
  -> TransactionL l
transactionL
  (Filtered (Sersetted _ (RunningBalance _ (Sorted (Sersetted _
    (Filtered (Sersetted _ (txn, _)))))))) = txn

-- | Gets the 'Serset' resulting from pre-filtering.
sersetPreFiltered :: Clatch l -> Serset
sersetPreFiltered
  (Filtered (Sersetted _ (RunningBalance _ (Sorted (Sersetted _
    (Filtered (Sersetted srst _))))))) = srst

-- | Gets the 'Serset' resulting from sorting.
sersetSorted :: Clatch l -> Serset
sersetSorted
  (Filtered (Sersetted _ (RunningBalance _ (Sorted
    (Sersetted srst _))))) = srst

-- | Gets the running balance.
runningBalance :: Clatch l -> Balance
runningBalance
  (Filtered (Sersetted _ (RunningBalance bal _))) = bal

-- | Gets the 'Serset' resulting from post-filtering.
--
-- @
-- 'sersetPostFiltered' :: 'Clatch' l -> 'Serset'
-- @
sersetPostFiltered :: Clatch l -> Serset
sersetPostFiltered (Filtered (Sersetted srst _)) = srst

-- | Gets the 'Qty' using the 'Trio' in the 'PostingL'.
originalQtyRep
  :: Ledger l
  => Clatch l
  -- ^
  -> l (S3 RepNonNeutralNoSide QtyRepAnyRadix Qty)
originalQtyRep clch = (trio . postingL $ clch) >>= conv
  where
    conv tri = case tri of
      QC qr _ _ -> return $ S3b qr
      Q qr -> return $ S3b qr
      UC nn _ _ -> return $ S3a nn
      U nn -> return $ S3a nn
      _ -> liftM S3c . qty . postingL $ clch

-- | Gets the 'Qty' from the converted 'Amount', if there is one;
-- otherwise, get the original 'Qty'.
bestQty :: Ledger l => Clatch l -> l Qty
bestQty clch = case convertedAmount clch of
  Just (Amount _ qt) -> return qt
  Nothing -> qty . postingL $ clch

-- | Gets the 'Qty' from the converted Amount, if there is one.
-- Otherwise, gets the 'QtyRep' from the 'Trio', if there is one.
-- Otherwise, gets the 'Qty'.

bestQtyRep
  :: Ledger l
  => Clatch l
  -> l (S3 RepNonNeutralNoSide QtyRepAnyRadix Qty)
bestQtyRep clch = case convertedAmount clch of
  Just (Amount _ qt) -> return $ S3c qt
  Nothing -> originalQtyRep clch

-- | Gets the 'Commodity' from the converted Amount, if there is one.
-- Otherwise, gets the 'Commodity' from the 'PostingL'.
bestCommodity
  :: Ledger l
  => Clatch l
  -> l Commodity
bestCommodity clch = case convertedAmount clch of
  Just (Amount cy _) -> return cy
  Nothing -> commodity . postingL $ clch
