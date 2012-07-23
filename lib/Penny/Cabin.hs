-- | Cabin - Penny reports
module Penny.Cabin (allReportsWithDefaults) where

import qualified Penny.Cabin.Balance as B
import qualified Penny.Cabin.Posts as P
import qualified Penny.Copper as C
import qualified Penny.Cabin.Interface as I

allReportsWithDefaults ::
  C.DefaultTimeZone
  -> C.RadGroup
  -> [I.Report]
allReportsWithDefaults dtz rg =
  [B.defaultBalanceReport, P.defaultPostsReport dtz rg]
  
