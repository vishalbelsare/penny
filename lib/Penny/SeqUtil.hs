{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE DeriveTraversable #-}
-- |
-- Utilities for "Data.Sequence".

module Penny.SeqUtil
  ( SortKey(..)
  , mapKey
  , reverseOrder
  , sortByM
  , multipleSortByM
  , mapMaybeM
  , rights

  -- * Views
  , Viewer(..)
  , seqFromView
  , View(..)
  , allViews
  ) where

import Control.Applicative hiding (empty)
import Control.Monad
import Data.Sequence
import qualified Data.Traversable as T
import qualified Data.Foldable as F
import qualified Data.Sequence as S
import Data.Functor.Contravariant
import Data.Monoid

-- | A single sort key.
data SortKey f k a = SortKey (k -> k -> Ordering) (a -> f k)

instance Contravariant (SortKey f k) where
  contramap f (SortKey cmp get) = SortKey cmp (get . f)

mapKey
  :: Functor f
  => (k -> k')
  -> (k' -> k)
  -> SortKey f k a
  -> SortKey f k' a
mapKey fwd bak (SortKey cmp get) = SortKey cmp' get'
  where
    get' = fmap (fmap fwd) get
    cmp' x y = cmp (bak x) (bak y)

reverseOrder :: SortKey f k a -> SortKey f k a
reverseOrder (SortKey cmp get) = SortKey cmp' get
  where
    cmp' x y = case cmp x y of
      GT -> LT
      LT -> GT
      EQ -> EQ

-- | Sort a 'Seq', with effects.
sortByM
  :: Monad m
  => SortKey m k a
  -> Seq a
  -> m (Seq a)
sortByM (SortKey cmp get) sq = liftM go $ T.mapM get sq
  where
    go keys
      = fmap snd
      . S.sortBy (\x y -> cmp (fst x) (fst y))
      . S.zip keys
      $ sq

-- |
-- Sort using multiple keys.  Sorting is performed using each key in
-- turn, from left to right.
multipleSortByM
  :: (Monad m, F.Foldable c)
  => c (SortKey m k a)
  -> Seq a
  -> m (Seq a)
multipleSortByM keys sq = F.foldlM (flip sortByM) sq keys

mapMaybeM
  :: Monad m
  => (a -> m (Maybe b))
  -> Seq a
  -> m (Seq b)
mapMaybeM f sq = case viewl sq of
  EmptyL -> return empty
  x :< xs -> do
    mayB <- f x
    rest <- mapMaybeM f xs
    return $ case mayB of
      Nothing -> rest
      Just b -> b <| rest

rights :: Seq (Either a b) -> Seq b
rights sq = case viewl sq of
  EmptyL -> empty
  x :< xs -> case x of
    Left _ -> rights xs
    Right r -> r <| rights xs

-- | An interface for a view on a sequence.  There is always a current
-- item on view.
--
-- Does not include functions to construct the view; depending on the
-- particular view, such functions might break the internal
-- consistency of the view.

class Viewer a where
  type Viewed (a :: *) :: *
  onLeft :: a -> Seq (Viewed a)
  onRight :: a -> Seq (Viewed a)
  onView :: a -> Viewed a
  nextView :: a -> Maybe a
  previousView :: a -> Maybe a

seqFromView :: Viewer a => a -> Seq (Viewed a)
seqFromView v = (onLeft v |> onView v) <> onRight v

data View a = View (Seq a) a (Seq a)

instance Functor View where
  fmap f (View l c r) = View (fmap f l) (f c) (fmap f r)

instance F.Foldable View where
  foldr f z (View l c r) = F.foldr f (f c (F.foldr f z r)) l

instance T.Traversable View where
  sequenceA (View l c r) = View <$> T.sequenceA l <*> c <*> T.sequenceA r

instance Viewer (View a) where
  type Viewed (View a) = a
  onLeft (View l _ _) = l
  onRight (View _ _ r) = r
  onView (View _ c _) = c
  nextView (View l c r) = case viewl r of
    EmptyL -> Nothing
    x :< xs -> Just (View (l |> c) x xs)
  previousView (View l c r) = case viewr l of
    EmptyR -> Nothing
    xs :> x -> Just (View xs x (c <| r))

allViews :: Seq a -> Seq (View a)
allViews = go empty
  where
    go soFar sq = case viewl sq of
      EmptyL -> empty
      x :< xs -> View soFar x xs <| go (soFar |> x) xs
