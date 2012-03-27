-- | Each cell in the grid has a unique address. The row address is
-- determined both by the visible number of the posting (its ordinal
-- number) and by its tranche row. The column is generally identified
-- by the field that appears in the column, with the exception of the
-- Multi column, which holds more than one field, depending on the
-- tranche row. Instead of using numbers to identify these addresses,
-- these types are used.

module Penny.Cabin.Postings.Address where

import Data.Ix (Ix)

data Cols a = Cols {
  lineNum :: a
  , sLineNum :: a
  , date :: a
  , sDate :: a
  , multi :: a
  , sMulti :: a
  , num :: a
  , sNum :: a
  , payee :: a
  , sPayee :: a
  , account :: a
  , sAccount :: a
  , postingDrCr :: a
  , sPostingDrCr :: a
  , postingCommodity :: a
  , sPostingCommodity :: a
  , postingQty :: a
  , sPostingQty :: a
  , totalDrCr :: a
  , sTotalDrCr :: a
  , totalCommodity :: a
  , sTotalCommodity :: a
  , totalQty :: a
  } deriving Show

data Rows a = Rows {
  top :: Cols a
  , tags :: Cols a
  , memo :: Cols a
  , filename :: Cols a
  } deriving Show

-- | Identifies the column in the array. These are named for what
-- appears in the column, except for the Multi column. Many of these
-- are preceded by an @S@. These columns are spacers. They are named
-- for the column they immediately follow.
data Col =
  LineNum
  | SLineNum
  | Date
  | SDate
  | Multi
    -- ^ Flag, tags, memo, or filename, depending upon the tranche row
  | SMulti
  | Num
  | SNum
  | Payee
  | SPayee
  | Account
  | SAccount
  | PostingDrCr
  | SPostingDrCr
  | PostingCommodity
  | SPostingCommodity
  | PostingQty
  | SPostingQty
  | TotalDrCr
  | STotalDrCr
  | TotalCommodity
  | STotalCommodity
  | TotalQty
    deriving (Eq, Ord, Show, Ix, Bounded, Enum)

-- | Identifies the row in the grid.
data Row =
  Top
  | Tags
  | Memo
  | Filename
  deriving (Eq, Ord, Show, Ix, Bounded, Enum)
