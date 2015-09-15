{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE DeriveFunctor, DeriveFoldable, DeriveTraversable #-}
module Penny.Polar where

import Control.Lens

data Pole = North | South
  deriving (Eq, Ord, Show)

opposite :: Pole -> Pole
opposite North = South
opposite South = North

class Polar a where
  polar :: a -> Pole
  align :: Pole -> a -> a

class Equatorial a where
  equatorial :: a -> Maybe Pole

-- | An object that is polar.
data Polarized a = Polarized
  { _charged :: a
  , _charge :: Pole
  } deriving (Eq, Ord, Show, Functor, Foldable, Traversable)

makeLenses ''Polarized

instance Polar (Polarized a) where
  polar = view charge
  align pole = set charge pole

-- | An object that might be polar.
data Moderated n o
  = Moderate n
  | Extreme (Polarized o)
  deriving Show

instance Equatorial (Moderated n o) where
  equatorial (Moderate _) = Nothing
  equatorial (Extreme (Polarized _ c)) = Just c

makePrisms ''Moderated

debit :: Pole
debit = North

credit :: Pole
credit = South

positive :: Pole
positive = North

negative :: Pole
negative = South

instance Equatorial Int where
  equatorial i
    | i < 0 = Just South
    | i > 0 = Just North
    | otherwise = Nothing

instance Equatorial Integer where
  equatorial i
    | i < 0 = Just South
    | i > 0 = Just North
    | otherwise = Nothing
