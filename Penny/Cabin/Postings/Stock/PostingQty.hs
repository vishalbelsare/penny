module Penny.Cabin.Postings.Stock.PostingQty where

import qualified Data.Sequence as Seq
import qualified Data.Text as X

import qualified Penny.Cabin.Postings.Stock.Colors as C
import qualified Penny.Cabin.Postings.Base.Base as B
import qualified Penny.Cabin.Postings.Base.Row as R
import qualified Penny.Cabin.Postings.Stock.Columns as Columns
import qualified Penny.Cabin.Postings.Stock.Util as U
import Penny.Cabin.Postings.Stock.Columns (Fields, postingQty)
import qualified Penny.Lincoln.Bits as Bits
import qualified Penny.Lincoln.Queries as Q
import qualified Penny.Lincoln.Predicates as P


mainFormula ::
  (B.PostingInfo -> X.Text)
  -> Fields Bool
  -> C.DrCrColors
  -> B.Formula Columns.C
mainFormula render fields c = B.FGrowToFit f where
  f = if postingQty fields
      then (\_ _ p ci -> growFormula render c p ci)
      else U.zeroGrowToFit

spacerFormula :: Fields Bool
                 -> C.DrCrColors
                 -> B.Formula Columns.C
spacerFormula fields c = B.FGrowToFit f where
  f = if postingQty fields
      then \_ _ p ci -> spacer c p ci
      else U.zeroGrowToFit

spacer ::
  C.DrCrColors
  -> B.PostingInfo
  -> B.CellInfo Columns.C
  -> (B.ColumnWidth,
      B.Table Columns.C (B.PostingInfo, B.Queried Columns.C) -> R.Cell)
spacer colors p ci = U.makeSpacerCell U.Overran dcColors p ci True where
  dc = Q.drCr . B.postingBox $ p
  dcColors = C.drCrToBaseColors dc colors

growFormula ::
  (B.PostingInfo -> X.Text)
  -> C.DrCrColors
  -> B.PostingInfo
  -> B.CellInfo Columns.C
  -> (B.ColumnWidth,
      B.Table Columns.C (B.PostingInfo, B.Queried Columns.C) -> R.Cell)
growFormula render colors p ci = let
  ntct = U.Overran
  output = render p
  sq = Seq.singleton output
  dc = Q.drCr . B.postingBox $ p
  bc = C.drCrToBaseColors dc colors
  just = R.LeftJustify
  in U.makeGrowingCell ntct bc p ci just sq
