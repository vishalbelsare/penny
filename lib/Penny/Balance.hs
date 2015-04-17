module Penny.Balance where

import Penny.Amount
import qualified Data.Foldable as F
import Penny.Decimal
import Penny.Commodity
import Penny.Qty
import qualified Data.Map as M
import Data.Monoid

newtype Balance = Balance (M.Map Commodity Qty)
  deriving (Eq, Ord, Show)

instance Monoid Balance where
  mempty = Balance M.empty
  mappend (Balance x) (Balance y) = Balance $ M.unionWith (+) x y

c'Balance'Amount :: Amount -> Balance
c'Balance'Amount (Amount c q) = Balance $ M.singleton c q

addAmountToBalance :: Amount -> Balance -> Balance
addAmountToBalance (Amount c q) (Balance m) = Balance . M.alter f c $ m
  where
    f v = case v of
      Nothing -> Just q
      Just l -> Just $ q + l

isBalanced :: Balance -> Bool
isBalanced (Balance m) = F.all isZero m
  where
    isZero (Qty (Decimal signif _)) = signif == 0

newtype Imbalance = Imbalance (M.Map Commodity QtyNonZero)
  deriving (Eq, Ord, Show)

c'Imbalance'Amount :: Amount -> Imbalance
c'Imbalance'Amount = c'Imbalance'Balance . c'Balance'Amount

c'Imbalance'Balance :: Balance -> Imbalance
c'Imbalance'Balance (Balance m)
  = Imbalance
  . M.mapMaybe qtyToQtyNonZero $ m

c'Balance'Imbalance :: Imbalance -> Balance
c'Balance'Imbalance (Imbalance m)
  = Balance . fmap qtyNonZeroToQty $ m

instance Monoid Imbalance where
  mempty = Imbalance M.empty
  mappend x y =
    c'Imbalance'Balance $ mappend
      (c'Balance'Imbalance x) (c'Balance'Imbalance y)