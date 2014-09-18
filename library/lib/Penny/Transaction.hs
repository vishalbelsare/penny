module Penny.Transaction where

import qualified Penny.TopLine as TopLine
import qualified Penny.Balanced as Balanced
import qualified Penny.Lincoln.Posting as Posting

data T = T
  { topLine :: TopLine.T
  , postings :: Balanced.T Posting.T
  } deriving (Eq, Ord, Show)
