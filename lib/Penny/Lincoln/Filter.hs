module Penny.Lincoln.Filter where

import Data.Bifunctor
import Control.Applicative
import Penny.Lincoln.Serial
import Data.Sequence (Seq, ViewL(..), (<|))
import qualified Data.Sequence as S
import Prednote

serialedFilter
  :: Applicative f
  => PredM f a
  -> Seq a
  -> f (Seq (a, Serset), Seq Result)
serialedFilter p
  = fmap (first serialNumbers)
  . pdFilter p

pdFilter
  :: Applicative f
  => PredM f a
  -> Seq a
  -> f (Seq a, Seq Result)
pdFilter (PredM pd) sq = case S.viewl sq of
  S.EmptyL -> pure (S.empty, S.empty)
  x :< xs -> f <$> pd x <*> pdFilter (PredM pd) xs
    where
      f r (as, rs) = case splitResult r of
        Left _ -> (as, r <| rs)
        Right _ -> (x <| as, r <| rs)
