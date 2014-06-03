module Penny.Lincoln.Decimal.Amount where

import Penny.Lincoln.Decimal.Concrete
import Penny.Lincoln.Decimal.Abstract
import Penny.Lincoln.Decimal.Lane

-- | An amount is either an 'Abstract' or a 'Concrete'.  All
-- 'Amount' embody a decimal number along with a 'Lane' (that is, a
-- 'Penny.Lincoln.Decimal.Side.Debit', a
-- 'Penny.Lincoln.Decimal.Side.Credit', or neither if the number is
-- zero.)  Use 'lane' to determine the 'Lane' of an 'Amount'.  All
-- 'Amount' may be transformed to a 'Concrete' using 'concrete'; you
-- may perform arithmetic only on a 'Concrete'.  Transform a
-- 'Concrete' to an 'Abstract' (which is the only form that may be
-- rendered as a string) using the functions in
-- "Penny.Lincoln.Decimal.Represent".
data Amount
  = AAbstract Abstract
  | AConcrete Concrete
  deriving (Eq, Ord, Show)

instance HasConcrete Amount where
  concrete r = case r of
    AAbstract d -> concrete d
    AConcrete c -> concrete c

instance Laned Amount where
  lane r = case r of
    AAbstract a -> lane a
    AConcrete c -> lane c
